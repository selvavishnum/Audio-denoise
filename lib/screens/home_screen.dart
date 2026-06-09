import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/audio_params.dart';
import '../providers/audio_provider.dart';
import '../theme.dart';
import '../widgets/param_slider.dart';
import '../widgets/preset_card.dart';
import '../widgets/waveform_painter.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  bool _showProcessed = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  // ── Import ───────────────────────────────────────────────────────────

  Future<void> _importFile(AudioProvider prov) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;
    _showProcessed = false;
    await prov.loadFile(path);
  }

  // ── Record ───────────────────────────────────────────────────────────

  Future<void> _toggleRecord(AudioProvider prov) async {
    if (prov.isRecording) {
      await prov.stopRecording();
      _showProcessed = false;
    } else {
      final ok = await prov.startRecording();
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission required')),
        );
      }
    }
  }

  // ── Process ──────────────────────────────────────────────────────────

  Future<void> _process(AudioProvider prov) async {
    await prov.processAudio();
    if (prov.processedAudio != null) {
      setState(() => _showProcessed = true);
    }
    if (prov.errorMessage != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(prov.errorMessage!)));
    }
  }

  // ── Share ────────────────────────────────────────────────────────────

  Future<void> _share(AudioProvider prov) async {
    final path = prov.shareFilePath;
    if (path == null) return;
    await Share.shareXFiles([XFile(path)], text: 'NoiseClear processed audio');
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AudioProvider>(
      builder: (context, prov, _) {
        return Scaffold(
          backgroundColor: AppColors.bg,
          body: SafeArea(
            child: Column(
              children: [
                _buildHeader(prov),
                _buildModeSelector(prov),
                Expanded(
                  child: Column(
                    children: [
                      // Top half: input/output
                      Expanded(flex: 5, child: _buildIOPanel(prov)),
                      // Bottom half: controls
                      Expanded(flex: 6, child: _buildControls(prov)),
                    ],
                  ),
                ),
                _buildProcessButton(prov),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Header ────────────────────────────────────────────────────────────

  Widget _buildHeader(AudioProvider prov) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          // Logo
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.violet, AppColors.pink],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.noise_control_off,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('NoiseClear',
                  style: GoogleFonts.inter(
                    color: AppColors.textPrim,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  )),
              Text('Studio DSP Engine',
                  style: GoogleFonts.inter(
                    color: AppColors.textDim,
                    fontSize: 11,
                  )),
            ],
          ),
          const Spacer(),
          // Recording indicator
          if (prov.isRecording)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEF4444),
                      shape: BoxShape.circle,
                    ),
                  ).animate(onPlay: (c) => c.repeat())
                      .fadeIn(duration: 600.ms)
                      .then()
                      .fadeOut(duration: 600.ms),
                  const SizedBox(width: 5),
                  Text('REC',
                      style: GoogleFonts.inter(
                        color: const Color(0xFFEF4444),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      )),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Mode Selector ─────────────────────────────────────────────────────

  Widget _buildModeSelector(AudioProvider prov) {
    final modes = [
      (ProcessingMode.denoise, 'Denoise Only', Icons.noise_control_off),
      (ProcessingMode.voiceIsolate, 'Voice Isolate', Icons.record_voice_over),
      (ProcessingMode.extractMusic, 'Extract Music', Icons.music_note),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: modes.map((m) {
          final isActive = prov.params.mode == m.$1;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: GestureDetector(
                onTap: () => prov.updateParams(prov.params.copyWith(mode: m.$1)),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppColors.violet.withOpacity(0.18)
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isActive ? AppColors.violet.withOpacity(0.6) : AppColors.border,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(m.$3,
                          color: isActive ? AppColors.violet : AppColors.textDim,
                          size: 16),
                      const SizedBox(height: 2),
                      Text(m.$2,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            color: isActive ? AppColors.violet : AppColors.textDim,
                            fontSize: 9,
                            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                          )),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── I/O Panel ─────────────────────────────────────────────────────────

  Widget _buildIOPanel(AudioProvider prov) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        children: [
          // Action buttons row
          Row(
            children: [
              Expanded(child: _ActionButton(
                label: prov.isRecording ? 'Stop' : 'Record',
                icon: prov.isRecording ? Icons.stop : Icons.mic,
                color: prov.isRecording
                    ? const Color(0xFFEF4444)
                    : AppColors.violet,
                onTap: () => _toggleRecord(prov),
              )),
              const SizedBox(width: 8),
              Expanded(child: _ActionButton(
                label: 'Import',
                icon: Icons.file_upload_outlined,
                color: AppColors.cyan,
                onTap: () => _importFile(prov),
              )),
              const SizedBox(width: 8),
              Expanded(child: _ActionButton(
                label: 'Export',
                icon: Icons.ios_share,
                color: AppColors.green,
                onTap: prov.processedAudio != null ? () => _share(prov) : null,
              )),
            ],
          ),
          const SizedBox(height: 8),
          // Live amplitude bar
          if (prov.isRecording)
            StreamBuilder(
              stream: prov.amplitudeStream,
              builder: (_, snap) {
                final amp = snap.hasData
                    ? ((snap.data!.current + 60) / 60).clamp(0.0, 1.0)
                    : 0.0;
                return Column(
                  children: [
                    LiveAmplitudeBar(amplitude: amp),
                    const SizedBox(height: 6),
                  ],
                );
              },
            ),
          // Waveform
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (prov.processedAudio != null) {
                  setState(() => _showProcessed = !_showProcessed);
                }
              },
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      SizedBox.expand(
                        child: CustomPaint(
                          painter: WaveformPainter(
                            originalSamples: prov.originalAudio?.samples,
                            processedSamples: prov.processedAudio?.samples,
                            showProcessed: _showProcessed,
                          ),
                        ),
                      ),
                      if (prov.originalAudio == null)
                        Center(
                          child: Text('Import audio or record',
                              style: GoogleFonts.inter(
                                color: AppColors.textDim,
                                fontSize: 12,
                              )),
                        ),
                      if (prov.processedAudio != null)
                        Positioned(
                          top: 6,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: (_showProcessed ? AppColors.green : AppColors.violet)
                                  .withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: (_showProcessed ? AppColors.green : AppColors.violet)
                                    .withOpacity(0.4),
                              ),
                            ),
                            child: Text(
                              _showProcessed ? 'CLEAN' : 'ORIGINAL',
                              style: GoogleFonts.inter(
                                color: _showProcessed ? AppColors.green : AppColors.violet,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Progress bar
          if (prov.isProcessing)
            Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: prov.progress > 0 ? prov.progress : null,
                    backgroundColor: AppColors.border,
                    valueColor: const AlwaysStoppedAnimation(AppColors.violet),
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  prov.progress > 0
                      ? '${(prov.progress * 100).round()}% — Processing...'
                      : 'Initializing...',
                  style: GoogleFonts.inter(
                    color: AppColors.textDim, fontSize: 11),
                ),
              ],
            ),
          // Playback row
          if (prov.originalAudio != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Expanded(child: _PlayButton(
                    label: 'Original',
                    isPlaying: prov.playingOriginal,
                    color: AppColors.amber,
                    onTap: prov.togglePlayOriginal,
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: _PlayButton(
                    label: 'Processed',
                    isPlaying: prov.playingProcessed,
                    color: AppColors.green,
                    onTap: prov.processedAudio != null
                        ? prov.togglePlayProcessed
                        : null,
                  )),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Controls (tabs) ────────────────────────────────────────────────────

  Widget _buildControls(AudioProvider prov) {
    return Column(
      children: [
        Container(
          color: AppColors.surface,
          child: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: 'Presets'),
              Tab(text: 'Noise'),
              Tab(text: 'Voice'),
              Tab(text: 'EQ'),
              Tab(text: 'Dynamics'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _buildPresetsTab(prov),
              _buildNoiseTab(prov),
              _buildVoiceTab(prov),
              _buildEqTab(prov),
              _buildDynamicsTab(prov),
            ],
          ),
        ),
      ],
    );
  }

  // Tab 1: Presets
  Widget _buildPresetsTab(AudioProvider prov) {
    final presets = VoicePreset.values;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: GridView.count(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.85,
        children: presets.map((p) => PresetCard(
          preset: p,
          isSelected: prov.params.preset == p,
          onTap: () => prov.applyPreset(p),
        )).toList(),
      ),
    );
  }

  // Tab 2: Noise
  Widget _buildNoiseTab(AudioProvider prov) {
    final p = prov.params;
    void u(AudioParams np) => prov.updateParams(np);
    return _SliderPage(children: [
      ParamSlider(
        label: 'NR Strength', value: p.nrStrength, min: 0, max: 100,
        unit: '%', onChanged: (v) => u(p.copyWith(nrStrength: v))),
      ParamSlider(
        label: 'NR Smoothing (α)', value: p.nrAlpha, min: 0, max: 99,
        unit: '%', onChanged: (v) => u(p.copyWith(nrAlpha: v))),
      ParamSlider(
        label: 'Noise Floor Mult', value: p.nrFloor, min: 1, max: 12,
        displayDecimals: 1, onChanged: (v) => u(p.copyWith(nrFloor: v))),
      ParamSlider(
        label: 'Gate Threshold', value: p.gateThreshold, min: 0, max: 100,
        unit: '%', color: AppColors.cyan,
        onChanged: (v) => u(p.copyWith(gateThreshold: v))),
      ParamSlider(
        label: 'Gate Ratio', value: p.gateRatio, min: 0.5, max: 5.0,
        displayDecimals: 1, color: AppColors.cyan,
        onChanged: (v) => u(p.copyWith(gateRatio: v))),
      ParamSlider(
        label: 'VAD Sensitivity', value: p.vadSensitivity, min: 1, max: 10,
        displayDecimals: 1, color: AppColors.green,
        onChanged: (v) => u(p.copyWith(vadSensitivity: v))),
      IntParamSlider(
        label: 'VAD Hold', value: p.vadHoldMs, min: 20, max: 300,
        unit: 'ms', color: AppColors.green,
        onChanged: (v) => u(p.copyWith(vadHoldMs: v))),
    ]);
  }

  // Tab 3: Voice
  Widget _buildVoiceTab(AudioProvider prov) {
    final p = prov.params;
    void u(AudioParams np) => prov.updateParams(np);
    return _SliderPage(children: [
      ParamSlider(
        label: 'Pitch', value: p.pitchSemitones, min: -8, max: 8,
        divisions: 160, unit: ' st', displayDecimals: 1,
        color: AppColors.pink,
        onChanged: (v) => u(p.copyWith(pitchSemitones: v))),
      ParamSlider(
        label: 'Formant', value: p.formantFactor, min: 0.7, max: 1.4,
        divisions: 70, displayDecimals: 2, color: AppColors.pink,
        onChanged: (v) => u(p.copyWith(formantFactor: v))),
      ParamSlider(
        label: 'Harmonic Exciter', value: p.exciterAmount, min: 0, max: 100,
        unit: '%', color: AppColors.amber,
        onChanged: (v) => u(p.copyWith(exciterAmount: v))),
      ParamSlider(
        label: 'Spectral Smooth', value: p.smoothAmount, min: 0, max: 100,
        unit: '%', color: AppColors.cyan,
        onChanged: (v) => u(p.copyWith(smoothAmount: v))),
    ]);
  }

  // Tab 4: EQ
  Widget _buildEqTab(AudioProvider prov) {
    final p = prov.params;
    void u(AudioParams np) => prov.updateParams(np);
    return _SliderPage(children: [
      ParamSlider(
        label: 'High-Pass Freq', value: p.hpFreq, min: 20, max: 500,
        unit: ' Hz', onChanged: (v) => u(p.copyWith(hpFreq: v))),
      ParamSlider(
        label: 'Bass Shelf (+200Hz)', value: p.bassGain, min: -6, max: 6,
        unit: ' dB', displayDecimals: 1, color: AppColors.amber,
        onChanged: (v) => u(p.copyWith(bassGain: v))),
      ParamSlider(
        label: 'De-Harsh (3.5kHz)', value: p.deHarshGain, min: -9, max: 3,
        unit: ' dB', displayDecimals: 1, color: AppColors.pink,
        onChanged: (v) => u(p.copyWith(deHarshGain: v))),
      ParamSlider(
        label: 'Presence (5kHz)', value: p.presGain, min: -6, max: 9,
        unit: ' dB', displayDecimals: 1, color: AppColors.violet,
        onChanged: (v) => u(p.copyWith(presGain: v))),
      ParamSlider(
        label: 'Air Shelf (12kHz)', value: p.airGain, min: -6, max: 9,
        unit: ' dB', displayDecimals: 1, color: AppColors.cyan,
        onChanged: (v) => u(p.copyWith(airGain: v))),
    ]);
  }

  // Tab 5: Dynamics
  Widget _buildDynamicsTab(AudioProvider prov) {
    final p = prov.params;
    void u(AudioParams np) => prov.updateParams(np);
    return _SliderPage(children: [
      ParamSlider(
        label: 'Comp Threshold', value: p.compThreshold, min: -40, max: 0,
        unit: ' dB', displayDecimals: 1,
        onChanged: (v) => u(p.copyWith(compThreshold: v))),
      ParamSlider(
        label: 'Comp Ratio', value: p.compRatio, min: 1, max: 8,
        divisions: 70, displayDecimals: 1, color: AppColors.amber,
        onChanged: (v) => u(p.copyWith(compRatio: v))),
      ParamSlider(
        label: 'De-Ess Amount', value: p.deEssAmt, min: 0, max: 100,
        unit: '%', color: AppColors.pink,
        onChanged: (v) => u(p.copyWith(deEssAmt: v))),
      ParamSlider(
        label: 'Target LUFS', value: p.targetLufs, min: -24, max: -6,
        unit: ' dB', displayDecimals: 1, color: AppColors.green,
        onChanged: (v) => u(p.copyWith(targetLufs: v))),
    ]);
  }

  // ── Process Button ────────────────────────────────────────────────────

  Widget _buildProcessButton(AudioProvider prov) {
    final canProcess = prov.originalAudio != null && !prov.isProcessing && !prov.isRecording;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: GestureDetector(
        onTap: canProcess ? () => _process(prov) : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: canProcess ? 1.0 : 0.45,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.violet, AppColors.pink],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: canProcess
                  ? [
                      BoxShadow(
                        color: AppColors.violet.withOpacity(0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      )
                    ]
                  : null,
            ),
            child: Center(
              child: prov.isProcessing
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white))
                  : Text(
                      '✨  Process Audio',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Helper Widgets ────────────────────────────────────────────────────────

class _SliderPage extends StatelessWidget {
  final List<Widget> children;
  const _SliderPage({required this.children});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: children,
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: enabled ? 1.0 : 0.4,
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.4)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 5),
              Text(
                label,
                style: GoogleFonts.inter(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  final String label;
  final bool isPlaying;
  final Color color;
  final VoidCallback? onTap;

  const _PlayButton({
    required this.label,
    required this.isPlaying,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: onTap != null ? 1.0 : 0.35,
        child: Container(
          height: 34,
          decoration: BoxDecoration(
            color: isPlaying ? color.withOpacity(0.18) : AppColors.surface,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: isPlaying ? color.withOpacity(0.6) : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isPlaying ? Icons.stop_circle : Icons.play_circle,
                color: isPlaying ? color : AppColors.textDim,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: GoogleFonts.inter(
                  color: isPlaying ? color : AppColors.textDim,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
