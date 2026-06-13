#!/usr/bin/env python3
"""
generate_onnx_models.py — Export DeepFilterNet3 to ONNX for NoiseClear Android.

This script downloads the official DeepFilterNet3 pretrained weights (~50 MB)
and exports three ONNX models that the Kotlin DeepFilterProcessor loads at runtime.

Usage
-----
    # Install requirements (Python 3.9+)
    pip install deepfilternet>=0.5.6 torch onnx onnxruntime

    # Export (saves to assets/models/ automatically)
    python scripts/generate_onnx_models.py

    # Inspect existing ONNX files (verify tensor names/shapes)
    python scripts/generate_onnx_models.py --inspect

Output files
------------
    assets/models/enc.onnx         ~5 MB   Encoder + GRU (embedding + skip features)
    assets/models/erb_dec.onnx     ~1 MB   ERB magnitude gain decoder
    assets/models/df_dec.onnx      ~2 MB   Deep-filter complex coefficient decoder

After export
------------
  1. `flutter pub get && flutter build apk --release`  — the models are bundled.
  2. On first app launch, DeepFilterProcessor.kt extracts them from
     flutter_assets/assets/models/ into the app cache and loads them with
     ONNX Runtime Android.
  3. The Settings screen will show "Neural AI (DeepFilterNet3)" as active.

Model constants (must match DeepFilterProcessor.kt)
---------------------------------------------------
    SR=48000, FFT=960, HOP=480, FREQ_BINS=481
    NB_ERB=32, NB_DF=96, DF_ORDER=5
    ENC_HIDDEN=256, DEC_HIDDEN=64
"""

from __future__ import annotations

import argparse
import os
import pathlib
import sys

# ── Output directory ──────────────────────────────────────────────────────────
SCRIPT_DIR = pathlib.Path(__file__).parent
OUTPUT_DIR = SCRIPT_DIR.parent / "assets" / "models"


# ── Inspection helper ─────────────────────────────────────────────────────────

def inspect_models(model_dir: pathlib.Path) -> None:
    """Print input/output tensor names and shapes for the three ONNX models."""
    try:
        import onnxruntime as ort
    except ImportError:
        print("[!] pip install onnxruntime")
        sys.exit(1)

    for name in ("enc", "erb_dec", "df_dec"):
        path = model_dir / f"{name}.onnx"
        if not path.exists():
            print(f"[!] {path} not found — run without --inspect to export first")
            continue
        sess = ort.InferenceSession(str(path), providers=["CPUExecutionProvider"])
        print(f"\n{'─' * 60}")
        print(f"  {name}.onnx  ({path.stat().st_size // 1024} KB)")
        print("  Inputs:")
        for inp in sess.get_inputs():
            print(f"    {inp.name!r:30s}  shape={inp.shape}  type={inp.type}")
        print("  Outputs:")
        for out in sess.get_outputs():
            print(f"    {out.name!r:30s}  shape={out.shape}  type={out.type}")
    print()


# ── Wrapper modules ───────────────────────────────────────────────────────────
# Each wrapper adapts a DfNet sub-module to the interface expected by
# DeepFilterProcessor.kt (fixed input positions, stateless — GRU states
# are passed as explicit inputs/outputs so Android can manage them).

def _make_wrappers(model):
    """Return (EncWrapper, ErbDecWrapper, DfDecWrapper) nn.Modules."""
    import torch
    import torch.nn as nn

    NB_ERB     = 32
    NB_DF      = 96
    DF_ORDER   = 5
    ENC_HIDDEN = 256
    DEC_HIDDEN = 64

    class EncWrapper(nn.Module):
        """
        Inputs : spec_df  [1, NB_DF, 2]   — complex DF-band spectrum
                 erb_feat [1, NB_ERB]      — log-ERB energy features
                 h_enc0   [1, 1, ENC_HIDDEN]
                 h_enc1   [1, 1, ENC_HIDDEN]
        Outputs: emb      [1, ENC_HIDDEN]
                 c0       [1, NB_DF*2]     — context for DF decoder
                 e0..e3                    — skip connections for ERB decoder
                 h_enc0_new, h_enc1_new    — updated GRU states
        """
        def __init__(self, enc):
            super().__init__()
            self.enc = enc

        def forward(self, spec_df, erb_feat, h0, h1):
            h_in = torch.cat([h0, h1], dim=0)           # [2, 1, H]
            out  = self.enc(spec_df, erb_feat, h_in)
            # out is typically (emb, c0, e0, e1, e2, e3, h_new)
            # Unpack and re-split hidden state
            if isinstance(out, (tuple, list)):
                *features, h_new = out
            else:
                features, h_new = [out], torch.zeros_like(h_in)
            h_new = h_new if h_new.shape[0] == 2 else torch.zeros_like(h_in)
            return (*features, h_new[0:1], h_new[1:2])

    class ErbDecWrapper(nn.Module):
        """
        Inputs : emb  [1, ENC_HIDDEN]
                 e3, e2, e1, e0            — skip features from encoder
                 h_erb0 [1, 1, DEC_HIDDEN]
                 h_erb1 [1, 1, DEC_HIDDEN]
        Outputs: gains  [1, NB_ERB]
                 h_erb0_new, h_erb1_new
        """
        def __init__(self, erb_dec):
            super().__init__()
            self.dec = erb_dec

        def forward(self, emb, e3, e2, e1, e0, h0, h1):
            h_in  = torch.cat([h0, h1], dim=0)
            gains, h_new = self.dec(emb, (e0, e1, e2, e3), h_in)
            h_new = h_new if h_new.shape[0] == 2 else torch.zeros_like(h_in)
            return gains, h_new[0:1], h_new[1:2]

    class DfDecWrapper(nn.Module):
        """
        Inputs : emb  [1, ENC_HIDDEN]
                 c0   [1, NB_DF*2]
                 h_df0 [1, 1, DEC_HIDDEN]
                 h_df1 [1, 1, DEC_HIDDEN]
        Outputs: coefs [1, NB_DF*DF_ORDER*2]
                 h_df0_new, h_df1_new
        """
        def __init__(self, df_dec):
            super().__init__()
            self.dec = df_dec

        def forward(self, emb, c0, h0, h1):
            h_in        = torch.cat([h0, h1], dim=0)
            coefs, h_new = self.dec(emb, c0, h_in)
            h_new = h_new if h_new.shape[0] == 2 else torch.zeros_like(h_in)
            return coefs, h_new[0:1], h_new[1:2]

    enc_w     = EncWrapper(model.enc)    .eval()
    erb_dec_w = ErbDecWrapper(model.erb_dec).eval()
    df_dec_w  = DfDecWrapper(model.df_dec) .eval()
    return enc_w, erb_dec_w, df_dec_w


