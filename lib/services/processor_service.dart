import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import '../models/audio_params.dart';
import 'fft_service.dart';
import 'neural_processor_service.dart';

// ─── Public entry point ────────────────────────────────────────────────────

class ProcessorService {
  static Future<AudioData> process(
    AudioData input,
    AudioParams params, {
    void Function(double)? onProgress,
  }) async {
    // ── Stage 0: Neural denoising (0 → 25% of progress bar) ─────────────────
    // SpectralUNet IRM mask applied in a compute() isolate.
    // Falls back to DSP-only silently if model not bundled or inference fails.
    AudioData stageInput = input;
    final bool useNeural = NeuralProcessorService.isReady;

    if (useNeural) {
      onProgress?.call(0.01);
      final cleaned = await NeuralProcessorService.denoise(
        input.samples, input.sampleRate,
      );
      if (cleaned != null) {
        stageInput = AudioData.fromSamples(cleaned, input.sampleRate);
      }
      onProgress?.call(0.25);
    }

    // ── Stage 1: DSP refinement (25 → 100%, or 0 → 100% without neural) ─────
    final double progressOffset = useNeural ? 0.25 : 0.0;
    final double progressScale  = useNeural ? 0.75 : 1.0;

    final receivePort = ReceivePort();
    await Isolate.spawn(_processIsolate, {
      'sendPort':       receivePort.sendPort,
      'samples':        stageInput.samples,
      'rate':           stageInput.sampleRate,
      'params':         params.toMap(),
      'progressOffset': progressOffset,
      'progressScale':  progressScale,
    });

    Float32List? result;
    int resultRate = stageInput.sampleRate;

    await for (final msg in receivePort) {
      if (msg is double) {
        onProgress?.call(msg);
      } else if (msg is Map) {
        result     = msg['samples'] as Float32List;
        resultRate = msg['rate'] as int;
        break;
      }
    }
    receivePort.close();

    return AudioData.fromSamples(result ?? stageInput.samples, resultRate);
  }

  // ─── Isolate entry ─────────────────────────────────────────────────────

  static void _processIsolate(Map<String, dynamic> args) {
    final sendPort = args['sendPort'] as SendPort;
    final samples  = args['samples'] as Float32List;
    final rate     = args['rate'] as int;
    final params   = AudioParams.fromMap(args['params'] as Map<String, dynamic>);
    final double offset = (args['progressOffset'] as double?) ?? 0.0;
    final double scale  = (args['progressScale']  as double?) ?? 1.0;

    Float32List s = Float32List.fromList(samples);

    void progress(double p) => sendPort.send(offset + p * scale);

    progress(0.02);
    final noiseProfile = _buildNoiseProfile(s, rate, params);

    progress(0.10);
    s = _wienerFilter(s, noiseProfile, params);

    progress(0.22);
    s = _softSpectralGate(s, noiseProfile, params);

    progress(0.32);
    s = _vadGate(s, rate, params);

    progress(0.40);
    if (params.pitchSemitones.abs() > 0.05) {
      s = _pitchShift(s, params.pitchSemitones);
    }

    progress(0.52);
    if ((params.formantFactor - 1.0).abs() > 0.01) {
      s = _formantShift(s, params.formantFactor, rate);
    }

    progress(0.60);
    if (params.exciterAmount > 0.5) {
      s = _harmonicExciter(s, rate, params.exciterAmount);
    }

    progress(0.67);
    if (params.smoothAmount > 0.5) {
      s = _spectralSmooth(s, params.smoothAmount);
    }

    progress(0.74);
    s = _applyEQ(s, rate, params);

    progress(0.82);
    if (params.compRatio > 1.01) {
      s = _softCompress(s, params);
    }

    progress(0.88);
    if (params.deEssAmt > 0.5) {
      s = _deEss(s, rate, params);
    }

    progress(0.95);
    s = _normalizeLufs(s, params.targetLufs);

    progress(1.0);
    sendPort.send({'samples': s, 'rate': rate});
  }

  // ─── WAV Decode ────────────────────────────────────────────────────────

