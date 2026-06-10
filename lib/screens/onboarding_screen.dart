import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';
import 'package:flutter_animate/flutter_animate.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _ctrl  = PageController();
  int _page    = 0;

  static const _slides = [
    _Slide(
      icon: Icons.mic_rounded,
      color: AppColors.amber,
      title: 'Record or Import',
      body: 'Capture your voice live or import any audio file — WAV, MP3, M4A, FLAC, and more.',
    ),
    _Slide(
      icon: Icons.graphic_eq_rounded,
      color: AppColors.violet,
      title: 'AI Noise Removal',
      body: 'Remove fans, traffic, and crowd noise automatically. Your voice stays crystal clear.',
    ),
    _Slide(
      icon: Icons.ios_share_rounded,
      color: AppColors.cyan,
      title: 'Export Anywhere',
      body: 'Share studio-grade clean audio as WAV or MP3. Everything processed on-device — your audio never leaves your phone.',
    ),
  ];

  void _next() {
    if (_page < _slides.length - 1) {
      _ctrl.nextPage(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _finish();
    }
  }

  void _skip() => _finish();

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarded', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/home');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 12, 20, 0),
                child: _page < _slides.length - 1
                    ? GestureDetector(
                        onTap: _skip,
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Text(
                            'Skip',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textDim,
                            ),
                          ),
                        ),
                      )
                    : const SizedBox(height: 40),
              ),
            ),

            // Slides
            Expanded(
              child: PageView.builder(
                controller: _ctrl,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _SlideView(slide: _slides[i]),
              ),
            ),

            // Dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _slides.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width:  _page == i ? 22 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: _page == i ? AppColors.textPrim : AppColors.border,
                    borderRadius: BorderRadius.circular(3.5),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 36),

            // Next / Get Started
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
              child: GestureDetector(
                onTap: _next,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.textPrim,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      _page < _slides.length - 1 ? 'Next' : 'Get Started',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Slide {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  const _Slide({
    required this.icon, required this.color,
    required this.title, required this.body,
  });
}

class _SlideView extends StatelessWidget {
  final _Slide slide;
  const _SlideView({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: slide.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(slide.icon, size: 48, color: slide.color),
          )
          .animate()
          .scale(begin: const Offset(0.8, 0.8), duration: 420.ms, curve: Curves.easeOutBack)
          .fadeIn(duration: 320.ms),

          const SizedBox(height: 36),

          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrim,
              letterSpacing: -0.5,
            ),
          )
          .animate()
          .fadeIn(delay: 80.ms, duration: 340.ms)
          .slideY(begin: 0.15, end: 0, delay: 80.ms, duration: 340.ms, curve: Curves.easeOut),

          const SizedBox(height: 16),

          Text(
            slide.body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              color: AppColors.textSec,
              height: 1.55,
            ),
          )
          .animate()
          .fadeIn(delay: 160.ms, duration: 340.ms)
          .slideY(begin: 0.15, end: 0, delay: 160.ms, duration: 340.ms, curve: Curves.easeOut),
        ],
      ),
    );
  }
}
