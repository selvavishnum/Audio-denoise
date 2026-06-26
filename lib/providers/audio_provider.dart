import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/audio_params.dart';
import '../models/processing_stats.dart';
import '../services/processor_service.dart';
import '../services/stem_separator_service.dart';

const _videoChannel = MethodChannel('com.noiseclear.app/video');

class AudioProvider extends ChangeNotifier {
  AudioData? originalAudio;
  AudioData? _savedOriginal;
  AudioData? processedAudio;
  AudioParams params = AudioParams.presets[VoicePreset.natural]!;
  bool isRecording = false;
  bool isProcessing = false;
  double progress = 0.0;
  String? errorMessage;
  String? originalPath;
  String? processedPath;

  // ── Processing stats ──────────────────────────────────────────────────
  ProcessingStats? lastStats;

  // ── HD Mode ───────────────────────────────────────────────────────────
  bool hdModeEnabled = false;

  // ── AI Engine toggles ─────────────────────────────────────────────────
  bool isolatorEnabled = false; // Voice Isolator — aggressive 2-pass extraction

  // ── Vocal / Music split ──────────────────────────────────────────────
  AudioData? vocalsAudio;
  AudioData? musicAudio;
  String? vocalsPath;
  String? musicPath;
  bool isSplitting = false;
  double splitProgress = 0.0;

  // ── Recent history ────────────────────────────────────────────────────
  final List<HistoryItem> recentFiles = [];

  // ── Undo history ──────────────────────────────────────────────────────
  final List<AudioData> _history = [];
  static const int _maxHistory = 10;
  bool get canUndo => _history.isNotEmpty;

  // ── Usage / monetization counter ──────────────────────────────────────
  int _exportCount = 0;
  static const int freeExportLimit = 30;
  int get exportCount => _exportCount;
  int get freeExportsLeft => max(0, freeExportLimit - _exportCount);
  bool get hasReachedFreeLimit => _exportCount >= freeExportLimit;

  // ── Daily ad bonus ────────────────────────────────────────────────────
  String? _lastBonusDate;
  bool get canUseDailyBonus {
    if (_lastBonusDate == null) return true;
    return _lastBonusDate != _todayString();
  }

  static String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  // ── Playback ──────────────────────────────────────────────────────────
  final _origPlayer = AudioPlayer();
  final _procPlayer = AudioPlayer();
  final _vocalsPlayer = AudioPlayer();
  final _musicPlayer = AudioPlayer();
  bool _playingOrig = false;
  bool _playingProc = false;
  bool _playingVocals = false;
  bool _playingMusic = false;
  bool get playingOriginal  => _playingOrig;
  bool get playingProcessed => _playingProc;
  bool get playingVocals    => _playingVocals;
  bool get playingMusic     => _playingMusic;

  // ── Recording ─────────────────────────────────────────────────────────
  final _recorder = AudioRecorder();
  final _uuid = const Uuid();