  static AudioData? decodeWav(Uint8List bytes) {
    if (bytes.length < 44) return null;
    final bd = ByteData.sublistView(bytes);

    // Validate RIFF / WAVE markers
    if (bytes[0] != 0x52 || bytes[1] != 0x49 || bytes[2] != 0x46 || bytes[3] != 0x46) {
      return null;
    }
    if (bytes[8] != 0x57 || bytes[9] != 0x41 || bytes[10] != 0x56 || bytes[11] != 0x45) {
      return null;
    }

    int numChannels = 1, sampleRate = 44100, bitsPerSample = 16;
    int dataOffset = -1, dataSize = 0;
    int offset = 12;

    while (offset + 8 <= bytes.length) {
      final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = bd.getUint32(offset + 4, Endian.little);

      if (chunkId == 'fmt ') {
        numChannels = bd.getUint16(offset + 10, Endian.little);
        sampleRate = bd.getUint32(offset + 12, Endian.little);
        bitsPerSample = bd.getUint16(offset + 22, Endian.little);
      } else if (chunkId == 'data') {
        dataOffset = offset + 8;
        dataSize = chunkSize;
        break;
      }
      offset += 8 + chunkSize;
    }

    if (dataOffset < 0 || dataOffset + dataSize > bytes.length) return null;

    final int bytesPerSample = bitsPerSample ~/ 8;
    final int totalFrames = dataSize ~/ (bytesPerSample * numChannels);
    final samples = Float32List(totalFrames);

    for (int i = 0; i < totalFrames; i++) {
      double v = 0;
      for (int ch = 0; ch < numChannels; ch++) {
        final off = dataOffset + (i * numChannels + ch) * bytesPerSample;
        if (bitsPerSample == 16) {
          v += bd.getInt16(off, Endian.little) / 32768.0;
        } else if (bitsPerSample == 32) {
          v += bd.getInt32(off, Endian.little) / 2147483648.0;
        } else if (bitsPerSample == 8) {
          v += (bd.getUint8(off) - 128) / 128.0;
        }
      }
      samples[i] = (v / numChannels).clamp(-1.0, 1.0);
    }

    return AudioData.fromSamples(samples, sampleRate);
  }

  static Uint8List encodeWav(Float32List samples, int sampleRate) {
    final dataSize = samples.length * 2;
    final buffer = Uint8List(44 + dataSize);
    final bd = ByteData.sublistView(buffer);

    void writeStr(int off, String s) {
      for (int i = 0; i < s.length; i++) buffer[off + i] = s.codeUnitAt(i);
    }

    writeStr(0, 'RIFF');
    bd.setUint32(4, 36 + dataSize, Endian.little);
    writeStr(8, 'WAVE');
    writeStr(12, 'fmt ');
    bd.setUint32(16, 16, Endian.little);
    bd.setUint16(20, 1, Endian.little);  // PCM
    bd.setUint16(22, 1, Endian.little);  // mono
    bd.setUint32(24, sampleRate, Endian.little);
    bd.setUint32(28, sampleRate * 2, Endian.little);
    bd.setUint16(32, 2, Endian.little);
    bd.setUint16(34, 16, Endian.little);
    writeStr(36, 'data');
    bd.setUint32(40, dataSize, Endian.little);

    for (int i = 0; i < samples.length; i++) {
      final s = (samples[i].clamp(-1.0, 1.0) * 32767).round().clamp(-32768, 32767);
      bd.setInt16(44 + i * 2, s, Endian.little);
    }
    return buffer;
  }

  // ─── Algorithm 1: Build Noise Profile ─────────────────────────────────

  static Float64List _buildNoiseProfile(Float32List samples, int rate, AudioParams params) {
    const int FRAME = 2048;
    const int HOP = 512;
    final hann = FFTService.hannWindow(FRAME);
    final n = samples.length;

    // Compute RMS per frame
    final frameEnergies = <double>[];
    final frameSpectra = <Float64List>[];

    for (int pos = 0; pos + FRAME <= n; pos += HOP) {
      final re = Float64List(FRAME);
      final im = Float64List(FRAME);
      double energy = 0;
      for (int i = 0; i < FRAME; i++) {
        re[i] = samples[pos + i] * hann[i];
        energy += re[i] * re[i];
      }
      FFTService.fft(re, im);

      final mag = Float64List(FRAME ~/ 2 + 1);
      for (int k = 0; k <= FRAME ~/ 2; k++) {
        mag[k] = sqrt(re[k] * re[k] + im[k] * im[k]);
      }

      frameEnergies.add(sqrt(energy / FRAME));
      frameSpectra.add(mag);
    }

    if (frameEnergies.isEmpty) {
      return Float64List(FRAME ~/ 2 + 1);
    }

    // Sort by energy; take lowest 30% (noise frames)
    final sorted = List<int>.generate(frameEnergies.length, (i) => i)
      ..sort((a, b) => frameEnergies[a].compareTo(frameEnergies[b]));

    final int numNoise = max(10, (sorted.length * 0.30).round());
    final profile = Float64List(FRAME ~/ 2 + 1);

    for (int j = 0; j < numNoise; j++) {
      final spec = frameSpectra[sorted[j]];
      for (int k = 0; k < profile.length; k++) {
        profile[k] += spec[k];
      }
    }
    for (int k = 0; k < profile.length; k++) {
      profile[k] = (profile[k] / numNoise) * params.nrFloor;
    }
    return profile;
  }

