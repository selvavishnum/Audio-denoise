import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../providers/audio_provider.dart';
import '../providers/subscription_provider.dart';
import '../services/ad_service.dart';
import '../services/analytics_service.dart';
import '../services/eleven_labs_service.dart';
import '../services/video_processor_service.dart';
import '../theme.dart';
import '../widgets/save_gate_sheet.dart';
import 'paywall_screen.dart';

enum _Engine { onDevice, elevenLabs }

class VideoDenoiseScreen extends StatefulWidget {
  const VideoDenoiseScreen({super.key});

  @override
  State<VideoDenoiseScreen> createState() => _VideoDenoiseScreenState();
}

class _VideoDenoiseScreenState extends State<VideoDenoiseScreen> {
  String?  _videoPath;
  String?  _processedPath;
  bool     _processing  = false;
  double   _progress    = 0.0;
  String?  _error;
  String   _statusMsg   = '';
  _Engine  _engine      = _Engine.onDevice;

  VideoPlayerController? _origCtrl;
  VideoPlayerController? _procCtrl;

  @override
  void dispose() {
    _origCtrl?.dispose();
    _procCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Uploading, processing, and previewing video noise removal is free and
    // unlimited for everyone. Only Export (saving the result) is gated —
    // see _export() below, which shares the same 30-free-save pool as
    // Studio and Voice.
    return SafeArea(child: _mainContent(context));
  }

  // ── Main content ──────────────────────────────────────────────────────────

