import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/audio_provider.dart';
import '../providers/subscription_provider.dart';
import '../theme.dart';

/// Pro / free-saves-left badge. Shared across Studio, Video, and Voice —
/// all three monetized "save" actions draw from the SAME 30-free-save pool
/// (AudioProvider.exportCount / freeExportLimit), so this one badge shows
/// the correct remaining count no matter which screen it's shown on.
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

/// Shows the monetization gate bottom sheet: offers a rewarded ad for one
/// more free save, or upgrading to Pro. Used identically by Studio (audio
/// export), Video (video export), and Voice (audio download) so all three
/// "save this result" actions share one gate and one free-save pool.
///
/// Creating (recording, importing, processing, generating, and previewing)
/// is ALWAYS free and unlimited everywhere — this gate only ever appears
/// when the user tries to save/download/export a result after the shared
/// 30 free saves are used up.
Future<void> showSaveGateSheet(
  BuildContext context, {
  required bool canWatchAd,
  required VoidCallback onWatchAd,
  required VoidCallback onUpgrade,
  String title = '${AudioProvider.freeExportLimit} free saves used',
}) {
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
    ),
  );
}

class SaveGateSheet extends StatelessWidget {
  final String title;
  final bool canWatchAd;
  final VoidCallback onWatchAd;
  final VoidCallback onUpgrade;

  const SaveGateSheet({
    super.key,
    required this.title,
    required this.canWatchAd,
    required this.onWatchAd,
    required this.onUpgrade,
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
                  canWatchAd ? 'Watch a short ad for 1 free save today' : 'Upgrade for unlimited access',
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
            onTap: onUpgrade,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: canWatchAd ? AppColors.surface : AppColors.textPrim,
                borderRadius: BorderRadius.circular(14),
                border: canWatchAd ? Border.all(color: AppColors.border, width: 0.5) : null,
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.workspace_premium_rounded, size: 18,
                    color: canWatchAd ? AppColors.textSec : AppColors.white),
                const SizedBox(width: 8),
                Text('Upgrade Pro  —  from ₹199/month',
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
