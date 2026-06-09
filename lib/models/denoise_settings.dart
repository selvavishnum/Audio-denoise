class DenoiseSettings {
  final String mode;
  final double noiseReduction;    // 0-100%
  final double noiseFloor;         // -80 to -20 dB
  final double highPassHz;         // 20-500 Hz
  final double lowPassKhz;         // 2-20 kHz
  final bool voiceEnhance;
  final bool deReverb;
  final double outputGain;         // -12 to +12 dB
  final double compressorRatio;    // 1:1 to 8:1

  const DenoiseSettings({
    this.mode = 'ai_quick',
    this.noiseReduction = 50.0,
    this.noiseFloor = -25.0,
    this.highPassHz = 80.0,
    this.lowPassKhz = 18.0,
    this.voiceEnhance = false,
    this.deReverb = false,
    this.outputGain = 0.0,
    this.compressorRatio = 2.0,
  });

  static DenoiseSettings forMode(String mode) {
    switch (mode) {
      case 'ai_quick':
        return const DenoiseSettings(
          mode: 'ai_quick',
          noiseReduction: 60,
          noiseFloor: -25,
        );
      case 'voice':
        return const DenoiseSettings(
          mode: 'voice',
          noiseReduction: 70,
          noiseFloor: -22,
          highPassHz: 80,
          lowPassKhz: 10,
          voiceEnhance: true,
        );
      case 'podcast':
        return const DenoiseSettings(
          mode: 'podcast',
          noiseReduction: 65,
          noiseFloor: -22,
          highPassHz: 100,
          lowPassKhz: 12,
          voiceEnhance: true,
          compressorRatio: 3,
        );
      case 'music':
        return const DenoiseSettings(
          mode: 'music',
          noiseReduction: 40,
          noiseFloor: -30,
          highPassHz: 30,
          lowPassKhz: 20,
        );
      default:
        return const DenoiseSettings();
    }
  }

  String buildFFmpegFilter() {
    final filters = <String>[];

    if (mode == 'music') {
      final s = (noiseReduction / 100 * 15).clamp(0.5, 15).toStringAsFixed(1);
      filters.add('anlmdn=s=$s:p=0.002:r=0.002:m=15');
    } else {
      final nr = noiseReduction.round();
      final nf = noiseFloor.round();
      filters.add('afftdn=nf=$nf:nr=$nr');
    }

    if (highPassHz > 20) {
      filters.add('highpass=f=${highPassHz.round()}');
    }

    if (lowPassKhz < 20) {
      final hz = (lowPassKhz * 1000).round();
      filters.add('lowpass=f=$hz');
    }

    if (voiceEnhance) {
      filters.add('equalizer=f=3000:t=q:w=1:g=3');
    }

    if (deReverb) {
      filters.add('aecho=0.8:0.9:40:0.4');
    }

    if (compressorRatio > 1.5) {
      final ratio = compressorRatio.toStringAsFixed(1);
      filters.add('acompressor=ratio=$ratio:threshold=0.125:attack=5:release=50');
    }

    if (outputGain != 0) {
      final gain = outputGain.toStringAsFixed(1);
      filters.add('volume=${gain}dB');
    }

    return filters.join(',');
  }

  DenoiseSettings copyWith({
    String? mode,
    double? noiseReduction,
    double? noiseFloor,
    double? highPassHz,
    double? lowPassKhz,
    bool? voiceEnhance,
    bool? deReverb,
    double? outputGain,
    double? compressorRatio,
  }) {
    return DenoiseSettings(
      mode: mode ?? this.mode,
      noiseReduction: noiseReduction ?? this.noiseReduction,
      noiseFloor: noiseFloor ?? this.noiseFloor,
      highPassHz: highPassHz ?? this.highPassHz,
      lowPassKhz: lowPassKhz ?? this.lowPassKhz,
      voiceEnhance: voiceEnhance ?? this.voiceEnhance,
      deReverb: deReverb ?? this.deReverb,
      outputGain: outputGain ?? this.outputGain,
      compressorRatio: compressorRatio ?? this.compressorRatio,
    );
  }
}
