import 'package:equatable/equatable.dart';

import 'tempo.dart';

/// The beats of a piece of music as instants: what a beat tracker found
/// (the irregular, real beat positions and the downbeats among them), or a
/// regular grid built from a [Tempo] ([BeatGrid.regular]).
///
/// On the clock of the signal it was detected from. The beat fields of an
/// `AudioFrame` ([beatIndexAt], [phaseAt], [barPhaseAt]) and the beat-based
/// bindings follow it when a bake carries one; outside the first and the
/// last beat the grid is extrapolated with the mean [beatPeriod], so the
/// clock never stops (like a [Tempo], which extends in both directions).
class BeatGrid extends Equatable {
  /// [source] of a grid found by the Beat This! tracker.
  static const sourceBeatThis = 'beat-this';

  /// [source] of a regular grid estimated by autocorrelation (tempo + phase).
  static const sourceAutocorrelation = 'autocorrelation';

  /// Beats per bar assumed when the grid has no downbeats.
  static const defaultBeatsPerBar = 4;

  /// Beat instants, sorted, strictly increasing; at least one.
  final List<Duration> beats;

  /// The downbeats (first beats of bars): a sorted subset of [beats].
  /// Empty when unknown — bars are then counted every
  /// [defaultBeatsPerBar] beats from the first beat.
  final List<Duration> downbeats;

  /// The tempo, beats per minute: the producer's estimate of the mean tempo
  /// over the grid (see [meanBpm] for the beat list's own mean).
  final double bpm;

  /// How sure the detector is, `0..1`.
  final double confidence;

  /// Which detector produced the grid ([sourceBeatThis],
  /// [sourceAutocorrelation] or any other label).
  final String source;

  final Set<int> _downbeatMicros;

  /// The downbeats as beat indices.
  final List<int> _downbeatPositions;

  /// Throws an [ArgumentError] for an empty or unsorted [beats] list, a
  /// downbeat that is not a beat, or a non-finite/non-positive [bpm].
  BeatGrid({
    required List<Duration> beats,
    List<Duration> downbeats = const [],
    required this.bpm,
    this.confidence = 1,
    required this.source,
  })  : beats = List.unmodifiable(beats),
        downbeats = List.unmodifiable(downbeats),
        _downbeatMicros = {for (final d in downbeats) d.inMicroseconds},
        _downbeatPositions = [for (final d in downbeats) _indexAtOrBefore(beats, d.inMicroseconds)] {
    if (beats.isEmpty) throw ArgumentError.value(beats, 'beats', 'Must not be empty.');
    for (var i = 1; i < beats.length; i++) {
      if (beats[i] <= beats[i - 1]) throw ArgumentError.value(beats, 'beats', 'Must be strictly increasing.');
    }
    final beatMicros = {for (final b in beats) b.inMicroseconds};
    for (var i = 0; i < downbeats.length; i++) {
      if (!beatMicros.contains(downbeats[i].inMicroseconds)) {
        throw ArgumentError.value(downbeats, 'downbeats', 'Every downbeat must be a beat.');
      }
      if (i > 0 && downbeats[i] <= downbeats[i - 1]) {
        throw ArgumentError.value(downbeats, 'downbeats', 'Must be strictly increasing.');
      }
    }
    if (!bpm.isFinite || bpm <= 0) throw ArgumentError.value(bpm, 'bpm', 'Must be positive.');
    if (!confidence.isFinite || confidence < 0 || confidence > 1) {
      throw ArgumentError.value(confidence, 'confidence', 'Must be in [0, 1].');
    }
  }

  /// A regular grid of [tempo]'s beats over `[0, length)` (at least the
  /// first beat, even past [length]), every [beatsPerBar]th beat a downbeat
  /// (the first beat of the tempo is one).
  factory BeatGrid.regular(
    Tempo tempo, {
    required Duration length,
    int beatsPerBar = defaultBeatsPerBar,
    double confidence = 1,
    String source = sourceAutocorrelation,
  }) {
    if (beatsPerBar < 1) throw ArgumentError.value(beatsPerBar, 'beatsPerBar', 'Must be positive.');
    final interval = tempo.beatIntervalMicroseconds;
    final offset = tempo.firstBeatOffset.inMicroseconds;
    // The first beat at or after the timeline start.
    var n = offset < 0 ? (-offset / interval).ceil() : 0;
    final beats = <Duration>[];
    final downbeats = <Duration>[];
    while (true) {
      final at = (offset + n * interval).round();
      if (beats.isNotEmpty && at >= length.inMicroseconds) break;
      final beat = Duration(microseconds: at);
      beats.add(beat);
      if (n % beatsPerBar == 0) downbeats.add(beat);
      n++;
    }
    return BeatGrid(beats: beats, downbeats: downbeats, bpm: tempo.bpm, confidence: confidence, source: source);
  }

