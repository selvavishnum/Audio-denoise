import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/audio_params.dart';
import '../theme.dart';

class PresetCard extends StatelessWidget {
  final VoicePreset preset;
  final bool isSelected;
  final VoidCallback onTap;

  const PresetCard({
    super.key,
    required this.preset,
    required this.isSelected,
    required this.onTap,
  });

  static const _meta = {
    VoicePreset.crispy: _PresetMeta('✨', 'CRISPY', 'Studio Polish',
        [Color(0xFF8B5CF6), Color(0xFFA78BFA)]),
    VoicePreset.pop: _PresetMeta('🎤', 'POP', 'Chart Ready',
        [Color(0xFFEC4899), Color(0xFFF472B6)]),
    VoicePreset.radio: _PresetMeta('📻', 'RADIO', 'Broadcast Grade',
        [Color(0xFF06B6D4), Color(0xFF22D3EE)]),
    VoicePreset.deep: _PresetMeta('🔊', 'DEEP', 'Rich Bass Voice',
        [Color(0xFF3B82F6), Color(0xFF60A5FA)]),
    VoicePreset.natural: _PresetMeta('🍃', 'NATURAL', 'True to Life',
        [Color(0xFF22C55E), Color(0xFF4ADE80)]),
    VoicePreset.hype: _PresetMeta('⚡', 'HYPE', 'High Energy',
        [Color(0xFFF59E0B), Color(0xFFFBBF24)]),
  };

  @override
  Widget build(BuildContext context) {
    final m = _meta[preset]!;
    final p = AudioParams.presets[preset]!;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isSelected
                ? m.colors
                : [AppColors.card, AppColors.card],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? m.colors.first : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: m.colors.first.withValues(alpha:0.45),
                    blurRadius: 18,
                    spreadRadius: 2,
                  )
                ]
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(m.icon, style: const TextStyle(fontSize: 18)),
                  const Spacer(),
                  if (isSelected)
                    const Icon(Icons.check_circle, color: Colors.white, size: 14),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                m.name,
                style: GoogleFonts.inter(
                  color: isSelected ? Colors.white : AppColors.textPrim,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                m.subtitle,
                style: GoogleFonts.inter(
                  color: isSelected ? Colors.white.withValues(alpha: 0.8) : AppColors.textSec,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Pitch ${p.pitchSemitones >= 0 ? '+' : ''}${p.pitchSemitones.toStringAsFixed(1)}st',
                style: GoogleFonts.inter(
                  color: isSelected ? Colors.white.withValues(alpha: 0.75) : AppColors.textDim,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                'Formant ×${p.formantFactor.toStringAsFixed(2)}',
                style: GoogleFonts.inter(
                  color: isSelected ? Colors.white.withValues(alpha: 0.75) : AppColors.textDim,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetMeta {
  final String icon;
  final String name;
  final String subtitle;
  final List<Color> colors;
  const _PresetMeta(this.icon, this.name, this.subtitle, this.colors);
}
