"""
export_model.py — Train (or load) SpectralUNet and export to TFLite.

Usage
-----
# Export a randomly initialised model (architecture test / placeholder):
    python scripts/export_model.py --output assets/models/speech_denoise.tflite

# Train on DNS-Challenge data then export:
    python scripts/export_model.py \
        --train_dir /data/dns/train \
        --epochs 50 \
        --output assets/models/speech_denoise.tflite

# Load existing PyTorch checkpoint, convert, and export:
    python scripts/export_model.py \
        --checkpoint checkpoints/best.pt \
        --output assets/models/speech_denoise.tflite

Requirements
------------
    pip install torch torchaudio tensorflow onnx onnx-tf numpy soundfile

STFT constants (must match lib/services/neural_processor_service.dart):
    N_FFT        = 512   →  FREQ_BINS = 257
    HOP_LENGTH   = 128
    CHUNK_FRAMES = 128   (fixed TFLite input width)
    SAMPLE_RATE  = 16000
"""

from __future__ import annotations

import argparse
import os
import pathlib
import sys
from typing import Optional

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
import torchaudio

# ─── Constants (keep in sync with neural_processor_service.dart) ──────────────

N_FFT        = 512
HOP_LENGTH   = 128
WIN_LENGTH   = 512
FREQ_BINS    = N_FFT // 2 + 1   # 257
CHUNK_FRAMES = 128
SAMPLE_RATE  = 16_000


# ─── Model architecture ───────────────────────────────────────────────────────

class ConvBlock(nn.Module):
    def __init__(self, in_ch: int, out_ch: int, stride: int = 1):
        super().__init__()
        self.block = nn.Sequential(
            nn.Conv2d(in_ch, out_ch, 3, stride=stride, padding=1, bias=False),
            nn.BatchNorm2d(out_ch),
            nn.LeakyReLU(0.2, inplace=True),
            nn.Conv2d(out_ch, out_ch, 3, stride=1, padding=1, bias=False),
            nn.BatchNorm2d(out_ch),
            nn.LeakyReLU(0.2, inplace=True),
        )

    def forward(self, x):
        return self.block(x)


class UpBlock(nn.Module):
    def __init__(self, in_ch: int, skip_ch: int, out_ch: int):
        super().__init__()
        self.up   = nn.Upsample(scale_factor=2, mode='bilinear', align_corners=False)
        self.conv = ConvBlock(in_ch + skip_ch, out_ch)

    def forward(self, x, skip):
        x  = self.up(x)
        dh = skip.size(2) - x.size(2)
        dw = skip.size(3) - x.size(3)
        x  = F.pad(x, [0, dw, 0, dh])
        return self.conv(torch.cat([x, skip], dim=1))


