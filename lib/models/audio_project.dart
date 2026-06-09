import 'package:hive/hive.dart';

part 'audio_project.g.dart';

@HiveType(typeId: 0)
class AudioProject extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String originalPath;

  @HiveField(3)
  String? processedPath;

  @HiveField(4)
  DateTime createdAt;

  @HiveField(5)
  DateTime? processedAt;

  @HiveField(6)
  String denoiseMode;

  @HiveField(7)
  int originalDurationMs;

  @HiveField(8)
  double noiseReductionDb;

  @HiveField(9)
  bool isRecording;

  @HiveField(10)
  String? thumbnailWaveform;

  AudioProject({
    required this.id,
    required this.name,
    required this.originalPath,
    this.processedPath,
    required this.createdAt,
    this.processedAt,
    required this.denoiseMode,
    this.originalDurationMs = 0,
    this.noiseReductionDb = 0.0,
    this.isRecording = false,
    this.thumbnailWaveform,
  });

  bool get isProcessed => processedPath != null;

  String get displayName {
    if (name.isEmpty) {
      final date = createdAt;
      return 'Track ${date.day}/${date.month} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    }
    return name;
  }

  String get duration {
    if (originalDurationMs == 0) return '--:--';
    final secs = originalDurationMs ~/ 1000;
    final mins = secs ~/ 60;
    final remaining = secs % 60;
    return '${mins.toString().padLeft(2, '0')}:${remaining.toString().padLeft(2, '0')}';
  }

  AudioProject copyWith({
    String? processedPath,
    DateTime? processedAt,
    String? denoiseMode,
    int? originalDurationMs,
    double? noiseReductionDb,
  }) {
    return AudioProject(
      id: id,
      name: name,
      originalPath: originalPath,
      processedPath: processedPath ?? this.processedPath,
      createdAt: createdAt,
      processedAt: processedAt ?? this.processedAt,
      denoiseMode: denoiseMode ?? this.denoiseMode,
      originalDurationMs: originalDurationMs ?? this.originalDurationMs,
      noiseReductionDb: noiseReductionDb ?? this.noiseReductionDb,
      isRecording: isRecording,
    );
  }
}
