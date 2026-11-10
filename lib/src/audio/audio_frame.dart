import 'dart:math' as math;
import 'dart:typed_data';

import '../time/tempo.dart';
import 'audio_feature_extractor.dart';
import 'audio_feature_key.dart';

/// The audio features at one instant, all in `0..1` except [beatIndex] and
/// [bpm]; every value is 0 without a soundtrack (and the beat fields are 0
/// without a tempo).
final class AudioFrame {
  final Float32List _columns;

  /// Position within the current beat, `0..1`.
  final double beatPhase;

  /// Position within the current 4-beat bar, `0..1`.
  final double barPhase;

  /// 1 on a beat, decaying exponentially (`exp(-6 · beatPhase)`).
  final double beatPulse;

  /// Index of the current beat since the tempo's first beat (negative
  /// before it).
  final int beatIndex;

  /// The tempo, 0 without one.
  final double bpm;

  AudioFrame._(this._columns,
      {this.beatPhase = 0, this.barPhase = 0, this.beatPulse = 0, this.beatIndex = 0, this.bpm = 0});

  /// An all-zero frame.
  static final silent = AudioFrame._(Float32List(AudioFeatureKey.columnCount));

  /// A frame of the [AudioFeatureKey.columnCount] column values (copied),
  /// with the beat fields of [tempo] at [time].
  factory AudioFrame.fromColumns(List<double> columns, {Tempo? tempo, Duration time = Duration.zero}) {
    if (columns.length != AudioFeatureKey.columnCount) {
      throw ArgumentError.value(columns.length, 'columns', 'Must have ${AudioFeatureKey.columnCount} values.');
    }
    final data = Float32List.fromList(columns);
    if (tempo == null) return AudioFrame._(data);
    final position = tempo.beatPosition(time);
    final beat = position.floor();
    final phase = position - beat;
    final barPosition = position / 4;
    return AudioFrame._(
      data,
      beatPhase: phase,
      barPhase: barPosition - barPosition.floor(),
      beatPulse: math.exp(-6 * phase),
      beatIndex: beat,
      bpm: tempo.bpm,
    );
  }

  double get level => _columns[AudioFeatureKey.level.index];
  double get bass => _columns[AudioFeatureKey.bass.index];
  double get mid => _columns[AudioFeatureKey.mid.index];
  double get treble => _columns[AudioFeatureKey.treble.index];
  double get onset => _columns[AudioFeatureKey.onset.index];
  double get peakFrequency => _columns[AudioFeatureKey.peakFrequency.index];

  /// The 16 mel bands, low to high (a read-only view).
  List<double> get bands =>
      Float32List.sublistView(_columns, AudioFeatureKey.firstBand, AudioFeatureKey.columnCount).asUnmodifiableView();

  /// Mel band [index] (`0..15`).
  double band(int index) {
    RangeError.checkValueInInterval(index, 0, AudioFeatureKey.bandCount - 1, 'index');
    return _columns[AudioFeatureKey.firstBand + index];
  }

  /// The spectrum at [position] (`0` = lowest band, `1` = highest),
  /// linearly interpolated between the bands.
  double bandAt(double position) {
    final p = (position.isFinite ? position.clamp(0.0, 1.0) : 0.0) * (AudioFeatureKey.bandCount - 1);
    final low = p.floor();
    final high = math.min(low + 1, AudioFeatureKey.bandCount - 1);
    final f = p - low;
    return band(low) * (1 - f) + band(high) * f;
  }

  static final List<double> _bandCenters = AudioFeatureExtractor.bandCenters;

  static double _mel(double hz) => 2595 * math.log(1 + hz / 700) / math.ln10;

  /// The spectrum at [hz], interpolated on the mel scale between the two
  /// nearest band centers (the lowest/highest band below/above them).
  double bandAtHz(double hz) {
    if (!hz.isFinite) return 0;
    final low = _mel(_bandCenters.first);
    final high = _mel(_bandCenters.last);
    return bandAt((_mel(math.max(0.0, hz)) - low) / (high - low));
  }

  /// The energy of the frequency range `[lowHz, highHz]`: the mean of the
  /// mel bands whose centers fall inside it (the bounds are swapped when
  /// reversed). A range narrower than one band — no center inside it —
  /// takes the spectrum at its geometric middle (see [bandAtHz]). Clamped
  /// to `0..1`.
  double energyBetween(double lowHz, double highHz) {
    if (!lowHz.isFinite || !highHz.isFinite) return 0;
    final low = math.min(lowHz, highHz);
    final high = math.max(lowHz, highHz);
    var sum = 0.0;
    var count = 0;
    for (var i = 0; i < AudioFeatureKey.bandCount; i++) {
      final center = _bandCenters[i];
      if (center >= low && center <= high) {
        sum += band(i);
        count++;
      }
    }
    if (count == 0) return bandAtHz(math.sqrt(math.max(0.0, low) * math.max(0.0, high)));
    return (sum / count).clamp(0.0, 1.0);
  }

  /// The value of [key].
  double operator [](AudioFeatureKey key) => switch (key) {
        AudioFeatureKey.beatPulse => beatPulse,
        AudioFeatureKey.beatPhase => beatPhase,
        AudioFeatureKey.barPhase => barPhase,
        _ => _columns[key.index],
      };
}
