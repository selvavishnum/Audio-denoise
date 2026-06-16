import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'fft_service.dart';

class StemResult {
  final Float32List vocals;
  final Float32List instrumental;
  const StemResult(this.vocals, this.instrumental);
}

class _SeparateArgs {
  final Float32List samples;
  final int sampleRate;
  const _SeparateArgs(this.samples, this.sampleRate);
}

StemResult? _runSeparate(_SeparateArgs args) =>
    StemSeparatorService.separateSync(args.samples, args.sampleRate);

/// On-device vocal / instrumental separation.
///
/// Harmonic–percussive soft-mask split (Fitzgerald-style HPSS, using moving
/// averages as a cheap proxy for the usual median filters) plus vocal-band
/// emphasis (200–3800 Hz, the voice fundamental + formant range). The vocal
/// and instrumental masks are complementary (Mv + Mi = 1), so the two stems
/// always sum back exactly to the original mix — this is a spectral split of
/// the existing recording, not a generative model, and works on mono input
/// without any bundled weights.
class StemSeparatorService {
  static const int _nFft = 1024;
  static const int _hop = 256;
  static const int _bins = 513; // nFft / 2 + 1
  static const int _timeRadius = 21; // ~120 ms harmonic smoothing window
  static const int _freqRadius = 21; // ~900 Hz percussive smoothing window

  static Future<StemResult?> separate(
      Float32List samples, int sampleRate) async {
    try {
      return await compute(_runSeparate, _SeparateArgs(samples, sampleRate));
    } catch (_) {
      return null;
    }
  }

  static StemResult? separateSync(Float32List samples, int sampleRate) {
    try {
      final n = samples.length;
      if (n < _nFft) return StemResult(samples, Float32List(n));

      final hann = FFTService.hannWindow(_nFft);
      final mags = <Float64List>[];
      final phases = <Float64List>[];

      for (int pos = 0; pos < n; pos += _hop) {
        final re = Float64List(_nFft);
        final im = Float64List(_nFft);
        for (int i = 0; i < _nFft; i++) {
          final si = pos + i;
          re[i] = (si < n ? samples[si].toDouble() : 0.0) * hann[i];
        }
        FFTService.fft(re, im);

        final mag = Float64List(_bins);
        final phase = Float64List(_bins);
        for (int k = 0; k < _bins; k++) {
          mag[k] = sqrt(re[k] * re[k] + im[k] * im[k] + 1e-16);
          phase[k] = atan2(im[k], re[k]);
        }
        mags.add(mag);
        phases.add(phase);
      }

      final T = mags.length;
      if (T == 0) return null;

      // ── Harmonic estimate: moving average along time, per bin ────────────
      final harm = List<Float64List>.generate(T, (_) => Float64List(_bins));
      for (int k = 0; k < _bins; k++) {
        final prefix = Float64List(T + 1);
        for (int t = 0; t < T; t++) prefix[t + 1] = prefix[t] + mags[t][k];
        for (int t = 0; t < T; t++) {
          final lo = max(0, t - _timeRadius);
          final hi = min(T - 1, t + _timeRadius);
          harm[t][k] = (prefix[hi + 1] - prefix[lo]) / (hi - lo + 1);
        }
      }

      // ── Percussive estimate: moving average along frequency, per frame ───
      final perc = List<Float64List>.generate(T, (_) => Float64List(_bins));
      for (int t = 0; t < T; t++) {
        final prefix = Float64List(_bins + 1);
        for (int k = 0; k < _bins; k++) prefix[k + 1] = prefix[k] + mags[t][k];
        for (int k = 0; k < _bins; k++) {
          final lo = max(0, k - _freqRadius);
          final hi = min(_bins - 1, k + _freqRadius);
          perc[t][k] = (prefix[hi + 1] - prefix[lo]) / (hi - lo + 1);
        }
      }

      // ── Vocal-band weight: emphasise 200–3800 Hz, roll off outside ────────
      final vocalWeight = Float64List(_bins);
      for (int k = 0; k < _bins; k++) {
        final hz = k * sampleRate / _nFft.toDouble();
        if (hz < 120) {
          vocalWeight[k] = 0.15;
        } else if (hz < 250) {
          vocalWeight[k] = 0.15 + (hz - 120) / 130.0 * 0.65;
        } else if (hz <= 3800) {
          vocalWeight[k] = 1.0;
        } else if (hz < 8000) {
          vocalWeight[k] = 1.0 - 0.8 * (hz - 3800) / (8000 - 3800);
        } else {
          vocalWeight[k] = 0.2;
        }
      }

      // ── Complementary soft mask (Mv + Mi = 1) → ISTFT both stems ──────────
      final bufLen = n + _nFft;
      final vocOut = Float64List(bufLen);
      final instOut = Float64List(bufLen);
      final weights = Float64List(bufLen);

      for (int t = 0; t < T; t++) {
        final reV = Float64List(_nFft), imV = Float64List(_nFft);
        final reI = Float64List(_nFft), imI = Float64List(_nFft);

        for (int k = 0; k < _bins; k++) {
          final h = harm[t][k], p = perc[t][k];
          final harmonicShare = h * h / (h * h + p * p + 1e-12);
          final mv = (harmonicShare * vocalWeight[k]).clamp(0.0, 1.0);

          final mag = mags[t][k];
          final phase = phases[t][k];
          final re = mag * cos(phase);
          final im = mag * sin(phase);

          reV[k] = mv * re;
          imV[k] = mv * im;
          reI[k] = (1.0 - mv) * re;
          imI[k] = (1.0 - mv) * im;

          if (k > 0 && k < _nFft ~/ 2) {
            reV[_nFft - k] = reV[k];
            imV[_nFft - k] = -imV[k];
            reI[_nFft - k] = reI[k];
            imI[_nFft - k] = -imI[k];
          }
        }

        FFTService.ifft(reV, imV);
        FFTService.ifft(reI, imI);

        final pos = t * _hop;
        for (int i = 0; i < _nFft; i++) {
          final idx = pos + i;
          if (idx < bufLen) {
            vocOut[idx] += reV[i] * hann[i];
            instOut[idx] += reI[i] * hann[i];
            weights[idx] += hann[i] * hann[i];
          }
        }
      }

      final vocals = Float32List(n);
      final instrumental = Float32List(n);
      for (int i = 0; i < n; i++) {
        final w = weights[i] > 1e-12 ? weights[i] : 1.0;
        vocals[i] = (vocOut[i] / w).clamp(-1.0, 1.0);
        instrumental[i] = (instOut[i] / w).clamp(-1.0, 1.0);
      }

      return StemResult(vocals, instrumental);
    } catch (_) {
      return null;
    }
  }
}
