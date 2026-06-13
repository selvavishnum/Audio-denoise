import 'dart:typed_data';
import 'package:flutter/services.dart';

class DeepFilterService {
  static const _channel = MethodChannel('com.noiseclear.app/audio');

  static bool _ready = false;
  static bool get isReady => _ready;

  static Future<void> initialize() async {
    try {
      final ok = await _channel.invokeMethod<bool>('initDeepFilter') ?? false;
      _ready = ok;
    } catch (_) {
      _ready = false;
    }
  }

  /// Returns enhanced PCM as Float32List, or null on failure.
  static Future<Float32List?> denoise(Float32List samples, int sampleRate) async {
    if (!_ready) return null;
    try {
      // Pack Float32List into bytes (little-endian IEEE-754)
      final inputBytes = samples.buffer.asUint8List(
        samples.offsetInBytes, samples.lengthInBytes,
      );
      final result = await _channel.invokeMethod<Uint8List>('deepFilter', {
        'pcm':  inputBytes,
        'rate': sampleRate,
      });
      if (result == null) return null;
      // Unpack result bytes back to Float32List
      final bd = ByteData.sublistView(result);
      final out = Float32List(result.length ~/ 4);
      for (int i = 0; i < out.length; i++) {
        out[i] = bd.getFloat32(i * 4, Endian.little);
      }
      return out;
    } catch (_) {
      return null;
    }
  }
}
