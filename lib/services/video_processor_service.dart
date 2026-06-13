import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/audio_params.dart';
import '../services/processor_service.dart';
import '../services/eleven_labs_service.dart';

export '../models/audio_params.dart';

const _channel = MethodChannel('com.noiseclear.app/video');
const _uuid    = Uuid();

class VideoProcessorService {

  // ── On-device neural AI path ──────────────────────────────────────────────

  /// Extract audio from [videoPath], apply on-device neural AI denoising,
  /// return path to cleaned WAV. Returns null on failure.
  static Future<String?> extractAndDenoise(
    String videoPath,
    AudioParams params, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      final dir    = await getTemporaryDirectory();
      final rawWav = '${dir.path}/vid_raw_${_uuid.v4()}.wav';

      onProgress?.call(0.05);
      final extracted = await _channel.invokeMethod<bool>('extractAudioToWav', {
        'videoPath':  videoPath,
        'outputPath': rawWav,
      }) ?? false;
      if (!extracted) return null;
      onProgress?.call(0.3);

      final bytes = await File(rawWav).readAsBytes();
      final audio = ProcessorService.decodeWav(bytes);
      try { await File(rawWav).delete(); } catch (_) {}
      if (audio == null) return null;

      final cleaned = await ProcessorService.process(
        audio, params,
        onProgress: (p) => onProgress?.call(0.3 + p * 0.55),
      );
      onProgress?.call(0.9);

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

  // ── ElevenLabs cloud AI path ──────────────────────────────────────────────

  /// Extract audio from [videoPath], send to ElevenLabs Audio Isolation API,
  /// return path to isolated WAV. Returns null on failure.
  ///
  /// Throws [ElevenLabsException] on API errors (missing key, quota, etc.).
  static Future<String?> extractAndDenoiseWithElevenLabs(
    String videoPath, {
    String? apiKey,
    void Function(double progress)? onProgress,
    void Function(String status)? onStatus,
  }) async {
    final dir    = await getTemporaryDirectory();
    final rawWav = '${dir.path}/vid_raw_${_uuid.v4()}.wav';

    // Step 1: extract audio track (0–30 %)
    onProgress?.call(0.05);
    onStatus?.call('Extracting audio track…');

    final extracted = await _channel.invokeMethod<bool>('extractAudioToWav', {
      'videoPath':  videoPath,
      'outputPath': rawWav,
    }) ?? false;
    if (!extracted) return null;
    onProgress?.call(0.3);

    // Step 2: send to ElevenLabs (30–90 %)
    final wavBytes = await File(rawWav).readAsBytes();
    try { await File(rawWav).delete(); } catch (_) {}

    final isolatedBytes = await ElevenLabsService.isolateAudio(
      wavBytes, 'audio/wav',
      apiKey: apiKey,
      onStatus: (s) {
        onStatus?.call(s);
        onProgress?.call(0.3 + 0.5 *
            (s.contains('Processing') ? 0.8 : s.contains('Done') ? 1.0 : 0.3));
      },
    );
    if (isolatedBytes == null) return null;
    onProgress?.call(0.9);

    // Step 3: write isolated audio to WAV (ElevenLabs returns the same format)
    final cleanWav = '${dir.path}/vid_clean_${_uuid.v4()}.wav';
    await File(cleanWav).writeAsBytes(isolatedBytes);
    onProgress?.call(1.0);
    return cleanWav;
  }

  // ── Mux clean audio back into video ──────────────────────────────────────

  /// Re-mux [cleanedWavPath] audio into [originalVideoPath] → output MP4.
  /// Returns the output path, or null on failure.
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
