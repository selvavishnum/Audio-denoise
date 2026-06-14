import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/audio_params.dart';
import '../models/processing_stats.dart';
import '../providers/audio_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/subscription_provider.dart';
import '../services/deepfilter_service.dart';
import '../theme.dart';
import 'paywall_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AudioProvider>();
    final sub  = context.watch<SubscriptionProvider>();
    final auth = context.watch<AuthProvider>();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 28),
            _header(context),
            const SizedBox(height: 32),
            _section(context, 'Account', _accountSection(context, auth, sub)),
            _section(context, 'Default Preset', _presetSelector(context)),
            _section(context, 'AI Engine', _engineToggles(context, prov)),
            _section(context, 'About', _about(context)),
            if (prov.recentFiles.isNotEmpty)
              _section(context, 'Recent Files', _historyList(prov)),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Settings', style: Theme.of(context).textTheme.displayLarge),
      const SizedBox(height: 4),
      Text('App preferences', style: Theme.of(context).textTheme.bodyMedium),
    ],
  );

  Widget _section(BuildContext context, String title, Widget content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textDim,
              letterSpacing: 1.0,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: content,
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _accountSection(BuildContext context, AuthProvider auth, SubscriptionProvider sub) {
    final isAdmin = auth.isAdmin;
    final badgeLabel = isAdmin ? 'Admin' : (sub.isPro ? sub.planLabel : 'Free');
    final badgeActive = sub.isPro || isAdmin;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Profile card ──────────────────────────────────────────────
          Row(children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(28),
              ),
              clipBehavior: Clip.antiAlias,
              child: auth.isLoggedIn && auth.photoUrl != null
                  ? Image.network(auth.photoUrl!, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _initials(auth.displayName))
                  : _initials(auth.displayName),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  auth.isLoggedIn && auth.displayName.isNotEmpty
                      ? auth.displayName
                      : 'Guest User',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrim),
                ),
                const SizedBox(height: 3),
                if (auth.isLoggedIn && auth.email.isNotEmpty)
                  Text(auth.email,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSec),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                if (!auth.isLoggedIn)
                  const Text('Sign in to sync and unlock Pro',
                      style: TextStyle(fontSize: 12, color: AppColors.textSec)),
              ]),
            ),
            // Plan / Admin badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: badgeActive ? AppColors.textPrim : AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: badgeActive ? null : Border.all(color: AppColors.border, width: 0.5),
              ),
              child: Text(
                badgeLabel,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: badgeActive ? AppColors.white : AppColors.textSec),
              ),
            ),
          ]),

          const SizedBox(height: 16),
          const Divider(height: 0, color: AppColors.border, thickness: 0.5),
          const SizedBox(height: 14),

          // ── Actions ───────────────────────────────────────────────────
          if (!auth.isLoggedIn) ...[
            // Google Sign-In button
            _GoogleSignInButton(onTap: () async {
              final authProv = context.read<AuthProvider>();
              final ok = await authProv.signInWithGoogle();
              if (!context.mounted) return;
              if (ok) {
                final uid = authProv.user?.uid;
                if (uid != null) {
                  await context.read<SubscriptionProvider>().loginUser(uid);
                }
              } else if (authProv.lastError != null) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(authProv.lastError!),
                  duration: const Duration(seconds: 8),
                  backgroundColor: AppColors.danger,
                ));
              }
            }),
          ] else ...[
            // Upgrade button for non-Pro, non-admin users
            if (!sub.isPro && !isAdmin) ...[
              GestureDetector(
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const PaywallScreen())),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.textPrim,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('Upgrade to Pro',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                          color: AppColors.white)),
                ),
              ),
              const SizedBox(height: 10),
            ],
            // Sign Out — always shown when logged in
            GestureDetector(
              onTap: () async {
                await context.read<AuthProvider>().signOut();
                await context.read<SubscriptionProvider>().logoutUser();
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
                child: const Text('Sign Out',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                        color: AppColors.textSec)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _initials(String name) {
    final letter = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Center(
      child: Text(letter,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
              color: AppColors.textSec)),
    );
  }

  Widget _presetSelector(BuildContext context) {
    final prov = context.watch<AudioProvider>();
    const labels = {
      VoicePreset.natural: 'Clean',
      VoicePreset.crispy:  'Crispy',
      VoicePreset.radio:   'Radio',
      VoicePreset.deep:    'Deep',
      VoicePreset.pop:     'Pop',
      VoicePreset.hype:    'Hype',
    };
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Select the default voice preset applied on startup.',
            style: TextStyle(fontSize: 12, color: AppColors.textSec),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: VoicePreset.values.map((p) {
              final active = prov.params.preset == p;
              return GestureDetector(
                onTap: () => context.read<AudioProvider>().applyPreset(p),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: active ? AppColors.textPrim : AppColors.bg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: active ? AppColors.textPrim : AppColors.border,
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    labels[p] ?? p.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: active ? AppColors.white : AppColors.textSec,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _engineToggles(BuildContext context, AudioProvider prov) {
    final onnxReady    = DeepFilterService.isReady;
    final builtInReady = DeepFilterService.isBuiltInReady;
    final engineLabel  = onnxReady
        ? 'DeepFilterNet3 ONNX · Studio-grade quality'
        : builtInReady
            ? 'Built-in OMLSA-IMCRA · Always available'
            : 'Dart MMSE-STSA · Always-on fallback';
    return Column(
      children: [
        _SettingsRow(
          icon: Icons.auto_awesome_rounded,
          title: 'Neural AI',
          subtitle: engineLabel,
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.textPrim,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('On',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                    color: AppColors.white)),
          ),
        ),
        _divider(),
        _SettingsRow(
          icon: Icons.record_voice_over_rounded,
          title: 'Voice Isolator',
          subtitle: '2-pass aggressive extraction · Removes music & other voices',
          trailing: Switch(
            value: prov.isolatorEnabled,
            onChanged: (_) => context.read<AudioProvider>().toggleIsolator(),
            activeColor: AppColors.textPrim,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }

  Widget _about(BuildContext context) {
    return Column(
      children: [
        _SettingsRow(
          icon: Icons.info_outline_rounded,
          title: 'NoiseClear',
          subtitle: 'Professional audio noise cancellation',
          trailing: const Text(
            'v1.0.0',
            style: TextStyle(fontSize: 12, color: AppColors.textDim),
          ),
        ),
      ],
    );
  }

  Widget _historyList(AudioProvider prov) {
    return Column(
      children: prov.recentFiles.asMap().entries.map((e) {
        final item   = e.value;
        final isLast = e.key == prov.recentFiles.length - 1;
        return Column(children: [
          _HistoryRow(item: item),
          if (!isLast) _divider(),
        ]);
      }).toList(),
    );
  }

  Widget _divider() => const Divider(
    height: 0,
    indent: 56,
    endIndent: 0,
    color: AppColors.border,
    thickness: 0.5,
  );
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;

  const _SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle = '',
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: AppColors.textSec),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrim)),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(fontSize: 11, color: AppColors.textSec)),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}


class _GoogleSignInButton extends StatefulWidget {
  final Future<void> Function() onTap;
  const _GoogleSignInButton({required this.onTap});

  @override
  State<_GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends State<_GoogleSignInButton> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _loading ? null : () async {
        setState(() => _loading = true);
        await widget.onTap();
        if (mounted) setState(() => _loading = false);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.textPrim,
          borderRadius: BorderRadius.circular(12),
        ),
        child: _loading
            ? const SizedBox(
                height: 18,
                child: Center(
                  child: SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.white),
                  ),
                ),
              )
            : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.login_rounded, size: 16, color: AppColors.white),
                SizedBox(width: 8),
                Text('Sign in with Google',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                        color: AppColors.white)),
              ]),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final HistoryItem item;
  const _HistoryRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.audio_file_rounded, size: 18, color: AppColors.textSec),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.name,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrim),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(_timeAgo(item.date),
                style: const TextStyle(fontSize: 11, color: AppColors.textSec)),
          ]),
        ),
        Text(
          '${item.noiseReductionPct.round()}% cleaned',
          style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textDim),
        ),
      ]),
    );
  }

  static String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
