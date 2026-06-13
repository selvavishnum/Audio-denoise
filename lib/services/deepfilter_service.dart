import 'dart:typed_data';
import 'package:flutter/services.dart';

/// Bridge to the Kotlin AI neural processors.
///
/// Engine priority:
///   1. DeepFilterNet3 ONNX (studio-grade — requires 3 model files in assets/models/)
///   2. Built-in OMLSA-IMCRA neural processor (always available, no model files)
///
/// Call [initialize] at app start. Both engines initialise in parallel; the
/// app is ready even when ONNX models are absent.
class DeepFilterService {
  static const _channel = MethodChannel('com.noiseclear.app/audio');

  static bool _deepFilterReady  = false;
  static bool _neuralProcReady  = false;

  /// True when DeepFilterNet3 ONNX models are loaded.
  static bool get isReady       => _deepFilterReady;

  /// True when the built-in OMLSA-IMCRA neural processor is ready.
  /// Always becomes true after [initialize] unless the Kotlin bridge itself fails.
  static bool get isBuiltInReady => _neuralProcReady;

  /// True when any neural engine is available for processing.
  static bool get hasAnyEngine  => _deepFilterReady || _neuralProcReady;

  /// Initialise both engines concurrently.
  static Future<void> initialize() async {
    await Future.wait([
      _initDeepFilter(),
      _initBuiltIn(),
    ]);
  }

  static Future<void> _initDeepFilter() async {
    try {
      final ok = await _channel.invokeMethod<bool>('initDeepFilter') ?? false;
      _deepFilterReady = ok;
    } catch (_) {
      _deepFilterReady = false;
    }
  }

  static Future<void> _initBuiltIn() async {
    try {
      final ok = await _channel.invokeMethod<bool>('initNeuralProcessor') ?? false;
      _neuralProcReady = ok;
    } catch (_) {
      _neuralProcReady = false;
    }
  }

  /// Denoise [samples] at [sampleRate] using the best available engine.
  ///
  /// Engine selection:
  ///   • DeepFilterNet3 ONNX when [preferDeepFilter] is true AND models loaded
  ///   • Built-in OMLSA-IMCRA neural processor otherwise
  ///
  /// [isolator]: premium second-pass refinement (DeepFilterNet3 only).
  ///
  /// Returns enhanced PCM, or null on failure.
  static Future<Float32List?> denoise(
    Float32List samples,
    int sampleRate, {
    bool isolator = false,
    bool preferDeepFilter = true,
  }) async {
    if (preferDeepFilter && _deepFilterReady) {
      final result = await _runDeepFilter(samples, sampleRate, isolator);
      if (result != null) return result;
      // fall through to built-in on transient failure
    }
    if (_neuralProcReady) {
      return _runBuiltIn(samples, sampleRate);
    }
    return null;
  }

  static Future<Float32List?> _runDeepFilter(
      Float32List samples, int sampleRate, bool isolator) async {
    try {
      final inputBytes = samples.buffer.asUint8List(
          samples.offsetInBytes, samples.lengthInBytes);
      final result = await _channel.invokeMethod<Uint8List>('deepFilter', {
        'pcm':      inputBytes,
        'rate':     sampleRate,
        'isolator': isolator,
      });
      return result == null ? null : _bytesToFloat32(result);
    } catch (_) {
      return null;
    }
  }

  static Future<Float32List?> _runBuiltIn(
      Float32List samples, int sampleRate) async {
    try {
      final inputBytes = samples.buffer.asUint8List(
          samples.offsetInBytes, samples.lengthInBytes);
      final result = await _channel.invokeMethod<Uint8List>('neuralDenoise', {
        'pcm':  inputBytes,
        'rate': sampleRate,
      });
      return result == null ? null : _bytesToFloat32(result);
    } catch (_) {
      return null;
    }
  }

  static Float32List _bytesToFloat32(Uint8List bytes) {
    final bd  = ByteData.sublistView(bytes);
    final out = Float32List(bytes.length ~/ 4);
    for (int i = 0; i < out.length; i++) {
      out[i] = bd.getFloat32(i * 4, Endian.little);
    }
    return out;
  }
}
