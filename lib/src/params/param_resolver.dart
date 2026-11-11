import 'dart:math' as math;
import 'dart:typed_data';

import 'package:icicles_animation_dart/icicles_animation_dart.dart';

import '../audio/audio_feature_key.dart';
import '../audio/audio_features.dart';
import '../audio/audio_frame.dart';
import '../time/beat_grid.dart';
import '../time/tempo.dart';
import '../util/color.dart';
import 'param_binding.dart';
import 'param_spec.dart';
import 'param_values.dart';

/// The BPM of the beat-based bindings when the request has no beat clock
/// (neither beats nor a tempo; then the beats are counted on clip time from
/// the clip start).
const fallbackBpm = 120.0;

/// Evaluates the parameter bindings frame by frame on a frame grid.
///
/// Frame `i` is at generator time `framerate.frameStart(i)`, which is song
/// time `audioOrigin + framerate.frameStart(i)` on the clock of [audio],
/// [beats] and [tempo]. The beat clock is [beats] (the real beats) when
/// given, else [tempo]. Audio followers, random glides and envelopes are stepped once
/// per frame, so [at] is meant to be called in order; asking for an earlier
/// frame replays from frame 0 and a later one steps through the frames in
/// between, so the result never depends on the call pattern.
///
/// [macros] are the composition's named global bindings, evaluated every
/// frame before the parameters so a [MacroBinding] can read them (a macro
/// reading another macro resolves to nothing). [seed] seeds the random
/// bindings without a seed of their own (the setup's seed in a bake).
final class ParamResolver {
  final List<ParamSpec> specs;

  /// The salvaged bindings, one per spec.
  final Map<String, ParamBinding> bindings;
  final Map<String, ParamBinding> macros;
  final Framerate framerate;

  /// Frames of the bake (the end of ramps).
  final int frameCount;
  final AudioFeatures? audio;
  final Tempo? tempo;
  final BeatGrid? beats;
  final Duration audioOrigin;
  final int seed;

  static final _silentColumns = Float32List(AudioFeatureKey.columnCount);

  /// Per-binding state (followers, envelopes, trigger edges) keyed by the
  /// binding's path.
  final Map<String, Object> _state = {};
  final Map<String, Object?> _macroValues = {};
  int _next = 0;
  int _lastIndex = -1;
  ParamValues? _lastValues;
  AudioFrame _lastAudio = AudioFrame.silent;

  ParamResolver({
    required this.specs,
    required Map<String, ParamBinding> bindings,
    required this.framerate,
    required this.frameCount,
    this.audio,
    this.tempo,
    this.beats,
    this.audioOrigin = Duration.zero,
    Map<String, ParamBinding> macros = const {},
    this.seed = 0,
  })  : bindings = salvageBindings(specs, bindings),
        macros = Map.unmodifiable(macros);

  /// The values at frame [frameIndex].
  ParamValues at(int frameIndex) {
    _advanceTo(frameIndex);
    return _lastValues!;
  }

  /// The audio features (with the beat fields) at frame [frameIndex].
  AudioFrame audioAt(int frameIndex) {
    _advanceTo(frameIndex);
    return _lastAudio;
  }

  /// Forgets the stepped state: the next [at] replays from frame 0 (what
  /// asking for an earlier frame does implicitly).
  void reset() {
    _state.clear();
    _macroValues.clear();
    _next = 0;
    _lastIndex = -1;
    _lastValues = null;
    _lastAudio = AudioFrame.silent;
  }

  void _advanceTo(int frameIndex) {
    RangeError.checkNotNegative(frameIndex, 'frameIndex');
    if (frameIndex == _lastIndex && _lastValues != null) return;
    if (frameIndex < _next) reset();
    while (_next <= frameIndex) {
      _step(_next++);
    }
  }

