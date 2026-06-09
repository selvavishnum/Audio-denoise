// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'audio_project.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AudioProjectAdapter extends TypeAdapter<AudioProject> {
  @override
  final int typeId = 0;

  @override
  AudioProject read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AudioProject(
      id: fields[0] as String,
      name: fields[1] as String,
      originalPath: fields[2] as String,
      processedPath: fields[3] as String?,
      createdAt: fields[4] as DateTime,
      processedAt: fields[5] as DateTime?,
      denoiseMode: fields[6] as String,
      originalDurationMs: fields[7] as int,
      noiseReductionDb: fields[8] as double,
      isRecording: fields[9] as bool,
      thumbnailWaveform: fields[10] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, AudioProject obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.originalPath)
      ..writeByte(3)
      ..write(obj.processedPath)
      ..writeByte(4)
      ..write(obj.createdAt)
      ..writeByte(5)
      ..write(obj.processedAt)
      ..writeByte(6)
      ..write(obj.denoiseMode)
      ..writeByte(7)
      ..write(obj.originalDurationMs)
      ..writeByte(8)
      ..write(obj.noiseReductionDb)
      ..writeByte(9)
      ..write(obj.isRecording)
      ..writeByte(10)
      ..write(obj.thumbnailWaveform);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioProjectAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
