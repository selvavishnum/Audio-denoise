import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  // Anonymous users get a small local-only allowance. Signing in unlocks a
  // much larger allowance tracked server-side in Firestore, keyed by uid —
  // that's what makes it survive a reinstall or switching to a different
  // Gmail account (a fresh local install can never see a fresh Firestore
  // doc for an account that's already used its allowance).
  static const int anonFreeLimit     = 5;
  static const int loggedInFreeLimit = 25;
  static const int freeExportLimit   = anonFreeLimit + loggedInFreeLimit; // 30, display only

  int _anonExportCount     = 0;
  int _loggedInExportCount = 0;
  bool _isLoggedIn = false;
  String? _uid;

  bool get isLoggedInForUsage => _isLoggedIn;

  /// Current tier's usage count (anonymous or logged-in, whichever is active).
  int get exportCount => _isLoggedIn ? _loggedInExportCount : _anonExportCount;

  int get freeExportsLeft => _isLoggedIn
      ? max(0, loggedInFreeLimit - _loggedInExportCount)
      : max(0, anonFreeLimit - _anonExportCount);

  bool get hasReachedFreeLimit => _isLoggedIn
      ? _loggedInExportCount >= loggedInFreeLimit
      : _anonExportCount >= anonFreeLimit;

  /// True once the anonymous allowance is used up and the user still isn't
  /// signed in — the save-gate should offer "sign in for 25 more free"
  /// here instead of "upgrade to Pro".
  bool get needsLoginForMoreFree => !_isLoggedIn && _anonExportCount >= anonFreeLimit;

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
    // Migrate the old flat 30-count key (pre-tiered-limit installs) into the
    // new anonymous-tier key exactly once — preserves already-used history
    // instead of handing out a free reset.
    _anonExportCount = prefs.getInt('anonExportCount') ?? prefs.getInt('exportCount') ?? 0;
    hdModeEnabled  = prefs.getBool('hdMode') ?? false;
    _lastBonusDate = prefs.getString('lastBonusDate');
    isolatorEnabled = prefs.getBool('isolatorEnabled') ?? false;
    _loadHistory(prefs);

    // Pick up an already-signed-in Firebase session (e.g. app restart while
    // logged in) so the logged-in 25-free tier applies immediately, not just
    // after the next explicit sign-in action.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await loginUser(uid);
    } else {
      notifyListeners();
    }
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

  /// Clear all loaded/processed audio so the Studio screen returns to its
  /// empty Record / Upload state (used by the "New Record" action).
  Future<void> resetForNew() async {
    await stopAllPlayback();
    originalAudio  = null;
    _savedOriginal = null;
    originalPath   = null;
    processedAudio = null;
    processedPath  = null;
    lastStats      = null;
    vocalsAudio    = null;
    musicAudio     = null;
    vocalsPath     = null;
    musicPath      = null;
    errorMessage   = null;
    _history.clear();
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
    if (_isLoggedIn && _uid != null) {
      await _recordLoggedInExport(_uid!);
    } else {
      _anonExportCount++;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('anonExportCount', _anonExportCount);
      notifyListeners();
    }
  }

  Future<void> _recordLoggedInExport(String uid) async {
    // Optimistic local bump first so the UI updates instantly; Firestore is
    // the source of truth and gets reconciled on the next loginUser() call.
    _loggedInExportCount++;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('loggedInExportCountCache', _loggedInExportCount);
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'exportCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Offline / Firestore unavailable — keep the optimistic local value.
      // It reconciles against the server next time loginUser() succeeds.
    }
  }

  /// Call right after a successful Google Sign-In (and on app start if a
  /// session is already active) so the 25-free logged-in allowance —
  /// tracked server-side in Firestore, keyed by uid — takes over from the
  /// local anonymous counter. This is what stops "used up the free tier,
  /// sign into a different Gmail, get a fresh allowance": the allowance
  /// lives on the account, not on the device.
  Future<void> loginUser(String uid) async {
    _uid = uid;
    _isLoggedIn = true;
    final prefs = await SharedPreferences.getInstance();
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      _loggedInExportCount = (doc.data()?['exportCount'] as num?)?.toInt() ?? 0;
      await prefs.setInt('loggedInExportCountCache', _loggedInExportCount);
    } catch (_) {
      // Offline — fall back to the last-synced cached value rather than
      // resetting to 0, so a momentary network blip can't look like a
      // fresh allowance.
      _loggedInExportCount = prefs.getInt('loggedInExportCountCache') ?? 0;
    }
    notifyListeners();
  }

  void logoutUser() {
    _isLoggedIn = false;
    _uid = null;
    _loggedInExportCount = 0;
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

  /// Persist the current in-memory [originalAudio] to a WAV file and point
  /// [originalPath] at it, so playback (togglePlayOriginal) reflects edits.
  Future<void> _persistOriginal() async {
    final audio = originalAudio;
    if (audio == null) { originalPath = null; return; }
    try {
      await stopAllPlayback();
      final dir  = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/edit_${_uuid.v4()}.wav';
      await File(path).writeAsBytes(
          ProcessorService.encodeWav(audio.samples, audio.sampleRate));
      originalPath = path;
    } catch (_) {}
    notifyListeners();
  }

  Future<void> undo() async {
    if (_history.isEmpty) return;
    originalAudio  = _history.removeLast();
    processedAudio = null;
    processedPath  = null;
    _clearStems();
    notifyListeners();
    await _persistOriginal();
  }

  Future<void> restoreOriginal() async {
    if (_savedOriginal == null) return;
    _history.clear();
    originalAudio  = _savedOriginal;
    processedAudio = null;
    processedPath  = null;
    _clearStems();
    notifyListeners();
    await _persistOriginal();
  }

  Future<void> trimAudio(double startSec, double endSec) async {
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
    await _persistOriginal();
  }

  Future<void> joinAudio(AudioData second) async {
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
    await _persistOriginal();
  }

  Future<void> mixWithMusic(AudioData music, double voiceVol, double musicVol) async {
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
    await _persistOriginal();
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