  /// The mean time between two beats (the span from the first to the last
  /// beat over the number of intervals), or `60 / bpm` with a single beat.
  Duration get beatPeriod {
    if (beats.length < 2) return Duration(microseconds: (Duration.microsecondsPerMinute / bpm).round());
    final span = beats.last.inMicroseconds - beats.first.inMicroseconds;
    return Duration(microseconds: (span / (beats.length - 1)).round());
  }

  /// The mean tempo of the beat list itself (`60 s / beatPeriod`), which
  /// may differ slightly from [bpm].
  double get meanBpm => Duration.microsecondsPerMinute / beatPeriod.inMicroseconds;

  /// Whether [time] is exactly a downbeat of the grid.
  bool isDownbeat(Duration time) => _downbeatMicros.contains(time.inMicroseconds);

  /// Beats elapsed at [time] since the first beat: whole beats plus the
  /// fraction of the way to the next one (linear between consecutive beats,
  /// at the mean [beatPeriod] before the first and after the last beat).
  /// Negative before the first beat. The counterpart of
  /// [Tempo.beatPosition].
  double beatPositionAt(Duration time) {
    final t = time.inMicroseconds;
    final first = beats.first.inMicroseconds;
    final period = beatPeriod.inMicroseconds.toDouble();
    if (t < first) return (t - first) / period;
    final last = beats.last.inMicroseconds;
    if (t >= last) return (beats.length - 1) + (t - last) / period;
    final i = _lastBeatIndexBefore(t);
    final a = beats[i].inMicroseconds;
    final b = beats[i + 1].inMicroseconds;
    return i + (t - a) / (b - a);
  }

  /// Index of the beat at or before [time] (negative before the first
  /// beat, counted at the mean period; past the last beat likewise).
  int beatIndexAt(Duration time) => beatPositionAt(time).floor();

  /// Position within the current beat, `0..1`.
  double phaseAt(Duration time) {
    final position = beatPositionAt(time);
    return position - position.floor();
  }

  /// Bars elapsed at [time] since the first downbeat, fractional (negative
  /// before it): bar `k` spans downbeat `k` to downbeat `k + 1`; the first
  /// bar's length (in beats) continues before the first downbeat and the
  /// last bar's after the last one. Without downbeats, bars are
  /// [defaultBeatsPerBar] beats from the first beat. The counterpart of
  /// `Tempo.beatPosition(t) / 4`.
  double barPositionAt(Duration time) {
    final position = beatPositionAt(time);
    final starts = _downbeatPositions;
    if (starts.isEmpty) return position / defaultBeatsPerBar;
    if (starts.length == 1) return (position - starts.single) / defaultBeatsPerBar;
    if (position < starts.first) return (position - starts.first) / (starts[1] - starts[0]);
    if (position >= starts.last) {
      final length = starts.last - starts[starts.length - 2];
      return (starts.length - 1) + (position - starts.last) / length;
    }
    var i = 0;
    while (i + 1 < starts.length && starts[i + 1] <= position) {
      i++;
    }
    return i + (position - starts[i]) / (starts[i + 1] - starts[i]);
  }

  /// Position within the current bar, `0..1` (the fraction of
  /// [barPositionAt]).
  double barPhaseAt(Duration time) {
    final bar = barPositionAt(time);
    return bar - bar.floor();
  }

  /// The beat nearest to [time] (only real beats, never extrapolated).
  Duration nearestBeat(Duration time) {
    final t = time.inMicroseconds;
    if (t <= beats.first.inMicroseconds) return beats.first;
    if (t >= beats.last.inMicroseconds) return beats.last;
    final i = _lastBeatIndexBefore(t);
    final a = beats[i];
    final b = beats[i + 1];
    return (t - a.inMicroseconds) <= (b.inMicroseconds - t) ? a : b;
  }

