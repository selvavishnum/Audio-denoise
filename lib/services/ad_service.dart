import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdService {
  // Replace with real rewarded ad unit ID from AdMob console.
  // Current value is Google's official test ID — shows real test ads.
  static const _rewardedAdUnitId = 'ca-app-pub-3940256099942544/5224354917';

  static RewardedAd? _ad;
  static bool _loading = false;

  static Future<void> initialize() async {
    await MobileAds.instance.initialize();
    _loadAd();
  }

  static void _loadAd() {
    if (_loading) return;
    _loading = true;
    RewardedAd.load(
      adUnitId: _rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _loading = false;
        },
        onAdFailedToLoad: (_) {
          _ad = null;
          _loading = false;
        },
      ),
    );
  }

  static bool get isReady => _ad != null;

  // Returns true if the user earned the reward, false if they skipped/failed.
  static Future<bool> showRewardedAd({
    required void Function() onRewarded,
  }) async {
    if (_ad == null) return false;
    bool rewarded = false;

    _ad!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _ad = null;
        _loadAd();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        _ad = null;
        _loadAd();
      },
    );

    await _ad!.show(
      onUserEarnedReward: (_, __) {
        rewarded = true;
        onRewarded();
      },
    );
    return rewarded;
  }
}
