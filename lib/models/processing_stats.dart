import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

class ProcessingStats {
  final double noiseReductionPct;
  final Duration processingTime;
  final String qualityGrade;

  const ProcessingStats({
    required this.noiseReductionPct,
    required this.processingTime,
    required this.qualityGrade,
  });

  static ProcessingStats compute(
    Float32List inputSamples,
    Float32List outputSamples,
    Duration elapsed,
  ) {
    const frameSize = 882; // 20 ms at 44 100 Hz

    List<double> rmsFrames(Float32List s) {
      final frames = <double>[];
      for (int i = 0; i + frameSize <= s.length; i += frameSize) {
        double sum = 0;
        for (int j = i; j < i + frameSize; j++) sum += s[j] * s[j];
        frames.add(sqrt(sum / frameSize));
      }
      return frames;
    }

    final inF  = rmsFrames(inputSamples)..sort();
    final outF = rmsFrames(outputSamples)..sort();

    if (inF.isEmpty || outF.isEmpty) {
      return ProcessingStats(
          noiseReductionPct: 0, processingTime: elapsed, qualityGrade: 'Good');
    }

    final n = max(1, (inF.length  * 0.25).round());
    final m = max(1, (outF.length * 0.25).round());
    final inNoise  = inF .take(n).reduce((a, b) => a + b) / n;
    final outNoise = outF.take(m).reduce((a, b) => a + b) / m;

    final pct = inNoise > 1e-8
        ? ((1 - outNoise / inNoise) * 100).clamp(0.0, 99.0)
        : 0.0;

    return ProcessingStats(
      noiseReductionPct: pct,
      processingTime: elapsed,
      qualityGrade: _grade(pct),
    );
  }

  static String _grade(double pct) {
    if (pct >= 75) return 'Studio Grade';
    if (pct >= 55) return 'Professional';
    if (pct >= 35) return 'Good';
    return 'Fair';
  }
}

class HistoryItem {
  final String name;
  final DateTime date;
  final double noiseReductionPct;

  const HistoryItem({
    required this.name,
    required this.date,
    required this.noiseReductionPct,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'date': date.toIso8601String(),
    'pct': noiseReductionPct,
  };

  factory HistoryItem.fromJson(Map<String, dynamic> j) => HistoryItem(
    name: j['name'] as String,
    date: DateTime.parse(j['date'] as String),
    noiseReductionPct: (j['pct'] as num).toDouble(),
  );

  static HistoryItem? tryParse(String s) {
    try {
      return HistoryItem.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static String serialize(HistoryItem item) => jsonEncode(item.toJson());
}
