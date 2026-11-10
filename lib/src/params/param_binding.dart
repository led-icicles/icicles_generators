import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:icicles_animation_dart/icicles_animation_dart.dart';

import '../audio/audio_feature_key.dart';
import 'easing.dart';

export 'easing.dart';

/// How a parameter gets its value at each frame.
///
/// Only [ConstantBinding] fits every parameter type; the modulators
/// ([AudioBinding], [BeatBinding], [RampBinding], [RandomBinding],
/// [StepBinding], [EnvelopeBinding], [StackedBinding]) drive number and
/// integer parameters, their `min`/`max`/`from`/`to` in the parameter's
/// units; [KeyframeBinding] and [MacroBinding] also drive color parameters.
/// Encoded by `ParamBindingJson`.
sealed class ParamBinding extends Equatable {
  const ParamBinding();

  /// Whether the binding reads the analysed audio.
  bool get usesAudioFeatures => false;

  /// Whether the binding reads the tempo (beat clock).
  bool get usesTempo => false;
}

/// A fixed value: a `double` (number), an `int` (integer), a `bool`, a
/// `String` (choice id), a [Color] or a `Palette`.
final class ConstantBinding extends ParamBinding {
  final Object value;

  const ConstantBinding(this.value);

  @override
  List<Object?> get props => [value];
}

/// A number following an audio feature: the feature (`0..1`) is smoothed by
/// a one-pole follower ([attack] while rising, [release] while falling),
/// shaped by `pow(v, curve)`, optionally inverted, and mapped to
/// [min]..[max].
///
/// Evaluates to [min] when the feature is unavailable (no soundtrack, or no
/// tempo for the beat keys).
final class AudioBinding extends ParamBinding {
  /// Longest [attack]/[release].
  static const maxSmoothing = Duration(seconds: 10);

  /// Range of [curve].
  static const minCurve = 0.1;
  static const maxCurve = 10.0;

  final AudioFeatureKey feature;
  final double min;
  final double max;
  final Duration attack;
  final Duration release;
  final double curve;
  final bool invert;

  const AudioBinding({
    required this.feature,
    required this.min,
    required this.max,
    this.attack = const Duration(milliseconds: 10),
    this.release = const Duration(milliseconds: 200),
    this.curve = 1.0,
    this.invert = false,
  });

  @override
  bool get usesAudioFeatures => feature.isColumn;

  @override
  bool get usesTempo => feature.isBeat;

  /// This binding with its fields in their valid ranges.
  AudioBinding normalized() => AudioBinding(
        feature: feature,
        min: _finite(min),
        max: _finite(max),
        attack: _clampDuration(attack, maxSmoothing),
        release: _clampDuration(release, maxSmoothing),
        curve: curve.isFinite ? curve.clamp(minCurve, maxCurve) : 1.0,
        invert: invert,
      );

  AudioBinding copyWith({
    AudioFeatureKey? feature,
    double? min,
    double? max,
    Duration? attack,
    Duration? release,
    double? curve,
    bool? invert,
  }) =>
      AudioBinding(
        feature: feature ?? this.feature,
        min: min ?? this.min,
        max: max ?? this.max,
        attack: attack ?? this.attack,
        release: release ?? this.release,
        curve: curve ?? this.curve,
        invert: invert ?? this.invert,
      );

  @override
  List<Object?> get props => [feature, min, max, attack, release, curve, invert];
}

/// Shape of a [BeatBinding] over one period (`p` = 0 on the beat).
enum BeatShape {
  /// `exp(-6p)`: a hit on the beat, decaying.
  pulse,

  /// `p`: a ramp up, restarting on the beat.
  saw,

  /// `(1 + cos 2πp) / 2`: highest on the beat.
  sine,

  /// 1 for the first half of the period, 0 for the second.
  square;

  /// The shape's value (`0..1`) at phase [p] (`0..1`).
  double at(double p) => switch (this) {
        BeatShape.pulse => math.exp(-6 * p),
        BeatShape.saw => p,
        BeatShape.sine => (1 + math.cos(2 * math.pi * p)) / 2,
        BeatShape.square => p < 0.5 ? 1.0 : 0.0,
      };
}

/// A number following the tempo (an LFO synced to beats): [shape] over
/// [periodBeats] beats, shifted by [phase] (of a period), mapped to
/// [min]..[max]. Evaluates to [min] without a tempo.
final class BeatBinding extends ParamBinding {
  static const minPeriodBeats = 0.25;
  static const maxPeriodBeats = 16.0;

