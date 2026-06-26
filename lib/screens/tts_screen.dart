import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../providers/audio_provider.dart';
import '../theme.dart';

// Voice gender selection
enum _VoiceGender { female, male }

class TtsScreen extends StatefulWidget {
  const TtsScreen({super.key});

  @override
  State<TtsScreen> createState() => _TtsScreenState();
}

class _TtsScreenState extends State<TtsScreen> {
  final FlutterTts _tts        = FlutterTts();
  final AudioPlayer _player    = AudioPlayer();
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus       = FocusNode();

  _VoiceGender _gender         = _VoiceGender.female;
  double _speed                = 0.9;   // 0.5 – 2.0
  double _pitch                = 1.0;   // 0.5 – 2.0
  bool _generating             = false;
  bool _playing                = false;
  bool _hasSpeech              = false;
  String? _speechPath;
  String? _error;

  // All available TTS voices fetched from the engine
  List<Map<String, String>> _allVoices = [];
  Map<String, String>? _femaleVoice;
  Map<String, String>? _maleVoice;

  static const _placeholder = 'Type anything here — news headlines, scripts, '
      'podcast intros, or just a sentence — and let the AI voice read it aloud.';

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(_speed);
    await _tts.setPitch(_pitch);
    await _tts.awaitSpeakCompletion(true);

    // Fetch all voices; pick best female + male
    final raw = await _tts.getVoices;
    if (raw != null) {
      _allVoices = (raw as List)
          .map((v) => Map<String, String>.from(v as Map))
          .where((v) {
            final name = (v['name'] ?? '').toLowerCase();
            final lang = (v['locale'] ?? '');
            return lang.startsWith('en');
          })
          .toList();

      _femaleVoice = _pickVoice(female: true);
      _maleVoice   = _pickVoice(female: false);
    }

    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _playing = false);
    });
    _tts.setErrorHandler((msg) {
      if (mounted) setState(() { _playing = false; _error = msg.toString(); });
    });
  }

  Map<String, String>? _pickVoice({required bool female}) {
    // Priority keywords for each gender in Google TTS voice names
    final femaleKeys = ['female', '-sfg-', '-tpc-', '-sfc-', 'wavenet-c',
                        'wavenet-e', 'wavenet-f', 'journey', 'news-n'];
    final maleKeys   = ['male', '-tpd-', '-tpf-', '-tpg-', 'wavenet-a',
                        'wavenet-b', 'wavenet-d', 'wavenet-j'];
    final keys       = female ? femaleKeys : maleKeys;

    for (final key in keys) {
      final match = _allVoices.firstWhere(
        (v) => (v['name'] ?? '').toLowerCase().contains(key),
        orElse: () => {},
      );
      if (match.isNotEmpty) return match;
    }
    // Fallback: first English voice
    return _allVoices.isNotEmpty ? _allVoices.first : null;
  }

  @override
  void dispose() {
    _tts.stop();
    _player.dispose();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _focus.unfocus();

    setState(() { _generating = true; _error = null; _hasSpeech = false; });

    try {
      // Apply gender-specific voice and pitch
      final voice = _gender == _VoiceGender.female ? _femaleVoice : _maleVoice;
      if (voice != null && voice.isNotEmpty) {
        await _tts.setVoice(voice);
      }
      // Pitch nudge for gender when voice names don't distinguish
      final pitchBias = _gender == _VoiceGender.female ? 0.1 : -0.1;
      await _tts.setPitch((_pitch + pitchBias).clamp(0.5, 2.0));
      await _tts.setSpeechRate(_speed);

      // Synthesise to file
      final dir  = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.wav';

      final fileResult = await _tts.synthesizeToFile(text, path);
      final generated  = fileResult == 1 && await File(path).exists();

      if (generated) {
        _speechPath = path;
        setState(() { _generating = false; _hasSpeech = true; });
      } else {
        // Fallback: play through speaker (no file)
        setState(() { _generating = false; _hasSpeech = false;
          _error = 'Could not save to file — using speaker preview instead.'; });
        await _tts.speak(text);
      }
    } catch (e) {
      setState(() { _generating = false; _error = 'TTS error: $e'; });
    }
  }

  Future<void> _togglePlay() async {
    if (_speechPath == null) return;
    if (_playing) {
      await _player.stop();
      setState(() => _playing = false);
    } else {
      setState(() => _playing = true);
      try {
        await _player.setFilePath(_speechPath!);
        await _player.play();
      } catch (_) {}
      setState(() => _playing = false);
    }
  }

  Future<void> _sendToDenoise() async {
    if (_speechPath == null) return;
    final prov = context.read<AudioProvider>();
    await prov.loadFile(_speechPath!);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Voice loaded — open the Denoise tab to process it'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _focus.unfocus(),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 28),
              _header(context),
              const SizedBox(height: 28),
              _genderRow(),
              const SizedBox(height: 20),
              _textInput(),
              const SizedBox(height: 16),
              _sliders(),
              const SizedBox(height: 20),
              _generateBtn(),
              const SizedBox(height: 12),
              if (_error != null) _errorBadge(),
              if (_hasSpeech) ...[
                const SizedBox(height: 16),
                _playbackRow(),
              ],
              const Spacer(),
              if (_hasSpeech) _actionRow(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Text to Voice', style: Theme.of(context).textTheme.displayLarge),
      const SizedBox(height: 4),
      Text('AI neural speech synthesis',
          style: Theme.of(context).textTheme.bodyMedium),
    ],
  );

  Widget _genderRow() => Row(
    children: [
      Expanded(child: _GenderChip(
        label: 'Female',
        icon: Icons.person_2_outlined,
        selected: _gender == _VoiceGender.female,
        onTap: () => setState(() => _gender = _VoiceGender.female),
      )),
      const SizedBox(width: 12),
      Expanded(child: _GenderChip(
        label: 'Male',
        icon: Icons.person_outlined,
        selected: _gender == _VoiceGender.male,
        onTap: () => setState(() => _gender = _VoiceGender.male),
      )),
    ],
  );

  Widget _textInput() => Container(
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border, width: 0.5),
    ),
    child: TextField(
      controller: _ctrl,
      focusNode: _focus,
      maxLines: 7,
      minLines: 5,
      style: const TextStyle(fontSize: 14, color: AppColors.textPrim, height: 1.55),
      decoration: InputDecoration(
        hintText: _placeholder,
        hintStyle: const TextStyle(fontSize: 13, color: AppColors.textDim, height: 1.55),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.all(16),
      ),
    ),
  );

  Widget _sliders() => Column(
    children: [
      _Slider(
        label: 'Speed',
        value: _speed,
        min: 0.5, max: 2.0,
        onChanged: (v) => setState(() => _speed = v),
        leftLabel: 'Slow',
        rightLabel: 'Fast',
      ),
      const SizedBox(height: 12),
      _Slider(
        label: 'Pitch',
        value: _pitch,
        min: 0.5, max: 2.0,
        onChanged: (v) => setState(() => _pitch = v),
        leftLabel: 'Deep',
        rightLabel: 'High',
      ),
    ],
  );

  Widget _generateBtn() => GestureDetector(
    onTap: _generating ? null : _generate,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: _generating ? AppColors.border : AppColors.textPrim,
        borderRadius: BorderRadius.circular(16),
      ),
      child: _generating
          ? const Center(
              child: SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.white),
              ),
            )
          : const Text(
              'Generate Voice',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.white),
            ),
    ),
  );

  Widget _errorBadge() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.danger.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.danger.withValues(alpha: 0.25), width: 0.5),
    ),
    child: Text(_error!,
        style: const TextStyle(fontSize: 12, color: AppColors.danger)),
  );

  Widget _playbackRow() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border, width: 0.5),
    ),
    child: Row(children: [
      GestureDetector(
        onTap: _togglePlay,
        child: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: AppColors.textPrim,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Icon(
            _playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
            color: AppColors.white, size: 22,
          ),
        ),
      ),
      const SizedBox(width: 14),
      const Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Preview',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                  color: AppColors.textPrim)),
          SizedBox(height: 2),
          Text('Tap play to hear your generated voice',
              style: TextStyle(fontSize: 11, color: AppColors.textSec)),
        ]),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text('Ready',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                color: AppColors.success)),
      ),
    ]),
  );

  Widget _actionRow() => Row(children: [
    Expanded(
      child: _ActionBtn(
        label: 'Denoise Voice',
        icon: Icons.graphic_eq_rounded,
        filled: true,
        onTap: _sendToDenoise,
      ),
    ),
    const SizedBox(width: 12),
    Expanded(
      child: _ActionBtn(
        label: 'Regenerate',
        icon: Icons.refresh_rounded,
        filled: false,
        onTap: _generate,
      ),
    ),
  ]);
}

