import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../models/denoise_settings.dart';
import '../common/glass_card.dart';

class StudioControlsPanel extends StatelessWidget {
  final DenoiseSettings settings;
  final void Function(DenoiseSettings) onChanged;

  const StudioControlsPanel({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Noise Reduction', Icons.noise_control_off),
        const SizedBox(height: 12),
        _StudioSlider(
          label: 'Strength',
          value: settings.noiseReduction,
          min: 0,
          max: 100,
          displaySuffix: '%',
          activeColor: AppColors.primaryStart,
          onChanged: (v) => onChanged(settings.copyWith(noiseReduction: v)),
        ),
        const SizedBox(height: 10),
        _StudioSlider(
          label: 'Noise Floor',
          value: settings.noiseFloor,
          min: -80,
          max: -10,
          displaySuffix: ' dB',
          activeColor: AppColors.accentStart,
          onChanged: (v) => onChanged(settings.copyWith(noiseFloor: v)),
        ),
        const SizedBox(height: 20),
        _buildSectionHeader('Frequency Filter', Icons.equalizer),
        const SizedBox(height: 12),
        _StudioSlider(
          label: 'High Pass',
          value: settings.highPassHz,
          min: 20,
          max: 500,
          displaySuffix: ' Hz',
          activeColor: const Color(0xFF10B981),
          onChanged: (v) => onChanged(settings.copyWith(highPassHz: v)),
        ),
        const SizedBox(height: 10),
        _StudioSlider(
          label: 'Low Pass',
          value: settings.lowPassKhz,
          min: 2,
          max: 20,
          displaySuffix: ' kHz',
          activeColor: const Color(0xFFF59E0B),
          onChanged: (v) => onChanged(settings.copyWith(lowPassKhz: v)),
        ),
        const SizedBox(height: 20),
        _buildSectionHeader('Enhancement', Icons.auto_fix_high),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ToggleChip(
                label: 'Voice Enhance',
                icon: Icons.record_voice_over,
                isActive: settings.voiceEnhance,
                activeColor: AppColors.primaryStart,
                onTap: () => onChanged(
                    settings.copyWith(voiceEnhance: !settings.voiceEnhance)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ToggleChip(
                label: 'De-Reverb',
                icon: Icons.layers_clear,
                isActive: settings.deReverb,
                activeColor: AppColors.accentStart,
                onTap: () => onChanged(
                    settings.copyWith(deReverb: !settings.deReverb)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _buildSectionHeader('Dynamics', Icons.compress),
        const SizedBox(height: 12),
        _StudioSlider(
          label: 'Compressor Ratio',
          value: settings.compressorRatio,
          min: 1,
          max: 8,
          displaySuffix: ':1',
          displayDecimals: 1,
          activeColor: const Color(0xFF8B5CF6),
          onChanged: (v) => onChanged(settings.copyWith(compressorRatio: v)),
        ),
        const SizedBox(height: 10),
        _StudioSlider(
          label: 'Output Gain',
          value: settings.outputGain,
          min: -12,
          max: 12,
          displaySuffix: ' dB',
          displayDecimals: 1,
          activeColor: AppColors.recording,
          onChanged: (v) => onChanged(settings.copyWith(outputGain: v)),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppColors.textAccent, size: 16),
        const SizedBox(width: 8),
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: AppColors.textAccent,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

class _StudioSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String displaySuffix;
  final int displayDecimals;
  final Color activeColor;
  final ValueChanged<double> onChanged;

  const _StudioSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.displaySuffix = '',
    this.displayDecimals = 0,
    this.activeColor = AppColors.primaryStart,
  });

  String get displayValue {
    if (displayDecimals == 0) return '${value.round()}$displaySuffix';
    return '${value.toStringAsFixed(displayDecimals)}$displaySuffix';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: activeColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: activeColor.withOpacity(0.4)),
              ),
              child: Text(
                displayValue,
                style: TextStyle(
                  color: activeColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
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
            overlayColor: activeColor.withOpacity(0.2),
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final Color activeColor;
  final VoidCallback onTap;

  const _ToggleChip({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? activeColor.withOpacity(0.15) : AppColors.bgCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive ? activeColor.withOpacity(0.6) : AppColors.border,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive ? activeColor : AppColors.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isActive ? activeColor : AppColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