  final BeatShape shape;
  final double periodBeats;
  final double phase;
  final double min;
  final double max;

  const BeatBinding({
    required this.shape,
    this.periodBeats = 1,
    this.phase = 0,
    required this.min,
    required this.max,
  });

  @override
  bool get usesTempo => true;

  /// This binding with its fields in their valid ranges.
  BeatBinding normalized() {
    var p = phase.isFinite ? phase % 1.0 : 0.0;
    if (p < 0) p += 1;
    return BeatBinding(
      shape: shape,
      periodBeats: periodBeats.isFinite ? periodBeats.clamp(minPeriodBeats, maxPeriodBeats) : 1,
      phase: p,
      min: _finite(min),
      max: _finite(max),
    );
  }

  @override
  List<Object?> get props => [shape, periodBeats, phase, min, max];
}

/// Easing of a [RampBinding], one of the library's [Curves].
enum RampCurve {
  linear,
  sinIn,
  sinOut,
  sinInOut,
  quadIn,
  quadOut,
  quadInOut,
  cubicIn,
  cubicOut,
  cubicInOut,
  expIn,
  expOut,
  expInOut,
  circleIn,
  circleOut,
  circleInOut,
  bounceOut,
  elasticOut;

  Curve get curve => switch (this) {
        RampCurve.linear => Curves.linear,
        RampCurve.sinIn => Curves.sinIn,
        RampCurve.sinOut => Curves.sinOut,
        RampCurve.sinInOut => Curves.sinInOut,
        RampCurve.quadIn => Curves.quadIn,
        RampCurve.quadOut => Curves.quadOut,
        RampCurve.quadInOut => Curves.quadInOut,
        RampCurve.cubicIn => Curves.cubicIn,
        RampCurve.cubicOut => Curves.cubicOut,
        RampCurve.cubicInOut => Curves.cubicInOut,
        RampCurve.expIn => Curves.expIn,
        RampCurve.expOut => Curves.expOut,
        RampCurve.expInOut => Curves.expInOut,
        RampCurve.circleIn => Curves.circleIn,
        RampCurve.circleOut => Curves.circleOut,
        RampCurve.circleInOut => Curves.circleInOut,
        RampCurve.bounceOut => Curves.bounceOut,
        RampCurve.elasticOut => Curves.elasticOut,
      };
}

/// A number going from [from] (first frame) to [to] (last frame) along
/// [curve] over the whole bake.
final class RampBinding extends ParamBinding {
  final double from;
  final double to;
  final RampCurve curve;

  const RampBinding({required this.from, required this.to, this.curve = RampCurve.linear});

  @override
  List<Object?> get props => [from, to, curve];
}

/// The clock of a [KeyframeBinding]'s key times.
enum KeyTime {
  /// Clip-local seconds (generator time).
  seconds,

  /// Clip-local beats: seconds × bpm / 60 at the tempo's BPM (120 BPM
  /// without a tempo).
  beats,
}

/// One key of a [KeyframeBinding]: at clip time [at] (seconds or beats, see
/// [KeyTime]) the parameter is [value] — a `num` for number/integer
/// parameters or a [Color] for color parameters — and moves to the next
/// key's value along [easing] (Premiere style: the segment takes the easing
/// of the key it starts at).
final class Keyframe extends Equatable {
  final double at;
  final Object value;
  final Easing easing;

  const Keyframe({required this.at, required this.value, this.easing = Easing.linear});

  Keyframe copyWith({double? at, Object? value, Easing? easing}) =>
      Keyframe(at: at ?? this.at, value: value ?? this.value, easing: easing ?? this.easing);

  @override
  List<Object?> get props => [at, value, easing];
}

/// A value animated by [keys] over clip time: before the first key the first
/// value, after the last the last value (or, with [loop], the keys repeat
/// from the first key's time with the period `last.at − first.at`), between
/// two keys the first key's [Keyframe.easing] interpolates them. Numbers
/// interpolate linearly, colors in HSV along the shortest hue path.
///
/// Keys are sorted by time at salvage (a stable sort: of two keys at the
/// same time the later one wins).
final class KeyframeBinding extends ParamBinding {
  /// Most keys kept at salvage.
  static const maxKeys = 1024;

  final List<Keyframe> keys;
  final KeyTime timeBase;
  final bool loop;

