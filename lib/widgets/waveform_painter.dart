import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme.dart';

class WaveformPainter extends CustomPainter {
  final Float32List? originalSamples;
  final Float32List? processedSamples;
  final bool showProcessed;

  const WaveformPainter({
    this.originalSamples,
    this.processedSamples,
    this.showProcessed = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (originalSamples != null && originalSamples!.isNotEmpty) {
      _drawWaveform(
        canvas, size, originalSamples!,
        showProcessed
            ? AppColors.textDim.withValues(alpha: 0.40)
            : AppColors.textPrim.withValues(alpha: 0.70),
      );
    }

    if (showProcessed && processedSamples != null && processedSamples!.isNotEmpty) {
      _drawWaveform(canvas, size, processedSamples!, AppColors.textPrim);
    }

    // Idle flat line
    if (originalSamples == null || originalSamples!.isEmpty) {
      final paint = Paint()
        ..color = AppColors.border
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        paint,
      );
    }
  }

  void _drawWaveform(Canvas canvas, Size size, Float32List samples, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    final int step = max(1, samples.length ~/ size.width.round());
    final double centerY = size.height / 2;

    bool first = true;
    for (int x = 0; x < size.width; x++) {
      final int idx = ((x / size.width) * samples.length).round().clamp(0, samples.length - 1);
      double peak = 0;
      for (int j = idx; j < min(idx + step, samples.length); j++) {
        peak = max(peak, samples[j].abs());
      }
      if (first) {
        path.moveTo(x.toDouble(), centerY);
        first = false;
      }
      canvas.drawLine(
        Offset(x.toDouble(), centerY - peak * centerY * 0.9),
        Offset(x.toDouble(), centerY + peak * centerY * 0.9),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(WaveformPainter old) =>
      old.originalSamples != originalSamples ||
      old.processedSamples != processedSamples ||
      old.showProcessed != showProcessed;
}

class LiveAmplitudeBar extends StatelessWidget {
  final double amplitude; // 0–1

  const LiveAmplitudeBar({super.key, required this.amplitude});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        return Container(
          height: 8,
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(4),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: amplitude.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.green,
                    amplitude > 0.7 ? AppColors.amber : AppColors.violet,
                    if (amplitude > 0.9) const Color(0xFFEF4444),
                  ],
                ),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        );
      },
    );
  }
}
