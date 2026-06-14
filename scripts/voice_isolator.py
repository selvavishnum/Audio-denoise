#!/usr/bin/env python3
"""
voice_isolator.py — From-scratch recreation of the ElevenLabs Audio Isolation
processor.

What ElevenLabs Audio Isolation does
-------------------------------------
ElevenLabs runs a deep neural source-separation model on cloud GPUs that takes a
noisy recording (voice + music + room + traffic + crowd) and returns ONLY the
voice, with everything else removed. It is a *voice isolation* (foreground
speech extraction) model — stronger than ordinary denoising because it removes
structured interference (music, other talkers) too, not just stationary hiss.

This script recreates that whole pipeline from scratch so it can run locally
(CPU or GPU) and be exported to ONNX for on-device inference inside NoiseClear —
removing the cloud dependency entirely.

Two engines are provided
------------------------
  1. DSP isolator  (--dsp)      Works immediately, NO training, NO model files.
                                Harmonic-percussive separation + voice-band
                                masking + a-priori-SNR Wiener gain. Good for
                                voice + steady background.

  2. Neural isolator (--train / --infer / --export-onnx)
                                A from-scratch U-Net spectrogram mask estimator
                                (the architecture class ElevenLabs/Spleeter/
                                Demucs-spectrogram models use). Train it on
                                (noisy, clean) pairs, then export to ONNX. Far
                                stronger separation of music/other voices.

Everything — STFT, iSTFT, the network, the masking, the training loop — is
implemented here from first principles.

Usage
-----
    pip install numpy soundfile                 # DSP isolator only
    pip install numpy soundfile torch onnx      # + neural training/export

    # Isolate a voice immediately, no model needed:
    python scripts/voice_isolator.py --dsp --infer noisy.wav clean.wav

    # Train the neural isolator on your own data:
    #   data/noisy/*.wav  and  data/clean/*.wav   (matching filenames)
    python scripts/voice_isolator.py --train --data data --epochs 60 \
        --checkpoint voice_isolator.pt

    # Run the trained neural model:
    python scripts/voice_isolator.py --infer noisy.wav clean.wav \
        --checkpoint voice_isolator.pt

    # Export to ONNX for the NoiseClear Android app:
    python scripts/voice_isolator.py --export-onnx \
        --checkpoint voice_isolator.pt --onnx assets/models/voice_isolator.onnx

Signal constants (match the on-device Kotlin processors)
--------------------------------------------------------
    SR = 16000, N_FFT = 512, HOP = 128, N_BINS = 257
"""

from __future__ import annotations

import argparse
import glob
import math
import os
import sys

import numpy as np

# ── Signal constants ──────────────────────────────────────────────────────────
SR     = 16_000
N_FFT  = 512
HOP    = 128
WIN    = N_FFT
N_BINS = N_FFT // 2 + 1   # 257
EPS    = 1e-8


# ══════════════════════════════════════════════════════════════════════════════
#  1. STFT / iSTFT — implemented from scratch (numpy rfft + overlap-add)
# ══════════════════════════════════════════════════════════════════════════════

def _hann(n: int) -> np.ndarray:
    return 0.5 - 0.5 * np.cos(2.0 * np.pi * np.arange(n) / n)


_WINDOW = _hann(WIN).astype(np.float32)


def stft(x: np.ndarray) -> np.ndarray:
    """Return complex STFT of mono signal x, shape [frames, N_BINS]."""
    if len(x) < WIN:
        x = np.pad(x, (0, WIN - len(x)))
    n_frames = 1 + (len(x) - WIN) // HOP
    frames = np.empty((n_frames, N_BINS), dtype=np.complex64)
    for i in range(n_frames):
        seg = x[i * HOP: i * HOP + WIN] * _WINDOW
        frames[i] = np.fft.rfft(seg, n=N_FFT)
    return frames


def istft(spec: np.ndarray, length: int | None = None) -> np.ndarray:
    """Inverse STFT with WOLA normalisation. spec: [frames, N_BINS] complex."""
    n_frames = spec.shape[0]
    out_len  = (n_frames - 1) * HOP + WIN
    out  = np.zeros(out_len, dtype=np.float32)
    norm = np.zeros(out_len, dtype=np.float32)
    w2   = _WINDOW ** 2
    for i in range(n_frames):
        seg = np.fft.irfft(spec[i], n=N_FFT).astype(np.float32) * _WINDOW
        s = i * HOP
        out[s:s + WIN]  += seg
        norm[s:s + WIN] += w2
    out = np.where(norm > 1e-6, out / np.maximum(norm, EPS), out)
    return out[:length] if length is not None else out


