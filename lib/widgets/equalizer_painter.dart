import 'dart:math';
import 'package:flutter/material.dart';
import '../theme.dart';

/// Animated frequency bar visualizer — the only colorful element in the app.
/// Feed it 0–1 magnitudes (one per bar); colors shift from bass (amber) → mid
/// (violet) → voice (pink) → treble (cyan) depending on frequency position.
class EqualizerPainter extends CustomPainter {
  final List<double> bars;
  final bool isActive;

  const EqualizerPainter({required this.bars, this.isActive = true});

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;
    final int n = bars.length;
    final double barW = (size.width / n) * 0.55;
    final double step = size.width / n;

    for (int i = 0; i < n; i++) {
      final double t     = i / (n - 1).toDouble();
      final double mag   = isActive ? bars[i].clamp(0.0, 1.0) : 0.06;
      final double barH  = max(barW, mag * size.height * 0.96);
      final double x     = i * step + (step - barW) / 2;
      final double y     = size.height - barH;
      final Color  color = _eqColor(t, mag);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barW, barH),
          Radius.circular(barW / 2),
        ),
        Paint()..color = color,
      );
    }
  }

  // Frequency-to-color mapping: amber → violet → pink → cyan
  Color _eqColor(double t, double mag) {
    Color base;
    if (t < 0.33) {
      base = Color.lerp(AppColors.eqLow, AppColors.eqMid, t / 0.33)!;
    } else if (t < 0.66) {
      base = Color.lerp(AppColors.eqMid, AppColors.eqVoice, (t - 0.33) / 0.33)!;
    } else {
      base = Color.lerp(AppColors.eqVoice, AppColors.eqHigh, (t - 0.66) / 0.34)!;
    }
    return base.withValues(alpha: 0.18 + mag * 0.82);
  }

  @override
  bool shouldRepaint(EqualizerPainter old) =>
      old.isActive != isActive || !_listsEqual(old.bars, bars);

  bool _listsEqual(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if ((a[i] - b[i]).abs() > 0.001) return false;
    }
    return true;
  }
}

/// Idle state equalizer — draws a gentle static wave at low height.
List<double> idleEqBars(int count) => List.generate(count, (i) {
  return 0.06 + sin(pi * i / count) * 0.06;
});

/// Convert amplitude (0–1) and a random seed to animated bar heights.
/// Call on each timer tick and setState to animate.
List<double> animateEqBars({
  required List<double> prev,
  required double amplitude,
  required Random rng,
}) {
  final int n = prev.length;
  return List.generate(n, (i) {
    final double freqW = sin(pi * i / n);
    final double target = amplitude * freqW * (0.4 + rng.nextDouble() * 0.6);
    return (prev[i] * 0.55 + target.clamp(0.04, 1.0) * 0.45);
  });
}
