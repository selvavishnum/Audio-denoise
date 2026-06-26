import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../providers/auth_provider.dart';
import '../providers/subscription_provider.dart';
import '../services/analytics_service.dart';
import '../theme.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  int _selectedIndex = 1; // default: yearly (best value)
  bool _loading = false;

  static const _fallbackPlans = [
    _PlanData(id: 'monthly', title: 'Monthly', price: '₹199', period: '/month', badge: null),
    _PlanData(id: 'yearly',  title: 'Yearly',  price: '₹799', period: '/year',  badge: 'BEST VALUE'),
    _PlanData(id: 'lifetime',title: 'Lifetime',price: '₹999', period: ' once',  badge: 'FOREVER'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SubscriptionProvider>().loadOfferings();
    });
  }

  @override
  Widget build(BuildContext context) {
    final sub  = context.watch<SubscriptionProvider>();
    final auth = context.watch<AuthProvider>();

    if (sub.isPro) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.workspace_premium_rounded, size: 64, color: AppColors.textPrim),
              const SizedBox(height: 20),
              Text('You\'re on ${sub.planLabel}',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrim)),
              const SizedBox(height: 8),
              const Text('Enjoy unlimited access to all features.',
                  style: TextStyle(fontSize: 14, color: AppColors.textSec)),
              const SizedBox(height: 32),
              _OutlineBtn(label: 'Go Back', onTap: () => Navigator.pop(context)),
            ]),
          ),
        ),
      );
    }

    final packages = sub.packages;
    final plans    = _resolvePlans(packages);
    // Guard against the default selection (1) exceeding a shorter plan list —
    // e.g. when only one package type is configured in RevenueCat.
    final selIdx   = _selectedIndex < plans.length ? _selectedIndex : 0;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 8, 0),
              child: Row(
                children: [
                  const Expanded(child: SizedBox()),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppColors.textDim),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon + title
                    Container(
                      width: 56, height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.textPrim,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.workspace_premium_rounded, color: AppColors.white, size: 28),
                    ),
                    const SizedBox(height: 16),
                    const Text('NoiseClear Pro',
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.textPrim)),
                    const SizedBox(height: 6),
                    const Text('Professional audio, unlimited exports, zero ads.',
                        style: TextStyle(fontSize: 14, color: AppColors.textSec)),
                    const SizedBox(height: 28),

                    // Plan cards
                    ...plans.asMap().entries.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _PlanCard(
                        plan: e.value,
                        selected: _selectedIndex == e.key,
                        onTap: () => setState(() => _selectedIndex = e.key),
                      ),
                    )),

                    const SizedBox(height: 20),

                    // Feature list
                    const _FeatureRow(icon: Icons.all_inclusive_rounded,      text: 'Unlimited exports — no daily limits'),
                    const _FeatureRow(icon: Icons.block_rounded,              text: 'Zero ads'),
                    const _FeatureRow(icon: Icons.content_cut_rounded,        text: 'Trim, join, and mix audio'),
                    const _FeatureRow(icon: Icons.tune_rounded,               text: 'All 6 presets + advanced EQ controls'),
                    const _FeatureRow(icon: Icons.hd_rounded,                 text: 'HD Mode for deeper noise removal'),
                    const _FeatureRow(icon: Icons.new_releases_rounded,       text: 'All future features included'),
                    const SizedBox(height: 12),

                    // Signed-in notice
                    if (auth.isLoggedIn)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(children: [
                          const Icon(Icons.check_circle_outline_rounded, size: 14, color: AppColors.success),
                          const SizedBox(width: 6),
                          Expanded(child: Text('Signed in as ${auth.email}',
                              style: const TextStyle(fontSize: 11, color: AppColors.textSec))),
                        ]),
                      ),

                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),

            // Bottom CTA
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
              decoration: const BoxDecoration(
                color: AppColors.bg,
                border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
              ),
              child: Column(children: [
                _loading
                    ? const SizedBox(
                        height: 50,
                        child: Center(child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.textPrim)),
                      )
                    : GestureDetector(
                        onTap: () => _handlePurchase(context, plans, sub, auth),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          decoration: BoxDecoration(
                            color: AppColors.textPrim,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            auth.isLoggedIn ? 'Subscribe — ${plans[selIdx].price}' : 'Continue with Google',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.white),
                          ),
                        ),
                      ),
                const SizedBox(height: 10),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _TextBtn(
                    label: 'Restore Purchase',
                    onTap: () => _handleRestore(context, sub),
                  ),
                ]),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  List<_PlanData> _resolvePlans(List<Package> packages) {
    if (packages.isEmpty) return _fallbackPlans;
    final result = <_PlanData>[];
    for (final p in packages) {
      final id    = p.storeProduct.identifier;
      final price = p.storeProduct.priceString;
      if (p.packageType == PackageType.monthly) {
        result.add(_PlanData(id: id, title: 'Monthly', price: price, period: '/month', badge: null));
      } else if (p.packageType == PackageType.annual) {
        result.add(_PlanData(id: id, title: 'Yearly', price: price, period: '/year', badge: 'BEST VALUE'));
      } else if (p.packageType == PackageType.lifetime) {
        result.add(_PlanData(id: id, title: 'Lifetime', price: price, period: ' once', badge: 'FOREVER'));
      }
    }
    return result.isEmpty ? _fallbackPlans : result;
  }

  Future<void> _handlePurchase(
    BuildContext context,
    List<_PlanData> plans,
    SubscriptionProvider sub,
    AuthProvider auth,
  ) async {
    setState(() => _loading = true);

    final selIdx = _selectedIndex < plans.length ? _selectedIndex : 0;
    await AnalyticsService.logPlanSelected(plans[selIdx].id);

    if (!auth.isLoggedIn) {
      final ok = await auth.signInWithGoogle();
      if (!ok || !mounted) {
        setState(() => _loading = false);
        return;
      }
      await sub.loginUser(auth.user!.uid);
    }

    if (sub.packages.isEmpty) {
      // RevenueCat not configured yet — show informational message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchases not available — contact support')),
        );
      }
      setState(() => _loading = false);
      return;
    }

    final pkg = sub.packages.length > _selectedIndex ? sub.packages[_selectedIndex] : sub.packages.first;
    final ok  = await sub.purchase(pkg);

    if (!mounted) return;
    setState(() => _loading = false);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Welcome to Pro! Enjoy unlimited access.')),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Purchase could not be completed. Try again.')),
      );
    }
  }

  Future<void> _handleRestore(BuildContext context, SubscriptionProvider sub) async {
    setState(() => _loading = true);
    final ok = await sub.restorePurchases();
    if (!mounted) return;
    setState(() => _loading = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Purchase restored successfully!' : 'No previous purchase found.'),
    ));
    if (ok) Navigator.pop(context);
  }
}

