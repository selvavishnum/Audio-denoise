import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../models/audio_params.dart';
import '../services/processor_service.dart';

class AudioProvider extends ChangeNotifier {
  AudioData? originalAudio;
  AudioData? processedAudio;
  AudioParams params = AudioParams.presets[VoicePreset.natural]!;
  bool isRecording = false;
  bool isProcessing = false;
  double progress = 0.0;
  String? errorMessage;
  String? originalPath;
  String? processedPath;

  // Playback
  final _origPlayer = AudioPlayer();
  final _procPlayer = AudioPlayer();
  bool _playingOrig = false;
  bool _playingProc = false;
  bool get playingOriginal => _playingOrig;
  bool get playingProcessed => _playingProc;

  // Recording
  final _recorder = AudioRecorder();

  final _uuid = const Uuid();

  // ── Preset ──────────────────────────────────────────────────────────

  void applyPreset(VoicePreset preset) {
    params = AudioParams.presets[preset]!.copyWith(mode: params.mode);
    notifyListeners();
  }

  void updateParams(AudioParams p) {
    params = p;
    notifyListeners();
  }

  // ── Import ───────────────────────────────────────────────────────────

  Future<void> loadFile(String path) async {
    errorMessage = null;
    processedAudio = null;
    processedPath = null;
    try {
      final bytes = await File(path).readAsBytes();
      AudioData? data;

      if (path.toLowerCase().endsWith('.wav')) {
        data = ProcessorService.decodeWav(bytes);
      } else {
        // For MP3/AAC: use FFmpeg to convert to WAV first
        data = await _convertToWavAndDecode(path);
      }

      if (data == null) {
        errorMessage = 'Could not decode audio file';
      } else {
        originalAudio = data;
        originalPath = path;
      }
    } catch (e) {
      errorMessage = 'Error loading file: $e';
    }
    notifyListeners();
  }

  Future<AudioData?> _convertToWavAndDecode(String inputPath) async {
    // Non-WAV decoding is not supported; WAV files are handled directly.
    return null;
  }

  // ── Recording ────────────────────────────────────────────────────────

  Future<bool> startRecording() async {
    if (!await _recorder.hasPermission()) return false;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/rec_${_uuid.v4()}.wav';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 44100,
          numChannels: 1,
        ),
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
    progress = 0;
    errorMessage = null;
    notifyListeners();

    try {
      processedAudio = await ProcessorService.process(
        originalAudio!,
        params,
        onProgress: (p) {
          progress = p;
          notifyListeners();
        },
      );
      await _saveProcessed();
    } catch (e) {
      errorMessage = 'Processing error: $e';
    }

    isProcessing = false;
    progress = 0;
    notifyListeners();
  }

  Future<void> _saveProcessed() async {
    if (processedAudio == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/processed_${_uuid.v4()}.wav';
    final wavBytes = ProcessorService.encodeWav(
        processedAudio!.samples, processedAudio!.sampleRate);
    await File(path).writeAsBytes(wavBytes);
    processedPath = path;
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
      _origPlayer.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
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
      _procPlayer.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
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

  void trimAudio(double startSec, double endSec) {
    final audio = originalAudio;
    if (audio == null) return;
    final sr    = audio.sampleRate;
    final start = (startSec * sr).round().clamp(0, audio.samples.length);
    final end   = (endSec   * sr).round().clamp(start, audio.samples.length);
    final trimmed = Float32List.fromList(audio.samples.sublist(start, end));
    originalAudio  = AudioData.fromSamples(trimmed, sr);
    processedAudio = null;
    processedPath  = null;
    notifyListeners();
  }

  void joinAudio(AudioData second) {
    final audio = originalAudio;
    if (audio == null) return;
    final combined = Float32List(audio.samples.length + second.samples.length);
    combined.setAll(0, audio.samples);
    combined.setAll(audio.samples.length, second.samples);
    originalAudio  = AudioData.fromSamples(combined, audio.sampleRate);
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

