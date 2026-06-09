import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/app_provider.dart';
import '../../services/storage_service.dart';
import '../../widgets/common/glass_card.dart';
import '../denoiser/denoiser_screen.dart';
import '../library/library_screen.dart';
import '../recorder/recorder_screen.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const _HomePage(),
    const LibraryScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => RecorderProvider()),
        ChangeNotifierProvider(create: (_) => DenoiserProvider()),
        ChangeNotifierProvider(create: (_) => LibraryProvider()..loadProjects()),
        ChangeNotifierProvider(create: (_) => SessionProvider()..refresh()),
      ],
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: _pages,
        ),
        bottomNavigationBar: _buildNavBar(),
      ),
    );
  }

  Widget _buildNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        border: const Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(icon: Icons.home_filled, label: 'Home', index: 0,
                  currentIndex: _currentIndex, onTap: (i) => setState(() => _currentIndex = i)),
              _NavItem(icon: Icons.library_music, label: 'Library', index: 1,
                  currentIndex: _currentIndex, onTap: (i) => setState(() => _currentIndex = i)),
              _NavItem(icon: Icons.settings, label: 'Settings', index: 2,
                  currentIndex: _currentIndex, onTap: (i) => setState(() => _currentIndex = i)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final int currentIndex;
  final void Function(int) onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = index == currentIndex;
    return GestureDetector(
      onTap: () => onTap(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryStart.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? AppColors.primaryStart : AppColors.textMuted,
              size: 22,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? AppColors.primaryStart : AppColors.textMuted,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomePage extends StatelessWidget {
  const _HomePage();

  Future<void> _importAudio(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return;
    final filePath = result.files.first.path;
    if (filePath == null) return;

    final project = await StorageService.instance.createProjectFromFile(filePath);
    if (context.mounted) {
      context.read<LibraryProvider>().loadProjects();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DenoiserScreen(project: project),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context),
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildUsageCard(context),
                const SizedBox(height: 20),
                _buildActionCards(context),
                const SizedBox(height: 24),
                _buildRecentSection(context),
                const SizedBox(height: 20),
                _buildFeatureHighlights(),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 120,
      floating: true,
      pinned: false,
      backgroundColor: AppColors.bgPrimary,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 16,
            left: 20,
            right: 20,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ClearWave',
                      style: GoogleFonts.rajdhani(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 1,
                      ),
                    ),
                    const Text(
                      'Studio-level noise cancellation',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryStart.withOpacity(0.4),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: const Icon(Icons.noise_control_off, color: Colors.white, size: 22),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUsageCard(BuildContext context) {
    return Consumer<SessionProvider>(
      builder: (_, session, __) {
        if (session.isLoading) return const SizedBox.shrink();
        if (session.isUnlimited) {
          return GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            gradient: LinearGradient(
              colors: [
                AppColors.premium.withOpacity(0.15),
                AppColors.premium.withOpacity(0.05),
              ],
            ),
            border: Border.all(color: AppColors.premium.withOpacity(0.4)),
            child: Row(
              children: [
                Icon(Icons.all_inclusive, color: AppColors.premium, size: 22),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Unlimited Access Active',
                          style: TextStyle(
                              color: AppColors.premium,
                              fontWeight: FontWeight.w600,
                              fontSize: 14)),
                      Text('Enjoy studio-grade noise cancellation',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return GlassCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Free Uses Remaining',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  Text(
                    '${session.remainingUses} / 100',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: 1.0 - session.usagePercent,
                  backgroundColor: AppColors.border,
                  valueColor: AlwaysStoppedAnimation(
                    session.usagePercent > 0.7
                        ? AppColors.recording
                        : AppColors.primaryStart,
                  ),
                  minHeight: 6,
                ),
              ),
              if (session.remainingUses < 20) ...[
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => _showPromoDialog(context),
                  child: const Text(
                    'Running low? Enter a promo code for unlimited access →',
                    style: TextStyle(
                      color: AppColors.primaryStart,
                      fontSize: 12,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _showPromoDialog(BuildContext context) {
    showDialog(context: context, builder: (_) => const _PromoCodeDialog());
  }

  Widget _buildActionCards(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionCard(
            title: 'New Recording',
            subtitle: 'Record & clean audio',
            icon: Icons.mic,
            gradient: AppColors.primaryGradient,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RecorderScreen()),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ActionCard(
            title: 'Import Audio',
            subtitle: 'Denoise any file',
            icon: Icons.file_upload_outlined,
            gradient: AppColors.accentGradient,
            onTap: () => _importAudio(context),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentSection(BuildContext context) {
    return Consumer<LibraryProvider>(
      builder: (_, library, __) {
        final recent = library.projects.take(3).toList();
        if (recent.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Recent Projects',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
                GestureDetector(
                  onTap: () {},
                  child: const Text('See all',
                      style: TextStyle(
                          color: AppColors.primaryStart,
                          fontSize: 13,
                          fontWeight: FontWeight.w500)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...recent.asMap().entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _RecentProjectTile(
                project: e.value,
                delay: (e.key * 80).ms,
              ),
            )),
          ],
        );
      },
    );
  }

  Widget _buildFeatureHighlights() {
    final features = [
      ('AI Quick', 'One-tap noise removal', Icons.bolt, AppColors.primaryStart),
      ('Studio Mode', 'Full pro controls', Icons.tune, AppColors.accentStart),
      ('Local Only', 'Your audio stays private', Icons.lock, AppColors.success),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Features',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Row(
          children: features.map((f) => Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GlassCard(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Icon(f.$3, color: f.$4, size: 24),
                    const SizedBox(height: 8),
                    Text(f.$1,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(f.$2,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 10)),
                  ],
                ),
              ),
            ),
          )).toList(),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Gradient gradient;
  final VoidCallback onTap;

  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 130,
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: (gradient as LinearGradient).colors.first.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -10,
              top: -10,
              child: Icon(icon,
                  size: 90,
                  color: Colors.white.withOpacity(0.08)),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: Colors.white, size: 20),
                  ),
                  const SizedBox(height: 10),
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                  Text(subtitle,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.75),
                          fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn().slideY(begin: 0.1, end: 0);
  }
}

class _RecentProjectTile extends StatelessWidget {
  final dynamic project;
  final Duration delay;

  const _RecentProjectTile({required this.project, required this.delay});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: () {},
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: project.isProcessed
                  ? AppColors.success.withOpacity(0.15)
                  : AppColors.border,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              project.isProcessed ? Icons.check_circle : Icons.audio_file,
              color: project.isProcessed ? AppColors.success : AppColors.textMuted,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(project.displayName,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(project.duration,
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
          ),
          if (project.isProcessed)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('Clean',
                  style: TextStyle(
                      color: AppColors.success,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    ).animate(delay: delay).fadeIn().slideX(begin: 0.05, end: 0);
  }
}

class _PromoCodeDialog extends StatefulWidget {
  const _PromoCodeDialog();

  @override
  State<_PromoCodeDialog> createState() => _PromoCodeDialogState();
}

class _PromoCodeDialogState extends State<_PromoCodeDialog> {
  final _controller = TextEditingController();
  bool _isLoading = false;
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
            const Icon(Icons.local_offer, color: AppColors.premium, size: 40),
            const SizedBox(height: 12),
            const Text('Enter Promo Code',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text(
              'Instagram influencers get unlimited access with a promo code',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _controller,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'ENTER CODE HERE',
                errorText: _error,
                prefixIcon: const Icon(Icons.lock_open, color: AppColors.textMuted, size: 20),
              ),
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _activate,
                child: _isLoading
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Activate'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _activate() async {
    setState(() { _isLoading = true; _error = null; });
    final success = await context.read<SessionProvider>().activateCode(_controller.text);
    if (mounted) {
      if (success) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unlimited access activated!')),
        );
      } else {
        setState(() { _isLoading = false; _error = 'Invalid code. Please try again.'; });
      }
    }
  }
}
