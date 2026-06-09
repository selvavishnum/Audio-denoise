import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';

class UsageService {
  static UsageService? _instance;
  static UsageService get instance => _instance ??= UsageService._();
  UsageService._();

  Future<int> getDenoiseCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(AppConstants.keyDenoiseCount) ?? 0;
  }

  Future<int> getRemainingUses() async {
    if (await isUnlimited()) return 999999;
    final count = await getDenoiseCount();
    return (AppConstants.maxFreeDenoises - count).clamp(0, AppConstants.maxFreeDenoises);
  }

  Future<bool> canDenoise() async {
    if (await isUnlimited()) return true;
    final count = await getDenoiseCount();
    return count < AppConstants.maxFreeDenoises;
  }

  Future<void> incrementDenoiseCount() async {
    if (await isUnlimited()) return;
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt(AppConstants.keyDenoiseCount) ?? 0;
    await prefs.setInt(AppConstants.keyDenoiseCount, count + 1);
  }

  Future<bool> isUnlimited() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(AppConstants.keyIsUnlimited) ?? false;
  }

  Future<bool> activatePromoCode(String code) async {
    final normalizedCode = code.trim().toUpperCase();
    if (!AppConstants.validPromoCodes.contains(normalizedCode)) {
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyIsUnlimited, true);
    await prefs.setString(AppConstants.keyActivatedCode, normalizedCode);
    return true;
  }

  Future<String?> getActivatedCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.keyActivatedCode);
  }

  Future<bool> isOnboardingDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(AppConstants.keyOnboardingDone) ?? false;
  }

  Future<void> markOnboardingDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyOnboardingDone, true);
  }

  double getUsagePercent(int count) {
    return (count / AppConstants.maxFreeDenoises).clamp(0.0, 1.0);
  }
}