class SpectralUNet(nn.Module):
    """
    Input:   [B, 1, FREQ_BINS, CHUNK_FRAMES]  log-normalised magnitude
    Output:  [B, 1, FREQ_BINS, CHUNK_FRAMES]  IRM mask ∈ [0, 1]
    """
    BASE = [32, 64, 128, 256, 512]

    def __init__(self):
        super().__init__()
        b = self.BASE
        self.enc1 = ConvBlock(1,    b[0], 1)
        self.enc2 = ConvBlock(b[0], b[1], 2)
        self.enc3 = ConvBlock(b[1], b[2], 2)
        self.enc4 = ConvBlock(b[2], b[3], 2)
        self.enc5 = ConvBlock(b[3], b[4], 2)

        self.bottleneck = ConvBlock(b[4], b[4])
        self.se_pool    = nn.AdaptiveAvgPool2d(1)
        self.se_fc      = nn.Sequential(
            nn.Flatten(),
            nn.Linear(b[4], b[4] // 8),
            nn.ReLU(inplace=True),
            nn.Linear(b[4] // 8, b[4]),
            nn.Sigmoid(),
        )

        self.dec4 = UpBlock(b[4], b[3], b[3])
        self.dec3 = UpBlock(b[3], b[2], b[2])
        self.dec2 = UpBlock(b[2], b[1], b[1])
        self.dec1 = UpBlock(b[1], b[0], b[0])

        self.head = nn.Sequential(
            nn.Conv2d(b[0], 1, 1),
            nn.Sigmoid(),
        )

    def _se(self, x):
        attn = self.se_pool(x)
        attn = self.se_fc(attn).view(attn.size(0), -1, 1, 1)
        return x * attn

    def forward(self, x):
        # x: [B, 1, F, T]
        s1 = self.enc1(x)
        s2 = self.enc2(s1)
        s3 = self.enc3(s2)
        s4 = self.enc4(s3)
        s5 = self.enc5(s4)
        b  = self._se(self.bottleneck(s5))
        d4 = self.dec4(b,  s4)
        d3 = self.dec3(d4, s3)
        d2 = self.dec2(d3, s2)
        d1 = self.dec1(d2, s1)
        return self.head(d1)


# ─── Loss functions ───────────────────────────────────────────────────────────

class HybridLoss(nn.Module):
    def __init__(self, w_spec: float = 1.0, w_sisnr: float = 0.5):
        super().__init__()
        self.w_spec   = w_spec
        self.w_sisnr  = w_sisnr

    @staticmethod
    def log_mag_l1(pred, target):
        eps = 1e-8
        return F.l1_loss(torch.log1p(pred + eps), torch.log1p(target + eps))

    @staticmethod
    def si_snr(pred, clean):
        eps = 1e-8
        pred  = pred  - pred.mean(-1, keepdim=True)
        clean = clean - clean.mean(-1, keepdim=True)
        s     = (pred * clean).sum(-1, keepdim=True) / (clean.pow(2).sum(-1, keepdim=True) + eps) * clean
        noise = pred - s
        ratio = s.pow(2).sum(-1) / (noise.pow(2).sum(-1) + eps)
        return -(10.0 * torch.log10(ratio + eps)).mean()

    def forward(self, pred_mag, clean_mag, pred_wav, clean_wav):
        return (self.w_spec  * self.log_mag_l1(pred_mag, clean_mag) +
                self.w_sisnr * self.si_snr(pred_wav, clean_wav))


# ─── Training helpers ─────────────────────────────────────────────────────────

def wav_to_stft(wav: torch.Tensor, window: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor]:
    """[T] → magnitude [F, T_f], phase [F, T_f]"""
    spec = torch.stft(wav, N_FFT, HOP_LENGTH, WIN_LENGTH, window, return_complex=False)
    real, imag = spec[..., 0], spec[..., 1]
    return torch.sqrt(real**2 + imag**2 + 1e-8), torch.atan2(imag, real)


def normalise(mag: torch.Tensor) -> tuple[torch.Tensor, float, float]:
    lm   = torch.log1p(mag)
    mean = lm.mean().item()
    std  = lm.std().item() + 1e-8
    return (lm - mean) / std, mean, std


def denormalise(x: torch.Tensor, mean: float, std: float) -> torch.Tensor:
    return torch.expm1((x * std + mean).clamp(min=0.0))


def train(model: SpectralUNet, train_dir: str, epochs: int, device: torch.device) -> None:
    """
    Simple training loop over (noisy, clean) WAV pairs in train_dir.

    Expected directory layout:
        train_dir/
            noisy/  *.wav   (noisy recordings, 16 kHz mono)
            clean/  *.wav   (corresponding clean recordings, 16 kHz mono)

    For best results, use DNS Challenge 4 data:
        https://github.com/microsoft/DNS-Challenge
    """
    optimizer = torch.optim.AdamW(model.parameters(), lr=3e-4, weight_decay=1e-4)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, epochs)
    loss_fn   = HybridLoss()
    window    = torch.hann_window(WIN_LENGTH).to(device)
    model.train()

    noisy_dir = pathlib.Path(train_dir) / 'noisy'
    clean_dir = pathlib.Path(train_dir) / 'clean'
    files     = sorted(noisy_dir.glob('*.wav'))
    if not files:
        print(f"[!] No *.wav files found in {noisy_dir} — exporting untrained model")
        return

    for epoch in range(1, epochs + 1):
        total_loss = 0.0
        for f in files:
            noisy_wav, sr = torchaudio.load(f)
            clean_wav, _  = torchaudio.load(clean_dir / f.name)

            if sr != SAMPLE_RATE:
                noisy_wav = torchaudio.functional.resample(noisy_wav, sr, SAMPLE_RATE)
                clean_wav = torchaudio.functional.resample(clean_wav, sr, SAMPLE_RATE)

            noisy_wav = noisy_wav.mean(0).to(device)
            clean_wav = clean_wav.mean(0).to(device)

            n_mag, n_phase = wav_to_stft(noisy_wav, window)
            c_mag, _       = wav_to_stft(clean_wav, window)

            norm_in, mean, std = normalise(n_mag)
            mask = model(norm_in.unsqueeze(0).unsqueeze(0)).squeeze()
            pred_mag = denormalise(norm_in * mask, mean, std)

            # iSTFT for waveform loss
            def to_wav(mag, phase):
                real = mag * torch.cos(phase)
                imag = mag * torch.sin(phase)
                return torch.istft(
                    torch.stack([real, imag], -1),
                    N_FFT, HOP_LENGTH, WIN_LENGTH, window,
                )

            loss = loss_fn(pred_mag, c_mag,
                           to_wav(pred_mag, n_phase),
                           to_wav(c_mag, n_phase))

            optimizer.zero_grad()
            loss.backward()
            nn.utils.clip_grad_norm_(model.parameters(), 5.0)
            optimizer.step()
            total_loss += loss.item()

        scheduler.step()
        avg = total_loss / max(len(files), 1)
        print(f"Epoch {epoch}/{epochs}  loss={avg:.4f}  lr={scheduler.get_last_lr()[0]:.2e}")

    print("[✓] Training complete")


# ─── TFLite export ────────────────────────────────────────────────────────────

def export_to_tflite(model: SpectralUNet, output_path: str) -> None:
    """
    PyTorch → ONNX → TensorFlow → TFLite pipeline.

    The TFLite model has fixed input shape [1, 1, FREQ_BINS, CHUNK_FRAMES]
    matching the chunked inference in neural_processor_service.dart.
    """
    import onnx
    import tensorflow as tf

    model.eval()
    dummy   = torch.randn(1, 1, FREQ_BINS, CHUNK_FRAMES)
    onnx_path = output_path.replace('.tflite', '.onnx')
    tf_path   = output_path.replace('.tflite', '_tf_saved_model')

    # ── Step 1: PyTorch → ONNX ───────────────────────────────────────────────
    torch.onnx.export(
        model, dummy, onnx_path,
        input_names  = ['input'],
        output_names = ['mask'],
        dynamic_axes = {},                  # fully static shape for TFLite
        opset_version = 17,
    )
    print(f"[✓] ONNX saved → {onnx_path}")

    # ── Step 2: ONNX → TensorFlow SavedModel ─────────────────────────────────
    try:
        from onnx_tf.backend import prepare
        onnx_model = onnx.load(onnx_path)
        tf_rep     = prepare(onnx_model)
        tf_rep.export_graph(tf_path)
        print(f"[✓] TF SavedModel → {tf_path}")
    except ImportError:
        print("[!] onnx-tf not installed. Install with: pip install onnx-tf")
        print("    Alternatively, use the direct Keras export path below.")
        sys.exit(1)

    # ── Step 3: TensorFlow → TFLite ──────────────────────────────────────────
    converter = tf.lite.TFLiteConverter.from_saved_model(tf_path)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    # INT8 quantisation (optional, halves model size, minimal quality impact):
    # converter.target_spec.supported_types = [tf.int8]
    tflite_model = converter.convert()

    pathlib.Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, 'wb') as f:
        f.write(tflite_model)

    size_mb = len(tflite_model) / 1024 / 1024
    print(f"[✓] TFLite saved → {output_path}  ({size_mb:.1f} MB)")


