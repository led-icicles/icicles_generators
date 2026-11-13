import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:icicles_animation_dart/icicles_animation_dart.dart';

import '../util/audio_range.dart';
import '../util/color.dart';

/// What audio reactivity does to a clip (LedFx style: every mode reads one
/// shared, smoothed energy of the chosen frequency range).
enum ReactiveModeKind {
  /// The frame's brightness follows the energy:
  /// `brightness × (min + (max − min) · energy)`.
  brightness,

  /// Time runs at `min + (max − min) · energy` times its normal rate (the
  /// program's own `speed` parameter when it declares one, else a time warp
  /// of the frame clock).
  speed,

  /// The output hue rotates by `min + (max − min) · source` turns, where the
  /// source is the energy or the loudest frequency ([ReactiveMode.hueSource]).
  hue,

  /// An additive flash of [ReactiveMode.flashColor] at intensity
  /// [ReactiveMode.max] on every trigger, decaying over
  /// [ReactiveMode.decay].
  flash,

  /// The program restarts with a new seed on every trigger (particles and
  /// snow start over, a scanner begins again).
  restart,

  /// The program's declared size parameter is set to
  /// `min + (max − min) · energy` of its range (nothing without a declared
  /// target).
  size;

  static ReactiveModeKind? fromName(String? name) => values.where((k) => k.name == name).firstOrNull;

  /// Whether the mode fires on a [ReactiveTrigger] rather than following
  /// the energy.
  bool get isTriggered => this == flash || this == restart;

  /// The mode as "React to music" turns it on: a sensible look without
  /// tweaking.
  ReactiveMode get defaultMode => switch (this) {
        brightness => const ReactiveMode(min: 0.2, max: 1),
        speed => const ReactiveMode(min: 1, max: 3),
        hue => const ReactiveMode(min: 0, max: 0.5),
        flash => const ReactiveMode(min: 0, max: 1),
        restart => const ReactiveMode(min: 0, max: 1),
        size => const ReactiveMode(min: 0.25, max: 1),
      };

  /// Whether a single "depth" slider describes the mode (the triggered
  /// restart has none).
  bool get hasDepth => this != restart;

  /// The mode of [depth] (`0..1`, the one-slider level of the UI) keeping
  /// the other fields of [base]: brightness/size dip to `1 − depth` at
  /// silence, speed reaches `1 + 3 · depth` at full energy, hue turns up to
  /// `depth` of a turn, a flash peaks at `depth`.
  ReactiveMode withDepth(double depth, {ReactiveMode? base}) {
    final d = depth.isFinite ? depth.clamp(0.0, 1.0) : 0.0;
    final from = base ?? defaultMode;
    return switch (this) {
      brightness || size => from.copyWith(min: 1 - d, max: 1),
      speed => from.copyWith(min: 1, max: 1 + 3 * d),
      hue || flash => from.copyWith(min: 0, max: d),
      restart => from,
    };
  }

  /// The inverse of [withDepth]: the depth (`0..1`) [mode] amounts to.
  double depthOf(ReactiveMode mode) {
    final d = switch (this) {
      brightness || size => mode.max - mode.min,
      speed => (mode.max - mode.min) / 3,
      hue || flash => mode.max,
      restart => 1.0,
    };
    return d.isFinite ? d.clamp(0.0, 1.0) : 0.0;
  }
}

/// What fires a triggered mode ([ReactiveModeKind.flash], [ReactiveModeKind.restart]).
enum ReactiveTrigger {
  /// Every beat of the beat clock (nothing without a tempo or beat grid).
  beat,

  /// The onset feature rising through [AudioReactivity.triggerLevel].
  onset,

  /// The (gained, gated) energy of the frequency range rising through
  /// [AudioReactivity.triggerLevel].
  range;

  static ReactiveTrigger? fromName(String? name) => values.where((t) => t.name == name).firstOrNull;

  bool get usesTempo => this == beat;
}

/// What the hue mode follows.
enum ReactiveHueSource {
  /// The shared energy.
  energy,

  /// The loudest frequency (`AudioFrame.peakFrequency`, log scale 40 Hz…16 kHz).
  frequency;

  static ReactiveHueSource? fromName(String? name) => values.where((s) => s.name == name).firstOrNull;
}

