import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../services/analytics_service.dart';

class SubscriptionProvider extends ChangeNotifier {
  // Replace with your RevenueCat Android public API key from the RC dashboard.
  static const _apiKey = 'REPLACE_WITH_REVENUECAT_ANDROID_API_KEY';
  static const _entitlementId = 'pro';
  static const _adminEmail = String.fromEnvironment(
    'ADMIN_EMAIL',
    defaultValue: 'selvavishnu.m@gmail.com',
  );
  // Play Store review account — Pro unlocked without purchase so Google's
  // reviewers can access all paid features (they cannot make purchases).
  static const _reviewEmail = 'noiseclear.review@gmail.com';

  /// Unlocks every paid feature for every user, no purchase or login
  /// required. Exists ONLY for the Closed Testing track Google Play
  /// requires new apps to run for 14 days before granting Production
  /// access — testers need to exercise the full feature set, not just what
  /// a free tier exposes. Compiled in via
  /// `--dart-define=UNLOCK_ALL_FEATURES=true`; the default (and every
  /// production build) is false, so normal gating applies unless a build
  /// explicitly opts in. Never set this for a Production-track build.
  static const bool _unlockAllFeatures = bool.fromEnvironment(
    'UNLOCK_ALL_FEATURES',
    defaultValue: false,
  );

  bool _isPro = false;
  String _activeProduct = '';
  List<Package> _packages = [];
  bool _initialized = false;

  // Closed-testing override, then admin/review emails, then a real
  // purchase — first match wins, no purchase required for the first two.
  bool get isPro {
    if (_unlockAllFeatures) return true;
    if (_isPro) return true;
    final e = (FirebaseAuth.instance.currentUser?.email ?? '').toLowerCase().trim();
    return e == _adminEmail.toLowerCase() || e == _reviewEmail;
  }
  String get activeProduct => _activeProduct;
  List<Package> get packages => _packages;

  String get planLabel {
    // Checks the isPro GETTER (closed-testing override + admin/review +
    // real purchase), not the private _isPro field — otherwise a
    // closed-testing tester or admin/review account sees "Free" here even
    // though every gate elsewhere already treats them as Pro.
    if (!isPro) return 'Free';
    if (_unlockAllFeatures && !_isPro) return 'Pro (Test Build)';
    if (_activeProduct.contains('yearly') || _activeProduct.contains('annual')) return 'Pro Yearly';
    if (_activeProduct.contains('lifetime')) return 'Pro Lifetime';
    return 'Pro Monthly';
  }

  bool get initialized => _initialized;

  Future<void> initialize([String? userId]) async {
    if (_initialized) {
      if (userId != null) await loginUser(userId);
      return;
    }
    try {
      await Purchases.setLogLevel(LogLevel.error);
      final config = PurchasesConfiguration(_apiKey);
      await Purchases.configure(config);
      _initialized = true;
      // Auto-link to already-signed-in Firebase user if no uid supplied
      final uid = userId ?? FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) await loginUser(uid);
      await refresh();
    } catch (_) {}
  }

  Future<void> loginUser(String userId) async {
    if (!_initialized) return;
    try {
      await Purchases.logIn(userId);
      await refresh();
    } catch (_) {}
  }

  Future<void> logoutUser() async {
    if (!_initialized) return;
    try {
      await Purchases.logOut();
      _isPro = false;
      _activeProduct = '';
      await AnalyticsService.setUserType('free_anonymous');
      notifyListeners();
    } catch (_) {}
  }

  Future<void> refresh() async {
    if (!_initialized) return;
    try {
      final info = await Purchases.getCustomerInfo();
      _isPro = info.entitlements.active.containsKey(_entitlementId);
      _activeProduct = _isPro
          ? (info.entitlements.active[_entitlementId]?.productIdentifier ?? '')
          : '';
      await AnalyticsService.setUserType(_isPro ? _typeFromProduct(_activeProduct) : 'free_anonymous');
      notifyListeners();
    } catch (_) {}
  }

  Future<void> loadOfferings() async {
    if (!_initialized) return;
    try {
      final offerings = await Purchases.getOfferings();
      _packages = offerings.current?.availablePackages ?? [];
      notifyListeners();
    } catch (_) {}
  }

  Future<bool> purchase(Package package) async {
    if (!_initialized) return false;
    try {
      // purchasePackage returns a PurchaseResult (wraps CustomerInfo +
      // StoreTransaction) as of purchases_flutter v9 / Play Billing Library 8 —
      // it used to return CustomerInfo directly.
      final result = await Purchases.purchasePackage(package);
      final info = result.customerInfo;
      _isPro = info.entitlements.active.containsKey(_entitlementId);
      _activeProduct = _isPro
          ? (info.entitlements.active[_entitlementId]?.productIdentifier ?? '')
          : '';
      if (_isPro) {
        await AnalyticsService.logSubscriptionStarted(package.storeProduct.identifier);
        await AnalyticsService.setUserType(_typeFromProduct(_activeProduct));
      }
      notifyListeners();
      return _isPro;
    } catch (_) {
      return false;
    }
  }

  Future<bool> restorePurchases() async {
    if (!_initialized) return false;
    try {
      final info = await Purchases.restorePurchases();
      _isPro = info.entitlements.active.containsKey(_entitlementId);
      _activeProduct = _isPro
          ? (info.entitlements.active[_entitlementId]?.productIdentifier ?? '')
          : '';
      notifyListeners();
      return _isPro;
    } catch (_) {
      return false;
    }
  }

  String _typeFromProduct(String id) {
    if (id.contains('yearly') || id.contains('annual')) return 'pro_yearly';
    if (id.contains('lifetime')) return 'pro_lifetime';
    return 'pro_monthly';
  }
}