  const KeyframeBinding({required this.keys, this.timeBase = KeyTime.seconds, this.loop = false});

  @override
  bool get usesTempo => timeBase == KeyTime.beats;

  KeyframeBinding copyWith({List<Keyframe>? keys, KeyTime? timeBase, bool? loop}) =>
      KeyframeBinding(keys: keys ?? this.keys, timeBase: timeBase ?? this.timeBase, loop: loop ?? this.loop);

  @override
  List<Object?> get props => [keys, timeBase, loop];
}

/// When a [RandomBinding] draws a new value.
enum RandomMode {
  /// On every beat of the tempo (120 BPM on clip time without one).
  perBeat,

  /// On every 4-beat bar.
  perBar,

  /// Every [RandomBinding.interval] of clip time.
  perTime,

  /// On every frame.
  perFrame,
}

/// A sample-and-hold random number: a new uniform value in [min]..[max] on
/// every hold of [mode], deterministic from [seed] (the setup's seed when
/// `null`) and the index of the hold, so a bake always repeats. [smooth]
/// (`0..1`) glides between the holds with a one-pole follower whose time
/// constant is `smooth` × the hold length (0 = steps).
final class RandomBinding extends ParamBinding {
  static const minInterval = Duration(milliseconds: 10);
  static const maxInterval = Duration(minutes: 1);

  final RandomMode mode;

  /// The hold length of [RandomMode.perTime].
  final Duration interval;
  final double min;
  final double max;
  final double smooth;
  final int? seed;

  const RandomBinding({
    this.mode = RandomMode.perBeat,
    this.interval = const Duration(milliseconds: 500),
    required this.min,
    required this.max,
    this.smooth = 0,
    this.seed,
  });

  @override
  bool get usesTempo => mode == RandomMode.perBeat || mode == RandomMode.perBar;

  /// This binding with its fields in their valid ranges.
  RandomBinding normalized() => RandomBinding(
        mode: mode,
        interval: interval < minInterval ? minInterval : (interval > maxInterval ? maxInterval : interval),
        min: _finite(min),
        max: _finite(max),
        smooth: smooth.isFinite ? smooth.clamp(0.0, 1.0) : 0.0,
        seed: seed,
      );

  RandomBinding copyWith({RandomMode? mode, Duration? interval, double? min, double? max, double? smooth, int? seed}) =>
      RandomBinding(
        mode: mode ?? this.mode,
        interval: interval ?? this.interval,
        min: min ?? this.min,
        max: max ?? this.max,
        smooth: smooth ?? this.smooth,
        seed: seed ?? this.seed,
      );

  @override
  List<Object?> get props => [mode, interval, min, max, smooth, seed];
}

/// A step sequencer in bar time: [steps] levels (`0..1`, [minSteps]..
/// [maxSteps] of them) played [stepsPerBar] per 4-beat bar of the tempo
/// (120 BPM on clip time without one), cycling, each mapped to
/// [min]..[max]. The value is held for [gate] of the step (`0..1`), then
/// [min]; [smooth] slides linearly from each step to the next instead of
/// jumping.
final class StepBinding extends ParamBinding {
  static const minSteps = 2;
  static const maxSteps = 64;
  static const maxStepsPerBar = 64;

  final List<double> steps;
  final int stepsPerBar;
  final double min;
  final double max;
  final bool smooth;
  final double gate;

  const StepBinding({
    required this.steps,
    this.stepsPerBar = 16,
    required this.min,
    required this.max,
    this.smooth = false,
    this.gate = 1,
  });

  @override
  bool get usesTempo => true;

  /// This binding with its fields in their valid ranges (the step list is
  /// cut to [maxSteps]; fewer than [minSteps] steps are not fixed here — the
  /// spec's salvage replaces such a binding).
  StepBinding normalized() => StepBinding(
        steps: List.unmodifiable([
          for (final s in steps.take(maxSteps)) s.isFinite ? s.clamp(0.0, 1.0) : 0.0,
        ]),
        stepsPerBar: stepsPerBar.clamp(1, maxStepsPerBar),
        min: _finite(min),
        max: _finite(max),
        smooth: smooth,
        gate: gate.isFinite ? gate.clamp(0.0, 1.0) : 1.0,
      );