  // ─── Algorithm 2: Wiener Filter (Decision-Directed MMSE) ──────────────

  static Float32List _wienerFilter(
      Float32List samples, Float64List noiseProfile, AudioParams params) {
    const int FRAME = 2048;
    const int HOP = 512;
    final double alpha = params.nrAlpha / 100.0;
    final double minGain = 1.0 - params.nrStrength / 100.0;
    final hann = FFTService.hannWindow(FRAME);
    final n = samples.length;
    final output = Float64List(n + FRAME);
    final weights = Float64List(n + FRAME);
    final prevMag = Float64List(FRAME ~/ 2 + 1);

    for (int pos = 0; pos < n; pos += HOP) {
      final re = Float64List(FRAME);
      final im = Float64List(FRAME);
      for (int i = 0; i < FRAME; i++) {
        final si = pos + i;
        re[i] = (si < n ? samples[si] : 0.0) * hann[i];
      }
      FFTService.fft(re, im);

      for (int k = 0; k <= FRAME ~/ 2; k++) {
        final mag = sqrt(re[k] * re[k] + im[k] * im[k]);
        final phase = atan2(im[k], re[k]);
        final nv = noiseProfile[k] * noiseProfile[k];
        final snrPost = max((mag * mag / max(nv, 1e-12)) - 1.0, 0.0);
        final snrPrio = alpha * (prevMag[k] * prevMag[k] / max(nv, 1e-12)) +
            (1.0 - alpha) * snrPost;
        var gain = snrPrio / (1.0 + snrPrio);
        gain = max(gain, minGain);
        prevMag[k] = mag * gain;
        final nm = mag * gain;
        re[k] = nm * cos(phase);
        im[k] = nm * sin(phase);
        if (k > 0 && k < FRAME ~/ 2) {
          re[FRAME - k] = nm * cos(phase);
          im[FRAME - k] = -(nm * sin(phase));
        }
      }

      FFTService.ifft(re, im);
      for (int i = 0; i < FRAME; i++) {
        output[pos + i] += re[i] * hann[i];
        weights[pos + i] += hann[i] * hann[i];
      }
    }

    final result = Float32List(n);
    for (int i = 0; i < n; i++) {
      result[i] = weights[i] > 1e-12 ? (output[i] / weights[i]).clamp(-1.0, 1.0) : 0.0;
    }
    return result;
  }

  // ─── Algorithm 3: Soft Spectral Gate ──────────────────────────────────
  // Quadratic gain rolloff below threshold instead of hard zero — eliminates
  // musical noise (isolated surviving bins that create crackling artifacts).

  static Float32List _softSpectralGate(
      Float32List samples, Float64List noiseProfile, AudioParams params) {
    const int FRAME = 2048;
    const int HOP = 512;
    final hann = FFTService.hannWindow(FRAME);
    final n = samples.length;
    final output = Float64List(n + FRAME);
    final weights = Float64List(n + FRAME);

    for (int pos = 0; pos < n; pos += HOP) {
      final re = Float64List(FRAME);
      final im = Float64List(FRAME);
      for (int i = 0; i < FRAME; i++) {
        final si = pos + i;
        re[i] = (si < n ? samples[si] : 0.0) * hann[i];
      }
      FFTService.fft(re, im);

      for (int k = 0; k <= FRAME ~/ 2; k++) {
        final mag = sqrt(re[k] * re[k] + im[k] * im[k]);
        final threshold =
            params.gateRatio * noiseProfile[k] * (params.gateThreshold / 100.0 + 0.5);
        if (mag < threshold && threshold > 1e-12) {
          // Smooth quadratic rolloff: gain = (mag/threshold)² → 0 at floor, 1 at threshold
          final double t = mag / threshold;
          final double gain = t * t;
          re[k] *= gain; im[k] *= gain;
          if (k > 0 && k < FRAME ~/ 2) {
            re[FRAME - k] *= gain; im[FRAME - k] *= gain;
          }
        }
      }

      FFTService.ifft(re, im);
      for (int i = 0; i < FRAME; i++) {
        output[pos + i] += re[i] * hann[i];
        weights[pos + i] += hann[i] * hann[i];
      }
    }

    final result = Float32List(n);
    for (int i = 0; i < n; i++) {
      result[i] = weights[i] > 1e-12 ? (output[i] / weights[i]).clamp(-1.0, 1.0) : 0.0;
    }
    return result;
  }

