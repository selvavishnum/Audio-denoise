import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme.dart';

class ParamSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String unit;
  final int displayDecimals;
  final ValueChanged<double> onChanged;
  final Color? color;

  const ParamSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions = 100,
    this.unit = '',
    this.displayDecimals = 0,
    this.color,
  });

  String get _displayValue {
    final v = value.clamp(min, max);
    if (displayDecimals == 0) return '${v.round()}$unit';
    return '${v.toStringAsFixed(displayDecimals)}$unit';
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = color ?? AppColors.violet;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  color: AppColors.textDim,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: activeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: activeColor.withValues(alpha: 0.35)),
                ),
                child: Text(
                  _displayValue,
                  style: GoogleFonts.inter(
                    color: activeColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: activeColor,
              inactiveTrackColor: AppColors.border,
              thumbColor: activeColor,
              overlayColor: activeColor.withValues(alpha: 0.15),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class IntParamSlider extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final String unit;
  final ValueChanged<int> onChanged;
  final Color? color;

  const IntParamSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.unit = '',
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ParamSlider(
      label: label,
      value: value.toDouble(),
      min: min.toDouble(),
      max: max.toDouble(),
      divisions: max - min,
      unit: unit,
      displayDecimals: 0,
      color: color,
      onChanged: (v) => onChanged(v.round()),
    );
  }
}
