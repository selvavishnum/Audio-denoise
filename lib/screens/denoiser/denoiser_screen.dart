import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/audio_project.dart';
import '../../models/denoise_settings.dart';
import '../../providers/app_provider.dart';
import '../../services/denoise_service.dart';
import '../../services/storage_service.dart';
import '../../services/usage_service.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/gradient_button.dart';
import '../../widgets/common/waveform_painter.dart';
import '../../widgets/studio/studio_controls_panel.dart';

class DenoiserScreen extends StatefulWidget {
  final AudioProject project;

  const DenoiserScreen({super.key, required this.project});

  @override
  State<DenoiserScreen> createState() => _DenoiserScreenState();
}

class _DenoiserScreenState extends State<DenoiserScreen> {
  late DenoiserProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = DenoiserProvider();
    _provider.loadAudio(widget.project.originalPath);
  }

  @override
  void dispose() {
    _provider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _provider,
      child: _DenoiserView(project: widget.project),
    );
  }
}

class _DenoiserView extends StatelessWidget {
  final AudioProject project;

  const _DenoiserView({required this.project});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DenoiserProvider>();

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        title: Text(
          project.displayName,
          style: GoogleFonts.rajdhani(fontSize: 20, fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () {
            provider.stopAllPlayback();
            Navigator.of(context).pop();
          },
        ),
        actions: [
          if (provider.state == DenoiserState.done)
            IconButton(
              icon: const Icon(Icons.ios_share),
              onPressed: () => _shareFile(context, provider.outputPath!),
              tooltip: 'Export',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAudioInfo(),
            const SizedBox(height: 20),
            _buildWaveformSection(provider),
            const SizedBox(height: 20),
            if (provider.state != DenoiserState.processing &&
                provider.state != DenoiserState.done)
              _buildModeSelector(context, provider),
            if (provider.state != DenoiserState.processing &&
                provider.state != DenoiserState.done)
              const SizedBox(height: 20),
            if (provider.showStudioControls && provider.state == DenoiserState.idle)
              _buildStudioControls(provider),
            _buildMainAction(context, provider),
            if (provider.state == DenoiserState.done) ...[
              const SizedBox(height: 16),
              _buildResultCard(provider),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAudioInfo() {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.audio_file, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  project.displayName,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  project.duration,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          if (project.isRecording)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.recording.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('Recorded',
                  style: TextStyle(
                      color: AppColors.recording,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }

  Widget _buildWaveformSection(DenoiserProvider provider) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Audio Preview',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5)),
              Row(
                children: [
                  _PlayButton(
                    label: 'Original',
                    isPlaying: provider.isPlayingOriginal,
                    color: AppColors.warning,
                    onTap: provider.playOriginal,
                  ),
                  if (provider.state == DenoiserState.done) ...[
                    const SizedBox(width: 8),
                    _PlayButton(
                      label: 'Clean',
                      isPlaying: provider.isPlayingClean,
                      color: AppColors.success,
                      onTap: provider.playClean,
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          AnimatedWaveform(
            isActive: provider.isPlayingOriginal || provider.isPlayingClean,
            color: provider.isPlayingClean
                ? AppColors.success
                : provider.isPlayingOriginal
                    ? AppColors.warning
                    : AppColors.primaryStart,
            height: 80,
            amplitude: 0.6,
          ),
          if (provider.state == DenoiserState.done) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LegendDot(color: AppColors.warning, label: 'Original'),
                const SizedBox(width: 16),
                _LegendDot(color: AppColors.success, label: 'Clean'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildModeSelector(BuildContext context, DenoiserProvider provider) {
    final modes = [
      ('ai_quick', 'AI Quick', Icons.bolt, 'One-tap magic'),
      ('voice', 'Voice', Icons.record_voice_over, 'Calls & speech'),
      ('podcast', 'Podcast', Icons.mic_external_on, 'Pro recording'),
      ('music', 'Music', Icons.music_note, 'Music restore'),
      ('studio', 'Studio', Icons.tune, 'Full control'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('DENOISE MODE',
            style: TextStyle(
                color: AppColors.textAccent,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2)),
        const SizedBox(height: 10),
        SizedBox(
          height: 80,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: modes.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final mode = modes[i];
              final isSelected = provider.selectedMode == mode.$1;
              return _ModeCard(
                label: mode.$2,
                subtitle: mode.$4,
                icon: mode.$3,
                isSelected: isSelected,
                onTap: () {
                  provider.setMode(mode.$1);
                  if (mode.$1 == 'studio') {
                    if (!provider.showStudioControls) {
                      provider.toggleStudioControls();
                    }
                  } else if (provider.showStudioControls) {
                    provider.toggleStudioControls();
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStudioControls(DenoiserProvider provider) {
    return Column(
      children: [
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.tune, color: AppColors.textAccent, size: 16),
                      SizedBox(width: 8),
                      Text('STUDIO CONTROLS',
                          style: TextStyle(
                              color: AppColors.textAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2)),
                    ],
                  ),
                  Text('Pro Mode',
                      style: TextStyle(
                          color: AppColors.primaryStart,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 16),
              StudioControlsPanel(
                settings: provider.settings,
                onChanged: provider.updateSettings,
              ),
            ],
          ),
        ).animate().fadeIn().slideY(begin: -0.05, end: 0),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildMainAction(BuildContext context, DenoiserProvider provider) {
    if (provider.state == DenoiserState.processing) {
      return _buildProcessingCard(provider);
    }

    if (provider.state == DenoiserState.done) {
      return Column(
        children: [
          GradientButton(
            label: 'Denoise Again',
            icon: Icons.refresh,
            gradient: AppColors.accentGradient,
            onPressed: () {
              provider.loadAudio(project.originalPath);
            },
          ),
        ],
      );
    }

    if (provider.state == DenoiserState.error) {
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.recording.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.recording.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: AppColors.recording, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    provider.errorMessage ?? 'Processing failed',
                    style: const TextStyle(
                        color: AppColors.recording, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GradientButton(
            label: 'Try Again',
            icon: Icons.refresh,
            onPressed: () => _startProcessing(context, provider),
          ),
        ],
      );
    }

    return Consumer<SessionProvider>(
      builder: (_, session, __) {
        final canUse = session.isUnlimited || session.remainingUses > 0;
        return Column(
          children: [
            GradientButton(
              label: canUse
                  ? 'Remove Noise  ✨'
                  : 'No Uses Remaining',
              gradient: canUse ? AppColors.primaryGradient : null,
              onPressed: canUse
                  ? () => _startProcessing(context, provider)
                  : null,
            ),
            if (!canUse) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => showDialog(
                  context: context,
                  builder: (_) => const _PromoDialog(),
                ),
                child: const Text(
                  'Enter promo code for unlimited access',
                  style: TextStyle(
                    color: AppColors.primaryStart,
                    fontSize: 13,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _startProcessing(
      BuildContext context, DenoiserProvider provider) async {
    final result = await provider.process();
    if (result == null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No remaining uses. Enter a promo code.')),
      );
      return;
    }

    if (result?.status == DenoiseStatus.success && context.mounted) {
      final updatedProject = project.copyWith(
        processedPath: result!.outputPath,
        processedAt: DateTime.now(),
        noiseReductionDb: result.noiseReductionDb,
        denoiseMode: provider.selectedMode,
      );
      await StorageService.instance.saveProject(updatedProject);
    }
  }

  Widget _buildProcessingCard(DenoiserProvider provider) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Text(
            'Removing Noise...',
            style: GoogleFonts.rajdhani(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _getProcessingMessage(provider.selectedMode),
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          AnimatedWaveform(
            isActive: true,
            color: AppColors.primaryStart,
            amplitude: 0.65,
            height: 60,
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: provider.progress > 0 ? provider.progress : null,
              backgroundColor: AppColors.border,
              valueColor: const AlwaysStoppedAnimation(AppColors.primaryStart),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            provider.progress > 0
                ? '${(provider.progress * 100).round()}%'
                : 'Processing...',
            style: const TextStyle(
                color: AppColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ).animate().fadeIn();
  }

  String _getProcessingMessage(String mode) {
    switch (mode) {
      case 'ai_quick':
        return 'AI is analyzing and removing background noise';
      case 'voice':
        return 'Enhancing voice clarity and removing background noise';
      case 'podcast':
        return 'Applying podcast-grade noise reduction and EQ';
      case 'music':
        return 'Using advanced algorithms to restore your music';
      case 'studio':
        return 'Applying your custom studio settings';
      default:
        return 'Applying noise cancellation filters';
    }
  }

  Widget _buildResultCard(DenoiserProvider provider) {
    return GlassCard(
      gradient: LinearGradient(
        colors: [
          AppColors.success.withOpacity(0.12),
          AppColors.success.withOpacity(0.05),
        ],
      ),
      border: Border.all(color: AppColors.success.withOpacity(0.35)),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: AppColors.success, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Noise Removed!',
                        style: TextStyle(
                            color: AppColors.success,
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
                    Text('Your audio is clean and studio-ready',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _StatBox(
                  label: 'Noise Reduced',
                  value: '${provider.noiseReductionDb.toStringAsFixed(1)} dB',
                  icon: Icons.trending_down,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatBox(
                  label: 'Mode',
                  value: _modeName(provider.selectedMode),
                  icon: Icons.auto_fix_high,
                  color: AppColors.primaryStart,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GradientButton(
            label: 'Export Audio',
            icon: Icons.ios_share,
            gradient: AppColors.greenGradient,
            height: 44,
            onPressed: () => _shareFile(context, provider.outputPath!),
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: 0.1, end: 0);
  }

  String _modeName(String mode) {
    const names = {
      'ai_quick': 'AI Quick',
      'voice': 'Voice',
      'podcast': 'Podcast',
      'music': 'Music',
      'studio': 'Studio',
    };
    return names[mode] ?? mode;
  }

  Future<void> _shareFile(BuildContext context, String path) async {
    final exportDir = await StorageService.instance.getExportDir();
    final fileName = File(path).uri.pathSegments.last;
    final exportPath = '$exportDir/$fileName';
    final exported = await DenoiseService.instance.exportToFile(path, exportPath);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(exported
              ? 'Exported to: $exportPath'
              : 'Export failed'),
        ),
      );
    }
  }
}

class _PlayButton extends StatelessWidget {
  final String label;
  final bool isPlaying;
  final Color color;
  final VoidCallback onTap;

  const _PlayButton({
    required this.label,
    required this.isPlaying,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isPlaying ? color.withOpacity(0.2) : AppColors.bgCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isPlaying ? color.withOpacity(0.6) : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPlaying ? Icons.stop : Icons.play_arrow,
              color: isPlaying ? color : AppColors.textMuted,
              size: 14,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isPlaying ? color : AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 11)),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModeCard({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 90,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          gradient: isSelected
              ? AppColors.primaryGradient
              : null,
          color: isSelected ? null : AppColors.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? Colors.transparent : AppColors.border,
            width: 1.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primaryStart.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isSelected ? Colors.white : AppColors.textMuted, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : AppColors.textSecondary,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatBox({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
          Text(label,
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 10)),
        ],
      ),
    );
  }
}

class _PromoDialog extends StatefulWidget {
  const _PromoDialog();

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
            const Icon(Icons.local_offer, color: AppColors.premium, size: 40),
            const SizedBox(height: 12),
            const Text('Promo Code',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'Enter code',
                errorText: _error,
              ),
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed: _loading ? null : _activate,
                child: _loading
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Activate'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _activate() async {
    setState(() { _loading = true; _error = null; });
    final ok = await UsageService.instance.activatePromoCode(_ctrl.text);
    if (mounted) {
      if (ok) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unlimited access activated!')));
      } else {
        setState(() { _loading = false; _error = 'Invalid code'; });
      }
    }
  }
}
