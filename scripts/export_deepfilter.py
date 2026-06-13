"""
export_deepfilter.py — Download DeepFilterNet2 pretrained weights and export to ONNX.

Usage
-----
    # Full export (downloads ~50 MB of pretrained weights automatically):
    pip install deepfilterlib onnxruntime
    python scripts/export_deepfilter.py --output assets/models

    # Inspect an existing export to get exact tensor names:
    python scripts/export_deepfilter.py --inspect assets/models

The script produces 3 ONNX files in the output directory:
    enc.onnx        ~5 MB  — encoder with GRU (produces embedding + skip features)
    erb_dec.onnx    ~1 MB  — ERB-domain magnitude gain predictor
    df_dec.onnx     ~2 MB  — deep-filtering complex coefficient predictor

These files are placed in assets/models/ which Flutter bundles into the APK.
On first launch, DeepFilterProcessor.kt extracts them from
    flutter_assets/assets/models/*.onnx
into the app's cache directory and loads them with ONNX Runtime Android.

References
----------
    DeepFilterNet2 paper: https://arxiv.org/abs/2205.05474
    Repository:           https://github.com/Rikorose/DeepFilterNet
    deepfilterlib:        https://pypi.org/project/deepfilterlib/
"""

from __future__ import annotations

import argparse
import pathlib
import sys


def inspect_models(model_dir: str) -> None:
    """Print tensor names and shapes for all 3 ONNX models."""
    try:
        import onnxruntime as ort
    except ImportError:
        print("[!] pip install onnxruntime  first"); sys.exit(1)

    for name in ["enc", "erb_dec", "df_dec"]:
        path = f"{model_dir}/{name}.onnx"
        if not pathlib.Path(path).exists():
            print(f"[!] {path} not found"); continue
        sess = ort.InferenceSession(path, providers=["CPUExecutionProvider"])
        print(f"\n{'─'*60}")
        print(f"  {name}.onnx")
        print(f"  Inputs:")
        for i in sess.get_inputs():
            print(f"    [{i.name}]  shape={i.shape}  type={i.type}")
        print(f"  Outputs:")
        for o in sess.get_outputs():
            print(f"    [{o.name}]  shape={o.shape}  type={o.type}")