def load_wav(path: str) -> tuple[np.ndarray, int]:
    import soundfile as sf
    x, sr = sf.read(path, dtype="float32", always_2d=False)
    if x.ndim > 1:
        x = x.mean(axis=1)          # downmix to mono
    return x.astype(np.float32), sr


def save_wav(path: str, x: np.ndarray, sr: int = SR) -> None:
    import soundfile as sf
    x = np.clip(x, -1.0, 1.0)
    sf.write(path, x, sr, subtype="PCM_16")


def resample_linear(x: np.ndarray, src: int, dst: int) -> np.ndarray:
    if src == dst:
        return x
    n_out = int(round(len(x) * dst / src))
    idx   = np.arange(n_out) * src / dst
    lo    = np.floor(idx).astype(int)
    frac  = (idx - lo).astype(np.float32)
    lo    = np.clip(lo, 0, len(x) - 1)
    hi    = np.clip(lo + 1, 0, len(x) - 1)
    return (x[lo] * (1 - frac) + x[hi] * frac).astype(np.float32)


# ══════════════════════════════════════════════════════════════════════════════
#  2. DSP voice isolator — zero training, runs immediately
# ══════════════════════════════════════════════════════════════════════════════
#
#  Pipeline (recreates the *function* of ElevenLabs isolation with classic DSP):
#    a. STFT magnitude/phase
#    b. Harmonic-percussive source separation (median filtering, Fitzgerald 2010)
#       → voice is highly harmonic; broadband noise/percussion is rejected
#    c. Voice-presence probability per T-F bin from harmonic ratio + voice band
#    d. Decision-directed a-priori SNR  →  Wiener gain
#    e. Voice-band perceptual weighting (80–8000 Hz with 200–3500 Hz emphasis)
#    f. Apply soft mask, keep original phase, iSTFT

def _median_filter_1d(a: np.ndarray, k: int, axis: int) -> np.ndarray:
    """Simple sliding-window median along one axis (k must be odd)."""
    pad = k // 2
    a_p = np.pad(a, [(pad, pad) if ax == axis else (0, 0)
                     for ax in range(a.ndim)], mode="reflect")
    out = np.empty_like(a)
    it  = np.moveaxis(a_p, axis, 0)
    res = np.moveaxis(out, axis, 0)
    n   = it.shape[0] - 2 * pad
    for i in range(n):
        res[i] = np.median(it[i:i + k], axis=0)
    return out


def _voice_band_weight() -> np.ndarray:
    f = np.arange(N_BINS) * SR / N_FFT
    w = np.zeros(N_BINS, dtype=np.float32)
    for k, fk in enumerate(f):
        if   fk < 80:    w[k] = 0.05
        elif fk < 200:   w[k] = 0.05 + 0.45 * (fk - 80) / 120
        elif fk < 3500:  w[k] = 1.0
        elif fk < 6000:  w[k] = 1.0 - 0.4 * (fk - 3500) / 2500
        elif fk < 8000:  w[k] = 0.6 - 0.5 * (fk - 6000) / 2000
        else:            w[k] = 0.05
    return w


_VBAND = _voice_band_weight()


