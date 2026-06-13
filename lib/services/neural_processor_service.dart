import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'fft_service.dart';

// ── Top-level helpers required by compute() ───────────────────────────────────

class _NeuralArgs {
  final Float32List samples;
  final int sampleRate;
  final Uint8List modelBytes;
  const _NeuralArgs(this.samples, this.sampleRate, this.modelBytes);
}

Float32List? _runNeuralDenoise(_NeuralArgs args) =>
    NeuralProcessorService.denoiseSync(args.samples, args.sampleRate, args.modelBytes);

// ── Service ───────────────────────────────────────────────────────────────────

class NeuralProcessorService {
  static const String _asset = 'assets/models/speech_denoise.tflite';

  // STFT parameters — match the Python export_model.py constants exactly
  static const int _nFft        = 512;
  static const int _hop         = 128;
  static const int _bins        = 257; // nFft / 2 + 1
  static const int _chunkFrames = 128; // fixed input width for TFLite model
  static const int _modelRate   = 16000;

  static Uint8List? _bytes;

  static bool get isReady  => _bytes != null;
  static Uint8List? get modelBytes => _bytes;

  /// Call once from main() after WidgetsFlutterBinding.ensureInitialized().
  static Future<void> initialize() async {
    try {
      final data = await rootBundle.load(_asset);
      _bytes = data.buffer.asUint8List();
    } catch (_) {
      // Model not bundled yet — DSP-only mode until model is added.
    }
  }

  /// Runs neural denoising in a background compute isolate.
  /// Returns null if model not loaded or inference fails (caller uses DSP only).
  static Future<Float32List?> denoise(Float32List samples, int sampleRate) async {
    if (_bytes == null) return null;
    try {
      return await compute(
        _runNeuralDenoise,
        _NeuralArgs(samples, sampleRate, _bytes!),
      );
    } catch (_) {
      return null;
    }
  }

  // ── Core inference — called inside compute() isolate ──────────────────────

  /// Exposed as non-private so the top-level _runNeuralDenoise can call it.
  static Float32List? denoiseSync(
    Float32List samples,
    int sampleRate,
    Uint8List modelBytes,
  ) {
    try {
      // 1. Resample to 16 kHz (model's expected sample rate)
      final wav    = sampleRate == _modelRate
          ? samples
          : _resample(samples, sampleRate, _modelRate);
      final origLen = wav.length;

      // 2. STFT → per-frame magnitude [T][F] and phase [T][F]
      final (:mags, :phases) = _stft(wav);
      final int T = mags.length;
      if (T == 0) return null;

      // 3. Flatten to [F × T] log-magnitude and globally normalise
      //    Layout: index = f * T + t  (matches TFLite [B=1, C=1, F, T] layout)
      final logMag = Float32List(_bins * T);
      for (int t = 0; t < T; t++) {
        for (int f = 0; f < _bins; f++) {
          logMag[f * T + t] = log(1.0 + mags[t][f]);
        }
      }
      var mean = 0.0;
      for (final v in logMag) { mean += v; }
      mean /= logMag.length;
      var variance = 0.0;
      for (final v in logMag) { variance += (v - mean) * (v - mean); }
      final std = sqrt(variance / logMag.length) + 1e-8;

      final normMag = Float32List(logMag.length);
      for (int i = 0; i < logMag.length; i++) {
        normMag[i] = (logMag[i] - mean) / std;
      }

      // 4. Run TFLite in fixed-size chunks → collect soft IRM mask
      //    Model input:  [1, 1, _bins, _chunkFrames]
      //    Model output: [1, 1, _bins, _chunkFrames]  — sigmoid ∈ [0, 1]
      final interpreter = Interpreter.fromBuffer(modelBytes);
      final mask = Float32List(_bins * T);

      for (int start = 0; start < T; start += _chunkFrames) {
        final end    = (start + _chunkFrames).clamp(0, T);
        final frames = end - start;

        interpreter.resizeInputTensor(0, [1, 1, _bins, _chunkFrames]);
        interpreter.allocateTensors();

        // Fill input — zero-pad last chunk if frames < _chunkFrames
        final input = Float32List(_bins * _chunkFrames);
        for (int f = 0; f < _bins; f++) {
          for (int t = 0; t < frames; t++) {
            input[f * _chunkFrames + t] = normMag[f * T + (start + t)];
          }
        }

        // tflite_flutter 0.10.x: write via ByteData buffer (no copyFrom)
        final td = interpreter.getInputTensor(0).data;
        td.buffer.asFloat32List(td.offsetInBytes, input.length).setAll(0, input);
        interpreter.invoke();

        final outBytes = interpreter.getOutputTensor(0).data;
        final outFloat = outBytes.buffer.asFloat32List(
          outBytes.offsetInBytes,
          outBytes.lengthInBytes ~/ Float32List.bytesPerElement,
        );

        // Copy valid frames from chunk output into full mask
        for (int f = 0; f < _bins; f++) {
          for (int t = 0; t < frames; t++) {
            mask[f * T + (start + t)] =
                outFloat[f * _chunkFrames + t].clamp(0.0, 1.0);
          }
        }
      }
      interpreter.close();

      // 5. Apply mask, denormalise to linear magnitude
      final enhMags = List.generate(T, (t) {
        final frame = Float64List(_bins);
        for (int f = 0; f < _bins; f++) {
          final maskedNorm = normMag[f * T + t] * mask[f * T + t];
          frame[f] = (exp(maskedNorm * std + mean) - 1.0).clamp(0.0, 1e9);
        }
        return frame;
      });

      // 6. iSTFT overlap-add → clean waveform at 16 kHz
      final cleaned = _istft(enhMags, phases, origLen);

      // 7. Resample back to the app's native rate (44100 Hz)
      return sampleRate == _modelRate
          ? cleaned
          : _resample(cleaned, _modelRate, sampleRate);
    } catch (_) {
      return null;
    }
  }

