import 'package:equatable/equatable.dart';

/// A constant beat grid: the composition's grid used for snapping, and the
/// clock of the beat fields of an `AudioFrame` and of beat bindings.
class Tempo extends Equatable {
  /// Lowest allowed [bpm].
  static const minBpm = 20.0;

  /// Highest allowed [bpm].
  static const maxBpm = 400.0;

  /// Beats per minute.
  final double bpm;

  /// Timeline time of one beat; the grid extends from it in both
  /// directions. It is also a downbeat: bars start every [beatsPerBar]
  /// beats from it.
  final Duration firstBeatOffset;

  /// The meter: beats in one bar (4 = 4/4, 3 = 3/4…).
  final int beatsPerBar;

  /// The default [beatsPerBar].
  static const defaultBeatsPerBar = 4;

  /// Highest allowed [beatsPerBar].
  static const maxBeatsPerBar = 16;

  Tempo({required this.bpm, this.firstBeatOffset = Duration.zero, this.beatsPerBar = defaultBeatsPerBar}) {
    if (!bpm.isFinite || bpm < minBpm || bpm > maxBpm) {
      throw ArgumentError.value(bpm, 'bpm', 'Must be in [$minBpm, $maxBpm].');
    }
    if (beatsPerBar < 1 || beatsPerBar > maxBeatsPerBar) {
      throw ArgumentError.value(beatsPerBar, 'beatsPerBar', 'Must be in [1, $maxBeatsPerBar].');
    }
  }

  /// Time between two beats, in microseconds.
  double get beatIntervalMicroseconds => Duration.microsecondsPerMinute / bpm;

  /// Beats elapsed at [time] since [firstBeatOffset], fractional and
  /// negative before it.
  double beatPosition(Duration time) =>
      (time.inMicroseconds - firstBeatOffset.inMicroseconds) / beatIntervalMicroseconds;

  /// Bars elapsed at [time] since [firstBeatOffset] (fractional).
  double barPosition(Duration time) => beatPosition(time) / beatsPerBar;

  /// The beat nearest to [time], never before the timeline start.
  Duration nearestBeat(Duration time) {
    final interval = beatIntervalMicroseconds;
    final offset = firstBeatOffset.inMicroseconds;
    var n = ((time.inMicroseconds - offset) / interval).round();
    var beat = (offset + n * interval).round();
    while (beat < 0) {
      n++;
      beat = (offset + n * interval).round();
    }
    return Duration(microseconds: beat);
  }

  /// Beats in `[from, to)` that are not before the timeline start.
  Iterable<Duration> beatsBetween(Duration from, Duration to) sync* {
    final interval = beatIntervalMicroseconds;
    final offset = firstBeatOffset.inMicroseconds;
    var n = ((from.inMicroseconds - offset) / interval).floor();
    while (true) {
      final beat = (offset + n * interval).round();
      if (beat >= to.inMicroseconds) return;
      if (beat >= 0 && beat >= from.inMicroseconds) yield Duration(microseconds: beat);
      n++;
    }
  }

  Tempo copyWith({double? bpm, Duration? firstBeatOffset, int? beatsPerBar}) => Tempo(
        bpm: bpm ?? this.bpm,
        firstBeatOffset: firstBeatOffset ?? this.firstBeatOffset,
        beatsPerBar: beatsPerBar ?? this.beatsPerBar,
      );

  @override
  List<Object?> get props => [bpm, firstBeatOffset, beatsPerBar];
}