  StepBinding copyWith({List<double>? steps, int? stepsPerBar, double? min, double? max, bool? smooth, double? gate}) =>
      StepBinding(
        steps: steps ?? this.steps,
        stepsPerBar: stepsPerBar ?? this.stepsPerBar,
        min: min ?? this.min,
        max: max ?? this.max,
        smooth: smooth ?? this.smooth,
        gate: gate ?? this.gate,
      );

  @override
  List<Object?> get props => [steps, stepsPerBar, min, max, smooth, gate];
}

/// What fires an [EnvelopeBinding].
sealed class EnvelopeTrigger extends Equatable {
  const EnvelopeTrigger();

  /// Every beat of the tempo (120 BPM on clip time without one).
  static const EnvelopeTrigger beat = BeatTrigger();

  /// Every 4-beat bar.
  static const EnvelopeTrigger bar = BarTrigger();

  /// The onset feature rising through [OnsetTrigger.threshold].
  const factory EnvelopeTrigger.onset({double threshold}) = OnsetTrigger;

  /// The energy of a frequency range rising through a threshold.
  const factory EnvelopeTrigger.rangeHit({required double lowHz, required double highHz, double threshold}) =
      RangeHitTrigger;

  bool get usesAudioFeatures => false;

  bool get usesTempo => false;

  EnvelopeTrigger normalized() => this;
}

final class BeatTrigger extends EnvelopeTrigger {
  const BeatTrigger();

  @override
  bool get usesTempo => true;

  @override
  List<Object?> get props => const [];
}

final class BarTrigger extends EnvelopeTrigger {
  const BarTrigger();

  @override
  bool get usesTempo => true;

  @override
  List<Object?> get props => const [];
}

final class OnsetTrigger extends EnvelopeTrigger {
  final double threshold;

  const OnsetTrigger({this.threshold = 0.5});

  @override
  bool get usesAudioFeatures => true;

  @override
  EnvelopeTrigger normalized() => OnsetTrigger(threshold: _unit(threshold, 0.5));

  @override
  List<Object?> get props => [threshold];
}

final class RangeHitTrigger extends EnvelopeTrigger {
  static const minHz = 20.0;
  static const maxHz = 16000.0;

  final double lowHz;
  final double highHz;
  final double threshold;

  const RangeHitTrigger({required this.lowHz, required this.highHz, this.threshold = 0.5});

  @override
  bool get usesAudioFeatures => true;

  @override
  EnvelopeTrigger normalized() {
    final lo = lowHz.isFinite ? lowHz.clamp(minHz, maxHz) : minHz;
    final hi = highHz.isFinite ? highHz.clamp(minHz, maxHz) : maxHz;
    return RangeHitTrigger(lowHz: math.min(lo, hi), highHz: math.max(lo, hi), threshold: _unit(threshold, 0.5));
  }

  @override
  List<Object?> get props => [lowHz, highHz, threshold];
}

/// An envelope fired by [trigger]: the level rises from 0 to 1 over
/// [attack], falls to [sustainLevel] over [decay], holds it for [sustain],
/// falls to 0 over [release] (all clip-time durations) and the value is
/// `min + (max − min) · level`. A trigger during a running envelope restarts
/// the attack from the current level when [retrigger] is set, and is
/// ignored otherwise.
final class EnvelopeBinding extends ParamBinding {
  /// Longest stage.
  static const maxStage = Duration(seconds: 30);

  final EnvelopeTrigger trigger;
  final Duration attack;
  final Duration decay;
  final Duration sustain;
  final Duration release;
  final double sustainLevel;
  final double min;
  final double max;
  final bool retrigger;

  const EnvelopeBinding({
    required this.trigger,
    this.attack = const Duration(milliseconds: 10),
    this.decay = const Duration(milliseconds: 100),
    this.sustain = Duration.zero,
    this.release = const Duration(milliseconds: 300),
    this.sustainLevel = 0.5,
    required this.min,
    required this.max,
    this.retrigger = true,
  });

  @override
  bool get usesAudioFeatures => trigger.usesAudioFeatures;

  @override
  bool get usesTempo => trigger.usesTempo;

  /// This binding with its fields in their valid ranges.
  EnvelopeBinding normalized() => EnvelopeBinding(
        trigger: trigger.normalized(),
        attack: _clampDuration(attack, maxStage),
        decay: _clampDuration(decay, maxStage),
        sustain: _clampDuration(sustain, maxStage),
        release: _clampDuration(release, maxStage),
        sustainLevel: _unit(sustainLevel, 0.5),
        min: _finite(min),
        max: _finite(max),
        retrigger: retrigger,
      );

