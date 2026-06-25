import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../models/audio_params.dart';
import '../providers/audio_provider.dart';
import '../theme.dart';
import '../widgets/equalizer_painter.dart';
import '../widgets/sample_demo.dart';

class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key});

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen>
    with TickerProviderStateMixin {
  List<double> _bars = idleEqBars(28);
  Timer? _eqTimer;
  int _seconds = 0;
  Timer? _clock;
  final _rng = Random();

  @override
  void dispose() {
    _eqTimer?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  void _startAnimating(double amp) {
    if (_eqTimer?.isActive == true) return;
    _eqTimer = Timer.periodic(const Duration(milliseconds: 75), (_) {
      if (!mounted) return;
      setState(() {
        _bars = animateEqBars(prev: _bars, amplitude: amp, rng: _rng);
      });
    });
  }

  void _stopAnimating() {
    _eqTimer?.cancel();
    _eqTimer = null;
    if (mounted) setState(() => _bars = idleEqBars(28));
  }

  Future<void> _onRecordTap(AudioProvider prov) async {
    if (prov.isRecording) {
      await prov.stopRecording();
      _clock?.cancel();
      setState(() => _seconds = 0);
      _stopAnimating();
    } else {
      _seconds = 0;
      _clock = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _seconds++);
      });
      final ok = await prov.startRecording();
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission required')),
        );
        _clock?.cancel();
      }
    }
  }

  String _fmt(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AudioProvider>();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 28),
            _header(context),
            const SizedBox(height: 32),
            _equalizer(prov),
            const SizedBox(height: 28),
            _timer(prov),
            const SizedBox(height: 24),
            _presets(prov),
            const Spacer(),
            _recordBtn(prov),
            const SizedBox(height: 12),
            _statusLine(prov),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Record', style: Theme.of(context).textTheme.displayLarge),
            const SizedBox(height: 4),
            Text('Live noise cancellation',
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
      GestureDetector(
        onTap: () => showSampleDemo(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: const [
            Icon(Icons.play_circle_outline_rounded,
                size: 15, color: AppColors.textPrim),
            SizedBox(width: 5),
            Text('Sample',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrim)),
          ]),
        ),
      ),
    ],
  );

  Widget _equalizer(AudioProvider prov) {
    return StreamBuilder<Amplitude>(
      stream: prov.isRecording ? prov.amplitudeStream : null,
      builder: (context, snap) {
        if (snap.hasData && prov.isRecording) {
          final db  = snap.data!.current.clamp(-80.0, 0.0);
          final amp = ((db + 80) / 80).clamp(0.0, 1.0);
          _startAnimating(amp);
        } else if (!prov.isRecording && _eqTimer?.isActive == true) {
          _eqTimer?.cancel(); _eqTimer = null;
        }
        return Container(
          height: 180,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: RepaintBoundary(
            child: CustomPaint(
              painter: EqualizerPainter(bars: _bars, isActive: prov.isRecording),
              size: Size.infinite,
            ),
          ),
        );
      },
    );
  }

  Widget _timer(AudioProvider prov) => Center(
    child: Text(
      prov.isRecording ? _fmt(_seconds) : '00:00',
      style: const TextStyle(
        fontSize: 52,
        fontWeight: FontWeight.w200,
        color: AppColors.textPrim,
        letterSpacing: 6,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    ),
  );

  Widget _presets(AudioProvider prov) {
    const labels = {
      VoicePreset.natural: 'Clean',
      VoicePreset.crispy:  'Crispy',
      VoicePreset.radio:   'Radio',
      VoicePreset.deep:    'Deep',
      VoicePreset.pop:     'Pop',
      VoicePreset.hype:    'Hype',
    };
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: VoicePreset.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final p      = VoicePreset.values[i];
          final active = prov.params.preset == p;
          return GestureDetector(
            onTap: () => prov.applyPreset(p),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              decoration: BoxDecoration(
                color:        active ? AppColors.textPrim : AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: active ? AppColors.textPrim : AppColors.border,
                  width: 0.5,
                ),
              ),
              child: Text(
                labels[p] ?? p.name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: active ? AppColors.white : AppColors.textSec,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _recordBtn(AudioProvider prov) => Center(
    child: GestureDetector(
      onTap: () => _onRecordTap(prov),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
        width: 80, height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: prov.isRecording ? AppColors.danger : AppColors.textPrim,
          boxShadow: [
            BoxShadow(
              color: (prov.isRecording ? AppColors.danger : AppColors.textPrim)
                  .withValues(alpha: 0.22),
              blurRadius: 28,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(
          prov.isRecording ? Icons.stop_rounded : Icons.mic_rounded,
          color: AppColors.white,
          size: 32,
        ),
      ),
    ),
  );

  Widget _statusLine(AudioProvider prov) {
    final (text, color) = prov.isRecording
        ? ('Recording — noise cancellation active', AppColors.danger)
        : prov.originalAudio != null
            ? ('Recording complete — open Denoise tab to process', AppColors.success)
            : ('Tap to start recording', AppColors.textDim);

    return Center(
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: color),
        textAlign: TextAlign.center,
      ),
    );
  }
}