  // ─── Algorithm 4: VAD Silence Gate ────────────────────────────────────

  static Float32List _vadGate(Float32List samples, int rate, AudioParams params) {
    final int frameSamples = (rate * 20 / 1000).round(); // 20ms frames
    final n = samples.length;
    final int numFrames = (n / frameSamples).ceil();

    // RMS per frame
    final frameRms = Float64List(numFrames);
    for (int f = 0; f < numFrames; f++) {
      final start = f * frameSamples;
      final end = min(start + frameSamples, n);
      double sumSq = 0;
      for (int i = start; i < end; i++) {
        sumSq += samples[i] * samples[i];
      }
      frameRms[f] = sqrt(sumSq / (end - start));
    }

    // Median RMS as noise floor estimate
    final sorted = Float64List.fromList(frameRms)..sort();
    final noiseRms = sorted[numFrames ~/ 2];
    final threshold = params.vadSensitivity * noiseRms;
    final int holdFrames = (params.vadHoldMs / 20).round();

    // State machine with hold
    int holdCounter = 0;
    final isSpeech = List<bool>.filled(numFrames, false);
    for (int f = 0; f < numFrames; f++) {
      if (frameRms[f] > threshold) {
        holdCounter = holdFrames;
        isSpeech[f] = true;
      } else {
        if (holdCounter > 0) {
          holdCounter--;
          isSpeech[f] = true;
        }
      }
    }

    // Apply with fade in/out (3-frame attack)
    final result = Float32List.fromList(samples);
    const int attackFrames = 3;

    for (int f = 0; f < numFrames; f++) {
      final start = f * frameSamples;
      final end = min(start + frameSamples, n);

      if (!isSpeech[f]) {
        // Check surrounding frames for fade
        double gain = 0.0;
        for (int d = 1; d <= attackFrames; d++) {
          if (f + d < numFrames && isSpeech[f + d]) {
            gain = max(gain, (attackFrames - d + 1) / (attackFrames + 1.0));
          }
          if (f - d >= 0 && isSpeech[f - d]) {
            gain = max(gain, (attackFrames - d + 1) / (attackFrames + 1.0));
          }
        }
        for (int i = start; i < end; i++) {
          result[i] = (result[i] * gain);
        }
      }
    }
    return result;
  }

  // ─── Algorithm 5: Phase Vocoder Pitch Shift ───────────────────────────

  static Float32List _pitchShift(Float32List samples, double semitones) {
    const int N = 2048;
    const int HOP_A = 512;
    final double ratio = pow(2.0, semitones / 12.0).toDouble();
    final int HOP_S = (HOP_A * ratio).round().clamp(1, N);
    final hann = FFTService.hannWindow(N);
    final int n = samples.length;

    final int synthLen = ((n.toDouble() / HOP_A) * HOP_S).round() + N * 2;
    final synth = Float64List(synthLen);
    final synthW = Float64List(synthLen);

    final prevPhase = Float64List(N ~/ 2 + 1);
    final synthPhase = Float64List(N ~/ 2 + 1);
    int synthPos = 0;

    for (int pos = 0; pos < n; pos += HOP_A) {
      final re = Float64List(N);
      final im = Float64List(N);
      for (int i = 0; i < N; i++) {
        final si = pos + i;
        re[i] = (si < n ? samples[si] : 0.0) * hann[i];
      }
      FFTService.fft(re, im);

      final outRe = Float64List(N);
      final outIm = Float64List(N);

      for (int k = 0; k <= N ~/ 2; k++) {
        final mag = sqrt(re[k] * re[k] + im[k] * im[k]);
        final phase = atan2(im[k], re[k]);
        final expected = 2.0 * pi * k * HOP_A / N;
        final diff = FFTService.princArg(phase - prevPhase[k] - expected);
        final trueFreq = 2.0 * pi * k / N + diff / HOP_A;
        synthPhase[k] = synthPhase[k] + trueFreq * HOP_S;
        prevPhase[k] = phase;
        outRe[k] = mag * cos(synthPhase[k]);
        outIm[k] = mag * sin(synthPhase[k]);
      }
      // Mirror for negative frequencies
      for (int k = 1; k < N ~/ 2; k++) {
        outRe[N - k] = outRe[k];
        outIm[N - k] = -outIm[k];
      }

      FFTService.ifft(outRe, outIm);

      if (synthPos + N <= synthLen) {
        for (int i = 0; i < N; i++) {
          synth[synthPos + i] += outRe[i] * hann[i];
          synthW[synthPos + i] += hann[i] * hann[i];
        }
      }
      synthPos += HOP_S;
    }

    // Normalize synthesis buffer
    final int usedLen = min(synthPos + N, synthLen);
    final normalized = Float64List(usedLen);
    for (int i = 0; i < usedLen; i++) {
      normalized[i] = synthW[i] > 1e-12 ? synth[i] / synthW[i] : 0.0;
    }

    // Resample back to original length
    final result = Float32List(n);
    final scale = normalized.length.toDouble() / n;
    for (int i = 0; i < n; i++) {
      final pos = i * scale;
      final idx = pos.floor();
      final frac = pos - idx;
      if (idx + 1 < normalized.length) {
        result[i] = FFTService.lerp(normalized[idx], normalized[idx + 1], frac).clamp(-1.0, 1.0);
      } else if (idx < normalized.length) {
        result[i] = normalized[idx].clamp(-1.0, 1.0);
      }
    }
    return result;
  }