def export_keras_tflite(output_path: str) -> None:
    """
    Alternative: build an equivalent model directly in Keras and export.
    Avoids the onnx-tf dependency entirely.
    Use this if the ONNX path fails.
    """
    import tensorflow as tf
    from tensorflow.keras import layers, Model

    def conv_block(x, filters, stride=1):
        x = layers.Conv2D(filters, 3, strides=stride, padding='same', use_bias=False)(x)
        x = layers.BatchNormalization()(x)
        x = layers.LeakyReLU(0.2)(x)
        x = layers.Conv2D(filters, 3, strides=1, padding='same', use_bias=False)(x)
        x = layers.BatchNormalization()(x)
        x = layers.LeakyReLU(0.2)(x)
        return x

    def up_block(x, skip, filters):
        x = layers.UpSampling2D(2, interpolation='bilinear')(x)
        x = layers.Concatenate()([x, skip])
        return conv_block(x, filters)

    b = [32, 64, 128, 256, 512]
    inp = layers.Input(shape=(1, FREQ_BINS, CHUNK_FRAMES), name='input')
    # Permute to channels-last for Keras: [B, F, T, C]
    x   = layers.Permute((2, 3, 1))(inp)

    s1  = conv_block(x,   b[0])
    s2  = conv_block(s1,  b[1], 2)
    s3  = conv_block(s2,  b[2], 2)
    s4  = conv_block(s3,  b[3], 2)
    s5  = conv_block(s4,  b[4], 2)
    bt  = conv_block(s5,  b[4])
    d4  = up_block(bt, s4, b[3])
    d3  = up_block(d4, s3, b[2])
    d2  = up_block(d3, s2, b[1])
    d1  = up_block(d2, s1, b[0])
    out = layers.Conv2D(1, 1, activation='sigmoid')(d1)
    # Permute back to channels-first: [B, C, F, T]
    out = layers.Permute((3, 1, 2), name='mask')(out)

    model   = Model(inputs=inp, outputs=out)
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    tflite_model = converter.convert()

    pathlib.Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, 'wb') as f:
        f.write(tflite_model)

    size_mb = len(tflite_model) / 1024 / 1024
    print(f"[✓] Keras TFLite saved → {output_path}  ({size_mb:.1f} MB)")
    print("    Note: this is an untrained model. Train on DNS-Challenge data for real quality.")


# ─── Entry point ──────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description='Export SpectralUNet → TFLite')
    parser.add_argument('--output',     default='assets/models/speech_denoise.tflite')
    parser.add_argument('--checkpoint', default=None,  help='Path to .pt weights')
    parser.add_argument('--train_dir',  default=None,  help='Path to training data dir')
    parser.add_argument('--epochs',     type=int, default=30)
    parser.add_argument('--keras',      action='store_true',
                        help='Use direct Keras export (no onnx-tf required)')
    args = parser.parse_args()

    if args.keras:
        export_keras_tflite(args.output)
        return

    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    model  = SpectralUNet().to(device)

    if args.checkpoint and pathlib.Path(args.checkpoint).exists():
        ck = torch.load(args.checkpoint, map_location=device)
        model.load_state_dict(ck.get('model', ck))
        print(f"[✓] Loaded weights from {args.checkpoint}")

    if args.train_dir:
        train(model, args.train_dir, args.epochs, device)
        torch.save({'model': model.state_dict()}, 'checkpoints/last.pt')

    export_to_tflite(model.cpu(), args.output)


if __name__ == '__main__':
    main()
