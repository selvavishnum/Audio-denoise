import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

/// Genuine on-device NEURAL speech denoiser.
///
/// Runs the GTCRN model (Group-wise Temporal Convolutional Recurrent Network)
/// — a trained neural network for speech enhancement — through sherpa_onnx /
/// ONNX Runtime via FFI. Unlike the DSP fallbacks (MMSE-STSA, OMLSA-IMCRA),
/// this is an actual neural model, so it removes far more noise and is honestly
/// labelled "Neural AI".
///
/// The model (~0.5 MB) is bundled in assets/models/gtcrn_simple.onnx, so neural
/// denoising works out of the box, fully offline, with no download. It uses
/// sherpa's own bundled libonnxruntime.so over a reliable FFI path — no large
/// PCM transfer over a MethodChannel (which is why the old native built-in
/// path silently fell back to DSP on real-length clips).
class NeuralDenoiserService {
  static const String _asset = 'assets/models/gtcrn_simple.onnx';
  static const int _modelRate = 16000; // GTCRN expects 16 kHz mono

  static bool _bindingsInited = false;
  static bool _initTried = false;
  static sherpa_onnx.OfflineSpeechDenoiser? _denoiser;

  static bool get isReady => _denoiser != null;

  /// Copy the bundled model to a real file and create the denoiser. Idempotent.
  static Future<bool> initialize() async {
    if (_denoiser != null) return true;
    if (_initTried) return _denoiser != null;
    _initTried = true;
    try {
      if (!_bindingsInited) {
        sherpa_onnx.initBindings();
        _bindingsInited = true;
      }
      final dir = await getApplicationSupportDirectory();
      final modelPath = '${dir.path}/gtcrn_simple.onnx';
      final f = File(modelPath);
      if (!f.existsSync() || f.lengthSync() == 0) {
        final data = await rootBundle.load(_asset);
        await f.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      }
      final config = sherpa_onnx.OfflineSpeechDenoiserConfig(
        model: sherpa_onnx.OfflineSpeechDenoiserModelConfig(
          gtcrn: sherpa_onnx.OfflineSpeechDenoiserGtcrnModelConfig(model: modelPath),
          numThreads: 2,
          debug: false,
        ),
      );
      _denoiser = sherpa_onnx.OfflineSpeechDenoiser(config);
      return true;
    } catch (_) {
      _denoiser = null;
      return false;
    }
  }

  /// Denoise [samples] at [sampleRate]. Returns null if unavailable or on error
  /// (so the caller can fall back). Processes in ~20 s chunks, yielding between
  /// chunks, so a long clip never blocks the UI thread (run() is synchronous).
  static Future<Float32List?> denoise(Float32List samples, int sampleRate) async {
    if (!await initialize()) return null;
    final d = _denoiser;
    if (d == null || samples.isEmpty) return null;
    try {
      final wav = sampleRate == _modelRate
          ? samples
          : _resample(samples, sampleRate, _modelRate);

      const int chunk = _modelRate * 20; // 20 s per native call
      Float32List out16;
      if (wav.length <= chunk) {
        out16 = d.run(samples: wav, sampleRate: _modelRate).samples;
      } else {
        final acc = <double>[];
        for (int start = 0; start < wav.length; start += chunk) {
          final end = (start + chunk) < wav.length ? start + chunk : wav.length;
          final seg = Float32List(end - start)
            ..setRange(0, end - start, wav, start);
          acc.addAll(d.run(samples: seg, sampleRate: _modelRate).samples);
          await Future<void>.delayed(Duration.zero);
        }
        out16 = Float32List.fromList(acc);
      }
      return sampleRate == _modelRate ? out16 : _resample(out16, _modelRate, sampleRate);
    } catch (_) {
      return null;
    }
  }

  static Float32List _resample(Float32List input, int srcRate, int dstRate) {
    if (srcRate == dstRate) return input;
    final ratio  = dstRate / srcRate;
    final outLen = (input.length * ratio).round();
    final out    = Float32List(outLen);
    for (int i = 0; i < outLen; i++) {
      final pos  = i / ratio;
      final idx  = pos.floor();
      final frac = pos - idx;
      if (idx + 1 < input.length) {
        out[i] = input[idx] * (1.0 - frac) + input[idx + 1] * frac;
      } else if (idx < input.length) {
        out[i] = input[idx];
      }
    }
    return out;
  }
}