  /// The beats in `[from, to)`.
  Iterable<Duration> beatsBetween(Duration from, Duration to) sync* {
    if (to <= from) return;
    var i = from <= beats.first ? 0 : _lastBeatIndexBefore(from.inMicroseconds);
    if (beats[i] < from) i++;
    for (; i < beats.length && beats[i] < to; i++) {
      yield beats[i];
    }
  }

  /// The downbeats in `[from, to)`, or every [defaultBeatsPerBar]th beat
  /// from the first beat when the grid has no downbeats.
  Iterable<Duration> downbeatsBetween(Duration from, Duration to) sync* {
    if (downbeats.isEmpty) {
      var index = 0;
      for (final beat in beats) {
        if (beat >= to) return;
        if (beat >= from && index % defaultBeatsPerBar == 0) yield beat;
        index++;
      }
      return;
    }
    for (final d in downbeats) {
      if (d >= to) return;
      if (d >= from) yield d;
    }
  }

  /// The grid moved by [offset] (the same beats on another clock, e.g.
  /// file time → timeline time).
  BeatGrid shifted(Duration offset) {
    if (offset == Duration.zero) return this;
    return BeatGrid(
      beats: [for (final b in beats) b + offset],
      downbeats: [for (final d in downbeats) d + offset],
      bpm: bpm,
      confidence: confidence,
      source: source,
    );
  }

  /// The grid as a constant [Tempo]: [bpm] (clamped to the tempo range)
  /// from the first beat.
  Tempo toTempo() => Tempo(bpm: bpm.clamp(Tempo.minBpm, Tempo.maxBpm), firstBeatOffset: beats.first);

  int _lastBeatIndexBefore(int micros) => _indexAtOrBefore(beats, micros);

  /// Index of the last of [beats] at or before [micros] (`0` before the
  /// first).
  static int _indexAtOrBefore(List<Duration> beats, int micros) {
    var low = 0;
    var high = beats.length - 1;
    while (low < high) {
      final mid = (low + high + 1) >> 1;
      if (beats[mid].inMicroseconds <= micros) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }

  @override
  List<Object?> get props => [beats, downbeats, bpm, confidence, source];
}

/// JSON form of a [BeatGrid]: `{beatsUs: [int…], downbeatsUs: [int…],
/// bpm, confidence, source}` (microseconds) — the plugin protocol and
/// the hosts' worker payloads use it.
abstract final class BeatGridJson {
  static Map<String, Object?>? toJson(BeatGrid? grid) => grid == null
      ? null
      : {
          'beatsUs': [for (final b in grid.beats) b.inMicroseconds],
          'downbeatsUs': [for (final d in grid.downbeats) d.inMicroseconds],
          'bpm': grid.bpm,
          'confidence': grid.confidence,
          'source': grid.source,
        };

  /// Decodes [toJson]; `null` for `null`, a malformed value or an invalid
  /// grid (so an old or foreign producer never breaks the consumer).
  static BeatGrid? fromJson(Object? json) {
    if (json is! Map) return null;
    final beats = _durations(json['beatsUs']);
    final downbeats = _durations(json['downbeatsUs']);
    final bpm = json['bpm'];
    final confidence = json['confidence'];
    final source = json['source'];
    if (beats == null || downbeats == null || bpm is! num) return null;
    try {
      return BeatGrid(
        beats: beats,
        downbeats: downbeats,
        bpm: bpm.toDouble(),
        confidence: confidence is num ? confidence.toDouble().clamp(0.0, 1.0) : 1,
        source: source is String ? source : 'unknown',
      );
    } on ArgumentError {
      return null;
    }
  }

  static List<Duration>? _durations(Object? value) {
    if (value == null) return const [];
    if (value is! List) return null;
    final out = <Duration>[];
    for (final item in value) {
      if (item is! num || !item.isFinite || item != item.truncateToDouble()) return null;
      out.add(Duration(microseconds: item.toInt()));
    }
    return out;
  }
}
