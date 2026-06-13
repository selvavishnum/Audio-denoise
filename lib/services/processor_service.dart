import 'dart:typed_data';

import '../models/audio_params.dart';
import 'deepfilter_service.dart';
import 'neural_processor_service.dart';

// ─── Public entry point ────────────────────────────────────────────────────
//
// NEURAL-ONLY pipeline (DSP and the standalone MMSE path were removed).
//
//   Free tier    → DeepFilterNet3 (on-device ONNX)            "Clean"
//   Premium tier → DeepFilterNet3 Voice Isolator (2-pass)     "Studio / 95%"
//
// MMSE-STSA remains ONLY as an automatic safety net for when the DeepFilterNet
// model files are not yet bundled in assets/models/ — so the app never emits
// unprocessed audio. Once the .onnx weights are present, DeepFilterNet always
// wins and the fallback is never reached.

class ProcessorService {
  /// True if the last process() call used DeepFilterNet3; false = MMSE fallback.
  static bool lastUsedNeural = false;

  /// [premium] selects the high-strength Voice Isolator pass (Pro/admin only).
  /// [deepFilterEnabled] — allow DeepFilterNet3 ONNX when models are present.
  /// [mmseEnabled]       — allow MMSE-STSA when neural is unavailable/disabled.
  static Future<AudioData> process(
    AudioData input,
    AudioParams params, {
    void Function(double)? onProgress,
    bool premium = false,
    bool deepFilterEnabled = true,
    bool mmseEnabled = true,
  }) async {
    onProgress?.call(0.05);

    // ── Primary: DeepFilterNet3 ONNX neural engine ───────────────────────────
    if (deepFilterEnabled && DeepFilterService.isReady) {
      final cleaned = await DeepFilterService.denoise(
        input.samples,
        input.sampleRate,
        isolator: premium,
      );
      if (cleaned != null) {
        lastUsedNeural = true;
        onProgress?.call(1.0);
        return AudioData.fromSamples(cleaned, input.sampleRate);
      }
    }

    // ── Fallback / DSP: MMSE-STSA spectral suppression ───────────────────────
    if (mmseEnabled) {
      lastUsedNeural = false;
      final fallback = await NeuralProcessorService.denoise(
          input.samples, input.sampleRate);
      onProgress?.call(1.0);
      return AudioData.fromSamples(fallback ?? input.samples, input.sampleRate);
    }

    // ── All engines disabled: return original unmodified ─────────────────────
    lastUsedNeural = false;
    onProgress?.call(1.0);
    return input;
  }

  // ─── WAV Decode ────────────────────────────────────────────────────────

  static AudioData? decodeWav(Uint8List bytes) {
    if (bytes.length < 44) return null;
    final bd = ByteData.sublistView(bytes);

    // Validate RIFF / WAVE markers
    if (bytes[0] != 0x52 || bytes[1] != 0x49 || bytes[2] != 0x46 || bytes[3] != 0x46) {
      return null;
    }
    if (bytes[8] != 0x57 || bytes[9] != 0x41 || bytes[10] != 0x56 || bytes[11] != 0x45) {
      return null;
    }

    int numChannels = 1, sampleRate = 44100, bitsPerSample = 16;
    int dataOffset = -1, dataSize = 0;
    int offset = 12;

    while (offset + 8 <= bytes.length) {
      final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = bd.getUint32(offset + 4, Endian.little);

      if (chunkId == 'fmt ') {
        numChannels = bd.getUint16(offset + 10, Endian.little);
        sampleRate = bd.getUint32(offset + 12, Endian.little);
        bitsPerSample = bd.getUint16(offset + 22, Endian.little);
      } else if (chunkId == 'data') {
        dataOffset = offset + 8;
        dataSize = chunkSize;
        break;
      }
      offset += 8 + chunkSize;
    }

    if (dataOffset < 0 || dataOffset + dataSize > bytes.length) return null;

    final int bytesPerSample = bitsPerSample ~/ 8;
    final int totalFrames = dataSize ~/ (bytesPerSample * numChannels);
    final samples = Float32List(totalFrames);

    for (int i = 0; i < totalFrames; i++) {
      double v = 0;
      for (int ch = 0; ch < numChannels; ch++) {
        final off = dataOffset + (i * numChannels + ch) * bytesPerSample;
        if (bitsPerSample == 16) {
          v += bd.getInt16(off, Endian.little) / 32768.0;
        } else if (bitsPerSample == 32) {
          v += bd.getInt32(off, Endian.little) / 2147483648.0;
        } else if (bitsPerSample == 8) {
          v += (bd.getUint8(off) - 128) / 128.0;
        }
      }
      samples[i] = (v / numChannels).clamp(-1.0, 1.0);
    }

    return AudioData.fromSamples(samples, sampleRate);
  }

  static Uint8List encodeWav(Float32List samples, int sampleRate) {
    final dataSize = samples.length * 2;
    final buffer = Uint8List(44 + dataSize);
    final bd = ByteData.sublistView(buffer);

    void writeStr(int off, String s) {
      for (int i = 0; i < s.length; i++) {
        buffer[off + i] = s.codeUnitAt(i);
      }
    }

    writeStr(0, 'RIFF');
    bd.setUint32(4, 36 + dataSize, Endian.little);
    writeStr(8, 'WAVE');
    writeStr(12, 'fmt ');
    bd.setUint32(16, 16, Endian.little);
    bd.setUint16(20, 1, Endian.little);  // PCM
    bd.setUint16(22, 1, Endian.little);  // mono
    bd.setUint32(24, sampleRate, Endian.little);
    bd.setUint32(28, sampleRate * 2, Endian.little);
    bd.setUint16(32, 2, Endian.little);
    bd.setUint16(34, 16, Endian.little);
    writeStr(36, 'data');
    bd.setUint32(40, dataSize, Endian.little);

    for (int i = 0; i < samples.length; i++) {
      final s = (samples[i].clamp(-1.0, 1.0) * 32767).round().clamp(-32768, 32767);
      bd.setInt16(44 + i * 2, s, Endian.little);
    }
    return buffer;
  }
}
