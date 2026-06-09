import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class LiveWaveformPainter extends CustomPainter {
  final List<double> samples;
  final Color color;
  final double amplitude;

  LiveWaveformPainter({
    required this.samples,
    this.color = AppColors.primaryStart,
    this.amplitude = 0.5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    if (samples.isEmpty) {
      _drawFlatLine(canvas, size, paint);
      return;
    }

    final barWidth = size.width / samples.length;
    final centerY = size.height / 2;

    for (int i = 0; i < samples.length; i++) {
      final x = i * barWidth + barWidth / 2;
      final barHeight = samples[i] * centerY * 0.9;

      final gradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withOpacity(0.9),
          color.withOpacity(0.4),
        ],
      );

      final barPaint = Paint()
        ..shader = gradient.createShader(
          Rect.fromCenter(center: Offset(x, centerY), width: barWidth, height: size.height),
        )
        ..strokeWidth = (barWidth * 0.65).clamp(1.5, 4.0)
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      canvas.drawLine(
        Offset(x, centerY - barHeight),
        Offset(x, centerY + barHeight),
        barPaint,
      );
    }
  }

  void _drawFlatLine(Canvas canvas, Size size, Paint paint) {
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      paint..color = paint.color.withOpacity(0.3),
    );
  }

  @override
  bool shouldRepaint(LiveWaveformPainter oldDelegate) {
    return oldDelegate.samples != samples || oldDelegate.amplitude != amplitude;
  }
}

class AnimatedWaveform extends StatefulWidget {
  final bool isActive;
  final Color color;
  final double height;
  final double amplitude;

  const AnimatedWaveform({
    super.key,
    required this.isActive,
    this.color = AppColors.primaryStart,
    this.height = 80,
    this.amplitude = 0.5,
  });

  @override
  State<AnimatedWaveform> createState() => _AnimatedWaveformState();
}

class _AnimatedWaveformState extends State<AnimatedWaveform>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  final List<double> _samples = List.filled(60, 0.0);
  final math.Random _random = math.Random();
  int _offset = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
    )..addListener(_updateSamples);
    if (widget.isActive) _controller.repeat();
  }

  void _updateSamples() {
    if (!widget.isActive) return;
    setState(() {
      _offset++;
      final idx = _offset % _samples.length;
      _samples[idx] = widget.amplitude > 0.05
          ? (widget.amplitude * (0.7 + _random.nextDouble() * 0.6)).clamp(0.05, 1.0)
          : 0.02 + _random.nextDouble() * 0.05;
    });
  }

  @override
  void didUpdateWidget(AnimatedWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isActive && _controller.isAnimating) {
      _controller.stop();
      setState(() {
        for (int i = 0; i < _samples.length; i++) {
          _samples[i] = 0.0;
        }
      });
    }
  }

  List<double> get _orderedSamples {
    final result = List<double>.filled(_samples.length, 0.0);
    for (int i = 0; i < _samples.length; i++) {
      result[i] = _samples[(_offset - _samples.length + 1 + i) % _samples.length];
    }
    return result;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: CustomPaint(
        painter: LiveWaveformPainter(
          samples: _orderedSamples,
          color: widget.color,
          amplitude: widget.amplitude,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class StaticWaveformBar extends StatelessWidget {
  final double fillPercent;
  final Color activeColor;
  final Color inactiveColor;
  final String label;

  const StaticWaveformBar({
    super.key,
    required this.fillPercent,
    this.activeColor = AppColors.primaryStart,
    this.inactiveColor = AppColors.border,
    this.label = '',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty) ...[
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
        ],
        Container(
          height: 6,
          decoration: BoxDecoration(
            color: inactiveColor,
            borderRadius: BorderRadius.circular(3),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: fillPercent.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [activeColor, activeColor.withOpacity(0.7)],
                ),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