// ── Data model ────────────────────────────────────────────────────────────────

class _PlanData {
  final String id;
  final String title;
  final String price;
  final String period;
  final String? badge;
  const _PlanData({required this.id, required this.title, required this.price,
      required this.period, this.badge});
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  final _PlanData plan;
  final bool selected;
  final VoidCallback onTap;
  const _PlanCard({required this.plan, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? AppColors.textPrim : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.textPrim : AppColors.border,
            width: selected ? 1.5 : 0.5,
          ),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(plan.title,
                    style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600,
                      color: selected ? AppColors.white : AppColors.textPrim,
                    )),
                if (plan.badge != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.white : AppColors.textPrim,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(plan.badge!,
                        style: TextStyle(
                          fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5,
                          color: selected ? AppColors.textPrim : AppColors.white,
                        )),
                  ),
                ],
              ]),
            ]),
          ),
          RichText(
            text: TextSpan(children: [
              TextSpan(
                text: plan.price,
                style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700,
                  color: selected ? AppColors.white : AppColors.textPrim,
                ),
              ),
              TextSpan(
                text: plan.period,
                style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w400,
                  color: selected ? AppColors.white.withAlpha(179) : AppColors.textSec,
                ),
              ),
            ]),
          ),
          const SizedBox(width: 10),
          Icon(
            selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
            size: 20,
            color: selected ? AppColors.white : AppColors.textDim,
          ),
        ]),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _FeatureRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Icon(icon, size: 16, color: AppColors.textPrim),
        const SizedBox(width: 10),
        Expanded(child: Text(text,
            style: const TextStyle(fontSize: 13, color: AppColors.textSec))),
      ]),
    );
  }
}

class _OutlineBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _OutlineBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border, width: 0.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSec)),
      ),
    );
  }
}

class _TextBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _TextBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(label,
            style: const TextStyle(fontSize: 12, color: AppColors.textDim,
                decoration: TextDecoration.underline, decorationColor: AppColors.textDim)),
      ),
    );
  }
}
