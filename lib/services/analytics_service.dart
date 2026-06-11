import 'package:firebase_analytics/firebase_analytics.dart';

class AnalyticsService {
  static final _a = FirebaseAnalytics.instance;

  static Future<void> setUserType(String type) async {
    await _a.setUserProperty(name: 'user_type', value: type);
  }

  static Future<void> logAppOpen(String userType) async {
    await _a.logEvent(name: 'app_open_nc', parameters: {'user_type': userType});
  }

  static Future<void> logExportCompleted({
    required int exportCount,
    required String format,
    required String userType,
  }) async {
    await _a.logEvent(name: 'export_completed', parameters: {
      'export_count': exportCount,
      'format': format,
      'user_type': userType,
    });
  }

  static Future<void> logFreeLimitReached() async {
    await _a.logEvent(name: 'free_limit_reached');
  }

  static Future<void> logRewardedAdShown() async {
    await _a.logEvent(name: 'rewarded_ad_shown');
  }

  static Future<void> logRewardedAdCompleted() async {
    await _a.logEvent(name: 'rewarded_ad_completed');
  }

  static Future<void> logRewardedAdSkipped() async {
    await _a.logEvent(name: 'rewarded_ad_skipped');
  }

  static Future<void> logBonusExportEarned() async {
    await _a.logEvent(name: 'bonus_export_earned');
  }

  static Future<void> logPaywallShown(String trigger) async {
    await _a.logEvent(name: 'paywall_shown', parameters: {'trigger': trigger});
  }

  static Future<void> logPlanSelected(String plan) async {
    await _a.logEvent(name: 'plan_selected', parameters: {'plan': plan});
  }

  static Future<void> logGoogleLoginStarted() async {
    await _a.logEvent(name: 'google_login_started');
  }

  static Future<void> logGoogleLoginCompleted() async {
    await _a.logEvent(name: 'google_login_completed');
  }

  static Future<void> logSubscriptionStarted(String plan) async {
    await _a.logEvent(name: 'subscription_started', parameters: {'plan': plan});
  }
}
