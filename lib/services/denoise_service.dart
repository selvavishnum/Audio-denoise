import 'dart:io';
import 'package:ffmpeg_kit_flutter_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_min_gpl/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_min_gpl/return_code.dart';
import '../models/denoise_settings.dart';
import 'storage_service.dart';

enum DenoiseStatus { idle, processing, success, error }

class DenoiseResult {
  final DenoiseStatus status;
  final String? outputPath;
  final String? error;
  final double noiseReductionDb;
  final Duration processingTime;

  const DenoiseResult({
    required this.status,
    this.outputPath,
    this.error,
    this.noiseReductionDb = 0,
    this.processingTime = Duration.zero,
  });
}

class DenoiseService {
  static DenoiseService? _instance;
  static DenoiseService get instance => _instance ??= DenoiseService._();
  DenoiseService._();

  Future<DenoiseResult> denoise({
    required String inputPath,
    required DenoiseSettings settings,
    void Function(double progress)? onProgress,
  }) async {
    final startTime = DateTime.now();

    final inputFile = File(inputPath);
    if (!await inputFile.exists()) {
      return const DenoiseResult(
        status: DenoiseStatus.error,
        error: 'Input file not found',
      );
    }

    final outputPath = await StorageService.instance.newProcessedPath(inputPath);
    final filterChain = settings.buildFFmpegFilter();

    // Enable statistics callback for progress
    FFmpegKitConfig.enableStatisticsCallback((stats) {
      final time = stats.getTime();
      if (time > 0 && onProgress != null) {
        // Rough progress estimation (won't be precise without total duration)
        onProgress((time / 1000).clamp(0.0, 0.95));
      }
    });

    final command = '-y -i "$inputPath" -af "$filterChain" -ar 44100 -ac 2 "$outputPath"';

    try {
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        onProgress?.call(1.0);
        final elapsed = DateTime.now().difference(startTime);
        final reduction = _estimateNoiseReduction(settings);
        return DenoiseResult(
          status: DenoiseStatus.success,
          outputPath: outputPath,
          noiseReductionDb: reduction,
          processingTime: elapsed,
        );
      } else {
        final logs = await session.getAllLogs();
        final errorMsg = logs.map((l) => l.getMessage()).join('\n');
        return DenoiseResult(
          status: DenoiseStatus.error,
          error: errorMsg,
        );
      }
    } catch (e) {
      return DenoiseResult(
        status: DenoiseStatus.error,
        error: e.toString(),
      );
    } finally {
      FFmpegKitConfig.enableStatisticsCallback(null);
    }
  }

  double _estimateNoiseReduction(DenoiseSettings settings) {
    // Estimate the effective noise reduction level in dB
    final base = settings.noiseReduction / 100 * 30;
    final floorBonus = (-settings.noiseFloor - 20) / 60 * 10;
    return (base + floorBonus).clamp(5, 45);
  }

  Future<String?> getAudioInfo(String path) async {
    try {
      final session = await FFmpegKit.execute('-i "$path" -hide_banner');
      final logs = await session.getAllLogs();
      return logs.map((l) => l.getMessage()).join('\n');
    } catch (e) {
      return null;
    }
  }

  Future<int?> getAudioDurationMs(String path) async {
    try {
      final session = await FFmpegKit.execute(
        '-v quiet -print_format compact=print_section=0 -show_entries format=duration -i "$path"',
      );
      final output = await session.getAllLogs();
      for (final log in output) {
        final msg = log.getMessage();
        if (msg.contains('duration=')) {
          final durationStr = msg.split('duration=').last.trim();
          final seconds = double.tryParse(durationStr);
          if (seconds != null) {
            return (seconds * 1000).round();
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<bool> exportToFile(String processedPath, String exportPath) async {
    try {
      final session = await FFmpegKit.execute(
        '-y -i "$processedPath" -b:a 320k "$exportPath"',
      );
      final returnCode = await session.getReturnCode();
      return ReturnCode.isSuccess(returnCode);
    } catch (e) {
      return false;
    }
  }
}
