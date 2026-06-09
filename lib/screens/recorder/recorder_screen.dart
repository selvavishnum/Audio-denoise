import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/audio_project.dart';
import '../../providers/app_provider.dart';
import '../../services/storage_service.dart';
import '../../widgets/common/gradient_button.dart';
import '../../widgets/common/waveform_painter.dart';
import '../denoiser/denoiser_screen.dart';

class RecorderScreen extends StatelessWidget {
  const RecorderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => RecorderProvider(),
      child: const _RecorderView(),
    );
  }
}

class _RecorderView extends StatelessWidget {
  const _RecorderView();

  @override
  Widget build(BuildContext context) {
    final recorder = context.watch<RecorderProvider>();

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        title: Text('New Recording',
            style: GoogleFonts.rajdhani(
                fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: 1)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () async {
            if (recorder.isRecording) await recorder.stopRecording();
            if (context.mounted) Navigator.of(context).pop();
          },
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Spacer(),
            _buildTimerDisplay(recorder),
            const SizedBox(height: 32),
            _buildWaveform(recorder),
            const SizedBox(height: 40),
            _buildVuMeter(recorder),
            const Spacer(),
            _buildControls(context, recorder),
            const SizedBox(height: 16),
            _buildHint(recorder),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildTimerDisplay(RecorderProvider recorder) {
    final elapsed = recorder.elapsed;
    final mins = elapsed.inMinutes.toString().padLeft(2, '0');
    final secs = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    final ms = (elapsed.inMilliseconds % 1000 ~/ 10).toString().padLeft(2, '0');

    return Column(
      children: [
        if (recorder.isRecording)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.recording.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.recording.withOpacity(0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.recording,
                    shape: BoxShape.circle,
                  ),
                ).animate(onPlay: (c) => c.repeat())
                    .fadeIn(duration: 500.ms)
                    .then()
                    .fadeOut(duration: 500.ms),
                const SizedBox(width: 6),
                const Text('RECORDING',
                    style: TextStyle(
                        color: AppColors.recording,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2)),
              ],
            ),
          )
        else if (recorder.state == RecordingState.paused)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.warning.withOpacity(0.5)),
            ),
            child: const Text('PAUSED',
                style: TextStyle(
                    color: AppColors.warning,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2)),
          )
        else
          const SizedBox(height: 26),
        const SizedBox(height: 12),
        Text(
          '$mins:$secs',
          style: GoogleFonts.rajdhani(
            fontSize: 72,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: -2,
          ),
        ),
        Text(
          '.$ms',
          style: GoogleFonts.rajdhani(
            fontSize: 32,
            fontWeight: FontWeight.w400,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildWaveform(RecorderProvider recorder) {
    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: AnimatedWaveform(
            isActive: recorder.isRecording,
            color: recorder.isRecording ? AppColors.recording : AppColors.primaryStart,
            amplitude: recorder.amplitude,
            height: 100,
          ),
        ),
      ),
    );
  }

  Widget _buildVuMeter(RecorderProvider recorder) {
    return Row(
      children: [
        const Icon(Icons.volume_up, color: AppColors.textMuted, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 80),
              height: 8,
              child: LinearProgressIndicator(
                value: recorder.amplitude,
                backgroundColor: AppColors.border,
                valueColor: AlwaysStoppedAnimation(
                  recorder.amplitude > 0.8
                      ? AppColors.recording
                      : recorder.amplitude > 0.6
                          ? AppColors.warning
                          : AppColors.success,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 40,
          child: Text(
            '${(recorder.amplitude * 100).round()}%',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildControls(BuildContext context, RecorderProvider recorder) {
    return Column(
      children: [
        if (recorder.state == RecordingState.idle) ...[
          GradientButton(
            label: 'Start Recording',
            icon: Icons.mic,
            gradient: const LinearGradient(
              colors: [AppColors.recording, Color(0xFFDC2626)],
            ),
            onPressed: () async {
              final ok = await recorder.startRecording();
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Microphone permission required')),
                );
              }
            },
          ),
        ] else if (recorder.isRecording) ...[
          Row(
            children: [
              Expanded(
                child: GradientButton(
                  label: 'Pause',
                  icon: Icons.pause,
                  gradient: LinearGradient(colors: [
                    AppColors.warning,
                    AppColors.warning.withOpacity(0.8)
                  ]),
                  onPressed: recorder.pauseRecording,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GradientButton(
                  label: 'Stop & Save',
                  icon: Icons.stop,
                  gradient: AppColors.primaryGradient,
                  onPressed: () => _stopAndProcess(context, recorder),
                ),
              ),
            ],
          ),
        ] else if (recorder.state == RecordingState.paused) ...[
          Row(
            children: [
              Expanded(
                child: GradientButton(
                  label: 'Resume',
                  icon: Icons.fiber_manual_record,
                  gradient: const LinearGradient(
                      colors: [AppColors.recording, Color(0xFFDC2626)]),
                  onPressed: recorder.resumeRecording,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GradientButton(
                  label: 'Save',
                  icon: Icons.check,
                  gradient: AppColors.primaryGradient,
                  onPressed: () => _stopAndProcess(context, recorder),
                ),
              ),
            ],
          ),
        ] else ...[
          const CircularProgressIndicator(color: AppColors.primaryStart),
        ],
      ],
    );
  }

  Future<void> _stopAndProcess(BuildContext context, RecorderProvider recorder) async {
    final path = await recorder.stopRecording();
    if (path == null || !context.mounted) return;

    final project = await StorageService.instance.createProjectFromFile(path);
    if (context.mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => DenoiserScreen(project: project)),
      );
    }
  }

  Widget _buildHint(RecorderProvider recorder) {
    if (recorder.state == RecordingState.idle) {
      return const Text(
        'Tap to start recording. All audio stays on your device.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
      );
    }
    return const SizedBox.shrink();
  }
}
