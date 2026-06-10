import 'dart:typed_data';

enum ProcessingMode { denoise, voiceIsolate, extractMusic }

enum VoicePreset { crispy, pop, radio, deep, natural, hype }

class AudioParams {
  // Noise Reduction (Wiener Filter)
  final double nrStrength;  // 0–100
  final double nrAlpha;     // 0–99 smoothing
  final double nrFloor;     // 1–12 noise floor multiplier

  // Hard Spectral Gate
  final double gateThreshold; // 0–100
  final double gateRatio;     // 0.5–5.0

  // VAD Silence Gate
  final double vadSensitivity; // 1–10
  final int vadHoldMs;         // 20–300ms

  // Voice Transformation
  final double pitchSemitones;  // -8 to +8
  final double formantFactor;   // 0.7–1.4
  final double exciterAmount;   // 0–100
  final double smoothAmount;    // 0–100

  // EQ
  final double hpFreq;       // Hz
  final double bassGain;     // dB
  final double deHarshGain;  // dB
  final double presGain;     // dB
  final double airGain;      // dB

  // Dynamics
  final double compThreshold; // dB
  final double compRatio;
  final double deEssFreq;    // Hz
  final double deEssAmt;     // 0–100
  final double targetLufs;   // dB

  final ProcessingMode mode;
  final VoicePreset preset;

  const AudioParams({
    this.nrStrength = 60,
    this.nrAlpha = 92,
    this.nrFloor = 2.0,
    this.gateThreshold = 30,
    this.gateRatio = 1.2,
    this.vadSensitivity = 2.5,
    this.vadHoldMs = 200,
    this.pitchSemitones = 2,
    this.formantFactor = 1.12,
    this.exciterAmount = 55,
    this.smoothAmount = 55,
    this.hpFreq = 85,
    this.bassGain = 1.0,
    this.deHarshGain = -2.5,
    this.presGain = 4.0,
    this.airGain = 4.0,
    this.compThreshold = -18,
    this.compRatio = 3.5,
    this.deEssFreq = 7500,
    this.deEssAmt = 40,
    this.targetLufs = -14,
    this.mode = ProcessingMode.denoise,
    this.preset = VoicePreset.natural,
  });

  static const Map<VoicePreset, AudioParams> presets = {
    VoicePreset.crispy: AudioParams(
      pitchSemitones: 2, formantFactor: 1.14, exciterAmount: 55, smoothAmount: 55,
      hpFreq: 85, bassGain: 1.0, deHarshGain: -2.5, presGain: 4.0, airGain: 4.0,
      compThreshold: -18, compRatio: 3.5, deEssAmt: 40, targetLufs: -14,
      preset: VoicePreset.crispy,
    ),
    VoicePreset.pop: AudioParams(
      pitchSemitones: 3, formantFactor: 1.18, exciterAmount: 65, smoothAmount: 50,
      hpFreq: 80, bassGain: 2.0, deHarshGain: -2.0, presGain: 3.5, airGain: 5.0,
      compThreshold: -16, compRatio: 3.0, deEssAmt: 35, targetLufs: -14,
      preset: VoicePreset.pop,
    ),
    VoicePreset.radio: AudioParams(
      pitchSemitones: -1, formantFactor: 0.92, exciterAmount: 35, smoothAmount: 65,
      hpFreq: 100, bassGain: 3.0, deHarshGain: -3.5, presGain: 1.5, airGain: -2.0,
      compThreshold: -20, compRatio: 4.0, deEssAmt: 35, targetLufs: -14,
      preset: VoicePreset.radio,
    ),
    VoicePreset.deep: AudioParams(
      pitchSemitones: -3, formantFactor: 0.85, exciterAmount: 45, smoothAmount: 60,
      hpFreq: 60, bassGain: 4.0, deHarshGain: -1.5, presGain: 2.0, airGain: 1.0,
      compThreshold: -22, compRatio: 3.5, deEssAmt: 30, targetLufs: -14,
      preset: VoicePreset.deep,
    ),
    // Natural = pure background noise removal. Zero voice alteration.
    VoicePreset.natural: AudioParams(
      nrStrength: 72, nrAlpha: 94, nrFloor: 1.6,
      gateThreshold: 15, gateRatio: 1.0,
      vadSensitivity: 1.8, vadHoldMs: 300,
      pitchSemitones: 0, formantFactor: 1.0,
      exciterAmount: 0, smoothAmount: 0,
      hpFreq: 60, bassGain: 0, deHarshGain: 0, presGain: 0, airGain: 0,
      compThreshold: 0, compRatio: 1.0, deEssAmt: 0,
      targetLufs: -14,
      preset: VoicePreset.natural,
    ),
    VoicePreset.hype: AudioParams(
      pitchSemitones: 2.5, formantFactor: 1.10, exciterAmount: 80, smoothAmount: 45,
      hpFreq: 90, bassGain: 1.5, deHarshGain: -1.5, presGain: 5.0, airGain: 4.5,
      compThreshold: -14, compRatio: 5.0, deEssAmt: 50, targetLufs: -12,
      preset: VoicePreset.hype,
    ),
  };