  Widget _mainContent(BuildContext context) => Column(children: [
    Expanded(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 28),
          _header(),
          const SizedBox(height: 16),
          _engineSelector(context),
          const SizedBox(height: 20),
          _videoArea(context),
          if (_processing) ...[
            const SizedBox(height: 20),
            _progressBar(),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!,
                  style: const TextStyle(fontSize: 12, color: AppColors.danger)),
            ),
          if (_processedPath != null) ...[
            const SizedBox(height: 20),
            _processedSection(),
          ],
          const SizedBox(height: 24),
        ]),
      ),
    ),
    _bottomBar(context),
  ]);

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _header() => Row(children: [
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Video Denoise',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700,
              color: AppColors.textPrim, letterSpacing: -0.5)),
      const SizedBox(height: 4),
      const Text('AI noise removal from your video audio track',
          style: TextStyle(fontSize: 13, color: AppColors.textSec)),
    ])),
    const FreeLimitBadge(),
  ]);

  // ── Engine selector ───────────────────────────────────────────────────────

  Widget _engineSelector(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.border, width: 0.5),
    ),
    child: Row(children: [
      _EngineTab(
        label: 'On-Device Neural AI',
        icon: Icons.memory_rounded,
        selected: _engine == _Engine.onDevice,
        onTap: () => setState(() { _engine = _Engine.onDevice; _error = null; }),
      ),
      _EngineTab(
        label: 'ElevenLabs Cloud AI',
        icon: Icons.cloud_rounded,
        selected: _engine == _Engine.elevenLabs,
        onTap: () => setState(() { _engine = _Engine.elevenLabs; _error = null; }),
      ),
    ]),
  );

  // ── Video area ────────────────────────────────────────────────────────────

  Widget _videoArea(BuildContext context) {
    if (_videoPath == null) {
      return GestureDetector(
        onTap: () => _pickVideo(ImageSource.gallery),
        child: Container(
          width: double.infinity, height: 200,
          decoration: BoxDecoration(
            color: AppColors.surface, borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: AppColors.textPrim, borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.video_library_rounded,
                  color: AppColors.white, size: 26),
            ),
            const SizedBox(height: 16),
            const Text('Import or Record Video',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                    color: AppColors.textPrim)),
            const SizedBox(height: 6),
            const Text('MP4, MOV, AVI',
                style: TextStyle(fontSize: 12, color: AppColors.textDim)),
          ]),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('ORIGINAL',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
              color: AppColors.textDim, letterSpacing: 1.0)),
      const SizedBox(height: 8),
      _VideoThumbnail(
        controller: _origCtrl,
        path: _videoPath!,
        label: _videoPath!.split('/').last,
      ),
    ]);
  }

  Widget _progressBar() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Expanded(
          child: Text(
            _statusMsg.isEmpty ? 'Removing noise…' : _statusMsg,
            style: const TextStyle(fontSize: 12, color: AppColors.textSec),
            maxLines: 1, overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text('${(_progress * 100).round()}%',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                color: AppColors.textPrim)),
      ]),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: _progress, minHeight: 4,
          backgroundColor: AppColors.border,
          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.textPrim),
        ),
      ),
    ],
  );

  Widget _processedSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        const Text('PROCESSED — CLEAN AUDIO',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                color: AppColors.textDim, letterSpacing: 1.0)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.textPrim.withAlpha(20),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            _engine == _Engine.elevenLabs ? 'ElevenLabs AI' : 'On-device AI',
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                color: AppColors.textPrim, letterSpacing: 0.3),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      _VideoThumbnail(
        controller: _procCtrl, path: _processedPath!,
        label: 'Clean version', highlight: true,
      ),
    ],
  );

  Widget _bottomBar(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
    decoration: const BoxDecoration(
      color: AppColors.white,
      border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
    ),
    child: Row(children: [
      _Btn(label: 'Record', icon: Icons.videocam_rounded, filled: false,
          onTap: _processing ? null : () => _pickVideo(ImageSource.camera)),
      const SizedBox(width: 8),
      _Btn(label: 'Import', icon: Icons.video_library_rounded, filled: false,
          onTap: _processing ? null : () => _pickVideo(ImageSource.gallery)),
      if (_videoPath != null) ...[
        const SizedBox(width: 8),
        Expanded(child: _Btn(
          label: _processing ? 'Processing…' : 'Remove Noise',
          icon: _processing
              ? Icons.hourglass_empty_rounded
              : Icons.auto_fix_high_rounded,
          filled: true, loading: _processing,
          onTap: _processing ? null : () => _process(context),
        )),
      ],
      if (_processedPath != null) ...[
        const SizedBox(width: 8),
        _Btn(label: 'Export', icon: Icons.ios_share_rounded, filled: false,
            onTap: _processing ? null : () => _export(context)),
      ],
    ]),
  );

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _pickVideo(ImageSource source) async {
    final xfile = await ImagePicker().pickVideo(
        source: source, maxDuration: const Duration(minutes: 10));
    if (xfile == null || !mounted) return;
    setState(() { _videoPath = xfile.path; _processedPath = null; _error = null; });
    _origCtrl?.dispose();
    _origCtrl = VideoPlayerController.file(File(xfile.path));
    await _origCtrl!.initialize();
    setState(() {});
  }

  Future<void> _process(BuildContext context) async {
    if (_videoPath == null) return;

    if (_engine == _Engine.elevenLabs) {
      await _processWithElevenLabs(context);
    } else {
      await _processOnDevice(context);
    }
  }

  Future<void> _processOnDevice(BuildContext context) async {
    setState(() { _processing = true; _progress = 0; _error = null;
                  _processedPath = null; _statusMsg = 'Extracting audio…'; });

    final params = context.read<AudioProvider>().params;

    final cleanWav = await VideoProcessorService.extractAndDenoise(
      _videoPath!, params,
      onProgress: (p) => setState(() { _progress = p * 0.75; }),
    );

    if (!mounted) return;
    if (cleanWav == null) {
      setState(() { _processing = false; _error = 'Could not extract audio from video'; });
      return;
    }

    setState(() { _progress = 0.8; _statusMsg = 'Re-encoding video…'; });
    final output = await VideoProcessorService.muxAudioIntoVideo(_videoPath!, cleanWav);
    try { await File(cleanWav).delete(); } catch (_) {}

    if (!mounted) return;
    if (output == null) {
      setState(() { _processing = false; _error = 'Could not write processed video'; });
      return;
    }

    await _loadProcessedVideo(output);
  }

  Future<void> _processWithElevenLabs(BuildContext context) async {
    // Ensure API key is available
    final savedKey = await ElevenLabsService.getApiKey();
    String? apiKey = savedKey;

    if (apiKey == null || apiKey.isEmpty) {
      if (!mounted) return;
      apiKey = await _showApiKeyDialog(context);
      if (apiKey == null || apiKey.isEmpty) return;
      await ElevenLabsService.saveApiKey(apiKey);
    }

    setState(() { _processing = true; _progress = 0.05; _error = null;
                  _processedPath = null; _statusMsg = 'Extracting audio…'; });

    try {
      final cleanWav = await VideoProcessorService.extractAndDenoiseWithElevenLabs(
        _videoPath!,
        apiKey: apiKey,
        onProgress: (p) => setState(() => _progress = p * 0.85),
        onStatus:   (s) => setState(() => _statusMsg = s),
      );

      if (!mounted) return;
      if (cleanWav == null) {
        setState(() { _processing = false; _error = 'Audio extraction failed'; });
        return;
      }

      setState(() { _progress = 0.9; _statusMsg = 'Re-encoding video…'; });
      final output = await VideoProcessorService.muxAudioIntoVideo(_videoPath!, cleanWav);
      try { await File(cleanWav).delete(); } catch (_) {}

      if (!mounted) return;
      if (output == null) {
        setState(() { _processing = false; _error = 'Video encoding failed'; });
        return;
      }

      await _loadProcessedVideo(output);
    } on ElevenLabsException catch (e) {
      if (!mounted) return;
      setState(() { _processing = false; _error = e.message; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _processing = false; _error = 'Unexpected error: $e'; });
    }
  }

  Future<void> _loadProcessedVideo(String path) async {
    _procCtrl?.dispose();
    _procCtrl = VideoPlayerController.file(File(path));
    await _procCtrl!.initialize();
    if (!mounted) return;
    setState(() { _processedPath = path; _processing = false; _progress = 0; _statusMsg = ''; });
  }

  // Uploading, processing, and previewing are always free. Saving/exporting
  // the cleaned video draws from the same shared 30-free-save pool as
  // Studio and Voice (AudioProvider.exportCount) — Pro subscribers skip
  // the gate entirely.
  Future<void> _export(BuildContext context) async {
    if (_processedPath == null) return;
    final prov  = context.read<AudioProvider>();
    final isPro = context.read<SubscriptionProvider>().isPro;

    if (isPro || !prov.hasReachedFreeLimit) {
      await _shareVideo(prov);
    } else {
      await AnalyticsService.logFreeLimitReached();
      await showSaveGateSheet(
        context,
        title: '30 free saves used',
        canWatchAd: prov.canUseDailyBonus && AdService.isReady,
        onWatchAd: () async {
          Navigator.pop(context);
          await _showRewardedAd(context, prov);
        },
        onUpgrade: () {
          Navigator.pop(context);
          _openPaywall(context);
        },
      );
    }
  }

  Future<void> _shareVideo(AudioProvider prov) async {
    if (_processedPath == null) return;
    await prov.recordExport();
    await SharePlus.instance.share(
        ShareParams(files: [XFile(_processedPath!)], text: 'NoiseClear — clean video'));
  }

  Future<void> _showRewardedAd(BuildContext context, AudioProvider prov) async {
    await AnalyticsService.logRewardedAdShown();
    bool rewarded = false;

    await AdService.showRewardedAd(onRewarded: () { rewarded = true; });

    if (rewarded) {
      await AnalyticsService.logRewardedAdCompleted();
      await AnalyticsService.logBonusExportEarned();
      await prov.useDailyBonus();
      if (mounted) await _shareVideo(prov);
    } else {
      await AnalyticsService.logRewardedAdSkipped();
    }
  }

  void _openPaywall(BuildContext context) {
    AnalyticsService.logPaywallShown('video_save');
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PaywallScreen()));
  }

  // ── ElevenLabs API key dialog ─────────────────────────────────────────────

  Future<String?> _showApiKeyDialog(BuildContext context) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('ElevenLabs API Key',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                color: AppColors.textPrim)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            'ElevenLabs Audio Isolation uses the cloud to extract voices from '
            'any background. Get a free API key at elevenlabs.io',
            style: TextStyle(fontSize: 12, color: AppColors.textSec, height: 1.5),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: ctrl,
            autofocus: true,
            obscureText: true,
            style: const TextStyle(fontSize: 13, color: AppColors.textPrim),
            decoration: InputDecoration(
              hintText: 'sk_...',
              hintStyle: const TextStyle(color: AppColors.textDim),
              filled: true, fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border, width: 0.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border, width: 0.5),
              ),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textDim)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save & Process',
                style: TextStyle(color: AppColors.textPrim,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ── Engine tab button ─────────────────────────────────────────────────────────

class _EngineTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _EngineTab({
    required this.label, required this.icon,
    required this.selected, required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.textPrim : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 14,
              color: selected ? AppColors.white : AppColors.textSec),
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
    ),
  );
}

