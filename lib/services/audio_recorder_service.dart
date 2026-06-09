import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'storage_service.dart';

class AudioRecorderService {
  static AudioRecorderService? _instance;
  static AudioRecorderService get instance => _instance ??= AudioRecorderService._();
  AudioRecorderService._();

  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  String? _currentPath;

  bool get isRecording => _isRecording;
  String? get currentPath => _currentPath;

  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<bool> hasPermission() async {
    return await _recorder.hasPermission();
  }

  Future<bool> startRecording() async {
    if (!await hasPermission()) {
      final granted = await requestPermission();
      if (!granted) return false;
    }

    if (_isRecording) await stopRecording();

    try {
      _currentPath = await StorageService.instance.newRecordingPath();
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 320000,
          sampleRate: 44100,
          numChannels: 2,
        ),
        path: _currentPath!,
      );
      _isRecording = true;
      return true;
    } catch (e) {
      _isRecording = false;
      return false;
    }
  }

  Future<String?> stopRecording() async {
    if (!_isRecording) return null;
    try {
      final path = await _recorder.stop();
      _isRecording = false;
      _currentPath = null;
      return path;
    } catch (e) {
      _isRecording = false;
      return null;
    }
  }

  Future<void> pauseRecording() async {
    if (_isRecording) await _recorder.pause();
  }

  Future<void> resumeRecording() async {
    await _recorder.resume();
  }

  Stream<Amplitude> get amplitudeStream {
    return _recorder.onAmplitudeChanged(const Duration(milliseconds: 80));
  }

  Future<bool> isPaused() async {
    return await _recorder.isPaused();
  }

  void dispose() {
    _recorder.dispose();
  }
}
