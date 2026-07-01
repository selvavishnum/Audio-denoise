import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/audio_params.dart';
import '../providers/audio_provider.dart';
import '../services/processor_service.dart';
import '../theme.dart';
import '../widgets/waveform_painter.dart';

class EditScreen extends StatefulWidget {
  const EditScreen({super.key});

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  double _selStart = 0.0;
  double _selEnd   = 1.0;

  // 0 = Trim, 1 = Join, 2 = Mix
  int _tab = 0;

  AudioData? _joinFile;
  AudioData? _musicFile;
  double     _voiceVol = 1.0;
  double     _musicVol = 0.5;

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AudioProvider>();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 28),
            _header(context, prov),
            const SizedBox(height: 20),
            _tabBar(),
            const SizedBox(height: 20),
            if (_tab == 0) _trimView(context, prov),
            if (_tab == 1) _joinView(context, prov),
            if (_tab == 2) _mixView(context, prov),
            if (prov.originalAudio != null) ...[
              const SizedBox(height: 24),
              _playBar(prov),
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ── Header with Undo / Restart ─────────────────────────────────────────

  Widget _header(BuildContext context, AudioProvider prov) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Editor', style: Theme.of(context).textTheme.displayLarge),
            const SizedBox(height: 4),
            Text('Cut, trim, join and mix audio',
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
      if (prov.originalAudio != null) ...[
        _IconBtn(
          icon: Icons.undo_rounded,
          tooltip: 'Undo',
          enabled: prov.canUndo,
          onTap: () => prov.undo(),
        ),
        const SizedBox(width: 6),
        _IconBtn(
          icon: Icons.restart_alt_rounded,
          tooltip: 'Restart to original',
          enabled: true,
          onTap: () => _confirmRestart(context, prov),
        ),
      ],
    ],
  );

  void _confirmRestart(BuildContext context, AudioProvider prov) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Restart to original?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrim)),
        content: const Text('All edits (trim, join, mix) will be lost.',
            style: TextStyle(fontSize: 13, color: AppColors.textSec)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textDim)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              prov.restoreOriginal();
              setState(() { _selStart = 0; _selEnd = 1; });
            },
            child: const Text('Restart',
                style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  /// Play / replay the current edited audio — works after trim, join or mix.
  Widget _playBar(AudioProvider prov) {
    final playing = prov.playingOriginal;
    return GestureDetector(
      onTap: () => prov.togglePlayOriginal(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(children: [
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              color: AppColors.textPrim, borderRadius: BorderRadius.circular(23),
            ),
            child: Icon(playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                color: AppColors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(playing ? 'Playing…' : 'Play edited audio',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                      color: AppColors.textPrim)),
              const SizedBox(height: 2),
              const Text('Preview your trim / join / mix result',
                  style: TextStyle(fontSize: 11, color: AppColors.textSec)),
            ]),
          ),
          const Icon(Icons.graphic_eq_rounded, size: 18, color: AppColors.textDim),
        ]),
      ),
    );
  }

  Widget _tabBar() => Container(
    height: 42,
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border, width: 0.5),
    ),
    child: Row(children: [
      _TabPill(label: 'Trim & Cut', index: 0, current: _tab, onTap: (i) => setState(() => _tab = i)),
      _TabPill(label: 'Join',       index: 1, current: _tab, onTap: (i) => setState(() => _tab = i)),
      _TabPill(label: 'Mix Music',  index: 2, current: _tab, onTap: (i) => setState(() => _tab = i)),
    ]),
  );

  // ── Trim view ──────────────────────────────────────────────────────────

  Widget _trimView(BuildContext context, AudioProvider prov) {
    final audio = prov.originalAudio;
    if (audio == null) {
      return _emptyState(
        icon:     Icons.content_cut_rounded,
        title:    'No audio loaded',
        subtitle: 'Record in the Record tab or import in the Denoise tab',
      );
    }
    final double dur      = audio.samples.length / audio.sampleRate;
    final double startSec = _selStart * dur;
    final double endSec   = _selEnd   * dur;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _waveformWithSelection(prov),
        const SizedBox(height: 20),
        RangeSlider(
          values:    RangeValues(_selStart, _selEnd),
          min: 0, max: 1, divisions: 200,
          activeColor:   AppColors.textPrim,
          inactiveColor: AppColors.border,
          onChanged: (v) {
            if (v.end - v.start >= 0.02) {
              setState(() { _selStart = v.start; _selEnd = v.end; });
            }
          },
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_fmtSec(startSec),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    color: AppColors.textPrim,
                    fontFeatures: [FontFeature.tabularFigures()])),
            Text('${_fmtSec(endSec - startSec)} selected',
                style: const TextStyle(fontSize: 12, color: AppColors.textSec)),
            Text(_fmtSec(endSec),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    color: AppColors.textPrim,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ],
        ),
        const SizedBox(height: 24),
        Row(children: [
          _ActionChip(
            icon:   Icons.content_cut_rounded,
            label:  'Trim to selection',
            filled: true,
            onTap:  () => _doTrim(context, prov, startSec, endSec),
          ),
          const SizedBox(width: 10),
          _ActionChip(
            icon:   Icons.select_all_rounded,
            label:  'Reset',
            filled: false,
            onTap:  () => setState(() { _selStart = 0; _selEnd = 1; }),
          ),
        ]),
      ],
    );
  }

  Widget _waveformWithSelection(AudioProvider prov) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        CustomPaint(
          painter: WaveformPainter(originalSamples: prov.originalAudio?.samples),
          size: Size.infinite,
        ),
        LayoutBuilder(builder: (_, c) {
          final w = c.maxWidth;
          return Stack(children: [
            Positioned(left: 0, top: 0, bottom: 0, width: w * _selStart,
                child: Container(color: AppColors.white.withValues(alpha: 0.65))),
            Positioned(right: 0, top: 0, bottom: 0, width: w * (1 - _selEnd),
                child: Container(color: AppColors.white.withValues(alpha: 0.65))),
            Positioned(left: w * _selStart - 1.5, top: 0, bottom: 0,
                width: 3, child: Container(color: AppColors.textPrim)),
            Positioned(left: w * _selEnd - 1.5,   top: 0, bottom: 0,
                width: 3, child: Container(color: AppColors.textPrim)),
          ]);
        }),
      ]),
    );
  }

  Future<void> _doTrim(BuildContext context, AudioProvider prov, double start, double end) async {
    await prov.trimAudio(start, end);
    if (!mounted) return;
    setState(() { _selStart = 0; _selEnd = 1; });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Audio trimmed — tap play to preview')));
  }

  // ── Join view ──────────────────────────────────────────────────────────

  Widget _joinView(BuildContext context, AudioProvider prov) {
    final audio = prov.originalAudio;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FileCard(
          title:    'First file',
          subtitle: audio != null
              ? '${(audio.samples.length / audio.sampleRate).toStringAsFixed(1)}s  ·  ${audio.sampleRate} Hz'
              : 'No audio loaded',
          hasFile: audio != null,
          onTap:   null,
        ),
        const SizedBox(height: 10),
        Center(
          child: Container(
            width: 32, height: 32,
            decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
            child: const Icon(Icons.add_rounded, color: AppColors.textDim, size: 18),
          ),
        ),
        const SizedBox(height: 10),
        _FileCard(
          title:    'Second file',
          subtitle: _joinFile != null
              ? '${(_joinFile!.samples.length / _joinFile!.sampleRate).toStringAsFixed(1)}s  ·  ${_joinFile!.sampleRate} Hz'
              : 'Tap to import a WAV file',
          hasFile: _joinFile != null,
          onTap:   _pickJoinFile,
        ),
        const SizedBox(height: 24),
        if (_joinFile != null && audio != null)
          _ActionChip(
            icon:   Icons.merge_rounded,
            label:  'Join files',
            filled: true,
            onTap:  () => _doJoin(context, prov),
          ),
        if (audio == null)
          _emptyState(
            icon:     Icons.merge_type_rounded,
            title:    'No first file',
            subtitle: 'Load audio in the Record or Denoise tab first',
          ),
      ],
    );
  }

  Future<void> _pickJoinFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['wav'],
    );
    if (result?.files.single.path == null) return;
    final bytes = await File(result!.files.single.path!).readAsBytes();
    final data  = ProcessorService.decodeWav(bytes);
    if (data == null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Could not load WAV file')));
      return;
    }
    if (mounted) setState(() => _joinFile = data);
  }

  Future<void> _doJoin(BuildContext context, AudioProvider prov) async {
    if (_joinFile == null) return;
    await prov.joinAudio(_joinFile!);
    if (!mounted) return;
    setState(() => _joinFile = null);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Files joined — tap play to preview')));
  }

  // ── Mix view ───────────────────────────────────────────────────────────

  Widget _mixView(BuildContext context, AudioProvider prov) {
    final audio = prov.originalAudio;
    if (audio == null) {
      return _emptyState(
        icon:     Icons.music_note_rounded,
        title:    'No voice audio loaded',
        subtitle: 'Record or import audio first',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FileCard(
          title:    'Voice audio',
          subtitle: '${(audio.samples.length / audio.sampleRate).toStringAsFixed(1)}s  ·  ${audio.sampleRate} Hz',
          hasFile: true,
          onTap:   null,
        ),
        const SizedBox(height: 16),
        _FileCard(
          title:    'Background music',
          subtitle: _musicFile != null
              ? '${(_musicFile!.samples.length / _musicFile!.sampleRate).toStringAsFixed(1)}s  ·  ${_musicFile!.sampleRate} Hz'
              : 'Tap to pick a music file (WAV, MP3, M4A)',
          hasFile: _musicFile != null,
          onTap:   _pickMusicFile,
        ),
        if (_musicFile != null) ...[
          const SizedBox(height: 24),
          _VolumeRow(
            label: 'Voice',
            icon:  Icons.mic_rounded,
            value: _voiceVol,
            onChanged: (v) => setState(() => _voiceVol = v),
          ),
          const SizedBox(height: 12),
          _VolumeRow(
            label: 'Music',
            icon:  Icons.music_note_rounded,
            value: _musicVol,
            onChanged: (v) => setState(() => _musicVol = v),
          ),
          const SizedBox(height: 24),
          _ActionChip(
            icon:   Icons.merge_type_rounded,
            label:  'Mix & Apply',
            filled: true,
            onTap:  () => _doMix(context, prov),
          ),
        ],
      ],
    );
  }

  Future<void> _pickMusicFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['wav', 'mp3', 'm4a', 'aac', 'flac'],
    );
    final path = result?.files.single.path;
    if (path == null) return;

    AudioData? data;
    if (path.toLowerCase().endsWith('.wav')) {
      final bytes = await File(path).readAsBytes();
      data = ProcessorService.decodeWav(bytes);
    } else {
      // Use provider's internal converter for non-WAV
      data = await context.read<AudioProvider>().convertFileToAudioData(path);
    }

    if (data == null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Could not load music file')));
      return;
    }
    if (mounted) setState(() => _musicFile = data);
  }

  Future<void> _doMix(BuildContext context, AudioProvider prov) async {
    if (_musicFile == null) return;
    await prov.mixWithMusic(_musicFile!, _voiceVol, _musicVol);
    if (!mounted) return;
    setState(() { _musicFile = null; _voiceVol = 1.0; _musicVol = 0.5; });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Music mixed in — tap play to preview')));
  }

  // ── Shared helpers ─────────────────────────────────────────────────────

  Widget _emptyState({required IconData icon, required String title, required String subtitle}) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 40, color: AppColors.textDim),
            const SizedBox(height: 14),
            Text(title,   style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textSec)),
            const SizedBox(height: 6),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textDim), textAlign: TextAlign.center),
          ]),
        ),
      );

  String _fmtSec(double s) {
    final m   = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toStringAsFixed(1).padLeft(4, '0');
    return '$m:$sec';
  }
}