// ── Video player tile ─────────────────────────────────────────────────────────

class _VideoThumbnail extends StatefulWidget {
  final VideoPlayerController? controller;
  final String path;
  final String label;
  final bool highlight;

  const _VideoThumbnail({
    required this.controller, required this.path, required this.label,
    this.highlight = false,
  });

  @override
  State<_VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<_VideoThumbnail> {
  bool _playing = false;

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    return Container(
      width: double.infinity, height: 200,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.highlight ? AppColors.textPrim : AppColors.border,
          width: widget.highlight ? 1.5 : 0.5,
        ),
      ),
      child: Stack(fit: StackFit.expand, children: [
        if (ctrl != null && ctrl.value.isInitialized)
          AspectRatio(aspectRatio: ctrl.value.aspectRatio, child: VideoPlayer(ctrl))
        else
          const Center(
              child: Icon(Icons.movie_rounded, size: 48, color: AppColors.textDim)),
        if (ctrl != null && ctrl.value.isInitialized)
          GestureDetector(
            onTap: () => setState(() {
              if (_playing) { ctrl.pause(); _playing = false; }
              else          { ctrl.play();  _playing = true;  }
            }),
            child: AnimatedOpacity(
              opacity: _playing ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                color: Colors.black26,
                child: const Center(
                    child: Icon(Icons.play_circle_filled_rounded,
                        size: 54, color: Colors.white)),
              ),
            ),
          ),
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter, end: Alignment.topCenter,
                colors: [Colors.black.withAlpha(153), Colors.transparent],
              ),
            ),
            child: Text(widget.label,
              style: const TextStyle(fontSize: 11, color: Colors.white,
                  fontWeight: FontWeight.w500),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      ]),
    );
  }
}

// ── Button ────────────────────────────────────────────────────────────────────

class _Btn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool filled;
  final bool loading;
  final VoidCallback? onTap;

  const _Btn({required this.label, required this.icon, required this.filled,
      this.onTap, this.loading = false});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      height: 48, padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: filled
            ? (onTap == null ? AppColors.textDim : AppColors.textPrim)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: filled ? null : Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center, children: [
        if (loading)
          const SizedBox(width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
        else
          Icon(icon, size: 15,
              color: filled ? Colors.white : AppColors.textSec),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
            color: filled ? Colors.white : AppColors.textSec)),
      ]),
    ),
  );
}
