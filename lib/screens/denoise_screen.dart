import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/audio_params.dart';
import '../models/processing_stats.dart';
import '../providers/audio_provider.dart';
import '../providers/subscription_provider.dart';
import '../services/ad_service.dart';
import '../services/analytics_service.dart';
import '../theme.dart';
import '../widgets/param_slider.dart';
import '../widgets/preset_card.dart';
import '../widgets/waveform_painter.dart';
import 'paywall_screen.dart';

class DenoiseScreen extends StatefulWidget {
  const DenoiseScreen({super.key});

  @override
  State<DenoiseScreen> createState() => _DenoiseScreenState();
}

class _DenoiseScreenState extends State<DenoiseScreen> {
  bool _showProcessed = false;
  bool _advancedOpen  = false;

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AudioProvider>();
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 28),
                  _header(context),
                  const SizedBox(height: 16),
                  if (prov.originalAudio != null) _modeSelector(prov),
                  const SizedBox(height: 8),
                  if (prov.originalAudio == null) _importCta(context, prov),
                  if (prov.originalAudio != null) ...[
                    _waveform(prov),
                    const SizedBox(height: 16),
                    if (_isSplitMode(prov)) ...[
                      if (prov.vocalsAudio != null) _stemsSection(prov),
                    ] else ...[
                      _abToggle(prov),
                      if (prov.processedAudio != null && prov.lastStats != null) ...[
                        const SizedBox(height: 14),
                        _StatsCard(stats: prov.lastStats!),
                      ],
                      const SizedBox(height: 20),
                      _presetsGrid(prov),
                      const SizedBox(height: 16),
                      _advancedSection(prov),
                    ],
                  ],
                  if (prov.isProcessing || prov.isSplitting) ...[
                    const SizedBox(height: 20),
                    _progressBar(prov),
                  ],
                  if (prov.errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(prov.errorMessage!,
                          style: const TextStyle(color: AppColors.danger, fontSize: 12)),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          if (prov.originalAudio != null) _bottomBar(context, prov),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final prov = context.watch<AudioProvider>();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Denoise', style: Theme.of(context).textTheme.displayLarge),
            const SizedBox(height: 4),
            Text('Import audio and remove noise', style: Theme.of(context).textTheme.bodyMedium),
          ],
        )),
        _buildExportBadge(context, prov),
      ],
    );
  }

  Widget _importCta(BuildContext context, AudioProvider prov) {
    return GestureDetector(
      onTap: () => _importFile(prov),
      child: Container(
        width: double.infinity,
        height: 200,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: AppColors.textPrim,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.upload_file_rounded, color: AppColors.white, size: 26),
            ),
            const SizedBox(height: 16),
            const Text('Import Audio File',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrim)),
            const SizedBox(height: 6),
            const Text('WAV, MP3, M4A, FLAC',
                style: TextStyle(fontSize: 12, color: AppColors.textDim)),
          ],
        ),
      ),
    );
  }

  Widget _waveform(AudioProvider prov) {
    return GestureDetector(
      onTap: () {
        if (prov.processedAudio != null) setState(() => _showProcessed = !_showProcessed);
      },
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: CustomPaint(
          painter: WaveformPainter(
            originalSamples:  prov.originalAudio?.samples,
            processedSamples: prov.processedAudio?.samples,
            showProcessed:    _showProcessed && prov.processedAudio != null,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }

  Widget _abToggle(AudioProvider prov) {
    if (prov.processedAudio == null) return const SizedBox.shrink();
    return Row(
      children: [
        _PlayChip(
          label: 'Original',
          active: !_showProcessed,
          playing: prov.playingOriginal,
          onTap: () {
            setState(() => _showProcessed = false);
            prov.togglePlayOriginal();
          },
        ),
        const SizedBox(width: 8),
        _PlayChip(
          label: 'Clean',
          active: _showProcessed,
          playing: prov.playingProcessed,
          onTap: () {
            setState(() => _showProcessed = true);
            prov.togglePlayProcessed();
          },
          isProcessed: true,
        ),
      ],
    );
  }

  Widget _presetsGrid(AudioProvider prov) {
    final presets = VoicePreset.values;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.88,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: presets.length,
      itemBuilder: (_, i) => PresetCard(
        preset:     presets[i],
        isSelected: prov.params.preset == presets[i],
        onTap:      () => prov.applyPreset(presets[i]),
      ),
    );
  }

  Widget _advancedSection(AudioProvider prov) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _advancedOpen = !_advancedOpen),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
            child: Row(
              children: [
                const Text('Advanced Parameters',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrim)),
                const Spacer(),
                Icon(
                  _advancedOpen ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  color: AppColors.textDim, size: 20,
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeInOut,
          child: _advancedOpen
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _AdvancedParams(prov: prov),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  bool _isSplitMode(AudioProvider prov) => prov.params.mode == ProcessingMode.extractMusic;

  Widget _modeSelector(AudioProvider prov) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.border, width: 0.5),
    ),
    child: Row(children: [
      Expanded(child: _ModeTab(
        label: 'Denoise',
        icon: Icons.noise_control_off_rounded,
        selected: !_isSplitMode(prov),
        onTap: () => prov.updateParams(prov.params.copyWith(mode: ProcessingMode.denoise)),
      )),
      Expanded(child: _ModeTab(
        label: 'Split Vocals & Music',
        icon: Icons.graphic_eq_rounded,
        selected: _isSplitMode(prov),
        onTap: () => prov.updateParams(prov.params.copyWith(mode: ProcessingMode.extractMusic)),
      )),
    ]),
  );

  Widget _stemsSection(AudioProvider prov) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border, width: 0.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('VOCALS & INSTRUMENTAL',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                color: AppColors.textDim, letterSpacing: 1.0)),
        const SizedBox(height: 14),
        _stemRow(prov, label: 'Vocals', icon: Icons.mic_rounded,
            playing: prov.playingVocals, onPlay: prov.togglePlayVocals,
            onExport: () => _exportStem(prov, prov.vocalsPath, 'vocals')),
        const SizedBox(height: 10),
        _stemRow(prov, label: 'Instrumental', icon: Icons.music_note_rounded,
            playing: prov.playingMusic, onPlay: prov.togglePlayMusic,
            onExport: () => _exportStem(prov, prov.musicPath, 'instrumental')),
      ],
    ),
  );

  Widget _stemRow(AudioProvider prov, {
    required String label,
    required IconData icon,
    required bool playing,
    required VoidCallback onPlay,
    required VoidCallback onExport,
  }) {
    return Row(children: [
      Container(
        width: 36, height: 36,
        decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 18, color: AppColors.textSec),
      ),
      const SizedBox(width: 12),
      Expanded(child: Text(label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrim))),
      GestureDetector(
        onTap: onPlay,
        child: Container(
          width: 34, height: 34,
          decoration: const BoxDecoration(color: AppColors.textPrim, shape: BoxShape.circle),
          child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: AppColors.white, size: 18),
        ),
      ),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: onExport,
        child: Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: const Icon(Icons.ios_share_rounded, color: AppColors.textSec, size: 16),
        ),
      ),
    ]);
  }

  Future<void> _exportStem(AudioProvider prov, String? path, String label) async {
    if (path == null) return;
    await prov.recordExport();
    await SharePlus.instance.share(
        ShareParams(files: [XFile(path)], text: 'NoiseClear — $label'));
  }

  Widget _progressBar(AudioProvider prov) {
    final splitting = prov.isSplitting;
    final value = splitting ? prov.splitProgress : prov.progress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(splitting ? 'Separating vocals & music…' : 'Processing…',
                style: const TextStyle(fontSize: 12, color: AppColors.textSec)),
            Text('${(value * 100).round()}%',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrim)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 4,
            backgroundColor: AppColors.border,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.textPrim),
          ),
        ),
      ],
    );
  }

  Widget _bottomBar(BuildContext context, AudioProvider prov) {
    final isPro = context.watch<SubscriptionProvider>().isPro;
    final isSplit = _isSplitMode(prov);
    final busy = prov.isProcessing || prov.isSplitting;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _BigBtn(
              label: busy
                  ? 'Processing…'
                  : (isSplit ? 'Split Vocals & Music' : (isPro ? 'Isolate Voice' : 'Process')),
              icon: busy ? Icons.hourglass_empty_rounded : Icons.auto_fix_high_rounded,
              filled: true,
              onTap: busy
                  ? null
                  : () => isSplit ? prov.splitStems() : prov.processAudio(premium: isPro),
              child: busy
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white))
                  : null,
            ),
          ),
          if (!isSplit && prov.processedAudio != null) ...[
            const SizedBox(width: 10),
            _BigBtn(
              label: 'Export',
              icon:  Icons.ios_share_rounded,
              filled: false,
              onTap: () => _export(context, prov),
            ),
          ],
          const SizedBox(width: 10),
          _BigBtn(
            label: 'Import',
            icon:  Icons.upload_file_rounded,
            filled: false,
            onTap: () => _importFile(prov),
          ),
        ],
      ),
    );
  }

  Future<void> _importFile(AudioProvider prov) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['wav', 'mp3', 'm4a', 'aac', 'flac', 'ogg'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() => _showProcessed = false);
      await prov.loadFile(result.files.single.path!);
    }
  }

  Widget _buildExportBadge(BuildContext context, AudioProvider prov) {
    final isPro = context.watch<SubscriptionProvider>().isPro;
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

  Future<void> _export(BuildContext context, AudioProvider prov) async {
    final path = prov.shareFilePath;
    if (path == null) return;

    final isPro = context.read<SubscriptionProvider>().isPro;
    if (isPro || !prov.hasReachedFreeLimit) {
      await _showExportFormatDialog(context, prov, path);
    } else {
      await AnalyticsService.logFreeLimitReached();
      await _showExportGate(context, prov, path);
    }
  }

  Future<void> _showExportFormatDialog(
      BuildContext context, AudioProvider prov, String wavPath) async {
    final format = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _ExportFormatSheet(),
    );
    if (format == null || !mounted) return;

    await prov.recordExport();

    if (format == 'mp3') {
      final snack = ScaffoldMessenger.of(context);
      snack.showSnackBar(const SnackBar(
        content: Text('Converting to MP3…'),
        duration: Duration(seconds: 2),
      ));
      final mp3Path = await prov.exportAsMp3();
      if (!mounted) return;
      if (mp3Path != null) {
        await SharePlus.instance.share(
          ShareParams(files: [XFile(mp3Path)], text: 'NoiseClear processed audio'),
        );
      } else {
        snack.showSnackBar(const SnackBar(content: Text('MP3 export failed — sharing WAV instead')));
        await SharePlus.instance.share(
          ShareParams(files: [XFile(wavPath)], text: 'NoiseClear processed audio'),
        );
      }
    } else {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(wavPath)], text: 'NoiseClear processed audio'),
      );
    }
  }

  Future<void> _showExportGate(BuildContext context, AudioProvider prov, String path) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ExportGateSheet(
        canWatchAd: prov.canUseDailyBonus && AdService.isReady,
        onWatchAd: () async {
          Navigator.pop(context);
          await _showRewardedAd(context, prov, path);
        },
        onUpgrade: () {
          Navigator.pop(context);
          _openPaywall(context);
        },
      ),
    );
  }

  Future<void> _showRewardedAd(BuildContext context, AudioProvider prov, String path) async {
    await AnalyticsService.logRewardedAdShown();
    bool rewarded = false;

    await AdService.showRewardedAd(
      onRewarded: () {
        rewarded = true;
      },
    );

    if (rewarded) {
      await AnalyticsService.logRewardedAdCompleted();
      await AnalyticsService.logBonusExportEarned();
      await prov.useDailyBonus();
      if (mounted) await _showExportFormatDialog(context, prov, path);
    } else {
      await AnalyticsService.logRewardedAdSkipped();
    }
  }

  void _openPaywall(BuildContext context) {
    AnalyticsService.logPaywallShown('export_limit');
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PaywallScreen()));
  }
}

