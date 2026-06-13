import 'dart:io';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// ElevenLabs Audio Isolation cloud service.
///
/// API: POST https://api.elevenlabs.io/v1/audio-isolation
///   Header: xi-api-key: <YOUR_KEY>
///   Body: multipart/form-data  field "audio" = audio file bytes
///   Response: cleaned audio file bytes (same format as input)
///
/// Free tier: 10,000 characters/month. Audio isolation uses credits.
/// Get a free key at https://elevenlabs.io
class ElevenLabsService {
  static const _keyPref    = 'eleven_labs_api_key';
  static const _baseUrl    = 'api.elevenlabs.io';
  static const _path       = '/v1/audio-isolation';
  static const _timeoutSec = 120;

  // ── API key persistence ───────────────────────────────────────────────────

  static Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyPref);
  }

  static Future<void> saveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    if (key.trim().isEmpty) {
      await prefs.remove(_keyPref);
    } else {
      await prefs.setString(_keyPref, key.trim());
    }
  }

  static Future<void> clearApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyPref);
  }

  // ── Audio isolation ───────────────────────────────────────────────────────

  /// Send [audioBytes] to ElevenLabs Audio Isolation API.
  ///
  /// [mimeType]: e.g. 'audio/wav', 'audio/mpeg', 'audio/mp4'
  /// [apiKey]: if null, loads from SharedPreferences.
  ///
  /// Returns isolated audio bytes, or null on failure.
  /// Throws [ElevenLabsException] with a human-readable message on API errors.
  static Future<Uint8List?> isolateAudio(
    Uint8List audioBytes,
    String mimeType, {
    String? apiKey,
    void Function(String status)? onStatus,
  }) async {
    final key = apiKey ?? await getApiKey();
    if (key == null || key.isEmpty) {
      throw const ElevenLabsException('No ElevenLabs API key configured.');
    }

    onStatus?.call('Connecting to ElevenLabs…');

    final boundary = 'nc_${_uuid.v4().replaceAll('-', '')}';
    final client   = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);

    try {
      final request = await client
          .postUrl(Uri.https(_baseUrl, _path))
          .timeout(const Duration(seconds: _timeoutSec));

      request.headers
        ..set('xi-api-key', key)
        ..set('Accept', 'audio/*')
        ..set(HttpHeaders.contentTypeHeader,
              'multipart/form-data; boundary=$boundary');

      // Build multipart body
      final part   = _buildMultipart(boundary, audioBytes, mimeType);
      request.contentLength = part.length;
      request.add(part);

      onStatus?.call('Uploading audio (${(audioBytes.length / 1024).round()} KB)…');
      final response = await request.close()
          .timeout(const Duration(seconds: _timeoutSec));

      if (response.statusCode == 401) {
        throw const ElevenLabsException(
            'Invalid API key. Check your ElevenLabs key.');
      }
      if (response.statusCode == 422) {
        throw const ElevenLabsException(
            'Unsupported audio format. Try WAV or MP3.');
      }
      if (response.statusCode == 429) {
        throw const ElevenLabsException(
            'ElevenLabs quota exceeded. Upgrade your plan or try later.');
      }
      if (response.statusCode != 200) {
        throw ElevenLabsException(
            'ElevenLabs error ${response.statusCode}.');
      }

      onStatus?.call('Processing with ElevenLabs AI…');

      final chunks = <int>[];
      await for (final chunk in response) {
        chunks.addAll(chunk);
      }

      onStatus?.call('Done — audio isolated');
      return Uint8List.fromList(chunks);
    } on ElevenLabsException {
      rethrow;
    } on SocketException {
      throw const ElevenLabsException('No internet connection.');
    } on HttpException catch (e) {
      throw ElevenLabsException('Network error: ${e.message}');
    } catch (e) {
      throw ElevenLabsException('Unexpected error: $e');
    } finally {
      client.close();
    }
  }

  // ── Internal helpers ──────────────────────────────────────────────────────

  static List<int> _buildMultipart(
      String boundary, Uint8List data, String mimeType) {
    final buf = <int>[];
    void add(String s) => buf.addAll(s.codeUnits);
    add('--$boundary\r\n');
    add('Content-Disposition: form-data; name="audio"; filename="audio.wav"\r\n');
    add('Content-Type: $mimeType\r\n\r\n');
    buf.addAll(data);
    add('\r\n--$boundary--\r\n');
    return buf;
  }
}

class ElevenLabsException implements Exception {
  final String message;
  const ElevenLabsException(this.message);
  @override
  String toString() => message;
}