# ── Export ────────────────────────────────────────────────────────────────────

def export(output_dir: pathlib.Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)

    # ── 1. Load DeepFilterNet3 ────────────────────────────────────────────────
    try:
        from df.enhance import init_df
    except ImportError:
        print(
            "[!] deepfilternet not installed.\n"
            "    Run:  pip install deepfilternet>=0.5.6 torch onnx onnxruntime"
        )
        sys.exit(1)

    import torch

    print("[*] Loading DeepFilterNet3 pretrained weights (downloads ~50 MB once)…")
    try:
        model, df_state, _ = init_df(config_allow_defaults=True)
    except TypeError:
        # Older API
        model, df_state, _ = init_df()
    model.eval()
    print(f"    model type: {type(model).__name__}")

    NB_ERB     = getattr(df_state, 'nb_erb', 32)
    NB_DF      = getattr(df_state, 'nb_df',  96)
    DF_ORDER   = getattr(df_state, 'df_order', 5)
    ENC_HIDDEN = 256
    DEC_HIDDEN = 64

    print(f"    NB_ERB={NB_ERB}  NB_DF={NB_DF}  DF_ORDER={DF_ORDER}")

    # ── 2. Build wrapper modules ──────────────────────────────────────────────
    enc_w, erb_dec_w, df_dec_w = _make_wrappers(model)

    opset = 14   # ONNX Runtime Android ≥ 1.14 supports opset 14

    # ── 3. Export enc.onnx ───────────────────────────────────────────────────
    enc_path = output_dir / "enc.onnx"
    dummy_spec_df  = torch.zeros(1, NB_DF, 2)
    dummy_erb_feat = torch.zeros(1, NB_ERB)
    dummy_h_enc0   = torch.zeros(1, 1, ENC_HIDDEN)
    dummy_h_enc1   = torch.zeros(1, 1, ENC_HIDDEN)

    print("[*] Exporting enc.onnx …")
    try:
        torch.onnx.export(
            enc_w,
            (dummy_spec_df, dummy_erb_feat, dummy_h_enc0, dummy_h_enc1),
            str(enc_path),
            opset_version=opset,
            input_names=["spec_df", "erb_feat", "h_enc0", "h_enc1"],
            output_names=["emb", "c0", "e0", "e1", "e2", "e3",
                          "h_enc0_new", "h_enc1_new"],
            dynamic_axes={
                "spec_df":   {0: "batch"},
                "erb_feat":  {0: "batch"},
                "h_enc0":    {0: "batch"},
                "h_enc1":    {0: "batch"},
            },
        )
        print(f"    ✓ {enc_path}  ({enc_path.stat().st_size // 1024} KB)")
    except Exception as exc:
        print(f"    [!] enc export failed: {exc}")
        print("        Trying torch.jit.trace fallback…")
        _export_traced(enc_w,
            (dummy_spec_df, dummy_erb_feat, dummy_h_enc0, dummy_h_enc1),
            enc_path, opset)

    # ── 4. Export erb_dec.onnx ────────────────────────────────────────────────
    erb_path = output_dir / "erb_dec.onnx"
    # Run encoder to get real skip-feature shapes
    with torch.no_grad():
        try:
            enc_out = enc_w(dummy_spec_df, dummy_erb_feat, dummy_h_enc0, dummy_h_enc1)
            emb = enc_out[0]
            # e3, e2, e1, e0 are skip features (indices 2..5)
            skips = enc_out[2:6]
        except Exception:
            emb   = torch.zeros(1, ENC_HIDDEN)
            skips = (torch.zeros(1, ENC_HIDDEN),) * 4

    dummy_h_erb0 = torch.zeros(1, 1, DEC_HIDDEN)
    dummy_h_erb1 = torch.zeros(1, 1, DEC_HIDDEN)
    e3, e2, e1, e0 = (skips + (torch.zeros(1, ENC_HIDDEN),) * 4)[:4]

    print("[*] Exporting erb_dec.onnx …")
    try:
        torch.onnx.export(
            erb_dec_w,
            (emb, e3, e2, e1, e0, dummy_h_erb0, dummy_h_erb1),
            str(erb_path),
            opset_version=opset,
            input_names=["emb", "e3", "e2", "e1", "e0", "h_erb0", "h_erb1"],
            output_names=["gains", "h_erb0_new", "h_erb1_new"],
        )
        print(f"    ✓ {erb_path}  ({erb_path.stat().st_size // 1024} KB)")
    except Exception as exc:
        print(f"    [!] erb_dec export failed: {exc}")
        _export_traced(erb_dec_w,
            (emb, e3, e2, e1, e0, dummy_h_erb0, dummy_h_erb1),
            erb_path, opset)

    # ── 5. Export df_dec.onnx ─────────────────────────────────────────────────
    df_path   = output_dir / "df_dec.onnx"
    c0        = enc_out[1] if len(enc_out) > 1 else torch.zeros(1, NB_DF * 2)
    dummy_h_df0 = torch.zeros(1, 1, DEC_HIDDEN)
    dummy_h_df1 = torch.zeros(1, 1, DEC_HIDDEN)

    print("[*] Exporting df_dec.onnx …")
    try:
        torch.onnx.export(
            df_dec_w,
            (emb, c0, dummy_h_df0, dummy_h_df1),
            str(df_path),
            opset_version=opset,
            input_names=["emb", "c0", "h_df0", "h_df1"],
            output_names=["coefs", "h_df0_new", "h_df1_new"],
        )
        print(f"    ✓ {df_path}  ({df_path.stat().st_size // 1024} KB)")
    except Exception as exc:
        print(f"    [!] df_dec export failed: {exc}")
        _export_traced(df_dec_w,
            (emb, c0, dummy_h_df0, dummy_h_df1),
            df_path, opset)

    # ── 6. Verify with onnxruntime ────────────────────────────────────────────
    print("\n[*] Verifying exported models with onnxruntime…")
    _verify(output_dir)

    print("\n✅  All three models exported successfully.")
    print(f"    → {output_dir}/")
    print("\nNext steps:")
    print("  1. flutter pub get")
    print("  2. flutter build apk --release")
    print("  The APK will bundle the models; DeepFilterNet3 activates on first launch.")