// ── Voice gender chip ──────────────────────────────────────────────────────────

class _GenderChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _GenderChip({
    required this.label, required this.icon,
    required this.selected, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? AppColors.textPrim : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.textPrim : AppColors.border,
            width: 0.5,
          ),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 18,
              color: selected ? AppColors.white : AppColors.textSec),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600,
                color: selected ? AppColors.white : AppColors.textSec,
              )),
        ]),
      ),
    );
  }
}

// ── Slider row ─────────────────────────────────────────────────────────────────

class _Slider extends StatelessWidget {
  final String label, leftLabel, rightLabel;
  final double value, min, max;
  final ValueChanged<double> onChanged;

  const _Slider({
    required this.label, required this.value,
    required this.min, required this.max,
    required this.onChanged,
    required this.leftLabel, required this.rightLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                color: AppColors.textSec)),
        const Spacer(),
        Text(value.toStringAsFixed(1),
            style: const TextStyle(fontSize: 12, color: AppColors.textDim)),
      ]),
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: AppColors.textPrim,
          inactiveTrackColor: AppColors.border,
          thumbColor: AppColors.textPrim,
          overlayColor: AppColors.textPrim.withValues(alpha: 0.12),
          trackHeight: 2,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        ),
        child: Slider(value: value, min: min, max: max, onChanged: onChanged),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(children: [
          Text(leftLabel,
              style: const TextStyle(fontSize: 10, color: AppColors.textDim)),
          const Spacer(),
          Text(rightLabel,
              style: const TextStyle(fontSize: 10, color: AppColors.textDim)),
        ]),
      ),
    ]);
  }
}

// ── Action button ──────────────────────────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.label, required this.icon,
    required this.filled, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: filled ? AppColors.textPrim : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: filled ? null : Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 16,
              color: filled ? AppColors.white : AppColors.textSec),
          const SizedBox(width: 7),
          Text(label,
              style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: filled ? AppColors.white : AppColors.textSec,
              )),
        ]),
      ),
    );
  }
}

