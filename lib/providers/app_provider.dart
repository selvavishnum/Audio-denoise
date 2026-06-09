import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../core/constants/app_constants.dart';
import '../models/audio_project.dart';
import '../models/denoise_settings.dart';
import '../services/audio_recorder_service.dart';
import '../services/denoise_service.dart';
import '../services/storage_service.dart';
import '../services/usage_service.dart';

// ── Recorder Provider ──────────────────────────────────────────────────────

enum RecordingState { idle, recording, paused, stopping }

class RecorderProvider extends ChangeNotifier {
  RecordingState _state = RecordingState.idle;
  Duration _elapsed = Duration.zero;
  double _amplitude = 0.0;
  String? _lastRecordedPath;

  RecordingState get state => _state;
  Duration get elapsed => _elapsed;
  double get amplitude => _amplitude;
  String? get lastRecordedPath => _lastRecordedPath;
  bool get isRecording => _state == RecordingState.recording;

  late Stopwatch _stopwatch;
  late Stream<int> _ticker;

  Future<bool> startRecording() async {
    final ok = await AudioRecorderService.instance.startRecording();
    if (!ok) return false;

    _state = RecordingState.recording;
    _stopwatch = Stopwatch()..start();
    _startAmplitudeStream();
    _startTimer();
    notifyListeners();
    return true;
  }

  void _startTimer() {
    Stream.periodic(const Duration(milliseconds: 100)).listen((_) {
      if (_state == RecordingState.recording) {
        _elapsed = _stopwatch.elapsed;
        notifyListeners();
      }
    });
  }

  void _startAmplitudeStream() {
    AudioRecorderService.instance.amplitudeStream.listen((amp) {
      // amp.current is in dBFS (negative), convert to 0-1 range
      _amplitude = ((amp.current + 60) / 60).clamp(0.0, 1.0);
      notifyListeners();
    });
  }

  Future<void> pauseRecording() async {
    await AudioRecorderService.instance.pauseRecording();
    _stopwatch.stop();
    _state = RecordingState.paused;
    notifyListeners();
  }

  Future<void> resumeRecording() async {
    await AudioRecorderService.instance.resumeRecording();
    _stopwatch.start();
    _state = RecordingState.recording;
    notifyListeners();
  }

  Future<String?> stopRecording() async {
    _state = RecordingState.stopping;
    notifyListeners();
    final path = await AudioRecorderService.instance.stopRecording();
    _lastRecordedPath = path;
    _state = RecordingState.idle;
    _elapsed = Duration.zero;
    _stopwatch.reset();
    notifyListeners();
    return path;
  }

  void reset() {
    _state = RecordingState.idle;
    _elapsed = Duration.zero;
    _amplitude = 0.0;
    _lastRecordedPath = null;
    notifyListeners();
  }
}

// ── Denoiser Provider ──────────────────────────────────────────────────────

enum DenoiserState { idle, processing, done, error }

class DenoiserProvider extends ChangeNotifier {
  DenoiserState _state = DenoiserState.idle;
  DenoiseSettings _settings = const DenoiseSettings();
  String? _inputPath;
  String? _outputPath;
  double _progress = 0.0;
  double _noiseReductionDb = 0.0;
  String? _errorMessage;
  bool _showStudioControls = false;
  String _selectedMode = AppConstants.modeAiQuick;

  // Playback
  final AudioPlayer _originalPlayer = AudioPlayer();
  final AudioPlayer _cleanPlayer = AudioPlayer();
  bool _isPlayingOriginal = false;
  bool _isPlayingClean = false;

  DenoiserState get state => _state;
  DenoiseSettings get settings => _settings;
  String? get inputPath => _inputPath;
  String? get outputPath => _outputPath;
  double get progress => _progress;
  double get noiseReductionDb => _noiseReductionDb;
  String? get errorMessage => _errorMessage;
  bool get showStudioControls => _showStudioControls;
  String get selectedMode => _selectedMode;
  bool get isPlayingOriginal => _isPlayingOriginal;
  bool get isPlayingClean => _isPlayingClean;
  AudioPlayer get originalPlayer => _originalPlayer;
  AudioPlayer get cleanPlayer => _cleanPlayer;

  void loadAudio(String path) {
    _inputPath = path;
    _outputPath = null;
    _state = DenoiserState.idle;
    _progress = 0.0;
    notifyListeners();
  }

  void setMode(String mode) {
    _selectedMode = mode;
    _settings = DenoiseSettings.forMode(mode);
    notifyListeners();
  }

  void toggleStudioControls() {
    _showStudioControls = !_showStudioControls;
    notifyListeners();
  }

  void updateSettings(DenoiseSettings settings) {
    _settings = settings;
    notifyListeners();
  }