  // ── STFT ──────────────────────────────────────────────────────────────────

  static ({List<Float64List> mags, List<Float64List> phases}) _stft(
      Float32List samples) {
    final hann   = FFTService.hannWindow(_nFft);
    final n      = samples.length;
    final mags   = <Float64List>[];
    final phases = <Float64List>[];

    for (int pos = 0; pos < n; pos += _hop) {
      final re = Float64List(_nFft);
      final im = Float64List(_nFft);
      for (int i = 0; i < _nFft; i++) {
        final si = pos + i;
        re[i] = (si < n ? samples[si].toDouble() : 0.0) * hann[i];
      }
      FFTService.fft(re, im);

      final mag   = Float64List(_bins);
      final phase = Float64List(_bins);
      for (int k = 0; k < _bins; k++) {
        mag[k]   = sqrt(re[k] * re[k] + im[k] * im[k] + 1e-16);
        phase[k] = atan2(im[k], re[k]);
      }
      mags.add(mag);
      phases.add(phase);
    }
    return (mags: mags, phases: phases);
  }

  // ── iSTFT (overlap-add) ───────────────────────────────────────────────────

  static Float32List _istft(
    List<Float64List> mags,
    List<Float64List> phases,
    int outputLen,
  ) {
    final hann    = FFTService.hannWindow(_nFft);
    final bufLen  = outputLen + _nFft;
    final output  = Float64List(bufLen);
    final weights = Float64List(bufLen);

    for (int t = 0; t < mags.length; t++) {
      final re = Float64List(_nFft);
      final im = Float64List(_nFft);
      for (int k = 0; k < _bins; k++) {
        final m = mags[t][k];
        final p = phases[t][k];
        re[k] = m * cos(p);
        im[k] = m * sin(p);
        if (k > 0 && k < _nFft ~/ 2) {
          re[_nFft - k] =  re[k];
          im[_nFft - k] = -im[k];
        }
      }
      FFTService.ifft(re, im);

      final pos = t * _hop;
      for (int i = 0; i < _nFft; i++) {
        final idx = pos + i;
        if (idx < bufLen) {
          output[idx]  += re[i] * hann[i];
          weights[idx] += hann[i] * hann[i];
        }
      }
    }

    final result = Float32List(outputLen);
    for (int i = 0; i < outputLen; i++) {
      result[i] = weights[i] > 1e-12
          ? (output[i] / weights[i]).clamp(-1.0, 1.0)
          : 0.0;
    }
    return result;
  }

  // ── Linear resampler (linear interpolation) ───────────────────────────────

  static Float32List _resample(
      Float32List input, int srcRate, int dstRate) {
    if (srcRate == dstRate) return input;
    final ratio  = dstRate / srcRate;
    final outLen = (input.length * ratio).round();
    final out    = Float32List(outLen);
    for (int i = 0; i < outLen; i++) {
      final pos = i / ratio;
      final idx = pos.floor();
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