/// The settings of one [ReactiveModeKind]: the output range [min]..[max]
/// (what the mode's quantity is at zero and at full energy, or the peak of
/// a flash in [max]) and the fields only some modes read.
final class ReactiveMode extends Equatable {
  /// Longest flash decay.
  static const maxDecay = Duration(seconds: 10);

  final double min;
  final double max;

  /// What fires a flash or a restart.
  final ReactiveTrigger trigger;

  /// Time constant of a flash's exponential decay.
  final Duration decay;

  /// What the hue mode follows.
  final ReactiveHueSource hueSource;

  /// The flash color (added to the frame).
  final Color flashColor;

  const ReactiveMode({
    required this.min,
    required this.max,
    this.trigger = ReactiveTrigger.beat,
    this.decay = const Duration(milliseconds: 300),
    this.hueSource = ReactiveHueSource.energy,
    this.flashColor = const Color(0xFFFFFFFF),
  });

  /// `min + (max − min) · t`.
  double at(double t) => min + (max - min) * t;

  /// This mode with its fields in their valid ranges for [kind]: finite
  /// bounds (brightness/size/hue/flash in `0..1`, speed in `0..8`), the
  /// decay in `0..maxDecay`.
  ReactiveMode normalized(ReactiveModeKind kind) {
    final (lo, hi) = switch (kind) {
      ReactiveModeKind.speed => (0.0, 8.0),
      ReactiveModeKind.brightness || ReactiveModeKind.size || ReactiveModeKind.hue || ReactiveModeKind.flash => (
          0.0,
          1.0
        ),
      ReactiveModeKind.restart => (0.0, 1.0),
    };
    double unit(double v, double fallback) => v.isFinite ? v.clamp(lo, hi) : fallback;
    final fallback = kind.defaultMode;
    return ReactiveMode(
      min: unit(min, fallback.min),
      max: unit(max, fallback.max),
      trigger: trigger,
      decay: decay.isNegative ? Duration.zero : (decay > maxDecay ? maxDecay : decay),
      hueSource: hueSource,
      flashColor: Color.fromRGB(flashColor.red, flashColor.green, flashColor.blue),
    );
  }

  ReactiveMode copyWith({
    double? min,
    double? max,
    ReactiveTrigger? trigger,
    Duration? decay,
    ReactiveHueSource? hueSource,
    Color? flashColor,
  }) =>
      ReactiveMode(
        min: min ?? this.min,
        max: max ?? this.max,
        trigger: trigger ?? this.trigger,
        decay: decay ?? this.decay,
        hueSource: hueSource ?? this.hueSource,
        flashColor: flashColor ?? this.flashColor,
      );

  @override
  List<Object?> get props => [min, max, trigger, decay, hueSource, flashColor.value];
}

/// Universal audio reactivity of a generator or effect clip, LedFx style:
/// one energy — the loudness of a frequency range ([range], or the custom
/// [lowHz]..[highHz]), gated by [threshold], scaled by [sensitivity],
/// smoothed by an [attack]/[release] follower and optionally [invert]ed —
/// drives every mode in [modes] ([ReactiveModeKind]). Independent of the
/// parameter bindings: the bake applies it around the program through
/// `ReactiveGeneratorInstance` / `ReactiveEffectInstance`.
///
/// [none] is the default: disabled, no modes. [defaults] is what "React to
/// music" turns on: brightness on the lows, sensitivity 1, 10/150 ms.
final class AudioReactivity extends Equatable {
  /// Largest [sensitivity].
  static const maxSensitivity = 4.0;

  /// Longest [attack]/[release].
  static const maxSmoothing = Duration(seconds: 10);

  /// The level the onset / range triggers fire at (rising edge).
  static const triggerLevel = 0.5;

  /// Nothing: disabled, no modes.
  static const none = AudioReactivity();

  /// The look of a freshly enabled clip: brightness follows the lows.
  static const defaults =
      AudioReactivity(enabled: true, modes: {ReactiveModeKind.brightness: ReactiveMode(min: 0.2, max: 1)});

  final bool enabled;

  /// The frequency range the energy is read from ([lowHz]/[highHz] for
  /// [AudioRangePreset.custom]).
  final AudioRangePreset range;
  final double lowHz;
  final double highHz;

  /// Gain of the energy (`0..4`, 1 = as analysed).
  final double sensitivity;

