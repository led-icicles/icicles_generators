import 'dart:math' as math;

import 'package:equatable/equatable.dart';

/// A drum class detected in music.
enum DrumClass {
  /// Bass drum.
  kick,

  /// Snare drum (and claps).
  snare,

  /// Toms (also low percussion and bass notes in dense electronic mixes).
  toms,

  /// Hi-hats, open and closed.
  hihat,

  /// Crash and ride cymbals.
  cymbals;

  static DrumClass? fromName(String? name) => values.where((c) => c.name == name).firstOrNull;
}

/// One drum hit: its onset [time] and [strength] (`0..1`; 1 = among the
/// loudest hits of its class in the song).
final class DrumHit extends Equatable {
  final Duration time;
  final double strength;

  const DrumHit(this.time, this.strength);

  @override
  List<Object?> get props => [time, strength];

  @override
  String toString() => 'DrumHit(${time.inMicroseconds} µs, ${strength.toStringAsFixed(2)})';
}

/// The drum hits of a piece of music per [DrumClass] — what a drum
/// transcription model (ADTOF) found — on the clock of the signal they were
/// detected from (like a `BeatGrid`).
///
/// Hits are events, not levels: an `AudioFrame` reports the hits whose onset
/// falls into its own frame span (`(t − span, t]`, the span the beat triggers
/// use), so every hit reaches exactly one frame of a frame grid at any frame
/// rate.
///
/// Equality compares [source] and a content hash of all hits (cheap for the
/// bake caches; computed once).
final class DrumHits extends Equatable {
  /// [source] of hits found by the ADTOF model.
  static const sourceAdtof = 'adtof';

  /// No hits (no detection).
  static final empty = DrumHits(const {}, source: 'none');

  /// Which detector produced the hits.
  final String source;

  final Map<DrumClass, List<DrumHit>> _hits;
  final Map<DrumClass, List<int>> _micros;
  final int _hash;

  /// Hits per class; each list is sorted by time (stable, so equal times
  /// keep their order) and strengths are clamped to `0..1` (non-finite → 1).
  factory DrumHits(Map<DrumClass, List<DrumHit>> hits, {required String source}) {
    final sorted = <DrumClass, List<DrumHit>>{};
    for (final cls in DrumClass.values) {
      final list = hits[cls];
      if (list == null || list.isEmpty) continue;
      final clean = [
        for (final h in list) DrumHit(h.time, h.strength.isFinite ? h.strength.clamp(0.0, 1.0) : 1.0),
      ];
      _mergeSort(clean, (a, b) => a.time.compareTo(b.time));
      sorted[cls] = List.unmodifiable(clean);
    }
    return DrumHits._(source, sorted);
  }

  DrumHits._(this.source, this._hits)
      : _micros = {
          for (final e in _hits.entries) e.key: [for (final h in e.value) h.time.inMicroseconds]
        },
        _hash = _contentHash(_hits);

  /// The hits of [cls], sorted by time.
  List<DrumHit> of(DrumClass cls) => _hits[cls] ?? const [];

  /// Whether no class has a hit.
  bool get isEmpty => _hits.isEmpty;

  bool get isNotEmpty => !isEmpty;

  /// Number of hits over all classes.
  int get count => _hits.values.fold(0, (sum, l) => sum + l.length);

  /// The strongest hit of [cls] with `from < time <= to`, or `null`.
  DrumHit? strongestIn(DrumClass cls, Duration from, Duration to) {
    final list = _hits[cls];
    if (list == null || to <= from) return null;
    final micros = _micros[cls]!;
    var i = _firstAfter(micros, from.inMicroseconds);
    DrumHit? best;
    final end = to.inMicroseconds;
    for (; i < micros.length && micros[i] <= end; i++) {
      if (best == null || list[i].strength > best.strength) best = list[i];
    }
    return best;
  }

  /// The last hit of [cls] at or before [time], or `null`.
  DrumHit? lastAtOrBefore(DrumClass cls, Duration time) {
    final list = _hits[cls];
    if (list == null) return null;
    final i = _firstAfter(_micros[cls]!, time.inMicroseconds) - 1;
    return i < 0 ? null : list[i];
  }