  // ─── Algorithm 6: Cepstral Formant Shift ──────────────────────────────

  static Float32List _formantShift(Float32List samples, double formantFactor, int rate) {
    const int N = 2048;
    const int HOP = 512;
    final int LIFTER = (N * 40.0 / rate).floor().clamp(10, N ~/ 4);
    final hann = FFTService.hannWindow(N);
    final int n = samples.length;
    final output = Float64List(n + N);
    final weights = Float64List(n + N);

    for (int pos = 0; pos < n; pos += HOP) {
      final re = Float64List(N);
      final im = Float64List(N);
      for (int i = 0; i < N; i++) {
        final si = pos + i;
        re[i] = (si < n ? samples[si] : 0.0) * hann[i];
      }
      FFTService.fft(re, im);

      // Log magnitude spectrum
      final mag = Float64List(N);
      final phase = Float64List(N);
      for (int k = 0; k < N; k++) {
        mag[k] = sqrt(re[k] * re[k] + im[k] * im[k]);
        phase[k] = atan2(im[k], re[k]);
      }

      final logMag = Float64List(N);
      for (int k = 0; k < N; k++) {
        logMag[k] = log(max(mag[k], 1e-10));
      }

      // Real cepstrum: IFFT of log magnitude
      final cRe = Float64List.fromList(logMag);
      final cIm = Float64List(N);
      FFTService.ifft(cRe, cIm);

      // Lifter: keep low quefrency, zero rest, mirror
      final liftered = Float64List(N);
      liftered[0] = cRe[0];
      for (int i = 1; i <= LIFTER && i < N ~/ 2; i++) {
        liftered[i] = cRe[i];
        liftered[N - i] = cRe[i]; // mirror
      }

      // FFT of liftered cepstrum → log spectral envelope
      final eRe = Float64List.fromList(liftered);
      final eIm = Float64List(N);
      FFTService.fft(eRe, eIm);

      // Linear envelope
      final env = Float64List(N ~/ 2 + 1);
      for (int k = 0; k <= N ~/ 2; k++) {
        env[k] = exp(eRe[k].clamp(-20.0, 20.0));
      }

      // Shift envelope by formantFactor
      final shiftedEnv = Float64List(N ~/ 2 + 1);
      for (int k = 0; k <= N ~/ 2; k++) {
        final srcK = k / formantFactor;
        final lo = srcK.floor();
        final hi = lo + 1;
        final frac = srcK - lo;
        if (hi <= N ~/ 2) {
          shiftedEnv[k] = FFTService.lerp(env[lo], env[hi], frac);
        } else if (lo <= N ~/ 2) {
          shiftedEnv[k] = env[lo];
        } else {
          shiftedEnv[k] = 1e-8;
        }
      }

      // Apply formant shift to spectrum
      for (int k = 0; k <= N ~/ 2; k++) {
        final nm = (mag[k] / max(env[k], 1e-8)) * shiftedEnv[k];
        re[k] = nm * cos(phase[k]);
        im[k] = nm * sin(phase[k]);
        if (k > 0 && k < N ~/ 2) {
          re[N - k] = nm * cos(phase[k]);
          im[N - k] = -(nm * sin(phase[k]));
        }
      }

      FFTService.ifft(re, im);
      for (int i = 0; i < N; i++) {
        output[pos + i] += re[i] * hann[i];
        weights[pos + i] += hann[i] * hann[i];
      }
    }

    final result = Float32List(n);
    for (int i = 0; i < n; i++) {
      result[i] = weights[i] > 1e-12 ? (output[i] / weights[i]).clamp(-1.0, 1.0) : 0.0;
    }
    return result;
  }