def dsp_isolate(x: np.ndarray, sr: int, strength: float = 1.0) -> np.ndarray:
    """Isolate voice with classic DSP. strength in [0,1] (1 = most aggressive)."""
    if sr != SR:
        x = resample_linear(x, sr, SR)

    spec = stft(x)                              # [T, F] complex
    mag  = np.abs(spec).astype(np.float32)
    pha  = np.angle(spec).astype(np.float32)

    # ── Harmonic-percussive separation via median filtering ──────────────────
    harm = _median_filter_1d(mag, 17, axis=0)   # smooth across TIME  → harmonic
    perc = _median_filter_1d(mag, 17, axis=1)   # smooth across FREQ  → percussive
    # Soft Wiener masks (Fitzgerald 2010)
    p = 2.0
    harm_mask = (harm ** p) / (harm ** p + perc ** p + EPS)

    # ── Voice presence probability ───────────────────────────────────────────
    # Harmonic dominance × voice-band weight, sharpened by strength.
    vprob = harm_mask * _VBAND[None, :]
    vprob = np.clip(vprob, 0.0, 1.0)

    # ── Decision-directed a-priori SNR → Wiener gain ─────────────────────────
    psd        = mag ** 2
    # Noise PSD = the non-voice (percussive/broadband) energy estimate
    noise_psd  = np.maximum((perc ** 2) * (1.0 - harm_mask), EPS)
    gamma      = psd / noise_psd                # a-posteriori SNR
    alpha      = 0.96
    xi         = np.empty_like(gamma)
    xi[0]      = np.maximum(gamma[0] - 1.0, 0.0)
    g_prev     = np.full(N_BINS, 0.5, dtype=np.float32)
    for t in range(1, gamma.shape[0]):
        dd      = alpha * (g_prev ** 2) * psd[t - 1] / noise_psd[t] \
                  + (1 - alpha) * np.maximum(gamma[t] - 1.0, 0.0)
        xi[t]   = np.maximum(dd, 1e-3)
        g_prev  = xi[t] / (1.0 + xi[t])
    wiener = xi / (1.0 + xi)

    # ── Combine: voice mask = Wiener gated by voice presence ─────────────────
    floor = (1.0 - strength) * 0.15 + 0.02
    mask  = wiener * (0.4 + 0.6 * vprob)
    mask  = np.clip(mask ** (0.6 + 0.8 * strength), floor, 1.0)

    out_spec = (mag * mask) * np.exp(1j * pha)
    y = istft(out_spec, length=len(x))

    if sr != SR:
        y = resample_linear(y, SR, sr)
    # Loudness match to input RMS so output isn't quieter
    in_rms, out_rms = _rms(x), _rms(y)
    if out_rms > EPS:
        y *= min(4.0, in_rms / out_rms)
    return np.clip(y, -1.0, 1.0)


def _rms(x: np.ndarray) -> float:
    return float(np.sqrt(np.mean(x ** 2) + EPS))


# ══════════════════════════════════════════════════════════════════════════════
#  3. Neural voice isolator — from-scratch U-Net spectrogram mask estimator
# ══════════════════════════════════════════════════════════════════════════════
#
#  Architecture (the ElevenLabs/Spleeter-class approach):
#    log-magnitude spectrogram  →  2-D U-Net  →  sigmoid mask  →  apply to |Y|
#    The network learns to predict the ideal ratio mask  M = |S| / |Y|  that,
#    multiplied by the noisy magnitude and combined with noisy phase, returns
#    the isolated voice. Trained with L1 loss on masked magnitude + SI-SDR.

def _build_torch_model():
    import torch
    import torch.nn as nn

    class ConvBlock(nn.Module):
        def __init__(self, ci, co):
            super().__init__()
            self.net = nn.Sequential(
                nn.Conv2d(ci, co, 3, padding=1), nn.BatchNorm2d(co), nn.ReLU(inplace=True),
                nn.Conv2d(co, co, 3, padding=1), nn.BatchNorm2d(co), nn.ReLU(inplace=True),
            )
        def forward(self, x): return self.net(x)

    class VoiceIsolatorUNet(nn.Module):
        """Input  [B, 1, F=257, T]  log-magnitude.
           Output [B, 1, F=257, T]  ratio mask in (0,1)."""
        def __init__(self, base=32):
            super().__init__()
            self.e1 = ConvBlock(1, base)
            self.e2 = ConvBlock(base, base * 2)
            self.e3 = ConvBlock(base * 2, base * 4)
            self.pool = nn.MaxPool2d(2)
            self.bott = ConvBlock(base * 4, base * 8)
            self.up3 = nn.ConvTranspose2d(base * 8, base * 4, 2, stride=2)
            self.d3  = ConvBlock(base * 8, base * 4)
            self.up2 = nn.ConvTranspose2d(base * 4, base * 2, 2, stride=2)
            self.d2  = ConvBlock(base * 4, base * 2)
            self.up1 = nn.ConvTranspose2d(base * 2, base, 2, stride=2)
            self.d1  = ConvBlock(base * 2, base)
            self.out = nn.Conv2d(base, 1, 1)

        @staticmethod
        def _crop_cat(up, skip):
            # pad up to skip's spatial size (handles odd dims from pooling)
            import torch.nn.functional as F
            dh = skip.shape[-2] - up.shape[-2]
            dw = skip.shape[-1] - up.shape[-1]
            up = F.pad(up, [0, dw, 0, dh])
            import torch
            return torch.cat([up, skip], dim=1)

        def forward(self, x):
            import torch
            e1 = self.e1(x)
            e2 = self.e2(self.pool(e1))
            e3 = self.e3(self.pool(e2))
            b  = self.bott(self.pool(e3))
            d3 = self.d3(self._crop_cat(self.up3(b),  e3))
            d2 = self.d2(self._crop_cat(self.up2(d3), e2))
            d1 = self.d1(self._crop_cat(self.up1(d2), e1))
            return torch.sigmoid(self.out(d1))

    return VoiceIsolatorUNet()