  /// Index of the first value greater than [micros].
  static int _firstAfter(List<int> sorted, int micros) {
    var lo = 0;
    var hi = sorted.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (sorted[mid] <= micros) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// FNV-1a over the hits, 32-bit arithmetic (safe under dart2js).
  static int _contentHash(Map<DrumClass, List<DrumHit>> hits) {
    var h = 0x811c9dc5;
    void mix(int v) {
      for (var shift = 0; shift < 32; shift += 8) {
        h ^= (v >> shift) & 0xff;
        h = (h * 0x01000193) & 0xffffffff;
      }
    }

    for (final e in hits.entries) {
      mix(e.key.index);
      mix(e.value.length);
      for (final hit in e.value) {
        final us = hit.time.inMicroseconds;
        mix(us & 0xffffffff);
        mix((us / 4294967296).floor() & 0xffffffff);
        mix((hit.strength * 65535).round());
      }
    }
    return h;
  }

  @override
  List<Object?> get props => [source, _hash, count];

  @override
  String toString() =>
      'DrumHits($source, ${[for (final c in DrumClass.values) '${c.name}: ${of(c).length}'].join(', ')})';
}

/// Stable merge sort (List.sort is not guaranteed stable).
void _mergeSort<T>(List<T> list, int Function(T a, T b) compare) {
  if (list.length < 2) return;
  final buffer = List<T>.of(list);
  void sort(int lo, int hi) {
    if (hi - lo < 2) return;
    final mid = (lo + hi) >> 1;
    sort(lo, mid);
    sort(mid, hi);
    var i = lo, j = mid, k = lo;
    while (i < mid && j < hi) {
      buffer[k++] = compare(list[j], list[i]) < 0 ? list[j++] : list[i++];
    }
    while (i < mid) {
      buffer[k++] = list[i++];
    }
    while (j < hi) {
      buffer[k++] = list[j++];
    }
    for (var m = lo; m < hi; m++) {
      list[m] = buffer[m];
    }
  }

  sort(0, list.length);
}

/// JSON form of [DrumHits] — `{source, hits: {kick: {us: [int…], s: [num…]}, …}}`
/// (onset microseconds and strengths, classes without hits omitted); the
/// plugin protocol and the hosts' worker payloads use it.
abstract final class DrumHitsJson {
  static Map<String, Object?>? toJson(DrumHits? drums) => drums == null
      ? null
      : {
          'source': drums.source,
          'hits': {
            for (final cls in DrumClass.values)
              if (drums.of(cls).isNotEmpty)
                cls.name: {
                  'us': [for (final h in drums.of(cls)) h.time.inMicroseconds],
                  's': [for (final h in drums.of(cls)) h.strength],
                },
          },
        };

  /// Decodes [toJson]; `null` for `null` or a malformed value (an old or
  /// foreign producer never breaks the consumer). Unknown classes are
  /// skipped.
  static DrumHits? fromJson(Object? json) {
    if (json is! Map) return null;
    final hits = json['hits'];
    if (hits is! Map) return null;
    final out = <DrumClass, List<DrumHit>>{};
    for (final entry in hits.entries) {
      final cls = DrumClass.fromName(entry.key is String ? entry.key as String : null);
      final value = entry.value;
      if (cls == null) continue;
      if (value is! Map) return null;
      final us = value['us'];
      final s = value['s'];
      if (us is! List || s is! List || us.length != s.length) return null;
      final list = <DrumHit>[];
      for (var i = 0; i < us.length; i++) {
        final t = us[i];
        final strength = s[i];
        if (t is! num || !t.isFinite || strength is! num) return null;
        list.add(DrumHit(Duration(microseconds: t.toInt()), math.max(0, strength.toDouble())));
      }
      out[cls] = list;
    }
    final source = json['source'];
    return DrumHits(out, source: source is String ? source : 'unknown');
  }
}
