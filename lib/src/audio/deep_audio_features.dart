import 'dart:math' as math;
import 'dart:typed_data';

import 'package:equatable/equatable.dart';

/// A stem of the separated mix (the order of the deep analysis' columns).
enum StemKind { drums, bass, other, vocals }

/// Per-stem loudness `0..1` every [hop] (10 ms, the feature matrix's rows),
/// on the file's time. Row `k` describes the audio around `k · hop`.
final class StemLevels {
  /// Row-major `rows × StemKind.values.length`.
  final Float32List data;
  final int rows;
  final Duration hop;

  StemLevels(this.data, {required this.rows, this.hop = const Duration(milliseconds: 10)}) {
    if (data.length != rows * StemKind.values.length) {
      throw ArgumentError.value(data.length, 'data', 'Expected $rows × ${StemKind.values.length} values.');
    }
    if (hop <= Duration.zero) throw ArgumentError.value(hop, 'hop', 'Must be positive.');
  }

  /// The loudness of [stem] in [row] (0 outside the rows).
  double at(int row, StemKind stem) => row < 0 || row >= rows ? 0 : data[row * StemKind.values.length + stem.index];

  /// The loudness of [stem] at file time [time], linearly interpolated
  /// between rows; 0 outside the rows.
  double sampleAt(StemKind stem, Duration time) {
    if (time.isNegative || rows == 0) return 0;
    final position = time.inMicroseconds / hop.inMicroseconds;
    final row = position.floor();
    if (row >= rows) return 0;
    final f = position - row;
    final next = row + 1 < rows ? row + 1 : row;
    return at(row, stem) * (1 - f) + at(next, stem) * f;
  }

  /// The mean loudness of [stem] over file time `[from, to)`.
  double mean(StemKind stem, Duration from, Duration to) {
    final a = (from.inMicroseconds / hop.inMicroseconds).floor().clamp(0, rows);
    final b = (to.inMicroseconds / hop.inMicroseconds).ceil().clamp(0, rows);
    if (b <= a) return 0;
    var sum = 0.0;
    for (var r = a; r < b; r++) {
      sum += data[r * StemKind.values.length + stem.index];
    }
    return sum / (b - a);
  }
}

/// Pitch-class profiles of the harmonic stems: [rowsPerSecond] rows of 12
/// values (C, C♯ … B), each a distribution (all zero in silence), on the
/// file's time.
final class Chroma {
  final Float32List data;
  final int rows;
  final int rowsPerSecond;

  Chroma(this.data, {required this.rows, this.rowsPerSecond = 10}) {
    if (data.length != rows * 12) throw ArgumentError.value(data.length, 'data', 'Expected $rows × 12 values.');
    if (rowsPerSecond <= 0) throw ArgumentError.value(rowsPerSecond, 'rowsPerSecond', 'Must be positive.');
  }

  /// The row at file time [time] (may be outside `0..rows`).
  int rowAt(Duration time) => (time.inMicroseconds * rowsPerSecond / Duration.microsecondsPerSecond).floor();

  /// The summed profile over file time `[from, to)` (the whole file without
  /// bounds).
  List<double> profile({Duration? from, Duration? to}) {
    final a = from == null ? 0 : rowAt(from).clamp(0, rows);
    final b =
        to == null ? rows : (to.inMicroseconds * rowsPerSecond / Duration.microsecondsPerSecond).ceil().clamp(0, rows);
    return _sum(a, b);
  }

  List<double> _sum(int a, int b) {
    final out = List<double>.filled(12, 0);
    for (var r = a; r < b; r++) {
      for (var c = 0; c < 12; c++) {
        out[c] += data[r * 12 + c];
      }
    }
    return out;
  }
}

enum KeyMode { major, minor }

/// A musical key: [tonic] 0 = C … 11 = B.
final class MusicalKey extends Equatable {
  final int tonic;
  final KeyMode mode;

  /// The correlation of the best key profile `-1..1`, minus the runner-up's
  /// (0: ambiguous).
  final double confidence;

  const MusicalKey(this.tonic, this.mode, {this.confidence = 1});

  static const pitchNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

  /// E.g. `A minor`.
  String get name => '${pitchNames[tonic]} ${mode.name}';

  @override
  List<Object?> get props => [tonic, mode, confidence];
}

/// Krumhansl–Kessler key profiles (C major / C minor).
const _majorProfile = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88];
const _minorProfile = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17];

