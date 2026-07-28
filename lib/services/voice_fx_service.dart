import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

// Top-level helpers required by compute() ─────────────────────────────────────

class _FxArgs {
  final Float32List samples;
  final double semitones;
  final double speed;
  const _FxArgs(this.samples, this.semitones, this.speed);
}

Float32List _runFx(_FxArgs a) =>
    VoiceFxService.applySync(a.samples, a.semitones, a.speed);

// ─────────────────────────────────────────────────────────────────────────────

/// Character voice effects (pitch + tempo) applied to already-rendered audio.
///
/// Deliberately operates on the finished PCM rather than on engine settings,
/// so both TTS engines behave identically: `flutter_tts` exposes only a
/// prosody-level `setPitch` (documented as a hint, capped 0.5–2.0, and it
/// bends F0 without moving formants), while the neural/sherpa path exposes no
/// pitch control at all. Post-processing is the only place both can share one
/// implementation — and it also guarantees that what the user previews is
/// byte-identical to what gets saved or shared.
enum VoiceEffect { none, cartoonKid, chipmunk, pandi }

class VoiceFxPreset {
  final String label;
  final String blurb;

  /// Pitch shift in semitones. Because stage 1 is a resample, formants shift
  /// by the same amount — that coupling is what makes it read as a character
  /// rather than as the same person singing higher.
  final double semitones;

  /// Net playback tempo relative to the source (1.0 = unchanged length).
  final double speed;

  const VoiceFxPreset({
    required this.label,
    required this.blurb,
    required this.semitones,
    required this.speed,
  });

  /// Resample ratio for stage 1.
  double get ratio => pow(2.0, semitones / 12.0).toDouble();

  /// Stage-2 time-stretch factor. Exactly 1.0 means stage 2 is skipped
  /// entirely and the result is artifact-free.
  double get stretch => ratio / speed;
}

/// Preset table.
///
/// The ~+5 semitone (1.335x) point is the largest uniform spectral shift that
/// still corresponds to a real human vocal-tract length (adult male to small
/// child). Below it a voice reads as "a different person"; above it, as a
/// cartoon. That is why Cartoon Kid sits at exactly +5 and is the safe default.
const Map<VoiceEffect, VoiceFxPreset> kVoiceFxPresets = {
  VoiceEffect.none: VoiceFxPreset(
    label: 'Normal',
    blurb: 'No effect',
    semitones: 0,
    speed: 1.0,
  ),
  VoiceEffect.cartoonKid: VoiceFxPreset(
    label: 'Cartoon Kid',
    blurb: 'Bright and playful, stays clear',
    semitones: 5,
    speed: 1.15,
  ),
  // speed == ratio, so stretch == 1.0 and no time-stretch stage runs at all.
  VoiceEffect.chipmunk: VoiceFxPreset(
    label: 'Chipmunk',
    blurb: 'Classic cartoon, no artifacts',
    semitones: 7,
    speed: 1.4983070768766815,
  ),
  VoiceEffect.pandi: VoiceFxPreset(
    label: 'Pandi',
    blurb: 'Extreme high pitch, very squeaky',
    semitones: 10,
    speed: 1.15,
  ),
};

class VoiceFxService {
  /// Apply [effect] to [samples] in a background isolate.
  ///
  /// Returns the original samples unchanged if the effect is a no-op or if
  /// processing fails, so a caller can always use the result directly.
  static Future<Float32List> apply(
    Float32List samples,
    VoiceEffect effect,
  ) async {
    final p = kVoiceFxPresets[effect];
    if (p == null || effect == VoiceEffect.none) return samples;
    if (samples.isEmpty) return samples;
    try {
      return await compute(_runFx, _FxArgs(samples, p.semitones, p.speed));
    } catch (_) {
      return samples;
    }
  }

  /// Shift pitch by [semitones] while preserving the original duration.
  ///
  /// Used by the denoise pipeline for the Studio "Pitch" slider, where
  /// changing clip length would be wrong.
  static Future<Float32List> applyPitch(
    Float32List samples,
    double semitones,
  ) async {
    if (semitones.abs() < 0.01 || samples.isEmpty) return samples;
    try {
      return await compute(_runFx, _FxArgs(samples, semitones, 1.0));
    } catch (_) {
      return samples;
    }
  }