// ── Shared small widgets ───────────────────────────────────────────────────────

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.tooltip, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: Icon(icon, size: 18,
              color: enabled ? AppColors.textPrim : AppColors.textDim),
        ),
      ),
    );
  }
}

class _VolumeRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final double value;
  final ValueChanged<double> onChanged;
  const _VolumeRow({required this.label, required this.icon, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSec),
        const SizedBox(width: 8),
        SizedBox(
          width: 54,
          child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSec)),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor:   AppColors.textPrim,
              inactiveTrackColor: AppColors.border,
              thumbColor:         AppColors.textPrim,
              overlayColor:       const Color(0x1A0A0A0A),
              trackHeight:        2.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(value: value, min: 0, max: 1, onChanged: onChanged),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text('${(value * 100).round()}%',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrim),
              textAlign: TextAlign.end),
        ),
      ],
    );
  }
}

class _TabPill extends StatelessWidget {
  final String label;
  final int index, current;
  final ValueChanged<int> onTap;
  const _TabPill({required this.label, required this.index, required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bool active = index == current;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: active ? AppColors.textPrim : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                  color: active ? AppColors.white : AppColors.textDim)),
        ),
      ),
    );
  }
}

class _FileCard extends StatelessWidget {
  final String title, subtitle;
  final bool hasFile;
  final VoidCallback? onTap;
  const _FileCard({required this.title, required this.subtitle, required this.hasFile, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasFile ? AppColors.textPrim.withValues(alpha: 0.18) : AppColors.border,
            width: 0.5,
          ),
        ),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: hasFile ? AppColors.textPrim : AppColors.border,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.audio_file_rounded, color: AppColors.white, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,   style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrim)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textSec)),
          ])),
          if (onTap != null)
            const Icon(Icons.chevron_right_rounded, color: AppColors.textDim, size: 20),
        ]),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;
  const _ActionChip({required this.icon, required this.label, required this.filled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        decoration: BoxDecoration(
          color: filled ? AppColors.textPrim : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: filled ? null : Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: filled ? AppColors.white : AppColors.textSec),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
              color: filled ? AppColors.white : AppColors.textSec)),
        ]),
      ),
    );
  }
}