  void _step(int index) {
    final start = framerate.frameStart(index);
    final songTime = audioOrigin + start;
    final features = audio;
    final frame = features != null
        ? features.sampleAt(songTime, tempo: tempo, beats: beats)
        : (!_hasBeatClock
            ? AudioFrame.silent
            : AudioFrame.fromColumns(_silentColumns, tempo: tempo, beats: beats, time: songTime));
    final dt = index == 0 ? framerate.frameDuration(0) : start - framerate.frameStart(index - 1);
    final f = _Frame(index: index, start: start, songTime: songTime, dt: dt, audio: frame);
    _macroValues.clear();
    for (final MapEntry(key: id, value: binding) in macros.entries) {
      _macroValues[id] = _evaluate(binding, '@$id', f, _unitRange, inMacro: true);
    }
    final values = <String, Object>{};
    for (final spec in specs) {
      final binding = bindings[spec.id]!;
      values[spec.id] = switch (spec) {
        NumberParam(:final min, :final max, :final defaultValue) => spec.numericValue(
            _asNumber(_evaluate(binding, spec.id, f, (min: min, max: max))) ?? defaultValue,
          ),
        IntParam(:final min, :final max, :final defaultValue) => spec.numericValue(
            _asNumber(_evaluate(binding, spec.id, f, (min: min.toDouble(), max: max.toDouble()))) ??
                defaultValue.toDouble(),
          ),
        ColorParam(:final defaultValue) => switch (_evaluate(binding, spec.id, f, _unitRange)) {
            final Color color => color,
            _ => defaultValue,
          },
        _ => switch (binding) {
            ConstantBinding(:final value) => value,
            _ => switch (spec.defaultBinding) {
                ConstantBinding(:final value) => value,
                _ => throw StateError('${spec.id} has no constant default.'),
              },
          },
      };
    }
    _lastIndex = index;
    _lastValues = ParamValues(values);
    _lastAudio = frame;
  }

  static const _unitRange = (min: 0.0, max: 1.0);

  static double? _asNumber(Object? value) => value is num ? value.toDouble() : null;

  /// The value of [binding] at frame [f]: a `double`, a [Color], another
  /// constant, or `null` when it cannot be resolved (a missing macro).
  /// [range] is the parameter's range (a stack's unit of depth, the
  /// normalization range of constant, keyframe and macro sources).
  Object? _evaluate(ParamBinding binding, String key, _Frame f, _Range range, {bool inMacro = false}) =>
      switch (binding) {
        ConstantBinding(:final value) => value,
        AudioBinding() => _audioValue(key, binding, f),
        BeatBinding() => _beatValue(binding, f.songTime),
        RampBinding() => _rampValue(binding, f.index),
        KeyframeBinding() => _keyframeValue(binding, f),
        RandomBinding() => _randomValue(key, binding, f),
        StepBinding() => _stepValue(binding, f),
        EnvelopeBinding() => _envelopeValue(key, binding, f),
        StackedBinding() => _stackedValue(key, binding, f, range, inMacro),
        MacroBinding(:final macroId) => inMacro ? null : _macroValues[macroId],
      };

  double _audioValue(String key, AudioBinding binding, _Frame f) {
    final available = binding.feature.isColumn ? audio != null : _hasBeatClock;
    if (!available) return binding.min;
    final input = f.audio[binding.feature].clamp(0.0, 1.0);
    final smoothed = _follow((_state[key] as double?) ?? 0, input, binding, f.dt);
    _state[key] = smoothed;
    var v = math.pow(smoothed, binding.curve).toDouble();
    if (binding.invert) v = 1 - v;
    return binding.min + (binding.max - binding.min) * v;
  }

  static double _follow(double previous, double input, AudioBinding binding, Duration dt) {
    final time = input > previous ? binding.attack : binding.release;
    if (time <= Duration.zero) return input;
    final k = 1 - math.exp(-dt.inMicroseconds / time.inMicroseconds);
    return previous + (input - previous) * k;
  }

  double _beatValue(BeatBinding binding, Duration songTime) {
    final grid = _gridPosition(songTime);
    if (grid == null) return binding.min;
    final position = grid / binding.periodBeats + binding.phase;
    final p = position - position.floor();
    return binding.min + (binding.max - binding.min) * binding.shape.at(p);
  }