  AudioProvider() {
    _init();
    // Subscribe to each player's completion ONCE here, not on every playback
    // toggle — otherwise a fresh listener accumulates with each tap and leaks.
    _origPlayer.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed && _playingOrig) {
        _playingOrig = false;
        notifyListeners();
      }
    });
    _procPlayer.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed && _playingProc) {
        _playingProc = false;
        notifyListeners();
      }
    });
    _vocalsPlayer.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed && _playingVocals) {
        _playingVocals = false;
        notifyListeners();
      }
    });
    _musicPlayer.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed && _playingMusic) {
        _playingMusic = false;
        notifyListeners();
      }
    });
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final idx    = prefs.getInt('preset') ?? VoicePreset.natural.index;
    final preset = VoicePreset.values[idx.clamp(0, VoicePreset.values.length - 1)];
    params        = AudioParams.presets[preset]!;
    _exportCount   = prefs.getInt('exportCount') ?? 0;
    hdModeEnabled  = prefs.getBool('hdMode') ?? false;
    _lastBonusDate = prefs.getString('lastBonusDate');
    isolatorEnabled = prefs.getBool('isolatorEnabled') ?? false;
    _loadHistory(prefs);
    notifyListeners();
  }

  void _loadHistory(SharedPreferences prefs) {
    final list = prefs.getStringList('history') ?? [];
    recentFiles.clear();
    for (final s in list) {
      final item = HistoryItem.tryParse(s);
      if (item != null) recentFiles.add(item);
    }
  }

  // ── Preset ───────────────────────────────────────────────────────────

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

  // ── HD Mode ───────────────────────────────────────────────────────────

  Future<void> toggleHdMode() async {
    hdModeEnabled = !hdModeEnabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hdMode', hdModeEnabled);
    notifyListeners();
  }

  Future<void> toggleIsolator() async {
    isolatorEnabled = !isolatorEnabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isolatorEnabled', isolatorEnabled);
    notifyListeners();
  }

  // ── Import ───────────────────────────────────────────────────────────

  Future<void> loadFile(String path) async {
    errorMessage   = null;
    processedAudio = null;
    processedPath  = null;
    lastStats      = null;
    vocalsAudio    = null;
    musicAudio     = null;
    vocalsPath     = null;
    musicPath      = null;
    _history.clear();

    try {
      AudioData? data;
      final ext = path.toLowerCase();

      if (ext.endsWith('.wav')) {
        final bytes = await File(path).readAsBytes();
        data = ProcessorService.decodeWav(bytes);
      } else {
        data = await _convertToWavAndDecode(path);
      }

      if (data == null) {
        errorMessage = 'Could not decode audio file';
      } else {
        originalAudio  = data;
        _savedOriginal = data;
        originalPath   = path;
      }
    } catch (e) {
      errorMessage = 'Error loading file: $e';
    }
    notifyListeners();
  }

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
      final dir     = await getTemporaryDirectory();
      final outPath = '${dir.path}/import_${_uuid.v4()}.wav';
      final ok = await _videoChannel.invokeMethod<bool>(
        'extractAudioToWav',
        {'videoPath': inputPath, 'outputPath': outPath},
      );
      if (ok != true) return null;
      final bytes = await File(outPath).readAsBytes();
      final data  = ProcessorService.decodeWav(bytes);
      File(outPath).deleteSync();
      return data;
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

  /// [premium] enables the Voice Isolator pass (Pro / admin users only).
  Future<void> processAudio({bool premium = false}) async {
    if (originalAudio == null) return;
    isProcessing = true;
    progress     = 0;
    errorMessage = null;
    notifyListeners();

    final startTime = DateTime.now();
    try {
      AudioData inputForDsp = originalAudio!;

      if (hdModeEnabled) {
        progress = 0.05;
        notifyListeners();
        final hdData = await _ffmpegPreDenoise(originalAudio!);
        if (hdData != null) inputForDsp = hdData;
      }

      processedAudio = await ProcessorService.process(
        inputForDsp, params,
        premium: premium || isolatorEnabled,
        onProgress: (p) {
          progress = hdModeEnabled ? 0.05 + p * 0.95 : p;
          notifyListeners();
        },
      );

      lastStats = ProcessingStats.compute(
        originalAudio!.samples,
        processedAudio!.samples,
        DateTime.now().difference(startTime),
        usedNeural: ProcessorService.lastUsedNeural,
      );

      await _saveProcessed();
      await _addToHistory();
    } catch (e) {
      errorMessage = 'Processing error: $e';
    }

    isProcessing = false;
    progress     = 0;
    notifyListeners();
  }

  Future<AudioData?> _ffmpegPreDenoise(AudioData audio) async {
    // FFmpeg-kit is not bundled; HD pre-denoise step is skipped.
    return null;
  }

  // ── Vocal / Music split ─────────────────────────────────────────────────

  Future<void> splitStems() async {
    if (originalAudio == null) return;
    isSplitting   = true;
    splitProgress = 0.1;
    errorMessage  = null;
    notifyListeners();

    try {
      final result = await StemSeparatorService.separate(
          originalAudio!.samples, originalAudio!.sampleRate);
      if (result == null) {
        errorMessage = 'Could not separate vocals and music';
      } else {
        vocalsAudio = AudioData.fromSamples(result.vocals, originalAudio!.sampleRate);
        musicAudio  = AudioData.fromSamples(result.instrumental, originalAudio!.sampleRate);
        splitProgress = 0.9;
        notifyListeners();
        await _saveStems();
      }
    } catch (e) {
      errorMessage = 'Split error: $e';
    }

    isSplitting   = false;
    splitProgress = 0;
    notifyListeners();
  }

  Future<void> _saveStems() async {
    if (vocalsAudio == null || musicAudio == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final vPath = '${dir.path}/vocals_${_uuid.v4()}.wav';
    final mPath = '${dir.path}/instrumental_${_uuid.v4()}.wav';
    await File(vPath).writeAsBytes(
        ProcessorService.encodeWav(vocalsAudio!.samples, vocalsAudio!.sampleRate));
    await File(mPath).writeAsBytes(
        ProcessorService.encodeWav(musicAudio!.samples, musicAudio!.sampleRate));
    vocalsPath = vPath;
    musicPath  = mPath;
  }

  Future<void> _saveProcessed() async {
    if (processedAudio == null) return;
    final dir  = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/processed_${_uuid.v4()}.wav';
    await File(path).writeAsBytes(
        ProcessorService.encodeWav(processedAudio!.samples, processedAudio!.sampleRate));
    processedPath = path;
  }

  Future<void> _addToHistory() async {
    if (lastStats == null) return;
    final raw  = originalPath ?? '';
    final name = raw.isNotEmpty ? raw.split('/').last : 'audio_${DateTime.now().millisecondsSinceEpoch}.wav';
    final item = HistoryItem(
      name: name,
      date: DateTime.now(),
      noiseReductionPct: lastStats!.noiseReductionPct,
    );
    recentFiles.insert(0, item);
    if (recentFiles.length > 10) recentFiles.removeLast();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('history', recentFiles.map(HistoryItem.serialize).toList());
  }

  // ── Export ────────────────────────────────────────────────────────────

  Future<void> recordExport() async {
    _exportCount++;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('exportCount', _exportCount);
    notifyListeners();
  }

  Future<void> useDailyBonus() async {
    _lastBonusDate = _todayString();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastBonusDate', _lastBonusDate!);
    notifyListeners();
  }

  Future<String?> exportAsMp3() async {
    // FFmpeg-kit is not bundled; MP3 export is not available.
    return null;
  }

  // ── Playback ──────────────────────────────────────────────────────────

  Future<void> togglePlayOriginal() async {
    await _procPlayer.stop();
    await _vocalsPlayer.stop();
    await _musicPlayer.stop();
    _playingProc = false;
    _playingVocals = false;
    _playingMusic = false;
    if (_playingOrig) {
      await _origPlayer.stop();
      _playingOrig = false;
    } else if (originalPath != null) {
      await _origPlayer.setFilePath(originalPath!);
      await _origPlayer.play();
      _playingOrig = true;
    }
    notifyListeners();
  }

  Future<void> togglePlayProcessed() async {
    await _origPlayer.stop();
    await _vocalsPlayer.stop();
    await _musicPlayer.stop();
    _playingOrig = false;
    _playingVocals = false;
    _playingMusic = false;
    if (_playingProc) {
      await _procPlayer.stop();
      _playingProc = false;
    } else if (processedPath != null) {
      await _procPlayer.setFilePath(processedPath!);
      await _procPlayer.play();
      _playingProc = true;
    }
    notifyListeners();
  }

  Future<void> togglePlayVocals() async {
    await _origPlayer.stop();
    await _procPlayer.stop();
    await _musicPlayer.stop();
    _playingOrig = false;
    _playingProc = false;
    _playingMusic = false;
    if (_playingVocals) {
      await _vocalsPlayer.stop();
      _playingVocals = false;
    } else if (vocalsPath != null) {
      await _vocalsPlayer.setFilePath(vocalsPath!);
      await _vocalsPlayer.play();
      _playingVocals = true;
    }
    notifyListeners();
  }

  Future<void> togglePlayMusic() async {
    await _origPlayer.stop();
    await _procPlayer.stop();
    await _vocalsPlayer.stop();
    _playingOrig = false;
    _playingProc = false;
    _playingVocals = false;
    if (_playingMusic) {
      await _musicPlayer.stop();
      _playingMusic = false;
    } else if (musicPath != null) {
      await _musicPlayer.setFilePath(musicPath!);
      await _musicPlayer.play();
      _playingMusic = true;
    }
    notifyListeners();
  }

  Future<void> stopAllPlayback() async {
    await _origPlayer.stop();
    await _procPlayer.stop();
    await _vocalsPlayer.stop();
    await _musicPlayer.stop();
    _playingOrig = false;
    _playingVocals = false;
    _playingMusic = false;
    _playingProc = false;
    notifyListeners();
  }

  // ── Edit operations ───────────────────────────────────────────────────

  void _pushHistory() {
    if (originalAudio == null) return;
    _history.add(originalAudio!);
    if (_history.length > _maxHistory) _history.removeAt(0);
  }

  void _clearStems() {
    vocalsAudio = null;
    musicAudio  = null;
    vocalsPath  = null;
    musicPath   = null;
  }

  void undo() {
    if (_history.isEmpty) return;
    originalAudio  = _history.removeLast();
    processedAudio = null;
    processedPath  = null;
    _clearStems();
    notifyListeners();
  }

  void restoreOriginal() {
    if (_savedOriginal == null) return;
    _history.clear();
    originalAudio  = _savedOriginal;
    processedAudio = null;
    processedPath  = null;
    _clearStems();
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
    _clearStems();
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
    _clearStems();
    notifyListeners();
  }

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
    _clearStems();
    notifyListeners();
  }

  String? get shareFilePath => processedPath;

  @override
  void dispose() {
    _origPlayer.dispose();
    _procPlayer.dispose();
    _vocalsPlayer.dispose();
    _musicPlayer.dispose();
    _recorder.dispose();
    super.dispose();
  }
}