  // ─── Algorithm 7: Harmonic Exciter ────────────────────────────────────

  static Float32List _harmonicExciter(
      Float32List samples, int rate, double exciterAmount) {
    final mix = exciterAmount / 100.0;
    final n = samples.length;

    // Generate harmonics via tanh saturation
    final excited = Float32List(n);
    for (int i = 0; i < n; i++) {
      excited[i] = _tanhApprox(samples[i] * 4.0) * 0.25;
    }

    // Bandpass: highpass at 2kHz, lowpass at 16kHz
    final hp = _biquadHP(excited, rate, 2000.0, 0.707);
    final bp = _biquadLP(hp, rate, 16000.0, 0.707);

    final result = Float32List(n);
    for (int i = 0; i < n; i++) {
      result[i] = (samples[i] + bp[i] * mix * 0.3).clamp(-1.0, 1.0);
    }
    return result;
  }

  static double _tanhApprox(double x) {
    // Fast tanh approximation
    final x2 = x * x;
    return x * (27.0 + x2) / (27.0 + 9.0 * x2);
  }

  // ─── Algorithm 8: Spectral Smoothing ──────────────────────────────────

  static Float32List _spectralSmooth(Float32List samples, double smoothAmount) {
    const int N = 2048;
    const int HOP = 512;
    final int W = max(1, (smoothAmount / 100.0 * 15).round());
    final hann = FFTService.hannWindow(N);
    final n = samples.length;
    final output = Float64List(n + N);
    final weights = Float64List(n + N);

    for (int pos = 0; pos < n; pos += HOP) {
      final re = Float64List(N);
      final im = Float64List(N);
      for (int i = 0; i < N; i++) {
        final si = pos + i;
        re[i] = (si < n ? samples[si] : 0.0) * hann[i];
      }
      FFTService.fft(re, im);

      final mag = Float64List(N ~/ 2 + 1);
      final phase = Float64List(N ~/ 2 + 1);
      for (int k = 0; k <= N ~/ 2; k++) {
        mag[k] = sqrt(re[k] * re[k] + im[k] * im[k]);
        phase[k] = atan2(im[k], re[k]);
      }

      // Moving average on magnitude
      final smooth = Float64List(N ~/ 2 + 1);
      for (int k = 0; k <= N ~/ 2; k++) {
        int cnt = 0;
        double sum = 0;
        for (int j = max(0, k - W); j <= min(N ~/ 2, k + W); j++) {
          sum += mag[j];
          cnt++;
        }
        smooth[k] = sum / cnt;
      }

      for (int k = 0; k <= N ~/ 2; k++) {
        final ratio = mag[k] > 1e-12 ? smooth[k] / mag[k] : 1.0;
        final nm = mag[k] * ratio;
        re[k] = nm * cos(phase[k]);
        im[k] = nm * sin(phase[k]);
        if (k > 0 && k < N ~/ 2) {
          re[N - k] = nm * cos(phase[k]);
          im[N - k] = -(nm * sin(phase[k]));
        }
      }

      FFTService.ifft(re, im);
      for (int i = 0; i < N; i++) {
        output[pos + i] += re[i] * hann[i];
        weights[pos + i] += hann[i] * hann[i];
      }
    }

    final result = Float32List(n);
    for (int i = 0; i < n; i++) {
      result[i] = weights[i] > 1e-12 ? (output[i] / weights[i]).clamp(-1.0, 1.0) : 0.0;
    }
    return result;
  }

  // ─── Algorithm 9: EQ (biquad chain) ───────────────────────────────────

