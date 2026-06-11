import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../services/analytics_service.dart';

class SubscriptionProvider extends ChangeNotifier {
  // Replace with your RevenueCat Android public API key from the RC dashboard.
  static const _apiKey = 'REPLACE_WITH_REVENUECAT_ANDROID_API_KEY';
  static const _entitlementId = 'pro';

  bool _isPro = false;
  String _activeProduct = '';
  List<Package> _packages = [];
  bool _initialized = false;

  bool get isPro => _isPro;
  String get activeProduct => _activeProduct;
  List<Package> get packages => _packages;

  String get planLabel {
    if (!_isPro) return 'Free';
    if (_activeProduct.contains('yearly') || _activeProduct.contains('annual')) return 'Pro Yearly';
    if (_activeProduct.contains('lifetime')) return 'Pro Lifetime';
    return 'Pro Monthly';
  }

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
      if (userId != null) await loginUser(userId);
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
      final result = await Purchases.purchasePackage(package);
      _isPro = result.entitlements.active.containsKey(_entitlementId);
      _activeProduct = _isPro
          ? (result.entitlements.active[_entitlementId]?.productIdentifier ?? '')
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
