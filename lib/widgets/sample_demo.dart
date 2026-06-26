import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../models/audio_params.dart';
import '../services/processor_service.dart';
import '../theme.dart';

/// Bundled demo clip: a short noisy voice-like sample shipped with the app so
/// brand-new users can hear what NoiseClear does before recording anything.
const String _kDemoAsset = 'assets/demo/sample_noisy.wav';

/// Opens the interactive "hear the difference" demo as a bottom sheet.
Future<void> showSampleDemo(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.bg,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const SampleDemoSheet(),
  );
}

class SampleDemoSheet extends StatefulWidget {
  const SampleDemoSheet({super.key});

  @override
  State<SampleDemoSheet> createState() => _SampleDemoSheetState();
}

enum _Track { none, before, after }

class _SampleDemoSheetState extends State<SampleDemoSheet> {
  final AudioPlayer _player = AudioPlayer();

  String? _cleanPath; // lazily-produced denoised WAV
  bool _processing = false;
  _Track _active = _Track.none;
  String? _error;

  @override
  void initState() {
    super.initState();
    _player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed && mounted) {
        _player.stop();
        setState(() => _active = _Track.none);
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _playBefore() async {
    if (_active == _Track.before) {
      await _player.stop();
      setState(() => _active = _Track.none);
      return;
    }
    try {
      await _player.stop();
      await _player.setAsset(_kDemoAsset);
      await _player.play();
      setState(() => _active = _Track.before);
    } catch (e) {
      setState(() => _error = 'Could not play sample');
    }
  }

  Future<void> _playAfter() async {
    if (_active == _Track.after) {
      await _player.stop();
      setState(() => _active = _Track.none);
      return;
    }
    if (_cleanPath == null) {
      await _processOnce();
      if (_cleanPath == null) return; // processing failed
    }
    try {
      await _player.stop();
      await _player.setFilePath(_cleanPath!);
      await _player.play();
      setState(() => _active = _Track.after);
    } catch (e) {
      setState(() => _error = 'Could not play cleaned sample');
    }
  }

  Future<void> _processOnce() async {
    setState(() {
      _processing = true;
      _error = null;
    });
    try {
      final bytes = (await rootBundle.load(_kDemoAsset)).buffer.asUint8List();
      final input = ProcessorService.decodeWav(bytes);
      if (input == null) throw Exception('decode');
      final cleaned = await ProcessorService.process(
        input,
        AudioParams.presets[VoicePreset.natural]!,
      );
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/demo_clean.wav';
      await File(path).writeAsBytes(
        ProcessorService.encodeWav(cleaned.samples, cleaned.sampleRate),
      );
      if (!mounted) return;
      setState(() => _cleanPath = path);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not process the sample');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 16, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.textPrim,
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(Icons.graphic_eq_rounded,
                  color: AppColors.white, size: 22),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Hear the difference',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrim)),
                  SizedBox(height: 2),
                  Text('A noisy sample, cleaned on your device',
                      style: TextStyle(fontSize: 12, color: AppColors.textSec)),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 24),
          _DemoButton(
            label: 'Before',
            sub: 'Original — with background noise',
            icon: _active == _Track.before
                ? Icons.stop_rounded
                : Icons.play_arrow_rounded,
            highlight: false,
            active: _active == _Track.before,
            busy: false,
            onTap: _playBefore,
          ),
          const SizedBox(height: 12),
          _DemoButton(
            label: 'After',
            sub: _processing
                ? 'Removing noise…'
                : 'Cleaned with NoiseClear AI',
            icon: _active == _Track.after
                ? Icons.stop_rounded
                : Icons.play_arrow_rounded,
            highlight: true,
            active: _active == _Track.after,
            busy: _processing,
            onTap: _processing ? null : _playAfter,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: const TextStyle(fontSize: 12, color: AppColors.danger)),
          ],
          const SizedBox(height: 20),
          const Row(children: [
            Icon(Icons.lock_outline_rounded, size: 13, color: AppColors.textDim),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                'Processed entirely on your phone — nothing is uploaded.',
                style: TextStyle(fontSize: 11, color: AppColors.textDim),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _DemoButton extends StatelessWidget {
  final String label;
  final String sub;
  final IconData icon;
  final bool highlight;
  final bool active;
  final bool busy;
  final VoidCallback? onTap;

  const _DemoButton({
    required this.label,
    required this.sub,
    required this.icon,
    required this.highlight,
    required this.active,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg = highlight ? AppColors.textPrim : AppColors.surface;
    final Color fg = highlight ? AppColors.white : AppColors.textPrim;
    final Color subFg = highlight ? AppColors.white.withAlpha(179) : AppColors.textSec;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? AppColors.success : AppColors.border,
            width: active ? 1.5 : 0.5,
          ),
        ),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: highlight ? AppColors.white.withAlpha(38) : AppColors.bg,
              shape: BoxShape.circle,
            ),
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(11),
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.white),
                  )
                : Icon(icon, color: fg, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700, color: fg)),
                const SizedBox(height: 2),
                Text(sub, style: TextStyle(fontSize: 11, color: subFg)),
              ],
            ),
          ),
          if (highlight)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.white.withAlpha(38),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('AI',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: AppColors.white)),
            ),
        ]),
      ),
    );
  }
}