  double _rampValue(RampBinding binding, int index) {
    final progress = frameCount <= 1 ? 0.0 : (index / (frameCount - 1)).clamp(0.0, 1.0);
    return binding.from + (binding.to - binding.from) * binding.curve.curve.transform(progress);
  }

  // Beat clocks.

  bool get _hasBeatClock => beats != null || tempo != null;

  /// The BPM of the beat clock: the beats', else the tempo's, else
  /// [fallbackBpm].
  double get _clockBpm => beats?.bpm ?? tempo?.bpm ?? fallbackBpm;

  /// Beats on the song's beat clock at [songTime] (the real beats, else the
  /// tempo), or null without a clock.
  double? _gridPosition(Duration songTime) {
    final grid = beats;
    if (grid != null) return grid.beatPositionAt(songTime);
    return tempo?.beatPosition(songTime);
  }

  /// Beats on the song's beat clock at [songTime], or at [fallbackBpm] on
  /// clip time [start] without one — what the random, step and envelope
  /// bindings count beats and bars with.
  double _gridBeats(Duration songTime, Duration start) => _gridPosition(songTime) ?? _seconds(start) * fallbackBpm / 60;

  /// Bars on the song's beat clock at [songTime] (between the real
  /// downbeats, else every 4 beats of the tempo), or at [fallbackBpm] on
  /// clip time without one — what the per-bar random, step and bar-trigger
  /// bindings count bars with.
  double _gridBars(Duration songTime, Duration start) =>
      beats?.barPositionAt(songTime) ?? _gridBeats(songTime, start) / 4;

  /// Clip-local beats at [start]: seconds × bpm / 60.
  double _clipBeats(Duration start) => _seconds(start) * _clockBpm / 60;

  /// Seconds per beat of the grid.
  double get _beatSeconds => 60 / _clockBpm;

  static double _seconds(Duration d) => d.inMicroseconds / Duration.microsecondsPerSecond;

  // Keyframes.

  Object _keyframeValue(KeyframeBinding binding, _Frame f) {
    final keys = binding.keys;
    var t = binding.timeBase == KeyTime.beats ? _clipBeats(f.start) : _seconds(f.start);
    final first = keys.first, last = keys.last;
    if (binding.loop && keys.length > 1) {
      final span = last.at - first.at;
      if (span > 0) t = first.at + (t - first.at) % span;
    }
    if (t < first.at) return first.value;
    if (t >= last.at) return last.value;
    // The last key at or before t, and the first key after it.
    var i = 0;
    while (i + 1 < keys.length && keys[i + 1].at <= t) {
      i++;
    }
    final from = keys[i];
    final to = keys[i + 1];
    final span = to.at - from.at;
    final p = span <= 0 ? 1.0 : (t - from.at) / span;
    return _lerpKey(from.value, to.value, from.easing.transform(p));
  }

  static Object _lerpKey(Object a, Object b, double p) {
    if (a is num && b is num) return a + (b - a) * p;
    if (a is Color && b is Color) return lerpHsv(a, b, p);
    return p < 1 ? a : b;
  }

  // Random.

  double _randomValue(String key, RandomBinding binding, _Frame f) {
    final (int hold, double holdSeconds) = switch (binding.mode) {
      RandomMode.perBeat => (_gridBeats(f.songTime, f.start).floor(), _beatSeconds),
      RandomMode.perBar => (_gridBars(f.songTime, f.start).floor(), 4 * _beatSeconds),
      RandomMode.perTime => (
          f.start.inMicroseconds ~/ binding.interval.inMicroseconds,
          _seconds(binding.interval),
        ),
      RandomMode.perFrame => (f.index, _seconds(f.dt)),
    };
    final u = uniformHash(binding.seed ?? seed, hold);
    final target = binding.min + (binding.max - binding.min) * u;
    final previous = _state[key] as double?;
    final tau = binding.smooth * holdSeconds;
    final double value;
    if (previous == null || tau <= 0) {
      value = target;
    } else {
      final k = 1 - math.exp(-_seconds(f.dt) / tau);
      value = previous + (target - previous) * k;
    }
    _state[key] = value;
    return value;
  }

