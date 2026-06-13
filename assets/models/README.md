# DeepFilterNet3 model files (REQUIRED for neural denoising)

The neural engine needs **3 ONNX files** placed in this folder:

```
assets/models/enc.onnx        (~15 MB)   encoder
assets/models/erb_dec.onnx    (~12 MB)   ERB decoder (magnitude gains)
assets/models/df_dec.onnx     (~13 MB)   deep-filter decoder (complex filter)
```

Until these files are present, the app falls back to the on-device MMSE-STSA
filter (good, ~65-80 %), NOT the studio-grade DeepFilterNet3 (~85-90 %).
**I cannot generate these files — they are trained neural weights (data, not code).**

## Where to get them

DeepFilterNet3 is open source (MIT/Apache). Get the ONNX exports from the
official project:

- Repo:    https://github.com/Rikorose/DeepFilterNet
- Models:  https://github.com/Rikorose/DeepFilterNet/tree/main/models/DeepFilterNet3

Export to ONNX with the project's `df/scripts/export.py` (produces
`enc.onnx`, `erb_dec.onnx`, `df_dec.onnx`), or download a pre-exported ONNX
bundle from the releases, then copy the three files here.

## After adding the files

```
flutter clean
flutter pub get
flutter build apk --release
```

The Kotlin side (`DeepFilterProcessor.kt`) auto-extracts them from
`flutter_assets/assets/models/` into the app cache on first launch.

> Tier behaviour:
> - Free users  → single neural pass ("Clean")
> - Pro / admin → 2-pass Voice Isolator ("Isolate Voice")