  static Float32List _applyEQ(Float32List samples, int rate, AudioParams params) {
    Float32List s = samples;
    // High-pass — always apply when hpFreq > 20 Hz (removes DC / sub-bass rumble)
    if (params.hpFreq > 20) s = _hpFilter(s, rate, params.hpFreq, 0.707);
    if (params.bassGain.abs() > 0.1)     s = _lowShelf(s, rate, 200.0, params.bassGain, 0.707);
    if (params.deHarshGain.abs() > 0.1)  s = _peakingEQ(s, rate, 3500.0, params.deHarshGain, 1.5);
    if (params.presGain.abs() > 0.1)     s = _peakingEQ(s, rate, 5000.0, params.presGain, 1.0);
    if (params.airGain.abs() > 0.1)      s = _highShelf(s, rate, 12000.0, params.airGain, 0.707);
    return s;
  }

  static Float32List _hpFilter(Float32List s, int rate, double freq, double q) {
    final w = 2.0 * pi * freq / rate;
    final alpha = sin(w) / (2.0 * q);
    final cosw = cos(w);
    final b0 = (1.0 + cosw) / 2.0;
    final b1 = -(1.0 + cosw);
    final b2 = (1.0 + cosw) / 2.0;
    final a0 = 1.0 + alpha;
    final a1 = -2.0 * cosw;
    final a2 = 1.0 - alpha;
    return _biquadFilter(s, b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0);
  }

  static Float32List _lowShelf(Float32List s, int rate, double freq, double gainDb, double q) {
    final A = pow(10.0, gainDb / 40.0).toDouble();
    final w = 2.0 * pi * freq / rate;
    final sinw = sin(w);
    final cosw = cos(w);
    final alpha = sinw / 2.0 * sqrt((A + 1.0 / A) * (1.0 / q - 1.0) + 2.0);
    final sqA = sqrt(A);
    final b0 = A * ((A + 1.0) - (A - 1.0) * cosw + 2.0 * sqA * alpha);
    final b1 = 2.0 * A * ((A - 1.0) - (A + 1.0) * cosw);
    final b2 = A * ((A + 1.0) - (A - 1.0) * cosw - 2.0 * sqA * alpha);
    final a0 = (A + 1.0) + (A - 1.0) * cosw + 2.0 * sqA * alpha;
    final a1 = -2.0 * ((A - 1.0) + (A + 1.0) * cosw);
    final a2 = (A + 1.0) + (A - 1.0) * cosw - 2.0 * sqA * alpha;
    return _biquadFilter(s, b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0);
  }

  static Float32List _peakingEQ(Float32List s, int rate, double freq, double gainDb, double q) {
    final A = pow(10.0, gainDb / 40.0).toDouble();
    final w = 2.0 * pi * freq / rate;
    final alpha = sin(w) / (2.0 * q);
    final cosw = cos(w);
    final b0 = 1.0 + alpha * A;
    final b1 = -2.0 * cosw;
    final b2 = 1.0 - alpha * A;
    final a0 = 1.0 + alpha / A;
    final a1 = -2.0 * cosw;
    final a2 = 1.0 - alpha / A;
    return _biquadFilter(s, b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0);
  }

  static Float32List _highShelf(Float32List s, int rate, double freq, double gainDb, double q) {
    final A = pow(10.0, gainDb / 40.0).toDouble();
    final w = 2.0 * pi * freq / rate;
    final sinw = sin(w);
    final cosw = cos(w);
    final alpha = sinw / 2.0 * sqrt((A + 1.0 / A) * (1.0 / q - 1.0) + 2.0);
    final sqA = sqrt(A);
    final b0 = A * ((A + 1.0) + (A - 1.0) * cosw + 2.0 * sqA * alpha);
    final b1 = -2.0 * A * ((A - 1.0) + (A + 1.0) * cosw);
    final b2 = A * ((A + 1.0) + (A - 1.0) * cosw - 2.0 * sqA * alpha);
    final a0 = (A + 1.0) - (A - 1.0) * cosw + 2.0 * sqA * alpha;
    final a1 = 2.0 * ((A - 1.0) - (A + 1.0) * cosw);
    final a2 = (A + 1.0) - (A - 1.0) * cosw - 2.0 * sqA * alpha;
    return _biquadFilter(s, b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0);
  }

  // Biquad helpers used by exciter
  static Float32List _biquadHP(Float32List s, int rate, double freq, double q) =>
      _hpFilter(s, rate, freq, q);

