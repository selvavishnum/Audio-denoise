import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../services/storage_service.dart';
import '../../services/usage_service.dart';
import '../home/home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _init();
  }

  Future<void> _init() async {
    await StorageService.instance.init();
    await Future.delayed(const Duration(milliseconds: 2500));
    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const HomeScreen(),
          transitionDuration: const Duration(milliseconds: 500),
          transitionsBuilder: (_, anim, __, child) {
            return FadeTransition(opacity: anim, child: child);
          },
        ),
      );
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.2,
            colors: [
              Color(0xFF0D0F1F),
              AppColors.bgDeep,
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              _buildLogo(),
              const SizedBox(height: 24),

              // App name
              Text(
                'ClearWave',
                style: GoogleFonts.rajdhani(
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.2, end: 0),

              Text(
                'STUDIO',
                style: GoogleFonts.rajdhani(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textAccent,
                  letterSpacing: 6,
                ),
              ).animate().fadeIn(delay: 500.ms),

              const SizedBox(height: 48),

              // Loading indicator
              SizedBox(
                width: 120,
                child: LinearProgressIndicator(
                  backgroundColor: AppColors.border,
                  valueColor: const AlwaysStoppedAnimation(AppColors.primaryStart),
                  minHeight: 2,
                ).animate().fadeIn(delay: 800.ms),
              ),

              const SizedBox(height: 16),
              Text(
                'AI-Powered Noise Cancellation',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ).animate().fadeIn(delay: 1000.ms),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (_, __) {
        final pulse = 1.0 + (_pulseController.value * 0.08);
        return Transform.scale(
          scale: pulse,
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primaryStart, AppColors.primaryEnd],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryStart.withOpacity(0.4 * _pulseController.value),
                  blurRadius: 40,
                  spreadRadius: 8,
                ),
              ],
            ),
            child: const Icon(
              Icons.noise_control_off,
              color: Colors.white,
              size: 48,
            ),
          ),
        );
      },
    ).animate().fadeIn(duration: 600.ms).scale(begin: const Offset(0.5, 0.5));
  }
}