  /// Follower time constants while the energy rises / falls.
  final Duration attack;
  final Duration release;

  /// Energy below this (`0..1`) counts as silence; the rest is re-stretched
  /// to `0..1`.
  final double threshold;

  /// Whether the energy is flipped (`1 − energy`): react to the quiet parts.
  final bool invert;

  /// The active modes and their settings.
  final Map<ReactiveModeKind, ReactiveMode> modes;

  const AudioReactivity({
    this.enabled = false,
    this.range = AudioRangePreset.lows,
    this.lowHz = audioRangeMinHz,
    this.highHz = 250,
    this.sensitivity = 1,
    this.attack = const Duration(milliseconds: 10),
    this.release = const Duration(milliseconds: 150),
    this.threshold = 0,
    this.invert = false,
    this.modes = const {},
  });

  /// Whether the reactivity changes anything: enabled with at least one
  /// mode.
  bool get isActive => enabled && modes.isNotEmpty;

  /// Whether the bake needs the analysed audio (every active reactivity
  /// reads the energy).
  bool get usesAudioFeatures => isActive;

  /// Whether a triggered mode follows the beat clock.
  bool get usesTempo => isActive && modes.entries.any((e) => e.key.isTriggered && e.value.trigger.usesTempo);

  /// The frequency range the energy is read from.
  AudioRange get audioRange =>
      range == AudioRangePreset.custom ? AudioRange(lowHz, highHz) : AudioRange.ofPreset(range);

  /// The settings of [kind], `null` while the mode is off.
  ReactiveMode? operator [](ReactiveModeKind kind) => modes[kind];

  /// This reactivity with every field in its valid range (the modes
  /// normalized for their kinds).
  AudioReactivity normalized() => AudioReactivity(
        enabled: enabled,
        range: range,
        lowHz: lowHz.isFinite ? lowHz.clamp(audioRangeMinHz, audioRangeMaxHz) : audioRangeMinHz,
        highHz: highHz.isFinite ? highHz.clamp(audioRangeMinHz, audioRangeMaxHz) : audioRangeMaxHz,
        sensitivity: sensitivity.isFinite ? sensitivity.clamp(0.0, maxSensitivity) : 1.0,
        attack: _clampDuration(attack),
        release: _clampDuration(release),
        threshold: threshold.isFinite ? threshold.clamp(0.0, 0.99) : 0.0,
        invert: invert,
        modes: {for (final MapEntry(:key, :value) in modes.entries) key: value.normalized(key)},
      );

  /// A copy with [kind] set to [mode] (`null` turns the mode off).
  AudioReactivity withMode(ReactiveModeKind kind, ReactiveMode? mode) {
    final next = {...modes};
    if (mode == null) {
      next.remove(kind);
    } else {
      next[kind] = mode;
    }
    return copyWith(modes: next);
  }

  AudioReactivity copyWith({
    bool? enabled,
    AudioRangePreset? range,
    double? lowHz,
    double? highHz,
    double? sensitivity,
    Duration? attack,
    Duration? release,
    double? threshold,
    bool? invert,
    Map<ReactiveModeKind, ReactiveMode>? modes,
  }) =>
      AudioReactivity(
        enabled: enabled ?? this.enabled,
        range: range ?? this.range,
        lowHz: lowHz ?? this.lowHz,
        highHz: highHz ?? this.highHz,
        sensitivity: sensitivity ?? this.sensitivity,
        attack: attack ?? this.attack,
        release: release ?? this.release,
        threshold: threshold ?? this.threshold,
        invert: invert ?? this.invert,
        modes: modes == null ? this.modes : Map.unmodifiable(modes),
      );

  static Duration _clampDuration(Duration d) => d.isNegative ? Duration.zero : (d > maxSmoothing ? maxSmoothing : d);

  @override
  List<Object?> get props => [
        enabled,
        range,
        lowHz,
        highHz,
        sensitivity,
        attack,
        release,
        threshold,
        invert,
        for (final kind in ReactiveModeKind.values) modes[kind],
      ];

  @override
  String toString() => isActive
      ? 'AudioReactivity(${range.id}, ×$sensitivity, ${modes.keys.map((k) => k.name).join('+')})'
      : 'AudioReactivity.none';
}