  AudioParams copyWith({
    double? nrStrength, double? nrAlpha, double? nrFloor,
    double? gateThreshold, double? gateRatio,
    double? vadSensitivity, int? vadHoldMs,
    double? pitchSemitones, double? formantFactor,
    double? exciterAmount, double? smoothAmount,
    double? hpFreq, double? bassGain, double? deHarshGain,
    double? presGain, double? airGain,
    double? compThreshold, double? compRatio,
    double? deEssFreq, double? deEssAmt, double? targetLufs,
    ProcessingMode? mode, VoicePreset? preset,
  }) {
    return AudioParams(
      nrStrength: nrStrength ?? this.nrStrength,
      nrAlpha: nrAlpha ?? this.nrAlpha,
      nrFloor: nrFloor ?? this.nrFloor,
      gateThreshold: gateThreshold ?? this.gateThreshold,
      gateRatio: gateRatio ?? this.gateRatio,
      vadSensitivity: vadSensitivity ?? this.vadSensitivity,
      vadHoldMs: vadHoldMs ?? this.vadHoldMs,
      pitchSemitones: pitchSemitones ?? this.pitchSemitones,
      formantFactor: formantFactor ?? this.formantFactor,
      exciterAmount: exciterAmount ?? this.exciterAmount,
      smoothAmount: smoothAmount ?? this.smoothAmount,
      hpFreq: hpFreq ?? this.hpFreq,
      bassGain: bassGain ?? this.bassGain,
      deHarshGain: deHarshGain ?? this.deHarshGain,
      presGain: presGain ?? this.presGain,
      airGain: airGain ?? this.airGain,
      compThreshold: compThreshold ?? this.compThreshold,
      compRatio: compRatio ?? this.compRatio,
      deEssFreq: deEssFreq ?? this.deEssFreq,
      deEssAmt: deEssAmt ?? this.deEssAmt,
      targetLufs: targetLufs ?? this.targetLufs,
      mode: mode ?? this.mode,
      preset: preset ?? this.preset,
    );
  }

  Map<String, dynamic> toMap() => {
    'nrStrength': nrStrength, 'nrAlpha': nrAlpha, 'nrFloor': nrFloor,
    'gateThreshold': gateThreshold, 'gateRatio': gateRatio,
    'vadSensitivity': vadSensitivity, 'vadHoldMs': vadHoldMs,
    'pitchSemitones': pitchSemitones, 'formantFactor': formantFactor,
    'exciterAmount': exciterAmount, 'smoothAmount': smoothAmount,
    'hpFreq': hpFreq, 'bassGain': bassGain, 'deHarshGain': deHarshGain,
    'presGain': presGain, 'airGain': airGain,
    'compThreshold': compThreshold, 'compRatio': compRatio,
    'deEssFreq': deEssFreq, 'deEssAmt': deEssAmt, 'targetLufs': targetLufs,
    'mode': mode.index, 'preset': preset.index,
  };

  factory AudioParams.fromMap(Map<String, dynamic> m) => AudioParams(
    nrStrength: (m['nrStrength'] as num).toDouble(),
    nrAlpha: (m['nrAlpha'] as num).toDouble(),
    nrFloor: (m['nrFloor'] as num).toDouble(),
    gateThreshold: (m['gateThreshold'] as num).toDouble(),
    gateRatio: (m['gateRatio'] as num).toDouble(),
    vadSensitivity: (m['vadSensitivity'] as num).toDouble(),
    vadHoldMs: m['vadHoldMs'] as int,
    pitchSemitones: (m['pitchSemitones'] as num).toDouble(),
    formantFactor: (m['formantFactor'] as num).toDouble(),
    exciterAmount: (m['exciterAmount'] as num).toDouble(),
    smoothAmount: (m['smoothAmount'] as num).toDouble(),
    hpFreq: (m['hpFreq'] as num).toDouble(),
    bassGain: (m['bassGain'] as num).toDouble(),
    deHarshGain: (m['deHarshGain'] as num).toDouble(),
    presGain: (m['presGain'] as num).toDouble(),
    airGain: (m['airGain'] as num).toDouble(),
    compThreshold: (m['compThreshold'] as num).toDouble(),
    compRatio: (m['compRatio'] as num).toDouble(),
    deEssFreq: (m['deEssFreq'] as num).toDouble(),
    deEssAmt: (m['deEssAmt'] as num).toDouble(),
    targetLufs: (m['targetLufs'] as num).toDouble(),
    mode: ProcessingMode.values[m['mode'] as int],
    preset: VoicePreset.values[m['preset'] as int],
  );
}

class AudioData {
  final Float32List samples;
  final int sampleRate;
  final Duration duration;

  const AudioData({
    required this.samples,
    required this.sampleRate,
    required this.duration,
  });

  factory AudioData.fromSamples(Float32List samples, int sampleRate) {
    return AudioData(
      samples: samples,
      sampleRate: sampleRate,
      duration: Duration(milliseconds: samples.length * 1000 ~/ sampleRate),
    );
  }
}
