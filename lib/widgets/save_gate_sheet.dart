import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/audio_provider.dart';
import '../providers/subscription_provider.dart';
import '../theme.dart';

/// Pro / free-saves-left badge. Shared across Studio, Video, and Voice —
/// all three monetized "save" actions draw from the same tiered pool
/// (5 free before sign-in, 25 more after — see AudioProvider's
/// anonFreeLimit/loggedInFreeLimit), so this one badge shows the correct
/// remaining count for whichever tier is currently active, no matter which
/// screen it's shown on.
class FreeLimitBadge extends StatelessWidget {
  const FreeLimitBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final isPro = context.watch<SubscriptionProvider>().isPro;
    final prov  = context.watch<AudioProvider>();
    if (isPro) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: AppColors.textPrim, borderRadius: BorderRadius.circular(20)),
        child: const Text('PRO',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                color: AppColors.white, letterSpacing: 0.5)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Text(
        prov.hasReachedFreeLimit ? 'Limit reached' : '${prov.freeExportsLeft} free left',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSec),
      ),
    );
  }
}

/// Shows the monetization gate bottom sheet. Two distinct end-states:
///
///  • [needsLogin] true (anonymous user, used up the 5-free anonymous tier):
///    primary action is "Sign in with Google" to unlock the 25-free
///    logged-in tier — NOT a purchase prompt yet.
///  • [needsLogin] false (signed-in user, used up the 25-free logged-in
///    tier): primary action is "Upgrade Pro", same as before.
///
/// Either way, a rewarded-ad "+1 free save today" option is offered first
/// when available. Used identically by Studio (audio export), Video (video
/// export), and Voice (audio download).
///
/// Creating (recording, importing, processing, generating, and previewing)
/// is ALWAYS free and unlimited everywhere — this gate only ever appears
/// when the user tries to save/download/export a result after their
/// current tier's free allowance is used up.
Future<void> showSaveGateSheet(
  BuildContext context, {
  required bool canWatchAd,
  required VoidCallback onWatchAd,
  required VoidCallback onUpgrade,
  bool needsLogin = false,
  VoidCallback? onSignIn,
  String title = '${AudioProvider.freeExportLimit} free saves used',
}) {
  assert(!needsLogin || onSignIn != null,
      'onSignIn is required when needsLogin is true');
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => SaveGateSheet(
      title: title,
      canWatchAd: canWatchAd,
      onWatchAd: onWatchAd,
      onUpgrade: onUpgrade,
      needsLogin: needsLogin,
      onSignIn: onSignIn,
    ),
  );
}

class SaveGateSheet extends StatelessWidget {
  final String title;
  final bool canWatchAd;
  final VoidCallback onWatchAd;
  final VoidCallback onUpgrade;
  final bool needsLogin;
  final VoidCallback? onSignIn;

  const SaveGateSheet({
    super.key,
    required this.title,
    required this.canWatchAd,
    required this.onWatchAd,
    required this.onUpgrade,
    this.needsLogin = false,
    this.onSignIn,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border, width: 0.5),
              ),
              child: const Icon(Icons.lock_open_rounded, size: 22, color: AppColors.textPrim),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrim)),
                const SizedBox(height: 2),
                Text(
                  canWatchAd
                      ? 'Watch a short ad for 1 free save today'
                      : needsLogin
                          ? 'Sign in with Google for 25 more free saves'
                          : 'Upgrade for unlimited access',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSec),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 24),
          if (canWatchAd) ...[
            GestureDetector(
              onTap: onWatchAd,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.textPrim,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.play_circle_rounded, size: 18, color: AppColors.white),
                  SizedBox(width: 8),
                  Text('Watch Ad  —  1 Free Save Today',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.white)),
                ]),
              ),
            ),
            const SizedBox(height: 10),
          ],
          GestureDetector(
            onTap: needsLogin ? onSignIn : onUpgrade,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: canWatchAd ? AppColors.surface : AppColors.textPrim,
                borderRadius: BorderRadius.circular(14),
                border: canWatchAd ? Border.all(color: AppColors.border, width: 0.5) : null,
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(needsLogin ? Icons.login_rounded : Icons.workspace_premium_rounded, size: 18,
                    color: canWatchAd ? AppColors.textSec : AppColors.white),
                const SizedBox(width: 8),
                Text(
                    needsLogin
                        ? 'Sign in with Google  —  25 more free'
                        : 'Upgrade Pro  —  from ₹199/month',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                        color: canWatchAd ? AppColors.textSec : AppColors.white)),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