// ── Advanced params panel ─────────────────────────────────────────────────────

class _AdvancedParams extends StatelessWidget {
  final AudioProvider prov;
  const _AdvancedParams({required this.prov});

  @override
  Widget build(BuildContext context) {
    final p = prov.params;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _section('Noise Reduction'),
          ParamSlider(label: 'NR Strength', value: p.nrStrength, min: 0, max: 100, unit: '%',
              color: AppColors.violet, onChanged: (v) => prov.updateParams(p.copyWith(nrStrength: v))),
          ParamSlider(label: 'NR Smoothing', value: p.nrAlpha, min: 0, max: 99, unit: '%',
              color: AppColors.violet, onChanged: (v) => prov.updateParams(p.copyWith(nrAlpha: v))),
          ParamSlider(label: 'Noise Floor', value: p.nrFloor, min: 1, max: 6, divisions: 50, displayDecimals: 1, unit: '×',
              color: AppColors.violet, onChanged: (v) => prov.updateParams(p.copyWith(nrFloor: v))),
          _section('Gate'),
          ParamSlider(label: 'Gate Threshold', value: p.gateThreshold, min: 0, max: 100, unit: '%',
              color: AppColors.cyan, onChanged: (v) => prov.updateParams(p.copyWith(gateThreshold: v))),
          ParamSlider(label: 'VAD Sensitivity', value: p.vadSensitivity, min: 1, max: 10, divisions: 90, displayDecimals: 1,
              color: AppColors.cyan, onChanged: (v) => prov.updateParams(p.copyWith(vadSensitivity: v))),
          IntParamSlider(label: 'VAD Hold', value: p.vadHoldMs, min: 20, max: 400, unit: 'ms',
              color: AppColors.cyan, onChanged: (v) => prov.updateParams(p.copyWith(vadHoldMs: v))),
          _section('Voice'),
          ParamSlider(label: 'Pitch', value: p.pitchSemitones, min: -8, max: 8, divisions: 160, displayDecimals: 1, unit: 'st',
              color: AppColors.pink, onChanged: (v) => prov.updateParams(p.copyWith(pitchSemitones: v))),
          ParamSlider(label: 'Formant', value: p.formantFactor, min: 0.7, max: 1.4, divisions: 70, displayDecimals: 2, unit: '×',
              color: AppColors.pink, onChanged: (v) => prov.updateParams(p.copyWith(formantFactor: v))),
          ParamSlider(label: 'Exciter', value: p.exciterAmount, min: 0, max: 100, unit: '%',
              color: AppColors.amber, onChanged: (v) => prov.updateParams(p.copyWith(exciterAmount: v))),
          _section('EQ'),
          ParamSlider(label: 'High-Pass Freq', value: p.hpFreq, min: 20, max: 400, unit: 'Hz',
              color: AppColors.amber, onChanged: (v) => prov.updateParams(p.copyWith(hpFreq: v))),
          ParamSlider(label: 'Bass', value: p.bassGain, min: -6, max: 9, divisions: 150, displayDecimals: 1, unit: 'dB',
              color: AppColors.amber, onChanged: (v) => prov.updateParams(p.copyWith(bassGain: v))),
          ParamSlider(label: 'Presence', value: p.presGain, min: -6, max: 9, divisions: 150, displayDecimals: 1, unit: 'dB',
              color: AppColors.violet, onChanged: (v) => prov.updateParams(p.copyWith(presGain: v))),
          ParamSlider(label: 'Air', value: p.airGain, min: -9, max: 9, divisions: 180, displayDecimals: 1, unit: 'dB',
              color: AppColors.cyan, onChanged: (v) => prov.updateParams(p.copyWith(airGain: v))),
          _section('Dynamics'),
          ParamSlider(label: 'Comp Threshold', value: p.compThreshold, min: -40, max: 0, unit: 'dB',
              color: AppColors.green, onChanged: (v) => prov.updateParams(p.copyWith(compThreshold: v))),
          ParamSlider(label: 'Comp Ratio', value: p.compRatio, min: 1, max: 8, divisions: 70, displayDecimals: 1,
              color: AppColors.green, onChanged: (v) => prov.updateParams(p.copyWith(compRatio: v))),
          ParamSlider(label: 'Target LUFS', value: p.targetLufs, min: -24, max: -6, unit: 'dB',
              color: AppColors.green, onChanged: (v) => prov.updateParams(p.copyWith(targetLufs: v))),
        ],
      ),
    );
  }

  Widget _section(String label) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 4),
    child: Text(label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
            color: AppColors.textDim, letterSpacing: 0.8)),
  );
}

