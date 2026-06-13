import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/audio_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/subscription_provider.dart';
import 'screens/onboarding_screen.dart';
import 'screens/record_screen.dart';
import 'screens/denoise_screen.dart';
import 'screens/video_denoise_screen.dart';
import 'screens/edit_screen.dart';
import 'screens/settings_screen.dart';
import 'services/ad_service.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: AppColors.bg,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  await _requestPermissions();

  // Firebase — wrapped so the app still launches if google-services.json
  // has not yet been replaced with real credentials.
  try {
    await Firebase.initializeApp();
  } catch (_) {}

  // AdMob initializes asynchronously; pre-loads first rewarded ad.
  unawaited(AdService.initialize());

  runApp(const NoiseClearApp());
}

void unawaited(Future<void> future) {}

Future<void> _requestPermissions() async {
  final perms = <Permission>[Permission.microphone];
  if (Platform.isAndroid) perms.add(Permission.storage);
  await perms.request();
}

class NoiseClearApp extends StatelessWidget {
  const NoiseClearApp({super.key});

  static Future<bool> _isOnboarded() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('onboarded') ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AudioProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(
          create: (_) => SubscriptionProvider()..initialize(),
        ),
      ],
      child: MaterialApp(
        title: 'NoiseClear',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routes: {'/home': (_) => const RootShell()},
        home: FutureBuilder<bool>(
          future: _isOnboarded(),
          builder: (ctx, snap) {
            if (!snap.hasData) {
              return const Scaffold(backgroundColor: AppColors.bg);
            }
            return snap.data! ? const RootShell() : const OnboardingScreen();
          },
        ),
      ),
    );
  }
}

// ── Root shell with bottom navigation ─────────────────────────────────────────

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  static const _screens = <Widget>[
    RecordScreen(),
    DenoiseScreen(),
    VideoDenoiseScreen(),
    EditScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: _BottomNav(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}

// ── Bottom navigation bar ──────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _BottomNav({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              _NavItem(icon: Icons.mic_none_rounded,    activeIcon: Icons.mic_rounded,          label: 'Record',   index: 0, current: currentIndex, onTap: onTap),
              _NavItem(icon: Icons.graphic_eq_outlined, activeIcon: Icons.graphic_eq,           label: 'Denoise',  index: 1, current: currentIndex, onTap: onTap),
              _NavItem(icon: Icons.videocam_outlined,   activeIcon: Icons.videocam_rounded,     label: 'Video',    index: 2, current: currentIndex, onTap: onTap),
              _NavItem(icon: Icons.content_cut_rounded, activeIcon: Icons.content_cut_rounded,  label: 'Editor',   index: 3, current: currentIndex, onTap: onTap),
              _NavItem(icon: Icons.settings_outlined,   activeIcon: Icons.settings_rounded,     label: 'Settings', index: 4, current: currentIndex, onTap: onTap),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon, activeIcon;
  final String label;
  final int index, current;
  final ValueChanged<int> onTap;

  const _NavItem({
    required this.icon, required this.activeIcon,
    required this.label,   required this.index,
    required this.current, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool active = index == current;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(index),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width:  active ? 32 : 0,
              height: 2.5,
              margin: const EdgeInsets.only(bottom: 5),
              decoration: BoxDecoration(
                color: active ? AppColors.textPrim : Colors.transparent,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
            Icon(
              active ? activeIcon : icon,
              color: active ? AppColors.textPrim : AppColors.textDim,
              size: 22,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? AppColors.textPrim : AppColors.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