  // Steps.

  double _stepValue(StepBinding binding, _Frame f) {
    final n = binding.steps.length;
    final position = _gridBars(f.songTime, f.start) * binding.stepsPerBar;
    final global = position.floor();
    final phase = position - global;
    final i = global % n;
    var level = binding.steps[i];
    if (binding.smooth) {
      final next = binding.steps[(i + 1) % n];
      level += (next - level) * phase;
    }
    if (binding.gate < 1 && phase >= binding.gate) return binding.min;
    return binding.min + (binding.max - binding.min) * level;
  }

  // Envelopes.

  double _envelopeValue(String key, EnvelopeBinding binding, _Frame f) {
    final env = (_state[key] as _Envelope?) ?? _Envelope();
    _state[key] = env;
    if (_fires(key, binding.trigger, f) && (binding.retrigger || !env.active)) {
      env.from = env.active ? env.level(binding) : 0.0;
      env.t = 0;
      env.active = true;
    }
    final level = env.active ? env.level(binding) : 0.0;
    if (env.active) {
      env.t += _seconds(f.dt);
      if (env.t >= env.total(binding)) env.active = false;
    }
    return binding.min + (binding.max - binding.min) * level;
  }

  bool _fires(String key, EnvelopeTrigger trigger, _Frame f) {
    switch (trigger) {
      case BeatTrigger():
        return _gridBeats(f.songTime, f.start).floor() != _gridBeats(f.songTime - f.dt, f.start - f.dt).floor();
      case BarTrigger():
        return _gridBars(f.songTime, f.start).floor() != _gridBars(f.songTime - f.dt, f.start - f.dt).floor();
      case OnsetTrigger(:final threshold):
        return _risingEdge('$key/edge', audio == null ? 0.0 : f.audio.onset, threshold);
      case RangeHitTrigger(:final lowHz, :final highHz, :final threshold):
        return _risingEdge('$key/edge', audio == null ? 0.0 : f.audio.energyBetween(lowHz, highHz), threshold);
    }
  }

  bool _risingEdge(String key, double value, double threshold) {
    final previous = (_state[key] as double?) ?? 0.0;
    _state[key] = value;
    return previous < threshold && value >= threshold;
  }

  // Stacking.

  Object? _stackedValue(String key, StackedBinding binding, _Frame f, _Range range, bool inMacro) {
    final base = _asNumber(_evaluate(binding.base, '$key/base', f, range, inMacro: inMacro));
    if (base == null) return null;
    var value = base;
    final span = range.max - range.min;
    for (var i = 0; i < binding.modulators.length; i++) {
      final m = binding.modulators[i];
      final source = _asNumber(_evaluate(m.source, '$key/m$i', f, range, inMacro: inMacro));
      if (source == null) continue;
      final (lo, hi) = _sourceRange(m.source, range);
      final norm = hi == lo ? 0.0 : ((source - lo) / (hi - lo)).clamp(0.0, 1.0);
      var depth = m.depth;
      if (m.depthBinding case final depthBinding?) {
        final d = _asNumber(_evaluate(depthBinding, '$key/m$i/depth', f, _depthRange, inMacro: inMacro));
        if (d != null) depth = d.clamp(-1.0, 1.0);
      }
      value = switch (m.mode) {
        ModulatorMode.add => value + depth * span * norm,
        ModulatorMode.multiply => value * (1 - depth * (1 - norm)),
      };
    }
    return value;
  }

  static const _depthRange = (min: -1.0, max: 1.0);

  /// The range a modulator source is normalized across: its own for the
  /// kinds that have one, the parameter's for the rest.
  static (double, double) _sourceRange(ParamBinding source, _Range range) => switch (source) {
        AudioBinding(:final min, :final max) => (min, max),
        BeatBinding(:final min, :final max) => (min, max),
        RandomBinding(:final min, :final max) => (min, max),
        StepBinding(:final min, :final max) => (min, max),
        EnvelopeBinding(:final min, :final max) => (min, max),
        RampBinding(:final from, :final to) => (math.min(from, to), math.max(from, to)),
        _ => (range.min, range.max),
      };
}

