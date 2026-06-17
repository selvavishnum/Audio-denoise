import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // ── Core whites ───────────────────────────────────────────────────────
  static const Color bg      = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFF7F7F7);
  static const Color card    = Color(0xFFF2F2F2);
  static const Color border  = Color(0xFFE8E8E8);
  static const Color divider = Color(0xFFF0F0F0);

  // ── Text ──────────────────────────────────────────────────────────────
  static const Color textPrim = Color(0xFF0A0A0A);
  static const Color textSec  = Color(0xFF6B6B6B);
  static const Color textDim  = Color(0xFFBBBBBB);

  // ── Accent (black only — premium minimal) ─────────────────────────────
  static const Color accent = Color(0xFF0A0A0A);
  static const Color white  = Color(0xFFFFFFFF);

  // ── Semantic ──────────────────────────────────────────────────────────
  static const Color danger  = Color(0xFFEF4444);
  static const Color success = Color(0xFF22C55E);

  // ── Equalizer/waveform — the ONLY color in the app ────────────────────
  static const Color eqLow   = Color(0xFFF59E0B); // amber  — bass
  static const Color eqMid   = Color(0xFF8B5CF6); // violet — midrange
  static const Color eqVoice = Color(0xFFEC4899); // pink   — voice peak
  static const Color eqHigh  = Color(0xFF06B6D4); // cyan   — treble

  // ── Legacy aliases (kept for compatibility) ───────────────────────────
  static const Color violet = Color(0xFF8B5CF6);
  static const Color pink   = Color(0xFFEC4899);
  static const Color cyan   = Color(0xFF06B6D4);
  static const Color green  = Color(0xFF22C55E);
  static const Color amber  = Color(0xFFF59E0B);
}

class AppTheme {
  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    final tt   = GoogleFonts.interTextTheme(base.textTheme);

    return base.copyWith(
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        brightness: Brightness.light,
        primary:   AppColors.accent,
        onPrimary: AppColors.white,
        secondary: AppColors.textSec,
        surface:   AppColors.bg,
        onSurface: AppColors.textPrim,
        outline:   AppColors.border,
      ),
      scaffoldBackgroundColor: AppColors.bg,
      textTheme: tt.copyWith(
        displayLarge:   tt.displayLarge?.copyWith(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.textPrim, letterSpacing: -0.5),
        headlineMedium: tt.headlineMedium?.copyWith(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.textPrim),
        titleLarge:     tt.titleLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrim),
        titleMedium:    tt.titleMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrim),
        bodyLarge:      tt.bodyLarge?.copyWith(fontSize: 14, color: AppColors.textSec),
        bodyMedium:     tt.bodyMedium?.copyWith(fontSize: 13, color: AppColors.textSec),
        labelLarge:     tt.labelLarge?.copyWith(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrim),
        labelSmall:     tt.labelSmall?.copyWith(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textDim),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.textPrim,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
      ),
      cardTheme: const CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: AppColors.border, width: 0.5),
        ),
        margin: EdgeInsets.zero,
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor:   AppColors.accent,
        inactiveTrackColor: AppColors.border,
        thumbColor:         AppColors.accent,
        overlayColor:       const Color(0x1A0A0A0A),
        trackHeight:        2.0,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 0.5,
        space: 0,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.textPrim,
        contentTextStyle: TextStyle(color: AppColors.white, fontSize: 13),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    );
  }

  // Keep old getter name so nothing else breaks
  static ThemeData get dark => light;
}
