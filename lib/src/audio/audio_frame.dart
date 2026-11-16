import 'dart:math' as math;
import 'dart:typed_data';

import '../time/beat_grid.dart';
import '../time/cue_hits.dart';
import '../time/drum_hits.dart';
import '../time/tempo.dart';
import 'audio_feature_extractor.dart';
import 'audio_feature_key.dart';
import 'deep_audio_features.dart';

/// The audio features at one instant, all in `0..1` except [beatIndex] and
/// [bpm]; every value is 0 without a soundtrack (and the beat fields are 0
/// without a beat clock — a [BeatGrid] or a [Tempo], the drum fields without
/// [DrumHits]).
final class AudioFrame {
  /// Time constant of [drumPulse]'s decay.
  static const drumPulseDecay = Duration(milliseconds: 80);

  final Float32List _columns;

  /// Per [DrumClass]: the strength of the hit in this frame's span (0 =
  /// none), then the pulse; `null` without drum hits.
  final Float32List? _drums;

  /// The cue hit in this frame's span, then the cue pulse; `null` without
  /// cues.
  final Float32List? _cues;

  /// The stems (in [StemKind] order), then pitch hue, pitch clarity and key
  /// hue (−1 for none); `null` without the deep analysis.
  final Float32List? _deep;

  /// Position within the current beat, `0..1`.
  final double beatPhase;

  /// Position within the current 4-beat bar, `0..1`.
  final double barPhase;

  /// 1 on a beat, decaying exponentially (`exp(-6 · beatPhase)`).
  final double beatPulse;

  /// Index of the current beat since the first beat of the grid or tempo
  /// (negative before it).
  final int beatIndex;

  /// The tempo, 0 without a beat clock.
  final double bpm;

  AudioFrame._(this._columns,
      {this.beatPhase = 0,
      this.barPhase = 0,
      this.beatPulse = 0,
      this.beatIndex = 0,
      this.bpm = 0,
      Float32List? drums,
      Float32List? cues,
      Float32List? deep})
      : _drums = drums,
        _cues = cues,
        _deep = deep;

  /// An all-zero frame.
  static final silent = AudioFrame._(Float32List(AudioFeatureKey.columnCount));