  static Float32List _biquadLP(Float32List s, int rate, double freq, double q) {
    final w = 2.0 * pi * freq / rate;
    final alpha = sin(w) / (2.0 * q);
    final cosw = cos(w);
    final b0 = (1.0 - cosw) / 2.0;
    final b1 = 1.0 - cosw;
    final b2 = (1.0 - cosw) / 2.0;
    final a0 = 1.0 + alpha;
    final a1 = -2.0 * cosw;
    final a2 = 1.0 - alpha;
    return _biquadFilter(s, b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0);
  }

  // Direct Form II transposed
  static Float32List _biquadFilter(
      Float32List s, double b0, double b1, double b2, double a1, double a2) {
    final result = Float32List(s.length);
    double z1 = 0, z2 = 0;
    for (int i = 0; i < s.length; i++) {
      final x = s[i].toDouble();
      final y = b0 * x + z1;
      z1 = b1 * x - a1 * y + z2;
      z2 = b2 * x - a2 * y;
      result[i] = y.clamp(-1.5, 1.5);
    }
    return result;
  }

  // ─── Algorithm 10: Soft Compressor ────────────────────────────────────

  static Float32List _softCompress(Float32List samples, AudioParams params) {
    final double threshold = params.compThreshold;
    final double ratio = params.compRatio;
    final double attackCoef = exp(-1.0 / (samples.length > 0
        ? (44100 * 0.003).clamp(1, double.infinity)
        : 132.3));
    final double releaseCoef = exp(-1.0 / (44100 * 0.1));
    final double makeupGain = -threshold * (1.0 - 1.0 / ratio) * 0.5;

    final result = Float32List(samples.length);
    double envelope = 0;

    for (int i = 0; i < samples.length; i++) {
      final level = samples[i].abs();
      if (level > envelope) {
        envelope = attackCoef * envelope + (1.0 - attackCoef) * level;
      } else {
        envelope = releaseCoef * envelope + (1.0 - releaseCoef) * level;
      }

      final levelDb = 20.0 * log(max(envelope, 1e-8)) / ln10;
      double gainDb;
      if (levelDb > threshold) {
        gainDb = threshold + (levelDb - threshold) / ratio - levelDb;
      } else {
        gainDb = 0.0;
      }

      result[i] = (samples[i] * pow(10.0, (gainDb + makeupGain) / 20.0).toDouble())
          .clamp(-1.0, 1.0);
    }
    return result;
  }

  // ─── Algorithm 11: De-esser ───────────────────────────────────────────

  static Float32List _deEss(Float32List samples, int rate, AudioParams params) {
    final double center = params.deEssFreq;
    // 2-octave bandwidth: center/2 to center*2
    final double loFreq = center / 2.0;
    final double hiFreq = (center * 2.0).clamp(0, rate / 2.0 - 1);

    // Extract sibilance band
    final sibBand = _biquadLP(_biquadHP(samples, rate, loFreq, 0.707), rate, hiFreq, 0.707);

    const int FRAME = 256;
    final result = Float32List.fromList(samples);

    for (int pos = 0; pos < samples.length; pos += FRAME) {
      final end = min(pos + FRAME, samples.length);
      double totalRms = 0, sibRms = 0;
      for (int i = pos; i < end; i++) {
        totalRms += samples[i] * samples[i];
        sibRms += sibBand[i] * sibBand[i];
      }
      final len = (end - pos).toDouble();
      totalRms = sqrt(totalRms / len);
      sibRms = sqrt(sibRms / len);

      final sibRatio = totalRms > 1e-10 ? sibRms / totalRms : 0.0;
      if (sibRatio > 0.6) {
        final reduction = (params.deEssAmt / 100.0) * ((sibRatio - 0.6) / 0.4).clamp(0.0, 1.0);
        for (int i = pos; i < end; i++) {
          result[i] = (samples[i] - sibBand[i] * reduction).clamp(-1.0, 1.0);
        }
      }
    }
    return result;
  }

  // ─── Algorithm 12: LUFS Normalization ─────────────────────────────────

  static Float32List _normalizeLufs(Float32List samples, double targetLufs) {
    double sumSq = 0;
    for (int i = 0; i < samples.length; i++) {
      sumSq += samples[i] * samples[i];
    }
    final rms = sqrt(sumSq / max(samples.length, 1));
    final currentLufs = 20.0 * log(max(rms, 1e-8)) / ln10;
    final gain = pow(10.0, (targetLufs - currentLufs) / 20.0).toDouble().clamp(0.1, 4.0);

    final result = Float32List(samples.length);
    for (int i = 0; i < samples.length; i++) {
      result[i] = (samples[i] * gain).clamp(-1.0, 1.0);
    }
    return result;
  }
}
