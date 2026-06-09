import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/app_provider.dart';
import '../../services/usage_service.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/gradient_button.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        title: Text('Settings',
            style: GoogleFonts.rajdhani(
                fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: 1)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildUsageSection(context),
            const SizedBox(height: 20),
            _buildPromoSection(context),
            const SizedBox(height: 20),
            _buildAboutSection(),
            const SizedBox(height: 20),
            _buildPrivacySection(),
          ],
        ),
      ),
    );
  }

  Widget _buildUsageSection(BuildContext context) {
    return Consumer<SessionProvider>(
      builder: (_, session, __) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(title: 'Usage', icon: Icons.data_usage),
            const SizedBox(height: 12),
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: session.isUnlimited
                  ? _buildUnlimitedBadge()
                  : _buildUsageStats(session),
            ),
          ],
        );
      },
    ).animate().fadeIn().slideY(begin: 0.05, end: 0);
  }

  Widget _buildUnlimitedBadge() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: AppColors.goldGradient,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.all_inclusive, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Unlimited Access',
                  style: TextStyle(
                      color: AppColors.premium,
                      fontWeight: FontWeight.w700,
                      fontSize: 16)),
              Text('No usage limits. Enjoy studio-grade audio.',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUsageStats(SessionProvider session) {
    final used = AppConstants.maxFreeDenoises - session.remainingUses;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Free Denoises Used',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
            Text(
              '$used / ${AppConstants.maxFreeDenoises}',
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: session.usagePercent,
            backgroundColor: AppColors.border,
            valueColor: AlwaysStoppedAnimation(
              session.usagePercent > 0.8
                  ? AppColors.recording
                  : AppColors.primaryStart,
            ),
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${session.remainingUses} uses remaining',
          style: TextStyle(
            color: session.remainingUses < 10
                ? AppColors.recording
                : AppColors.textMuted,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildPromoSection(BuildContext context) {
    return Consumer<SessionProvider>(
      builder: (_, session, __) {
        if (session.isUnlimited) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(title: 'Promo Code', icon: Icons.local_offer),
            const SizedBox(height: 12),
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.campaign, color: AppColors.premium, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Instagram Influencer? Get unlimited access free!',
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Promoters and content creators receive a unique promo code for unlimited noise cancellation.',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  GradientButton(
                    label: 'Enter Promo Code',
                    icon: Icons.vpn_key,
                    gradient: AppColors.goldGradient,
                    height: 44,
                    onPressed: () => _showPromoDialog(context, session),
                  ),
                ],
              ),
            ),
          ],
        ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.05, end: 0);
      },
    );
  }

  void _showPromoDialog(BuildContext context, SessionProvider session) {
    showDialog(context: context, builder: (_) => _PromoDialog(session: session));
  }

  Widget _buildAboutSection() {
    final items = [
      _SettingsTile(
        icon: Icons.info_outline,
        title: 'App Version',
        trailing: AppConstants.appVersion,
      ),
      _SettingsTile(
        icon: Icons.star_rate_outlined,
        title: 'Rate ClearWave Studio',
        onTap: () {},
      ),
      _SettingsTile(
        icon: Icons.share_outlined,
        title: 'Share with Friends',
        onTap: () {},
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'About', icon: Icons.info_outline),
        const SizedBox(height: 12),
        GlassCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: items.asMap().entries.map((e) => Column(
              children: [
                e.value,
                if (e.key < items.length - 1)
                  const Divider(height: 1, color: AppColors.border, indent: 48),
              ],
            )).toList(),
          ),
        ),
      ],
    ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.05, end: 0);
  }

  Widget _buildPrivacySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'Privacy & Storage', icon: Icons.privacy_tip_outlined),
        const SizedBox(height: 12),
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Row(
                children: [
                  Icon(Icons.lock, color: AppColors.success, size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('100% Local Processing',
                            style: TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 14)),
                        SizedBox(height: 2),
                        Text(
                          'Your audio never leaves your device. All noise cancellation happens locally.',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(color: AppColors.border),
              const SizedBox(height: 12),
              _PrivacyPoint(icon: Icons.cloud_off, text: 'No cloud uploads'),
              const SizedBox(height: 6),
              _PrivacyPoint(icon: Icons.no_accounts, text: 'No account required'),
              const SizedBox(height: 6),
              _PrivacyPoint(icon: Icons.storage, text: 'Files stored in app private folder'),
            ],
          ),
        ),
      ],
    ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.05, end: 0);
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
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
              letterSpacing: 1.2),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Icon(icon, color: AppColors.textSecondary, size: 20),
      title: Text(title,
          style: const TextStyle(
              color: AppColors.textPrimary, fontSize: 14)),
      trailing: trailing != null
          ? Text(trailing!,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13))
          : onTap != null
              ? const Icon(Icons.chevron_right,
                  color: AppColors.textMuted, size: 18)
              : null,
      onTap: onTap,
    );
  }
}

class _PrivacyPoint extends StatelessWidget {
  final IconData icon;
  final String text;

  const _PrivacyPoint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.textMuted, size: 14),
        const SizedBox(width: 8),
        Text(text,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 12)),
      ],
    );
  }
}

class _PromoDialog extends StatefulWidget {
  final SessionProvider session;

  const _PromoDialog({required this.session});

  @override
  State<_PromoDialog> createState() => _PromoDialogState();
}

class _PromoDialogState extends State<_PromoDialog> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: AppColors.goldGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.local_offer, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 14),
            const Text('Enter Promo Code',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text(
              'Instagram influencers and content creators get unlimited access',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _ctrl,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'PROMO CODE',
                errorText: _error,
                prefixIcon: const Icon(Icons.vpn_key, color: AppColors.textMuted),
              ),
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            GradientButton(
              label: 'Activate',
              gradient: AppColors.goldGradient,
              isLoading: _loading,
              onPressed: _loading ? null : _activate,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _activate() async {
    setState(() { _loading = true; _error = null; });
    final ok = await widget.session.activateCode(_ctrl.text);
    if (mounted) {
      if (ok) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unlimited access activated!')));
      } else {
        setState(() { _loading = false; _error = 'Invalid or expired code'; });
      }
    }
  }
}