  /// A frame of the [AudioFeatureKey.columnCount] column values (copied),
  /// with the beat fields at [time] of [beats] (the real beats and downbeats
  /// of the music) when given, else of the constant [tempo]; all zero
  /// without either.
  ///
  /// The drum fields come from [drums]: [drumHit] reports the strongest hit
  /// of each class with onset in `(time − span, time]` — the frame's own
  /// span, so on a frame grid every hit reaches exactly one frame — and
  /// [drumPulse] decays from the last hit at or before [time]. The cue
  /// fields ([cueHit], [cuePulse]) come from [cues] the same way. The
  /// stem and harmony fields ([stem], [pitchHue], [pitchClarity], [keyHue])
  /// come from [deep] at [time], else from their fallbacks over the columns.
  factory AudioFrame.fromColumns(
    List<double> columns, {
    Tempo? tempo,
    BeatGrid? beats,
    Duration time = Duration.zero,
    DrumHits? drums,
    CueHits? cues,
    DeepAudioFeatures? deep,
    Duration span = Duration.zero,
  }) {
    if (columns.length != AudioFeatureKey.columnCount) {
      throw ArgumentError.value(columns.length, 'columns', 'Must have ${AudioFeatureKey.columnCount} values.');
    }
    final data = Float32List.fromList(columns);
    final drumFields = drums == null || drums.isEmpty ? null : _drumFields(drums, time, span);
    final cueFields = cues == null || cues.isEmpty ? null : _cueFields(cues, time, span);
    final deepFields = deep == null ? null : _deepFields(deep, time);
    if (beats != null) {
      final position = beats.beatPositionAt(time);
      final beat = position.floor();
      final phase = position - beat;
      return AudioFrame._(
        data,
        beatPhase: phase,
        barPhase: beats.barPhaseAt(time),
        beatPulse: math.exp(-6 * phase),
        beatIndex: beat,
        bpm: beats.bpm,
        drums: drumFields,
        cues: cueFields,
        deep: deepFields,
      );
    }
    if (tempo == null) return AudioFrame._(data, drums: drumFields, cues: cueFields, deep: deepFields);
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
      drums: drumFields,
      cues: cueFields,
      deep: deepFields,
    );
  }

  static const _stemCount = 4; // StemKind.values.length

  static Float32List _deepFields(DeepAudioFeatures deep, Duration time) {
    final out = Float32List(_stemCount + 3);
    for (final stem in StemKind.values) {
      out[stem.index] = deep.stem(stem, time).clamp(0.0, 1.0);
    }
    final (pc, clarity) = deep.pitchAt(time);
    out[_stemCount] = pc == null ? -1 : fifthsHue(pc);
    out[_stemCount + 1] = clarity;
    final key = deep.keyAt(time);
    out[_stemCount + 2] = key == null ? -1 : fifthsHue(key.tonic);
    return out;
  }

  /// Whether the frame carries the deep analysis (separated stems and
  /// harmony); without it [stem], [pitchHue] and [keyHue] are approximations.
  bool get hasDeep => _deep != null;

  /// The loudness of [kind]'s stem (`0..1`). Without the deep analysis
  /// approximated from the mix: vocals by the 300–3400 Hz energy, drums by
  /// [onset], bass by [bass], the rest by [mid].
  double stem(StemKind kind) {
    final d = _deep;
    if (d != null) return d[kind.index];
    return switch (kind) {
      StemKind.vocals => energyBetween(300, 3400),
      StemKind.drums => onset,
      StemKind.bass => bass,
      StemKind.other => mid,
    };
  }

  /// The melody's dominant pitch class as a hue on the circle of fifths
  /// (see [AudioFeatureKey.pitchHue]); without the deep analysis (or in
  /// silence) the loudest frequency [peakFrequency].
  double get pitchHue {
    final v = _deep?[_stemCount] ?? -1;
    return v < 0 ? peakFrequency : v;
  }

  /// How clearly one pitch class dominates (`0..1`), 0 without the deep
  /// analysis.
  double get pitchClarity => _deep?[_stemCount + 1] ?? 0;

  /// The key's tonic around now as a hue on the circle of fifths, 0 without
  /// the deep analysis (or in silence).
  double get keyHue {
    final v = _deep?[_stemCount + 2] ?? -1;
    return v < 0 ? 0 : v;
  }

  static Float32List _cueFields(CueHits cues, Duration time, Duration span) {
    final out = Float32List(2);
    out[0] = cues.strongestIn(time - span, time)?.strength ?? 0;
    final last = cues.lastAtOrBefore(time);
    if (last != null) {
      out[1] = last.strength * math.exp(-(time - last.time).inMicroseconds / drumPulseDecay.inMicroseconds);
    }
    return out;
  }

  /// Whether the frame carries cues (the clip has a cue track with cues).
  bool get hasCues => _cues != null;

  /// The strength (`0..1`) of the strongest cue in this frame's span, 0
  /// without one.
  double get cueHit => _cues?[0] ?? 0;

  /// The strength of the last cue, decaying with [drumPulseDecay] (0 before
  /// the first cue and without cues).
  double get cuePulse => _cues?[1] ?? 0;

  static Float32List _drumFields(DrumHits drums, Duration time, Duration span) {
    const n = 5; // DrumClass.values.length
    final out = Float32List(2 * n);
    final decay = drumPulseDecay.inMicroseconds.toDouble();
    for (final cls in DrumClass.values) {
      out[cls.index] = drums.strongestIn(cls, time - span, time)?.strength ?? 0;
      final last = drums.lastAtOrBefore(cls, time);
      if (last != null) {
        out[n + cls.index] = last.strength * math.exp(-(time - last.time).inMicroseconds / decay);
      }
    }
    return out;
  }

  /// Whether the frame carries drum hits (the analysis found drums).
  bool get hasDrums => _drums != null;

  /// The strength (`0..1`) of the strongest hit of [cls] in this frame's
  /// span, 0 without one (see [AudioFrame.fromColumns]).
  double drumHit(DrumClass cls) => _drums?[cls.index] ?? 0;

  /// The strongest hit of any class in this frame's span.
  double get anyDrumHit {
    final d = _drums;
    if (d == null) return 0;
    var best = 0.0;
    for (var i = 0; i < DrumClass.values.length; i++) {
      best = math.max(best, d[i]);
    }
    return best;
  }

  /// The strength of the last hit of [cls], decaying with [drumPulseDecay]
  /// (0 before the first hit and without drum hits).
  double drumPulse(DrumClass cls) => _drums?[DrumClass.values.length + cls.index] ?? 0;

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
        AudioFeatureKey.kickPulse => drumPulse(DrumClass.kick),
        AudioFeatureKey.snarePulse => drumPulse(DrumClass.snare),
        AudioFeatureKey.hihatPulse => drumPulse(DrumClass.hihat),
        AudioFeatureKey.cuePulse => cuePulse,
        AudioFeatureKey.vocals => stem(StemKind.vocals),
        AudioFeatureKey.drumsStem => stem(StemKind.drums),
        AudioFeatureKey.bassStem => stem(StemKind.bass),
        AudioFeatureKey.otherStem => stem(StemKind.other),
        AudioFeatureKey.pitchHue => pitchHue,
        AudioFeatureKey.pitchClarity => pitchClarity,
        AudioFeatureKey.keyHue => keyHue,
        _ => _columns[key.index],
      };
}
