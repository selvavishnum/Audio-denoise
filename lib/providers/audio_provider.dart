import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_audio/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/audio_params.dart';
import '../services/processor_service.dart';

class AudioProvider extends ChangeNotifier {
  AudioData? originalAudio;
  AudioData? _savedOriginal; // snapshot taken at load time — used for Restart
  AudioData? processedAudio;
  AudioParams params = AudioParams.presets[VoicePreset.natural]!;
  bool isRecording = false;
  bool isProcessing = false;
  double progress = 0.0;
  String? errorMessage;
  String? originalPath;
  String? processedPath;

  // ── Undo history ──────────────────────────────────────────────────────
  final List<AudioData> _history = [];
  static const int _maxHistory = 10;
  bool get canUndo => _history.isNotEmpty;

  // ── Usage / monetization counter ──────────────────────────────────────
  int _exportCount = 0;
  static const int freeExportLimit = 10;
  int get exportCount => _exportCount;
  int get freeExportsLeft => max(0, freeExportLimit - _exportCount);
  bool get hasReachedFreeLimit => _exportCount >= freeExportLimit;

  // ── Playback ──────────────────────────────────────────────────────────
  final _origPlayer = AudioPlayer();
  final _procPlayer = AudioPlayer();
  bool _playingOrig = false;
  bool _playingProc = false;
  bool get playingOriginal  => _playingOrig;
  bool get playingProcessed => _playingProc;

  // ── Recording ─────────────────────────────────────────────────────────
  final _recorder = AudioRecorder();
  final _uuid = const Uuid();

  AudioProvider() {
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final idx   = prefs.getInt('preset') ?? VoicePreset.natural.index;
    final preset = VoicePreset.values[idx.clamp(0, VoicePreset.values.length - 1)];
    params        = AudioParams.presets[preset]!;
    _exportCount  = prefs.getInt('exportCount') ?? 0;
    notifyListeners();
  }

  // ── Preset ──────────────────────────────────────────────────────────