/// JSON form of [AudioReactivity], shared by the project codec, the presets
/// and the plugin protocol:
///
/// ```json
/// {"enabled": true, "range": "lows", "lowHz": 20, "highHz": 250, "sensitivity": 1.0,
///  "attackMs": 10, "releaseMs": 150, "threshold": 0.0, "invert": false,
///  "modes": {"brightness": {"min": 0.2, "max": 1.0},
///            "flash": {"min": 0.0, "max": 1.0, "trigger": "beat", "decayMs": 300, "color": "#ffffff"},
///            "hue": {"min": 0.0, "max": 0.5, "source": "frequency"}}}
/// ```
///
/// Decoding is lenient: unknown fields and modes are ignored, missing ones
/// get their defaults, and anything that is not an object decodes to
/// `null`.
abstract final class AudioReactivityJson {
  static Map<String, Object?> toJson(AudioReactivity r) => {
        'enabled': r.enabled,
        'range': r.range.id,
        'lowHz': _number(r.lowHz),
        'highHz': _number(r.highHz),
        'sensitivity': _number(r.sensitivity),
        'attackMs': r.attack.inMicroseconds / 1000,
        'releaseMs': r.release.inMicroseconds / 1000,
        'threshold': _number(r.threshold),
        'invert': r.invert,
        'modes': {
          for (final kind in ReactiveModeKind.values)
            if (r.modes[kind] case final mode?) kind.name: modeToJson(kind, mode),
        },
      };

  static Map<String, Object?> modeToJson(ReactiveModeKind kind, ReactiveMode mode) => {
        'min': _number(mode.min),
        'max': _number(mode.max),
        if (kind.isTriggered) 'trigger': mode.trigger.name,
        if (kind == ReactiveModeKind.flash) 'decayMs': mode.decay.inMicroseconds / 1000,
        if (kind == ReactiveModeKind.flash) 'color': colorToHex(mode.flashColor),
        if (kind == ReactiveModeKind.hue) 'source': mode.hueSource.name,
      };

  /// Decodes [toJson]; `null` for anything that is not an object.
  static AudioReactivity? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    const base = AudioReactivity.none;
    final modes = <ReactiveModeKind, ReactiveMode>{};
    if (json['modes'] case final Map<String, Object?> list) {
      for (final MapEntry(:key, :value) in list.entries) {
        final kind = ReactiveModeKind.fromName(key);
        final mode = kind == null ? null : modeFromJson(kind, value);
        if (kind != null && mode != null) modes[kind] = mode;
      }
    }
    return AudioReactivity(
      enabled: json['enabled'] == true,
      range: json['range'] is String ? AudioRangePreset.fromId(json['range'] as String, base.range) : base.range,
      lowHz: _double(json['lowHz']) ?? base.lowHz,
      highHz: _double(json['highHz']) ?? base.highHz,
      sensitivity: _double(json['sensitivity']) ?? base.sensitivity,
      attack: _durationMs(json['attackMs']) ?? base.attack,
      release: _durationMs(json['releaseMs']) ?? base.release,
      threshold: _double(json['threshold']) ?? base.threshold,
      invert: json['invert'] == true,
      modes: modes,
    ).normalized();
  }

  /// Decodes [modeToJson]; `null` for anything that is not an object.
  static ReactiveMode? modeFromJson(ReactiveModeKind kind, Object? json) {
    if (json is! Map<String, Object?>) return null;
    final fallback = kind.defaultMode;
    final color = json['color'] is String ? colorFromHex(json['color'] as String) : null;
    return ReactiveMode(
      min: _double(json['min']) ?? fallback.min,
      max: _double(json['max']) ?? fallback.max,
      trigger: ReactiveTrigger.fromName(_string(json['trigger'])) ?? fallback.trigger,
      decay: _durationMs(json['decayMs']) ?? fallback.decay,
      hueSource: ReactiveHueSource.fromName(_string(json['source'])) ?? fallback.hueSource,
      flashColor: color ?? fallback.flashColor,
    ).normalized(kind);
  }

  static num _number(double v) => v == v.roundToDouble() && v.abs() < 1e15 ? v.round() : v;

  static double? _double(Object? v) => v is num && v.isFinite ? v.toDouble() : null;

  static String? _string(Object? v) => v is String ? v : null;

  static Duration? _durationMs(Object? v) =>
      v is num && v.isFinite ? Duration(microseconds: (math.max(0, v) * 1000).round()) : null;
}
