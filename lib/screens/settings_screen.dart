import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/audio_params.dart';
import '../models/processing_stats.dart';
import '../providers/audio_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/subscription_provider.dart';
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
            _section(context, 'Processing', _processingToggles(context, prov)),
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
    return Column(
      children: [
        _SettingsRow(
          icon: sub.isPro ? Icons.workspace_premium_rounded : Icons.person_outline_rounded,
          title: sub.isPro ? sub.planLabel : 'Free Plan',
          subtitle: sub.isPro
              ? (auth.isLoggedIn ? auth.email : 'Unlimited access unlocked')
              : '${30} exports free · 1/day with ad after',
          trailing: sub.isPro
              ? const _Badge('Active')
              : GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PaywallScreen()),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.textPrim,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('Upgrade',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                            color: AppColors.white)),
                  ),
                ),
        ),
        if (auth.isLoggedIn) ...[
          _divider(),
          _SettingsRow(
            icon: Icons.logout_rounded,
            title: 'Sign Out',
            subtitle: auth.email,
            trailing: GestureDetector(
              onTap: () async {
                await context.read<AuthProvider>().signOut();
                await context.read<SubscriptionProvider>().logoutUser();
              },
              child: const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textDim),
            ),
          ),
        ],
      ],
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

  Widget _processingToggles(BuildContext context, AudioProvider prov) {
    return Column(
      children: [
        _SettingsRow(
          icon: Icons.graphic_eq_rounded,
          title: 'Noise Reduction',
          subtitle: 'MMSE Wiener filter with spectral gating',
          trailing: const _Badge('On'),
        ),
        _divider(),
        _SettingsRow(
          icon: Icons.compress_rounded,
          title: 'Dynamic Compression',
          subtitle: 'Automatic level and loudness control',
          trailing: const _Badge('On'),
        ),
        _divider(),
        _SettingsRow(
          icon: Icons.hearing_rounded,
          title: 'Voice Activity Detection',
          subtitle: 'Silence gating with adaptive hold time',
          trailing: const _Badge('On'),
        ),
        _divider(),
        _SettingsRow(
          icon: Icons.hd_rounded,
          title: 'HD Mode',
          subtitle: 'FFmpeg afftdn pre-processing for deeper noise removal',
          trailing: Switch(
            value: prov.hdModeEnabled,
            onChanged: (_) => context.read<AudioProvider>().toggleHdMode(),
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
        _divider(),
        _SettingsRow(
          icon: Icons.tune_rounded,
          title: 'Audio Engine',
          subtitle: 'MMSE Wiener  ·  Soft spectral gate  ·  LUFS normalize',
        ),
        _divider(),
        _SettingsRow(
          icon: Icons.code_rounded,
          title: 'Built with Flutter',
          subtitle: 'Flutter 3.44 · Dart 3.12 · Android API 24+',
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

class _Badge extends StatelessWidget {
  final String label;
  const _Badge(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.textPrim,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.white)),
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