  Future<void> applyPreset(VoicePreset preset) async {
    params = AudioParams.presets[preset]!.copyWith(mode: params.mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('preset', preset.index);
    notifyListeners();
  }

  void updateParams(AudioParams p) {
    params = p;
    notifyListeners();
  }

  // ── Import ───────────────────────────────────────────────────────────

  Future<void> loadFile(String path) async {
    errorMessage   = null;
    processedAudio = null;
    processedPath  = null;
    _history.clear();

    try {
      AudioData? data;
      final ext = path.toLowerCase();

      if (ext.endsWith('.wav')) {
        final bytes = await File(path).readAsBytes();
        data = ProcessorService.decodeWav(bytes);
      } else {
        // MP3, M4A, AAC, FLAC, OGG — convert via FFmpeg
        data = await _convertToWavAndDecode(path);
      }

      if (data == null) {
        errorMessage = 'Could not decode audio file';
      } else {
        originalAudio  = data;
        _savedOriginal = data; // save snapshot for Restart
        originalPath   = path;
      }
    } catch (e) {
      errorMessage = 'Error loading file: $e';
    }
    notifyListeners();
  }

  // Public helper so other screens (e.g. music picker in EditScreen) can decode any format
  Future<AudioData?> convertFileToAudioData(String path) async {
    final lower = path.toLowerCase();
    if (lower.endsWith('.wav')) {
      final bytes = await File(path).readAsBytes();
      return ProcessorService.decodeWav(bytes);
    }
    return _convertToWavAndDecode(path);
  }

  Future<AudioData?> _convertToWavAndDecode(String inputPath) async {
    try {
      final dir        = await getTemporaryDirectory();
      final outputPath = '${dir.path}/nc_import_${_uuid.v4()}.wav';
      final session    = await FFmpegKit.execute(
        '-y -i "$inputPath" -ar 44100 -ac 1 -acodec pcm_s16le "$outputPath"',
      );
      final rc = await session.getReturnCode();
      if (!ReturnCode.isSuccess(rc)) return null;
      final bytes = await File(outputPath).readAsBytes();
      await File(outputPath).delete().catchError((_) {});
      return ProcessorService.decodeWav(bytes);
    } catch (_) {
      return null;
    }
  }

  // ── Recording ────────────────────────────────────────────────────────

  Future<bool> startRecording() async {
    if (!await _recorder.hasPermission()) return false;
    try {
      final dir  = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/rec_${_uuid.v4()}.wav';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 44100, numChannels: 1),
        path: path,
      );
      isRecording = true;
      notifyListeners();
      return true;
    } catch (e) {
      errorMessage = 'Recording failed: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> stopRecording() async {
    final path = await _recorder.stop();
    isRecording = false;
    if (path != null) await loadFile(path);
    notifyListeners();
  }

  Stream<Amplitude> get amplitudeStream =>
      _recorder.onAmplitudeChanged(const Duration(milliseconds: 60));

  // ── Processing ────────────────────────────────────────────────────────

  Future<void> processAudio() async {
    if (originalAudio == null) return;
    isProcessing = true;
    progress     = 0;
    errorMessage = null;
    notifyListeners();

    try {
      processedAudio = await ProcessorService.process(
        originalAudio!, params,
        onProgress: (p) { progress = p; notifyListeners(); },
      );
      await _saveProcessed();
    } catch (e) {
      errorMessage = 'Processing error: $e';
    }

    isProcessing = false;
    progress     = 0;
    notifyListeners();
  }

  Future<void> _saveProcessed() async {
    if (processedAudio == null) return;
    final dir  = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/processed_${_uuid.v4()}.wav';
    await File(path).writeAsBytes(
        ProcessorService.encodeWav(processedAudio!.samples, processedAudio!.sampleRate));
    processedPath = path;
  }

  // ── Export / usage gate ───────────────────────────────────────────────

  Future<void> recordExport() async {
    _exportCount++;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('exportCount', _exportCount);
    notifyListeners();
  }

  // ── Playback ──────────────────────────────────────────────────────────

  Future<void> togglePlayOriginal() async {
    await _procPlayer.stop();
    _playingProc = false;
    if (_playingOrig) {
      await _origPlayer.stop();
      _playingOrig = false;
    } else if (originalPath != null) {
      await _origPlayer.setFilePath(originalPath!);
      await _origPlayer.play();
      _playingOrig = true;
      _origPlayer.playerStateStream.listen((s) {
        if (s.processingState == ProcessingState.completed) {
          _playingOrig = false;
          notifyListeners();
        }
      });
    }
    notifyListeners();
  }

  Future<void> togglePlayProcessed() async {
    await _origPlayer.stop();
    _playingOrig = false;
    if (_playingProc) {
      await _procPlayer.stop();
      _playingProc = false;
    } else if (processedPath != null) {
      await _procPlayer.setFilePath(processedPath!);
      await _procPlayer.play();
      _playingProc = true;
      _procPlayer.playerStateStream.listen((s) {
        if (s.processingState == ProcessingState.completed) {
          _playingProc = false;
          notifyListeners();
        }
      });
    }
    notifyListeners();
  }

  Future<void> stopAllPlayback() async {
    await _origPlayer.stop();
    await _procPlayer.stop();
    _playingOrig = false;
    _playingProc = false;
    notifyListeners();
  }

  // ── Edit operations ───────────────────────────────────────────────────

  void _pushHistory() {
    if (originalAudio == null) return;
    _history.add(originalAudio!);
    if (_history.length > _maxHistory) _history.removeAt(0);
  }

  void undo() {
    if (_history.isEmpty) return;
    originalAudio  = _history.removeLast();
    processedAudio = null;
    processedPath  = null;
    notifyListeners();
  }

  // Revert to the audio as it was when first loaded/recorded
  void restoreOriginal() {
    if (_savedOriginal == null) return;
    _history.clear();
    originalAudio  = _savedOriginal;
    processedAudio = null;
    processedPath  = null;
    notifyListeners();
  }

  void trimAudio(double startSec, double endSec) {
    final audio = originalAudio;
    if (audio == null) return;
    _pushHistory();
    final sr    = audio.sampleRate;
    final start = (startSec * sr).round().clamp(0, audio.samples.length);
    final end   = (endSec   * sr).round().clamp(start, audio.samples.length);
    originalAudio  = AudioData.fromSamples(
        Float32List.fromList(audio.samples.sublist(start, end)), sr);
    processedAudio = null;
    processedPath  = null;
    notifyListeners();
  }

  void joinAudio(AudioData second) {
    final audio = originalAudio;
    if (audio == null) return;
    _pushHistory();
    final combined = Float32List(audio.samples.length + second.samples.length);
    combined.setAll(0, audio.samples);
    combined.setAll(audio.samples.length, second.samples);
    originalAudio  = AudioData.fromSamples(combined, audio.sampleRate);
    processedAudio = null;
    processedPath  = null;
    notifyListeners();
  }

  // Mix voice audio with a background music track at independent volumes
  void mixWithMusic(AudioData music, double voiceVol, double musicVol) {
    final audio = originalAudio;
    if (audio == null) return;
    _pushHistory();
    final len   = max(audio.samples.length, music.samples.length);
    final mixed = Float32List(len);
    for (int i = 0; i < len; i++) {
      final v = i < audio.samples.length ? audio.samples[i] * voiceVol : 0.0;
      final m = i < music.samples.length ? music.samples[i] * musicVol : 0.0;
      mixed[i] = (v + m).clamp(-1.0, 1.0);
    }
    originalAudio  = AudioData.fromSamples(mixed, audio.sampleRate);
    processedAudio = null;
    processedPath  = null;
    notifyListeners();
  }

  String? get shareFilePath => processedPath;

  @override
  void dispose() {
    _origPlayer.dispose();
    _procPlayer.dispose();
    _recorder.dispose();
    super.dispose();
  }
}