typedef _Range = ({double min, double max});

final class _Frame {
  final int index;
  final Duration start;
  final Duration songTime;
  final Duration dt;
  final AudioFrame audio;

  const _Frame({
    required this.index,
    required this.start,
    required this.songTime,
    required this.dt,
    required this.audio,
  });
}

final class _Envelope {
  bool active = false;

  /// Seconds since the trigger.
  double t = 0;

  /// The level the attack started from.
  double from = 0;

  double total(EnvelopeBinding b) =>
      _secondsOf(b.attack) + _secondsOf(b.decay) + _secondsOf(b.sustain) + _secondsOf(b.release);

  double level(EnvelopeBinding b) {
    final a = _secondsOf(b.attack), d = _secondsOf(b.decay), s = _secondsOf(b.sustain), r = _secondsOf(b.release);
    var x = t;
    if (x < a) return from + (1 - from) * (x / a);
    x -= a;
    if (x < d) return 1 + (b.sustainLevel - 1) * (x / d);
    x -= d;
    if (x < s) return b.sustainLevel;
    x -= s;
    if (x < r) return b.sustainLevel * (1 - x / r);
    return 0;
  }

  static double _secondsOf(Duration d) => d.inMicroseconds / Duration.microsecondsPerSecond;
}

/// A uniform value in `[0, 1)` from [seed] and [index] — what a
/// [RandomBinding] draws for hold [index]. A 32-bit integer mix (murmur3's
/// finalizer over both words of each argument), the same on every platform.
double uniformHash(int seed, int index) {
  var h = (seed & 0xFFFFFFFF) ^ 0x9E3779B9;
  h = _mix(h ^ (index & 0xFFFFFFFF));
  h = _mix(h ^ ((index >> 32) & 0xFFFFFFFF));
  h = _mix(h ^ ((seed >> 32) & 0xFFFFFFFF));
  return h / 4294967296.0;
}

int _mix(int h) {
  h &= 0xFFFFFFFF;
  h ^= h >>> 16;
  h = _mul32(h, 0x85EBCA6B);
  h ^= h >>> 13;
  h = _mul32(h, 0xC2B2AE35);
  h ^= h >>> 16;
  return h & 0xFFFFFFFF;
}

/// `a * b mod 2^32` without exceeding 53 bits in any intermediate.
int _mul32(int a, int b) {
  final aLow = a & 0xFFFF, aHigh = (a >>> 16) & 0xFFFF;
  final bLow = b & 0xFFFF, bHigh = (b >>> 16) & 0xFFFF;
  final low = aLow * bLow;
  final cross = (aHigh * bLow + aLow * bHigh) & 0xFFFF;
  return (low + (cross << 16)) & 0xFFFFFFFF;
}

/// [a] to [b] by [p] (clamped) in HSV along the shorter hue path (a grey
/// takes the other color's hue, black also its saturation, so a color fades
/// to black without greying), opaque — how color keyframes interpolate.
Color lerpHsv(Color a, Color b, double p) {
  final f = p.isFinite ? p.clamp(0.0, 1.0) : 0.0;
  final ha = hsvOf(a), hb = hsvOf(b);
  final satA = ha.value <= 0 ? hb.saturation : ha.saturation;
  final satB = hb.value <= 0 ? satA : hb.saturation;
  final hueA = ha.saturation <= 0 ? hb.hue : ha.hue;
  final hueB = hb.saturation <= 0 ? hueA : hb.hue;
  var delta = hueB - hueA;
  if (delta > 0.5) delta -= 1;
  if (delta < -0.5) delta += 1;
  return hsv(hueA + delta * f, satA + (satB - satA) * f, ha.value + (hb.value - ha.value) * f);
}
