import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/audio_params.dart';
import '../services/processor_service.dart';

export '../models/audio_params.dart';

const _channel = MethodChannel('com.selvavishnu.clearwave/video');
const _uuid    = Uuid();

class VideoProcessorService {
  // Extract audio from [videoPath] as a WAV file, apply DSP, write cleaned WAV.
  // Returns the path to the cleaned WAV, or null on failure.
  static Future<String?> extractAndDenoise(
    String videoPath,
    AudioParams params, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      final dir    = await getTemporaryDirectory();
      final rawWav = '${dir.path}/vid_raw_${_uuid.v4()}.wav';

      // Step 1 — extract audio from video (0–30%)
      onProgress?.call(0.05);
      final extracted = await _channel.invokeMethod<bool>('extractAudioToWav', {
        'videoPath':  videoPath,
        'outputPath': rawWav,
      }) ?? false;
      if (!extracted) return null;
      onProgress?.call(0.3);

      // Step 2 — load WAV and run DSP (30–85%)
      final bytes = await File(rawWav).readAsBytes();
      final audio = ProcessorService.decodeWav(bytes);
      try { await File(rawWav).delete(); } catch (_) {}

      if (audio == null) return null;

      final cleaned = await ProcessorService.process(
        audio, params,
        onProgress: (p) => onProgress?.call(0.3 + p * 0.55),
      );
      onProgress?.call(0.85);

      // Step 3 — write cleaned WAV
      final cleanWav = '${dir.path}/vid_clean_${_uuid.v4()}.wav';
      await File(cleanWav).writeAsBytes(
        ProcessorService.encodeWav(cleaned.samples, cleaned.sampleRate),
      );
      onProgress?.call(1.0);
      return cleanWav;
    } catch (_) {
      return null;
    }
  }

  // Re-mux [cleanedWavPath] audio into [originalVideoPath] → output MP4.
  // Returns the output path, or null on failure.
  static Future<String?> muxAudioIntoVideo(
    String originalVideoPath,
    String cleanedWavPath,
  ) async {
    try {
      final dir    = await getApplicationDocumentsDirectory();
      final output = '${dir.path}/noiseclear_video_${_uuid.v4()}.mp4';
      final ok     = await _channel.invokeMethod<bool>('muxProcessedAudioIntoVideo', {
        'videoPath':  originalVideoPath,
        'wavPath':    cleanedWavPath,
        'outputPath': output,
      }) ?? false;
      return ok ? output : null;
    } catch (_) {
      return null;
    }
  }
}