// ── Mode tab button ────────────────────────────────────────────────────────────

class _ModeTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ModeTab({
    required this.label, required this.icon,
    required this.selected, required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: selected ? AppColors.textPrim : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 14, color: selected ? AppColors.white : AppColors.textSec),
        const SizedBox(width: 6),
        Flexible(
          child: Text(label,
            style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600,
              color: selected ? AppColors.white : AppColors.textSec,
            ),
            maxLines: 1, overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
    ),
  );
}

// ── Shared small widgets ──────────────────────────────────────────────────────

class _PlayChip extends StatelessWidget {
  final String label;
  final bool active, playing;
  final bool isProcessed;
  final VoidCallback onTap;

  const _PlayChip({
    required this.label, required this.active,
    required this.playing, required this.onTap,
    this.isProcessed = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color:        active ? AppColors.textPrim : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? AppColors.textPrim : AppColors.border, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 14, color: active ? AppColors.white : AppColors.textSec),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w500,
                  color: active ? AppColors.white : AppColors.textSec,
                )),
          ],
        ),
      ),
    );
  }
}

class _BigBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback? onTap;
  final Widget? child;

  const _BigBtn({required this.label, required this.icon,
      required this.filled, this.onTap, this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color:        filled ? (onTap == null ? AppColors.textDim : AppColors.textPrim) : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: filled ? null : Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            child ?? Icon(icon, size: 16, color: filled ? AppColors.white : AppColors.textSec),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600,
              color: filled ? AppColors.white : AppColors.textSec,
            )),
          ],
        ),
      ),
    );
  }
}