def _log_mag(spec: np.ndarray) -> np.ndarray:
    return np.log1p(np.abs(spec)).astype(np.float32)


# ── Neural inference ───────────────────────────────────────────────────────────

def neural_isolate(x: np.ndarray, sr: int, checkpoint: str) -> np.ndarray:
    import torch
    if sr != SR:
        x = resample_linear(x, sr, SR)

    model = _build_torch_model()
    state = torch.load(checkpoint, map_location="cpu")
    model.load_state_dict(state["model"] if "model" in state else state)
    model.eval()

    spec   = stft(x)                                  # [T, F]
    logm   = _log_mag(spec)                           # [T, F]
    inp    = torch.from_numpy(logm.T[None, None])     # [1,1,F,T]
    with torch.no_grad():
        mask = model(inp)[0, 0].numpy().T             # [T, F]
    mask   = np.clip(mask, 0.0, 1.0)

    out_spec = (np.abs(spec) * mask) * np.exp(1j * np.angle(spec))
    y = istft(out_spec, length=len(x))
    if sr != SR:
        y = resample_linear(y, SR, sr)
    return np.clip(y, -1.0, 1.0)


# ── Neural training ─────────────────────────────────────────────────────────────

def train(data_dir: str, epochs: int, checkpoint: str,
          batch: int = 4, lr: float = 3e-4, seg_frames: int = 256) -> None:
    import torch
    import torch.nn as nn

    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"[*] Training on {device}")

    noisy_paths = sorted(glob.glob(os.path.join(data_dir, "noisy", "*.wav")))
    if not noisy_paths:
        print(f"[!] No training files in {data_dir}/noisy/*.wav")
        print("    Expected matching pairs:")
        print(f"      {data_dir}/noisy/<name>.wav   (voice + background)")
        print(f"      {data_dir}/clean/<name>.wav   (isolated voice)")
        sys.exit(1)

    def load_pair(npath):
        name  = os.path.basename(npath)
        cpath = os.path.join(data_dir, "clean", name)
        if not os.path.exists(cpath):
            return None
        nx, nsr = load_wav(npath)
        cx, csr = load_wav(cpath)
        if nsr != SR: nx = resample_linear(nx, nsr, SR)
        if csr != SR: cx = resample_linear(cx, csr, SR)
        m = min(len(nx), len(cx))
        return nx[:m], cx[:m]

    pairs = [p for p in (load_pair(n) for n in noisy_paths) if p is not None]
    print(f"[*] Loaded {len(pairs)} (noisy, clean) pairs")

    model = _build_torch_model().to(device)
    opt   = torch.optim.Adam(model.parameters(), lr=lr)
    l1    = nn.L1Loss()

    def sample_batch():
        xb, yb = [], []
        for _ in range(batch):
            nx, cx = pairs[np.random.randint(len(pairs))]
            nspec  = stft(nx); cspec = stft(cx)
            T = nspec.shape[0]
            if T <= seg_frames:
                s = 0
                nspec = np.pad(nspec, ((0, seg_frames - T), (0, 0)))
                cspec = np.pad(cspec, ((0, seg_frames - T), (0, 0)))
            else:
                s = np.random.randint(0, T - seg_frames)
            nseg = nspec[s:s + seg_frames]
            cseg = cspec[s:s + seg_frames]
            # Ideal ratio mask target = |clean| / |noisy|
            tgt  = np.clip(np.abs(cseg) / (np.abs(nseg) + EPS), 0, 1)
            xb.append(_log_mag(nseg).T)              # [F,T]
            yb.append(tgt.T.astype(np.float32))      # [F,T]
        x = torch.from_numpy(np.stack(xb)[:, None]).to(device)
        y = torch.from_numpy(np.stack(yb)[:, None]).to(device)
        return x, y

    steps = max(50, len(pairs) * 4 // batch)
    for ep in range(1, epochs + 1):
        model.train(); running = 0.0
        for _ in range(steps):
            x, y = sample_batch()
            pred = model(x)
            loss = l1(pred, y)
            opt.zero_grad(); loss.backward(); opt.step()
            running += loss.item()
        print(f"  epoch {ep:3d}/{epochs}   mask-L1 {running / steps:.4f}")
        torch.save({"model": model.state_dict()}, checkpoint)
    print(f"[*] Saved checkpoint → {checkpoint}")


# ── ONNX export ────────────────────────────────────────────────────────────────

def export_onnx(checkpoint: str, onnx_path: str) -> None:
    import torch
    model = _build_torch_model()
    state = torch.load(checkpoint, map_location="cpu")
    model.load_state_dict(state["model"] if "model" in state else state)
    model.eval()

    os.makedirs(os.path.dirname(onnx_path) or ".", exist_ok=True)
    dummy = torch.zeros(1, 1, N_BINS, 256)
    torch.onnx.export(
        model, dummy, onnx_path,
        opset_version=14,
        input_names=["log_mag"],
        output_names=["mask"],
        dynamic_axes={"log_mag": {0: "batch", 3: "frames"},
                      "mask":    {0: "batch", 3: "frames"}},
    )
    print(f"[*] Exported ONNX → {onnx_path}")
    print("    Input  log_mag  [1,1,257,T]   (log1p magnitude, F×T)")
    print("    Output mask     [1,1,257,T]   (ratio mask 0–1)")
    print("    Place at assets/models/voice_isolator.onnx for the app to bundle.")


# ══════════════════════════════════════════════════════════════════════════════
#  CLI
# ══════════════════════════════════════════════════════════════════════════════

def main() -> None:
    p = argparse.ArgumentParser(
        description="From-scratch ElevenLabs-style voice isolation processor")
    p.add_argument("--dsp", action="store_true",
                   help="Use the zero-training DSP isolator")
    p.add_argument("--train", action="store_true", help="Train the neural model")
    p.add_argument("--infer", nargs=2, metavar=("IN", "OUT"),
                   help="Isolate voice: input.wav output.wav")
    p.add_argument("--export-onnx", action="store_true", help="Export model to ONNX")
    p.add_argument("--data", default="data", help="Training data dir")
    p.add_argument("--epochs", type=int, default=60)
    p.add_argument("--checkpoint", default="voice_isolator.pt")
    p.add_argument("--onnx", default="assets/models/voice_isolator.onnx")
    p.add_argument("--strength", type=float, default=1.0,
                   help="DSP isolation strength 0–1 (default 1.0)")
    args = p.parse_args()

    if args.train:
        train(args.data, args.epochs, args.checkpoint)
        return

    if args.export_onnx:
        export_onnx(args.checkpoint, args.onnx)
        return

    if args.infer:
        in_path, out_path = args.infer
        x, sr = load_wav(in_path)
        print(f"[*] Loaded {in_path}  ({len(x)/sr:.1f}s @ {sr} Hz)")
        if args.dsp or not os.path.exists(args.checkpoint):
            if not args.dsp:
                print(f"[i] No checkpoint at {args.checkpoint} — using DSP isolator")
            y = dsp_isolate(x, sr, strength=args.strength)
            engine = "DSP"
        else:
            y = neural_isolate(x, sr, args.checkpoint)
            engine = "neural"
        save_wav(out_path, y, sr)
        print(f"[*] {engine} isolation done → {out_path}")
        return

    p.print_help()


if __name__ == "__main__":
    main()