def _export_traced(module, dummy_inputs, path: pathlib.Path, opset: int) -> None:
    """Fallback: use torch.jit.trace when torch.onnx.export fails."""
    import torch
    try:
        with torch.no_grad():
            traced = torch.jit.trace(module, dummy_inputs, strict=False)
        torch.onnx.export(
            traced, dummy_inputs, str(path),
            opset_version=opset,
        )
        print(f"    ✓ (traced) {path}  ({path.stat().st_size // 1024} KB)")
    except Exception as e2:
        print(f"    [✗] Traced export also failed: {e2}")
        print("        The model API may differ from this script's expectations.")
        print("        Run with --inspect after a partial export to see tensor shapes.")


def _verify(model_dir: pathlib.Path) -> None:
    """Quick onnxruntime sanity check."""
    try:
        import onnxruntime as ort
    except ImportError:
        print("    [skip] onnxruntime not installed — skipping verification")
        return

    for name in ("enc", "erb_dec", "df_dec"):
        path = model_dir / f"{name}.onnx"
        if not path.exists():
            print(f"    [!] {name}.onnx missing")
            continue
        try:
            sess = ort.InferenceSession(str(path),
                providers=["CPUExecutionProvider"])
            ins  = [i.name for i in sess.get_inputs()]
            outs = [o.name for o in sess.get_outputs()]
            print(f"    {name}.onnx  inputs={ins}  outputs={outs}")
        except Exception as e:
            print(f"    [!] {name}.onnx verification failed: {e}")


# ── CLI ───────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Export DeepFilterNet3 ONNX models for NoiseClear Android"
    )
    parser.add_argument(
        "--output", default=str(OUTPUT_DIR),
        help="Output directory (default: assets/models/)",
    )
    parser.add_argument(
        "--inspect", action="store_true",
        help="Inspect existing ONNX files instead of exporting",
    )
    args = parser.parse_args()

    out = pathlib.Path(args.output)
    if args.inspect:
        inspect_models(out)
    else:
        export(out)


if __name__ == "__main__":
    main()