// ── Monetization gate bottom sheet ────────────────────────────────────────────

class _ExportGateSheet extends StatelessWidget {
  final bool canWatchAd;
  final VoidCallback onWatchAd;
  final VoidCallback onUpgrade;
  const _ExportGateSheet({
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
                const Text('30 free exports used',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrim)),
                const SizedBox(height: 2),
                Text(
                  canWatchAd ? 'Watch a short ad for 1 free export today' : 'Upgrade for unlimited access',
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
                  Text('Watch Ad  —  1 Free Export Today',
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

// ── Processing stats card ─────────────────────────────────────────────────────

class _StatsCard extends StatelessWidget {
  final ProcessingStats stats;
  const _StatsCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(children: [
        Expanded(child: _Stat(
          label: 'Noise Reduced',
          value: '${stats.noiseReductionPct.round()}%',
          color: AppColors.violet,
        )),
        Container(width: 0.5, height: 32, color: AppColors.border),
        Expanded(child: _Stat(
          label: 'Quality',
          value: stats.qualityGrade,
          color: AppColors.cyan,
        )),
        Container(width: 0.5, height: 32, color: AppColors.border),
        Expanded(child: _Stat(
          label: stats.usedNeural ? 'Neural AI' : 'DSP Mode',
          value: stats.processingTime.inSeconds >= 1
              ? '${stats.processingTime.inSeconds}s'
              : '${stats.processingTime.inMilliseconds}ms',
          color: stats.usedNeural ? AppColors.violet : AppColors.amber,
        )),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Stat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(value, style: TextStyle(
        fontSize: 15, fontWeight: FontWeight.w700, color: color)),
      const SizedBox(height: 3),
      Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textDim),
        textAlign: TextAlign.center),
    ]);
  }
}

// ── Export format sheet ───────────────────────────────────────────────────────

class _ExportFormatSheet extends StatelessWidget {
  const _ExportFormatSheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Export Format',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrim)),
          const SizedBox(height: 4),
          const Text('Choose file format for sharing',
            style: TextStyle(fontSize: 12, color: AppColors.textSec)),
          const SizedBox(height: 20),
          _FormatOption(
            format: 'WAV',
            title: 'WAV — Lossless',
            subtitle: 'Highest quality · Studio format',
            onTap: () => Navigator.pop(context, 'wav'),
          ),
          const SizedBox(height: 10),
          _FormatOption(
            format: 'MP3',
            title: 'MP3 — 192 kbps',
            subtitle: 'Compressed · Easy to share · Small file',
            onTap: () => Navigator.pop(context, 'mp3'),
          ),
        ],
      ),
    );
  }
}

class _FormatOption extends StatelessWidget {
  final String format;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _FormatOption({
    required this.format, required this.title,
    required this.subtitle, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.textPrim,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(format,
              style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700,
                color: AppColors.white, letterSpacing: 0.5)),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrim)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(
                fontSize: 11, color: AppColors.textSec)),
            ],
          )),
          const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textDim),
        ]),
      ),
    );
  }
}

