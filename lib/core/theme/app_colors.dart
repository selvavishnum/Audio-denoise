import 'package:flutter/material.dart';

class AppColors {
  // Background layers
  static const Color bgDeep = Color(0xFF060912);
  static const Color bgPrimary = Color(0xFF0A0E1A);
  static const Color bgSurface = Color(0xFF111827);
  static const Color bgCard = Color(0xFF1A2235);
  static const Color bgCardLight = Color(0xFF1F2A40);

  // Borders
  static const Color border = Color(0xFF2A3558);
  static const Color borderLight = Color(0xFF374369);

  // Brand gradients
  static const Color primaryStart = Color(0xFF6366F1); // indigo
  static const Color primaryEnd = Color(0xFF8B5CF6);   // purple
  static const Color accentStart = Color(0xFF06B6D4);  // cyan
  static const Color accentEnd = Color(0xFF0EA5E9);    // sky

  // Semantic colors
  static const Color success = Color(0xFF10B981);
  static const Color recording = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);
  static const Color premium = Color(0xFFF59E0B);
  static const Color info = Color(0xFF3B82F6);

  // Text
  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF4B5563);
  static const Color textAccent = Color(0xFF818CF8);

  // Waveform colors
  static const Color waveformBase = Color(0xFF374369);
  static const Color waveformClean = Color(0xFF10B981);
  static const Color waveformDirty = Color(0xFFF59E0B);
  static const Color waveformNoise = Color(0xFFEF4444);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryStart, primaryEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [accentStart, accentEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient darkGradient = LinearGradient(
    colors: [bgDeep, bgPrimary],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [bgCard, bgCardLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient get greenGradient => const LinearGradient(
    colors: [Color(0xFF059669), Color(0xFF10B981)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient get goldGradient => const LinearGradient(
    colors: [Color(0xFFD97706), Color(0xFFF59E0B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