def export(output_dir: str) -> None:
    """
    Download DeepFilterNet2 pretrained weights and export 3 ONNX streaming models.
    Requires: pip install deepfilterlib onnxruntime
    """
    try:
        from df import init_df
        from df.model import ModelExportWrapper
    except ImportError:
        print("[!] deepfilterlib not installed.")
        print("    Run:  pip install deepfilterlib")
        sys.exit(1)

    import torch
    import onnx

    print("[1/4] Loading DeepFilterNet2 pretrained model …")
    model, df_state, _ = init_df()   # downloads weights on first run (~50 MB)
    model.eval()

    out = pathlib.Path(output_dir)
    out.mkdir(parents=True, exist_ok=True)

    print("[2/4] Wrapping model for streaming ONNX export …")
    # ModelExportWrapper splits the model into the 3 streaming sub-networks
    # and handles stateful GRU hidden-state I/O.
    try:
        wrapper = ModelExportWrapper(model, df_state)
    except Exception as e:
        print(f"[!] ModelExportWrapper failed: {e}")
        print("    Trying manual sub-module export …")
        _export_manual(model, df_state, out)
        return

    sr        = df_state.sr()
    fft_size  = df_state.fft_size()
    hop_size  = df_state.hop_size()
    nb_erb    = df_state.nb_erb()
    nb_df     = df_state.nb_df()
    df_order  = df_state.df_order()

    print(f"    sr={sr}  fft={fft_size}  hop={hop_size}"
          f"  nb_erb={nb_erb}  nb_df={nb_df}  df_order={df_order}")

    # Dummy inputs for tracing
    spec     = torch.zeros(1, nb_df, 2)     # [B, NB_DF, 2]
    feat_erb = torch.zeros(1, nb_erb)        # [B, NB_ERB]

    print("[3/4] Exporting enc.onnx …")
    torch.onnx.export(
        wrapper.enc, (spec, feat_erb, *wrapper.enc_hidden_init()),
        str(out / "enc.onnx"),
        opset_version=17,
        input_names  = wrapper.enc_input_names(),
        output_names = wrapper.enc_output_names(),
        dynamic_axes = {},  # static shapes for TFLite-style mobile inference
    )

    print("[3/4] Exporting erb_dec.onnx …")
    emb_size = wrapper.enc.emb_size
    emb      = torch.zeros(1, emb_size)
    torch.onnx.export(
        wrapper.erb_dec,
        (emb, *wrapper.erb_dec_skip_inputs(), *wrapper.erb_dec_hidden_init()),
        str(out / "erb_dec.onnx"),
        opset_version=17,
        input_names  = wrapper.erb_dec_input_names(),
        output_names = wrapper.erb_dec_output_names(),
        dynamic_axes = {},
    )

    print("[3/4] Exporting df_dec.onnx …")
    c0 = torch.zeros(1, nb_df * 2)
    torch.onnx.export(
        wrapper.df_dec,
        (emb, c0, *wrapper.df_dec_hidden_init()),
        str(out / "df_dec.onnx"),
        opset_version=17,
        input_names  = wrapper.df_dec_input_names(),
        output_names = wrapper.df_dec_output_names(),
        dynamic_axes = {},
    )

    print("[4/4] Verifying exported models …")
    inspect_models(str(out))

    print(f"\n[✓] Done!  Models saved to {out.resolve()}")
    print("    Copy these 3 files to assets/models/ in your Flutter project.")
    print("    The Kotlin DeepFilterProcessor auto-discovers tensor names at runtime.")


def _export_manual(model, df_state, out: pathlib.Path) -> None:
    """
    Fallback: export via direct sub-module tracing for older deepfilterlib versions.
    """
    import torch

    nb_erb   = df_state.nb_erb()
    nb_df    = df_state.nb_df()

    enc      = model.enc.eval()
    erb_dec  = model.erb_dec.eval()
    df_dec   = model.df_dec.eval()

    # Encoder
    spec_in  = torch.zeros(1, 1, nb_df, 2)
    erb_in   = torch.zeros(1, 1, nb_erb)
    h_enc0   = torch.zeros(1, 1, 256)
    h_enc1   = torch.zeros(1, 1, 256)
    torch.onnx.export(enc, (spec_in, erb_in, h_enc0, h_enc1), str(out / "enc.onnx"),
                      opset_version=17, dynamic_axes={})

    # ERB decoder — feed dummy embedding
    emb_size = 256
    emb      = torch.zeros(1, 1, emb_size)
    h0       = torch.zeros(1, 1, 64)
    h1       = torch.zeros(1, 1, 64)
    torch.onnx.export(erb_dec, (emb, h0, h1), str(out / "erb_dec.onnx"),
                      opset_version=17, dynamic_axes={})

    # DF decoder
    c0 = torch.zeros(1, 1, nb_df, 2)
    torch.onnx.export(df_dec, (emb, c0, h0, h1), str(out / "df_dec.onnx"),
                      opset_version=17, dynamic_axes={})

    inspect_models(str(out))
    print(f"[✓] Manual export complete → {out.resolve()}")


def main() -> None:
    p = argparse.ArgumentParser(description="Export DeepFilterNet2 → ONNX for Android")
    p.add_argument("--output",  default="assets/models", help="Output directory")
    p.add_argument("--inspect", metavar="DIR", default=None,
                   help="Inspect existing ONNX models in DIR and print tensor names")
    args = p.parse_args()

    if args.inspect:
        inspect_models(args.inspect)
    else:
        export(args.output)


if __name__ == "__main__":
    main()