  EnvelopeBinding copyWith({
    EnvelopeTrigger? trigger,
    Duration? attack,
    Duration? decay,
    Duration? sustain,
    Duration? release,
    double? sustainLevel,
    double? min,
    double? max,
    bool? retrigger,
  }) =>
      EnvelopeBinding(
        trigger: trigger ?? this.trigger,
        attack: attack ?? this.attack,
        decay: decay ?? this.decay,
        sustain: sustain ?? this.sustain,
        release: release ?? this.release,
        sustainLevel: sustainLevel ?? this.sustainLevel,
        min: min ?? this.min,
        max: max ?? this.max,
        retrigger: retrigger ?? this.retrigger,
      );

  @override
  List<Object?> get props => [trigger, attack, decay, sustain, release, sustainLevel, min, max, retrigger];
}

/// How a [Modulator] combines with the value so far.
enum ModulatorMode {
  /// `value += depth · range · norm` (`range` = the parameter's `max − min`).
  add,

  /// `value *= 1 − depth · (1 − norm)`.
  multiply,
}

/// One modulator of a [StackedBinding]: [source] (any binding but a
/// [StackedBinding]) is evaluated to its own value and normalized to `0..1`
/// across its own range (`min..max` of an audio/beat/random/step/envelope
/// binding, `from..to` of a ramp, the parameter's range for a constant,
/// keyframe or macro binding), then applied with [depth] (`−1..1` of the
/// parameter's range) in [mode]. [depthBinding] (one level: any binding but
/// a [StackedBinding]) animates the depth itself, replacing [depth] by its
/// value clamped to `−1..1`.
final class Modulator extends Equatable {
  final ParamBinding source;
  final double depth;
  final ModulatorMode mode;
  final ParamBinding? depthBinding;

  const Modulator({required this.source, required this.depth, this.mode = ModulatorMode.add, this.depthBinding});

  Modulator copyWith({ParamBinding? source, double? depth, ModulatorMode? mode, ParamBinding? depthBinding}) =>
      Modulator(
        source: source ?? this.source,
        depth: depth ?? this.depth,
        mode: mode ?? this.mode,
        depthBinding: depthBinding ?? this.depthBinding,
      );

  @override
  List<Object?> get props => [source, depth, mode, depthBinding];
}

/// A [base] binding plus stacked [modulators] (Bitwig style): the base value
/// is modified by every modulator in order and clamped to the parameter.
/// Neither the base nor a modulator's source may be a [StackedBinding].
final class StackedBinding extends ParamBinding {
  /// Most modulators kept at salvage.
  static const maxModulators = 8;

  final ParamBinding base;
  final List<Modulator> modulators;

  const StackedBinding({required this.base, required this.modulators});

  @override
  bool get usesAudioFeatures =>
      base.usesAudioFeatures ||
      modulators.any((m) => m.source.usesAudioFeatures || (m.depthBinding?.usesAudioFeatures ?? false));

  @override
  bool get usesTempo =>
      base.usesTempo || modulators.any((m) => m.source.usesTempo || (m.depthBinding?.usesTempo ?? false));

  StackedBinding copyWith({ParamBinding? base, List<Modulator>? modulators}) =>
      StackedBinding(base: base ?? this.base, modulators: modulators ?? this.modulators);

  @override
  List<Object?> get props => [base, modulators];
}

/// The value of the composition macro [macroId]: a named global binding the
/// host supplies per bake (`BakeRequest.macros`), itself evaluated on the
/// same clock, so a macro can be keyframed or audio-driven. A macro the
/// request does not define, of the wrong type, or itself reading a macro
/// gives the parameter's default.
///
/// Whether a macro binding reads the audio or the tempo is only known with
/// the request's macros (see `needsAudioFeatures`); on its own a
/// [MacroBinding] reports neither.
final class MacroBinding extends ParamBinding {
  final String macroId;

  const MacroBinding(this.macroId);

  @override
  List<Object?> get props => [macroId];
}

double _unit(double v, double fallback) => v.isFinite ? v.clamp(0.0, 1.0) : fallback;

double _finite(double v) => v.isFinite ? v : 0.0;

Duration _clampDuration(Duration d, Duration max) => d.isNegative ? Duration.zero : (d > max ? max : d);
