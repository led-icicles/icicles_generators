import 'dart:math' as math;

import 'package:equatable/equatable.dart';

/// One user-placed cue: its [time] and [strength] (`0..1`).
final class CueHit extends Equatable {
  final Duration time;
  final double strength;

  const CueHit(this.time, [this.strength = 1]);

  @override
  List<Object?> get props => [time, strength];

  @override
  String toString() => 'CueHit(${time.inMicroseconds} µs, ${strength.toStringAsFixed(2)})';
}

/// User-placed cues — the marks of a timing track (a "cue track" of the
/// editor) that a clip's cue triggers fire on — on the song clock, like
/// `BeatGrid` and `DrumHits` (the host converts them from timeline time).
///
/// Cues are events: an `AudioFrame` reports the cues whose time falls into
/// its own frame span (`(t − span, t]`), so every cue reaches exactly one
/// frame of a frame grid at any frame rate. Unlike the drum triggers, the
/// cue triggers never fall back to the beat clock: no cues, no fire.
///
/// Equality compares a content hash of all cues (cheap for the bake caches;
/// computed once).
final class CueHits extends Equatable {
  /// No cues.
  static final empty = CueHits(const []);

  /// The cues, sorted by time (stable, so equal times keep their order),
  /// strengths clamped to `0..1` (non-finite → 1).
  final List<CueHit> hits;
  final List<int> _micros;
  final int _hash;

  factory CueHits(List<CueHit> hits) {
    final clean = [for (final h in hits) CueHit(h.time, h.strength.isFinite ? h.strength.clamp(0.0, 1.0) : 1.0)];
    _mergeSort(clean, (a, b) => a.time.compareTo(b.time));
    return CueHits._(List.unmodifiable(clean));
  }

  CueHits._(this.hits)
      : _micros = [for (final h in hits) h.time.inMicroseconds],
        _hash = _contentHash(hits);

  bool get isEmpty => hits.isEmpty;

  bool get isNotEmpty => hits.isNotEmpty;

  int get count => hits.length;

  /// The strongest cue with `from < time <= to`, or `null`.
  CueHit? strongestIn(Duration from, Duration to) {
    if (to <= from) return null;
    var i = _firstAfter(_micros, from.inMicroseconds);
    CueHit? best;
    final end = to.inMicroseconds;
    for (; i < _micros.length && _micros[i] <= end; i++) {
      if (best == null || hits[i].strength > best.strength) best = hits[i];
    }
    return best;
  }

  /// The last cue at or before [time], or `null`.
  CueHit? lastAtOrBefore(Duration time) {
    final i = _firstAfter(_micros, time.inMicroseconds) - 1;
    return i < 0 ? null : hits[i];
  }

  /// These cues shifted by [offset] (a clock change).
  CueHits shifted(Duration offset) =>
      offset == Duration.zero ? this : CueHits([for (final h in hits) CueHit(h.time + offset, h.strength)]);

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

  /// FNV-1a over the cues, 32-bit arithmetic (safe under dart2js).
  static int _contentHash(List<CueHit> hits) {
    var h = 0x811c9dc5;
    void mix(int v) {
      for (var shift = 0; shift < 32; shift += 8) {
        h ^= (v >> shift) & 0xff;
        h = (h * 0x01000193) & 0xffffffff;
      }
    }

    mix(hits.length);
    for (final hit in hits) {
      final us = hit.time.inMicroseconds;
      mix(us & 0xffffffff);
      mix((us / 4294967296).floor() & 0xffffffff);
      mix((hit.strength * 65535).round());
    }
    return h;
  }

  @override
  List<Object?> get props => [_hash, count];

  @override
  String toString() => 'CueHits($count)';
}

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

/// JSON form of [CueHits] — `{us: [int…], s: [num…]}` (times in
/// microseconds and strengths); the plugin protocol and the hosts' worker
/// payloads use it.
abstract final class CueHitsJson {
  static Map<String, Object?>? toJson(CueHits? cues) => cues == null
      ? null
      : {
          'us': [for (final h in cues.hits) h.time.inMicroseconds],
          's': [for (final h in cues.hits) h.strength],
        };

  /// Decodes [toJson]; `null` for `null` or a malformed value.
  static CueHits? fromJson(Object? json) {
    if (json is! Map) return null;
    final us = json['us'];
    final s = json['s'];
    if (us is! List || s is! List || us.length != s.length) return null;
    final list = <CueHit>[];
    for (var i = 0; i < us.length; i++) {
      final t = us[i];
      final strength = s[i];
      if (t is! num || !t.isFinite || strength is! num) return null;
      list.add(CueHit(Duration(microseconds: t.toInt()), math.max(0, strength.toDouble())));
    }
    return CueHits(list);
  }
}