  /// Synchronous implementation — safe to call directly inside an isolate.
  @visibleForTesting
  static Float32List applySync(
    Float32List samples,
    double semitones,
    double speed,
  ) {
    final ratio = pow(2.0, semitones / 12.0).toDouble();
    final shifted =
        (ratio - 1.0).abs() < 1e-6 ? samples : _resample(samples, ratio);
    return _wsola(shifted, ratio / speed);
  }

  // ── Stage 1: resample ──────────────────────────────────────────────────────

  /// Read the input at [ratio] speed with linear interpolation. Pitch,
  /// formants and tempo all scale by [ratio]; length divides by it.
  static Float32List _resample(Float32List x, double ratio) {
    final n = (x.length / ratio).floor();
    if (n <= 1) return Float32List(0);
    final out = Float32List(n);
    final last = x.length - 1;
    for (int i = 0; i < n; i++) {
      final pos = i * ratio;
      final i0 = pos.floor();
      final frac = pos - i0;
      final i1 = i0 + 1 <= last ? i0 + 1 : last;
      out[i] = x[i0] * (1.0 - frac) + x[i1] * frac;
    }
    return out;
  }

  // ── Stage 2: WSOLA time-stretch ────────────────────────────────────────────

  static const int _frame = 1024; // ~23 ms at 44.1 kHz
  static const int _search = 128; // +/- offsets probed for best alignment
  static const int _step = 4; // search stride, keeps the cost mobile-friendly

  /// Pitch-preserving time-stretch by [t] (output length ~= input * t).
  ///
  /// Waveform-Similarity Overlap-Add: each output frame is drawn from the
  /// position, within a small search window, whose waveform best continues
  /// what was already emitted. That alignment is what keeps frames phase
  /// coherent; plain overlap-add without it produces audible warble on
  /// sustained vowels.
  static Float32List _wsola(Float32List x, double t) {
    if ((t - 1.0).abs() < 1e-6 || x.length < _frame * 2) return x;

    const hs = _frame ~/ 2; // synthesis hop (fixed)
    final ha = max(1, (hs / t).round()); // analysis hop

    final w = Float32List(_frame);
    for (int i = 0; i < _frame; i++) {
      w[i] = 0.5 * (1.0 - cos(2 * pi * i / (_frame - 1)));
    }

    final outLen = (x.length * t).round() + 2 * _frame;
    final y = Float32List(outLen);
    final wsum = Float32List(outLen);

    // Frame 0 is emitted verbatim and defines the initial phase reference.
    for (int i = 0; i < _frame; i++) {
      y[i] += x[i] * w[i];
      wsum[i] += w[i];
    }
    int target = hs; // start index of the reference frame

    int m = 1;
    while (true) {
      final ideal = m * ha;
      final lo = max(0, ideal - _search);
      final hi = min(x.length - _frame, ideal + _search);
      if (hi <= lo) break;

      // Pick the offset best correlated with the reference frame. Full
      // resolution: ~25M mult-adds for a 5 s clip, which is well inside
      // budget in a background isolate, so there is no reason to approximate.
      int best = lo;
      double bestScore = -double.infinity;
      for (int d = lo; d <= hi; d += _step) {
        double score = 0;
        for (int i = 0; i < _frame; i++) {
          score += x[d + i] * x[target + i];
        }
        if (score > bestScore) {
          bestScore = score;
          best = d;
        }
      }

      final sp = m * hs;
      if (sp + _frame > outLen) break;
      for (int i = 0; i < _frame; i++) {
        y[sp + i] += x[best + i] * w[i];
        wsum[sp + i] += w[i];
      }

      final nxt = best + hs;
      if (nxt + _frame > x.length) break;
      target = nxt;
      m++;
    }

    final end = min(m * hs + _frame, outLen);
    final res = Float32List(end);
    for (int i = 0; i < end; i++) {
      res[i] = wsum[i] > 1e-6 ? y[i] / wsum[i] : y[i];
    }
    return res;
  }
}
