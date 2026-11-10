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
  /// directions.
  final Duration firstBeatOffset;

  Tempo({required this.bpm, this.firstBeatOffset = Duration.zero}) {
    if (!bpm.isFinite || bpm < minBpm || bpm > maxBpm) {
      throw ArgumentError.value(bpm, 'bpm', 'Must be in [$minBpm, $maxBpm].');
    }
  }

  /// Time between two beats, in microseconds.
  double get beatIntervalMicroseconds => Duration.microsecondsPerMinute / bpm;

  /// Beats elapsed at [time] since [firstBeatOffset], fractional and
  /// negative before it.
  double beatPosition(Duration time) =>
      (time.inMicroseconds - firstBeatOffset.inMicroseconds) / beatIntervalMicroseconds;

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

  Tempo copyWith({double? bpm, Duration? firstBeatOffset}) =>
      Tempo(bpm: bpm ?? this.bpm, firstBeatOffset: firstBeatOffset ?? this.firstBeatOffset);

  @override
  List<Object?> get props => [bpm, firstBeatOffset];
}