  Future<DenoiseResult?> process() async {
    if (_inputPath == null) return null;

    if (!await UsageService.instance.canDenoise()) return null;

    _state = DenoiserState.processing;
    _progress = 0.0;
    notifyListeners();

    final result = await DenoiseService.instance.denoise(
      inputPath: _inputPath!,
      settings: _settings,
      onProgress: (p) {
        _progress = p;
        notifyListeners();
      },
    );

    if (result.status == DenoiseStatus.success) {
      _outputPath = result.outputPath;
      _noiseReductionDb = result.noiseReductionDb;
      _state = DenoiserState.done;
      await UsageService.instance.incrementDenoiseCount();
    } else {
      _errorMessage = result.error;
      _state = DenoiserState.error;
    }

    notifyListeners();
    return result;
  }

  Future<void> playOriginal() async {
    await _cleanPlayer.stop();
    _isPlayingClean = false;

    if (_isPlayingOriginal) {
      await _originalPlayer.stop();
      _isPlayingOriginal = false;
    } else {
      await _originalPlayer.setFilePath(_inputPath!);
      await _originalPlayer.play();
      _isPlayingOriginal = true;

      _originalPlayer.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          _isPlayingOriginal = false;
          notifyListeners();
        }
      });
    }
    notifyListeners();
  }

  Future<void> playClean() async {
    if (_outputPath == null) return;
    await _originalPlayer.stop();
    _isPlayingOriginal = false;

    if (_isPlayingClean) {
      await _cleanPlayer.stop();
      _isPlayingClean = false;
    } else {
      await _cleanPlayer.setFilePath(_outputPath!);
      await _cleanPlayer.play();
      _isPlayingClean = true;

      _cleanPlayer.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          _isPlayingClean = false;
          notifyListeners();
        }
      });
    }
    notifyListeners();
  }

  Future<void> stopAllPlayback() async {
    await _originalPlayer.stop();
    await _cleanPlayer.stop();
    _isPlayingOriginal = false;
    _isPlayingClean = false;
    notifyListeners();
  }

  void reset() {
    stopAllPlayback();
    _state = DenoiserState.idle;
    _inputPath = null;
    _outputPath = null;
    _progress = 0.0;
    _noiseReductionDb = 0.0;
    _errorMessage = null;
    _showStudioControls = false;
    _selectedMode = AppConstants.modeAiQuick;
    _settings = const DenoiseSettings();
    notifyListeners();
  }

  @override
  void dispose() {
    _originalPlayer.dispose();
    _cleanPlayer.dispose();
    super.dispose();
  }
}

// ── Library Provider ────────────────────────────────────────────────────────

class LibraryProvider extends ChangeNotifier {
  List<AudioProject> _projects = [];
  final AudioPlayer _player = AudioPlayer();
  String? _currentlyPlayingId;
  bool _isGridView = true;

  List<AudioProject> get projects => _projects;
  AudioPlayer get player => _player;
  String? get currentlyPlayingId => _currentlyPlayingId;
  bool get isGridView => _isGridView;

  void toggleView() {
    _isGridView = !_isGridView;
    notifyListeners();
  }

  Future<void> loadProjects() async {
    _projects = StorageService.instance.getAllProjects();
    notifyListeners();
  }

  Future<void> deleteProject(String id) async {
    await StorageService.instance.deleteProject(id);
    if (_currentlyPlayingId == id) {
      await _player.stop();
      _currentlyPlayingId = null;
    }
    await loadProjects();
  }

  Future<void> togglePlay(AudioProject project) async {
    final playPath = project.processedPath ?? project.originalPath;
    if (!await File(playPath).exists()) return;

    if (_currentlyPlayingId == project.id) {
      await _player.stop();
      _currentlyPlayingId = null;
    } else {
      await _player.setFilePath(playPath);
      await _player.play();
      _currentlyPlayingId = project.id;
      _player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          _currentlyPlayingId = null;
          notifyListeners();
        }
      });
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}

// ── Session Provider ─────────────────────────────────────────────────────────

class SessionProvider extends ChangeNotifier {
  int _remainingUses = 0;
  bool _isUnlimited = false;
  bool _isLoading = true;

  int get remainingUses => _remainingUses;
  bool get isUnlimited => _isUnlimited;
  bool get isLoading => _isLoading;
  double get usagePercent {
    if (_isUnlimited) return 0.0;
    return 1.0 - (_remainingUses / AppConstants.maxFreeDenoises);
  }

  Future<void> refresh() async {
    _isLoading = true;
    notifyListeners();
    _isUnlimited = await UsageService.instance.isUnlimited();
    _remainingUses = await UsageService.instance.getRemainingUses();
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> activateCode(String code) async {
    final success = await UsageService.instance.activatePromoCode(code);
    if (success) await refresh();
    return success;
  }
}
