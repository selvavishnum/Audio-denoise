import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

/// On-device neural text-to-speech using Piper/VITS models via ONNX Runtime.
///
/// Voices are NOT bundled in the APK (they are 20–60 MB each). They are
/// downloaded once from the official sherpa-onnx model release, extracted to
/// app storage, and then run fully offline — no API key, no cloud, nothing
/// uploaded. After the one-time download a voice works with no network.
enum NeuralVoice { female, male }

class _VoiceSpec {
  /// Archive base name == extracted folder name.
  final String id;
  /// The .onnx file inside the extracted folder.
  final String onnxFile;
  /// Official sherpa-onnx release download URL (.tar.bz2).
  final String url;
  /// Human label.
  final String label;
  /// Approx download size for the UI.
  final String size;

  const _VoiceSpec(this.id, this.onnxFile, this.url, this.label, this.size);
}

class NeuralTtsService {
  static bool _bindingsInited = false;

  static const Map<NeuralVoice, _VoiceSpec> _voices = {
    NeuralVoice.female: _VoiceSpec(
      'vits-piper-en_US-amy-low',
      'en_US-amy-low.onnx',
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-amy-low.tar.bz2',
      'Amy · Female',
      '~28 MB',
    ),
    NeuralVoice.male: _VoiceSpec(
      'vits-piper-en_US-ryan-medium',
      'en_US-ryan-medium.onnx',
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-ryan-medium.tar.bz2',
      'Ryan · Male',
      '~63 MB',
    ),
  };

  final Map<NeuralVoice, sherpa_onnx.OfflineTts> _engines = {};

  String label(NeuralVoice v) => _voices[v]!.label;
  String size(NeuralVoice v)  => _voices[v]!.size;

  Future<Directory> _root() async {
    final base = await getApplicationSupportDirectory();
    final root = Directory('${base.path}/neural_tts');
    if (!root.existsSync()) root.createSync(recursive: true);
    return root;
  }

  Future<Directory> _voiceDir(NeuralVoice v) async =>
      Directory('${(await _root()).path}/${_voices[v]!.id}');

  /// True once the model has been downloaded and extracted.
  Future<bool> isReady(NeuralVoice v) async {
    final dir  = await _voiceDir(v);
    final onnx = File('${dir.path}/${_voices[v]!.onnxFile}');
    final tok  = File('${dir.path}/tokens.txt');
    return onnx.existsSync() && tok.existsSync();
  }

  /// Download + extract a voice pack. [onProgress] reports 0.0–1.0 during the
  /// download phase; extraction runs on a background isolate afterwards.
  /// Throws on network or extraction failure.
  Future<void> download(NeuralVoice v, {void Function(double)? onProgress}) async {
    final spec = _voices[v]!;
    final root = await _root();
    final tmp  = File('${root.path}/${spec.id}.tar.bz2');

    final client = http.Client();
    try {
      final req  = http.Request('GET', Uri.parse(spec.url));
      final resp = await client.send(req);
      if (resp.statusCode != 200) {
        throw Exception('Download failed (HTTP ${resp.statusCode})');
      }
      final total = resp.contentLength ?? 0;
      final sink  = tmp.openWrite();
      int received = 0;
      await for (final chunk in resp.stream) {
        received += chunk.length;
        sink.add(chunk);
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.close();
    } finally {
      client.close();
    }

    // Extract on a background isolate so the UI stays responsive.
    await compute(_extractTarBz2, [tmp.path, root.path]);

    if (tmp.existsSync()) {
      try { tmp.deleteSync(); } catch (_) {}
    }

    // Verify extraction produced the expected files.
    if (!await isReady(v)) {
      throw Exception('Voice pack extracted but model files are missing');
    }
  }

  /// Delete a downloaded voice to reclaim storage.
  Future<void> remove(NeuralVoice v) async {
    _engines.remove(v)?.free();
    final dir = await _voiceDir(v);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  /// Synthesize [text] with the given voice to a WAV file. Returns the file
  /// path, or null if the model isn't ready or synthesis fails.
  Future<String?> synthesize(
    NeuralVoice v,
    String text, {
    double speed = 1.0,
  }) async {
    if (text.trim().isEmpty) return null;
    final engine = await _engine(v);
    if (engine == null) return null;

    final audio = engine.generate(text: text, sid: 0, speed: speed);
    final docs  = await getApplicationDocumentsDirectory();
    final path  = '${docs.path}/neural_tts_${DateTime.now().millisecondsSinceEpoch}.wav';
    final ok = sherpa_onnx.writeWave(
      filename: path,
      samples: audio.samples,
      sampleRate: audio.sampleRate,
    );
    return ok ? path : null;
  }

  Future<sherpa_onnx.OfflineTts?> _engine(NeuralVoice v) async {
    final cached = _engines[v];
    if (cached != null) return cached;
    if (!await isReady(v)) return null;

    if (!_bindingsInited) {
      sherpa_onnx.initBindings();
      _bindingsInited = true;
    }

    final spec = _voices[v]!;
    final dir  = await _voiceDir(v);
    final config = sherpa_onnx.OfflineTtsConfig(
      model: sherpa_onnx.OfflineTtsModelConfig(
        vits: sherpa_onnx.OfflineTtsVitsModelConfig(
          model: '${dir.path}/${spec.onnxFile}',
          tokens: '${dir.path}/tokens.txt',
          dataDir: '${dir.path}/espeak-ng-data',
        ),
        numThreads: 2,
        debug: false,
      ),
    );
    final tts = sherpa_onnx.OfflineTts(config);
    _engines[v] = tts;
    return tts;
  }

  void dispose() {
    for (final e in _engines.values) {
      e.free();
    }
    _engines.clear();
  }
}

/// Top-level helper for compute(): decompress a .tar.bz2 and write every entry
/// under [destRoot]. args = [archivePath, destRoot].
void _extractTarBz2(List<String> args) {
  final archivePath = args[0];
  final destRoot    = args[1];

  final compressed = File(archivePath).readAsBytesSync();
  final tarBytes   = BZip2Decoder().decodeBytes(compressed);
  final archive    = TarDecoder().decodeBytes(tarBytes);

  for (final entry in archive) {
    final outPath = '$destRoot/${entry.name}';
    if (entry.isFile) {
      final f = File(outPath);
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(entry.content as List<int>);
    } else {
      Directory(outPath).createSync(recursive: true);
    }
  }
}