/// The Krumhansl–Schmuckler key of a pitch-class [profile] (12 values): the
/// major or minor key profile, rotated to each tonic, that correlates best.
/// Null for a silent profile.
MusicalKey? estimateKey(List<double> profile) {
  if (profile.length != 12 || profile.every((v) => v <= 0)) return null;
  double correlation(List<double> a, List<double> b, int shift) {
    final ma = a.reduce((x, y) => x + y) / 12;
    final mb = b.reduce((x, y) => x + y) / 12;
    var num = 0.0, da = 0.0, db = 0.0;
    for (var i = 0; i < 12; i++) {
      final x = a[(i + shift) % 12] - ma;
      final y = b[i] - mb;
      num += x * y;
      da += x * x;
      db += y * y;
    }
    final d = math.sqrt(da * db);
    return d == 0 ? 0 : num / d;
  }

  final scores = <(int, KeyMode, double)>[
    for (var tonic = 0; tonic < 12; tonic++) ...[
      (tonic, KeyMode.major, correlation(profile, _majorProfile, tonic)),
      (tonic, KeyMode.minor, correlation(profile, _minorProfile, tonic)),
    ],
  ]..sort((a, b) => b.$3.compareTo(a.$3));
  final (tonic, mode, best) = scores.first;
  return MusicalKey(tonic, mode, confidence: best - scores[1].$3);
}

/// Pitch class [pc] (0 = C … 11 = B) as a hue `0..1` on the circle of
/// fifths (C = 0, G = 1/12, D = 2/12 …): related notes and keys get near
/// hues.
double fifthsHue(int pc) => ((pc % 12) * 7 % 12) / 12;

/// The deep analysis' per-instant features a bake reads (the stem loudness
/// and the harmony), on the file's time like `AudioFeatures`. Encoded by
/// `DeepAudioFeaturesCodec`.
final class DeepAudioFeatures {
  /// Half the window the moving key is estimated over.
  static const keyWindow = Duration(seconds: 4);

  /// Spacing of the moving key estimates.
  static const keyStep = Duration(milliseconds: 500);

  final StemLevels stems;
  final Chroma chroma;

  List<MusicalKey?>? _keys;

  DeepAudioFeatures({required this.stems, required this.chroma});

  /// The loudness of [stem] at file time [time].
  double stem(StemKind stem, Duration time) => stems.sampleAt(stem, time);

  /// The dominant pitch class at [time] (the chroma row and its neighbours,
  /// weighted 1-2-1) and how clearly it dominates (`0..1`); `(null, 0)` in
  /// silence.
  (int?, double) pitchAt(Duration time) {
    final row = chroma.rowAt(time);
    if (row < 0 || row >= chroma.rows) return (null, 0);
    final profile = List<double>.filled(12, 0);
    for (final (r, w) in [(row - 1, 1.0), (row, 2.0), (row + 1, 1.0)]) {
      if (r < 0 || r >= chroma.rows) continue;
      for (var c = 0; c < 12; c++) {
        profile[c] += w * chroma.data[r * 12 + c];
      }
    }
    var best = 0, sum = 0.0;
    for (var c = 0; c < 12; c++) {
      sum += profile[c];
      if (profile[c] > profile[best]) best = c;
    }
    if (sum <= 0) return (null, 0);
    // 0 for a flat profile, 1 for a single pitch class.
    final clarity = ((profile[best] * 12 / sum - 1) / 11).clamp(0.0, 1.0);
    return (best, clarity);
  }

  /// The key around [time] (estimated over `±keyWindow`, on a [keyStep]
  /// grid); null in silence or outside the chroma.
  MusicalKey? keyAt(Duration time) {
    if (time.isNegative) return null;
    final keys = _keys ??= _estimateKeys();
    final i = (time.inMicroseconds / keyStep.inMicroseconds).round();
    return i < keys.length ? keys[i] : null;
  }

  List<MusicalKey?> _estimateKeys() {
    final duration = Duration(microseconds: chroma.rows * Duration.microsecondsPerSecond ~/ chroma.rowsPerSecond);
    final count = duration.inMicroseconds ~/ keyStep.inMicroseconds + 1;
    return [
      for (var i = 0; i < count; i++)
        estimateKey(chroma.profile(from: keyStep * i - keyWindow, to: keyStep * i + keyWindow)),
    ];
  }
}
