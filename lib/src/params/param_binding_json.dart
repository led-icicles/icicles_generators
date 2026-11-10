import 'package:icicles_animation_dart/icicles_animation_dart.dart';

import '../audio/audio_feature_key.dart';
import '../util/color.dart';
import '../util/palette.dart';
import 'param_binding.dart';

/// JSON form of [ParamBinding]s, shared by the project codec and the plugin
/// protocol. Self-describing, so it decodes without the parameter schema:
///
/// ```json
/// {"type": "constant", "value": 0.5}            // number, int, bool or choice id
/// {"type": "constant", "color": "#ff8800"}
/// {"type": "constant", "palette": [{"at": 0.0, "color": "#000000"}, {"at": 1.0, "color": "#ffffff"}]}
/// {"type": "audio", "feature": "bass", "min": 0.2, "max": 1.0,
///  "attackMs": 10, "releaseMs": 200, "curve": 1.0, "invert": false}
/// {"type": "beat", "shape": "pulse", "periodBeats": 1.0, "phase": 0.0, "min": 0.0, "max": 1.0}
/// {"type": "ramp", "from": 0.0, "to": 1.0, "curve": "linear"}
/// {"type": "keyframes", "timeBase": "seconds", "loop": false,
///  "keys": [{"at": 0.0, "value": 0.2, "easing": "easeInOut"},
///           {"at": 2.0, "value": 1.0, "easing": {"bezier": [0.42, 0.0, 0.58, 1.0]}},
///           {"at": 3.0, "color": "#ff8800", "easing": "hold"}]}       // color keys for a color parameter
/// {"type": "random", "mode": "perBeat", "intervalMs": 500, "min": 0.0, "max": 1.0, "smooth": 0.0, "seed": 7}
/// {"type": "steps", "steps": [1.0, 0.0, 0.5, 0.0], "stepsPerBar": 16, "min": 0.0, "max": 1.0,
///  "smooth": false, "gate": 1.0}
/// {"type": "envelope", "trigger": "onset", "threshold": 0.5,        // or "beat" / "bar" /
///  "attackMs": 10, "decayMs": 100, "sustainMs": 0, "releaseMs": 300,  // "rangeHit" + "lowHz", "highHz", "threshold"
///  "sustainLevel": 0.5, "min": 0.0, "max": 1.0, "retrigger": true}
/// {"type": "stack", "base": {…}, "modulators": [{"source": {…}, "depth": 0.5, "mode": "add", "depthBinding": {…}}]}
/// {"type": "macro", "macro": "intensity"}
/// ```
///
/// Decoding is lenient: unknown fields are ignored, missing optional fields
/// get their defaults, and an unreadable binding decodes to `null` (the
/// parameter then falls back to its default via `ParamSpec.salvage`).
abstract final class ParamBindingJson {
  static Map<String, Object?> toJson(ParamBinding binding) => switch (binding) {
        ConstantBinding(:final Color value) => {'type': 'constant', 'color': colorToHex(value)},
        ConstantBinding(:final Palette value) => {
            'type': 'constant',
            'palette': [
              for (final stop in value.stops) {'at': _number(stop.position), 'color': colorToHex(stop.color)},
            ],
          },
        ConstantBinding(:final double value) => {'type': 'constant', 'value': _number(value)},
        ConstantBinding(:final value) => {'type': 'constant', 'value': value},
        AudioBinding() => {
            'type': 'audio',
            'feature': binding.feature.name,
            'min': _number(binding.min),
            'max': _number(binding.max),
            'attackMs': binding.attack.inMicroseconds / 1000,
            'releaseMs': binding.release.inMicroseconds / 1000,
            'curve': _number(binding.curve),
            'invert': binding.invert,
          },
        BeatBinding() => {
            'type': 'beat',
            'shape': binding.shape.name,
            'periodBeats': _number(binding.periodBeats),
            'phase': _number(binding.phase),
            'min': _number(binding.min),
            'max': _number(binding.max),
          },
        RampBinding() => {
            'type': 'ramp',
            'from': _number(binding.from),
            'to': _number(binding.to),
            'curve': binding.curve.name,
          },
        KeyframeBinding() => {
            'type': 'keyframes',
            'timeBase': binding.timeBase.name,
            'loop': binding.loop,
            'keys': [for (final key in binding.keys) keyframeToJson(key)],
          },
        RandomBinding() => {
            'type': 'random',
            'mode': binding.mode.name,
            'intervalMs': binding.interval.inMicroseconds / 1000,
            'min': _number(binding.min),
            'max': _number(binding.max),
            'smooth': _number(binding.smooth),
            'seed': binding.seed,
          },
        StepBinding() => {
            'type': 'steps',
            'steps': [for (final s in binding.steps) _number(s)],
            'stepsPerBar': binding.stepsPerBar,
            'min': _number(binding.min),
            'max': _number(binding.max),
            'smooth': binding.smooth,
            'gate': _number(binding.gate),
          },
        EnvelopeBinding() => {
            'type': 'envelope',
            ...switch (binding.trigger) {
              BeatTrigger() => {'trigger': 'beat'},
              BarTrigger() => {'trigger': 'bar'},
              OnsetTrigger(:final threshold) => {'trigger': 'onset', 'threshold': _number(threshold)},
              RangeHitTrigger(:final lowHz, :final highHz, :final threshold) => {
                  'trigger': 'rangeHit',
                  'lowHz': _number(lowHz),
                  'highHz': _number(highHz),
                  'threshold': _number(threshold),
                },
            },
            'attackMs': binding.attack.inMicroseconds / 1000,
            'decayMs': binding.decay.inMicroseconds / 1000,
            'sustainMs': binding.sustain.inMicroseconds / 1000,
            'releaseMs': binding.release.inMicroseconds / 1000,
            'sustainLevel': _number(binding.sustainLevel),
            'min': _number(binding.min),
            'max': _number(binding.max),
            'retrigger': binding.retrigger,
          },
        StackedBinding() => {
            'type': 'stack',
            'base': toJson(binding.base),
            'modulators': [
              for (final m in binding.modulators)
                {
                  'source': toJson(m.source),
                  'depth': _number(m.depth),
                  'mode': m.mode.name,
                  if (m.depthBinding case final depth?) 'depthBinding': toJson(depth),
                },
            ],
          },
        MacroBinding() => {'type': 'macro', 'macro': binding.macroId},
      };

  /// JSON of one [Keyframe]: `{"at", "value" | "color", "easing"}`.
  static Map<String, Object?> keyframeToJson(Keyframe key) => {
        'at': _number(key.at),
        ...switch (key.value) {
          final Color color => {'color': colorToHex(color)},
          final double value => {'value': _number(value)},
          final value => {'value': value},
        },
        'easing': easingToJson(key.easing),
      };

  /// The keyframe of [json], `null` when unreadable (a key needs a finite
  /// `at` and a `value` number or a `color`).
  static Keyframe? keyframeFromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final at = _double(json['at']);
    if (at == null) return null;
    final Object value;
    if (json['color'] case final String hex) {
      final color = colorFromHex(hex);
      if (color == null) return null;
      value = color;
    } else {
      final number = _double(json['value']);
      if (number == null) return null;
      value = json['value'] is int ? json['value'] as int : number;
    }
    return Keyframe(at: at, value: value, easing: easingFromJson(json['easing']) ?? Easing.linear);
  }

  /// JSON of an [Easing]: a preset name, or `{"bezier": [x1, y1, x2, y2]}`.
  static Object easingToJson(Easing easing) => switch (easing) {
        PresetEasing(:final preset) => preset.name,
        BezierEasing(:final x1, :final y1, :final x2, :final y2) => {
            'bezier': [_number(x1), _number(y1), _number(x2), _number(y2)],
          },
      };

  /// The easing of [json], `null` when unreadable.
  static Easing? easingFromJson(Object? json) {
    if (json case {'bezier': final List<Object?> points} when points.length == 4) {
      final values = [for (final p in points) _double(p)];
      if (values.any((v) => v == null)) return null;
      return BezierEasing(values[0]!, values[1]!, values[2]!, values[3]!).normalized();
    }
    final preset = _enum(EasingPreset.values, json);
    return preset == null ? null : PresetEasing(preset);
  }

  /// The binding of [json], or `null` when it is not a readable binding.
  static ParamBinding? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    switch (json['type']) {
      case 'constant':
        if (json['color'] case final String hex) {
          final color = colorFromHex(hex);
          return color == null ? null : ConstantBinding(color);
        }
        if (json['palette'] case final List<Object?> stops) {
          final parsed = <PaletteStop>[];
          for (final stop in stops) {
            if (stop case {'at': final num at, 'color': final String hex}) {
              final color = colorFromHex(hex);
              if (color != null && at.isFinite) parsed.add(PaletteStop(at.toDouble(), color));
            }
          }
          final palette = Palette(parsed).normalized();
          return palette == null ? null : ConstantBinding(palette);
        }
        return switch (json['value']) {
          final int value => ConstantBinding(value),
          final double value when value.isFinite => ConstantBinding(value),
          final bool value => ConstantBinding(value),
          final String value => ConstantBinding(value),
          _ => null,
        };
      case 'audio':
        final feature = _enum(AudioFeatureKey.values, json['feature']);
        final min = _double(json['min']);
        final max = _double(json['max']);
        if (feature == null || min == null || max == null) return null;
        return AudioBinding(
          feature: feature,
          min: min,
          max: max,
          attack: _millis(json['attackMs']) ?? const Duration(milliseconds: 10),
          release: _millis(json['releaseMs']) ?? const Duration(milliseconds: 200),
          curve: _double(json['curve']) ?? 1.0,
          invert: json['invert'] == true,
        ).normalized();
      case 'beat':
        final shape = _enum(BeatShape.values, json['shape']);
        final min = _double(json['min']);
        final max = _double(json['max']);
        if (shape == null || min == null || max == null) return null;
        return BeatBinding(
          shape: shape,
          periodBeats: _double(json['periodBeats']) ?? 1,
          phase: _double(json['phase']) ?? 0,
          min: min,
          max: max,
        ).normalized();
      case 'ramp':
        final from = _double(json['from']);
        final to = _double(json['to']);
        if (from == null || to == null) return null;
        return RampBinding(from: from, to: to, curve: _enum(RampCurve.values, json['curve']) ?? RampCurve.linear);
      case 'keyframes':
        final keys = [
          if (json['keys'] case final List<Object?> list)
            for (final key in list)
              if (keyframeFromJson(key) case final parsed?) parsed,
        ];
        if (keys.isEmpty) return null;
        return KeyframeBinding(
          keys: List.unmodifiable(keys),
          timeBase: _enum(KeyTime.values, json['timeBase']) ?? KeyTime.seconds,
          loop: json['loop'] == true,
        );
      case 'random':
        final min = _double(json['min']);
        final max = _double(json['max']);
        if (min == null || max == null) return null;
        return RandomBinding(
          mode: _enum(RandomMode.values, json['mode']) ?? RandomMode.perBeat,
          interval: _millis(json['intervalMs']) ?? const Duration(milliseconds: 500),
          min: min,
          max: max,
          smooth: _double(json['smooth']) ?? 0,
          seed: json['seed'] is int ? json['seed'] as int : null,
        ).normalized();
      case 'steps':
        final min = _double(json['min']);
        final max = _double(json['max']);
        final steps = json['steps'];
        if (min == null || max == null || steps is! List<Object?>) return null;
        final levels = [for (final s in steps) _double(s) ?? 0.0];
        if (levels.length < StepBinding.minSteps) return null;
        final perBar = json['stepsPerBar'];
        return StepBinding(
          steps: levels,
          stepsPerBar: perBar is int ? perBar : 16,
          min: min,
          max: max,
          smooth: json['smooth'] == true,
          gate: _double(json['gate']) ?? 1,
        ).normalized();
      case 'envelope':
        final min = _double(json['min']);
        final max = _double(json['max']);
        final EnvelopeTrigger? trigger = switch (json['trigger']) {
          'beat' => EnvelopeTrigger.beat,
          'bar' => EnvelopeTrigger.bar,
          'onset' => OnsetTrigger(threshold: _double(json['threshold']) ?? 0.5),
          'rangeHit' => RangeHitTrigger(
              lowHz: _double(json['lowHz']) ?? RangeHitTrigger.minHz,
              highHz: _double(json['highHz']) ?? RangeHitTrigger.maxHz,
              threshold: _double(json['threshold']) ?? 0.5,
            ),
          _ => null,
        };
        if (min == null || max == null || trigger == null) return null;
        return EnvelopeBinding(
          trigger: trigger,
          attack: _millis(json['attackMs']) ?? const Duration(milliseconds: 10),
          decay: _millis(json['decayMs']) ?? const Duration(milliseconds: 100),
          sustain: _millis(json['sustainMs']) ?? Duration.zero,
          release: _millis(json['releaseMs']) ?? const Duration(milliseconds: 300),
          sustainLevel: _double(json['sustainLevel']) ?? 0.5,
          min: min,
          max: max,
          retrigger: json['retrigger'] != false,
        ).normalized();
      case 'stack':
        final base = fromJson(json['base']);
        if (base == null || base is StackedBinding) return null;
        final modulators = <Modulator>[];
        if (json['modulators'] case final List<Object?> list) {
          for (final item in list) {
            if (item is! Map<String, Object?>) continue;
            final source = fromJson(item['source']);
            if (source == null || source is StackedBinding) continue;
            final depthBinding = fromJson(item['depthBinding']);
            modulators.add(Modulator(
              source: source,
              depth: _double(item['depth']) ?? 0,
              mode: _enum(ModulatorMode.values, item['mode']) ?? ModulatorMode.add,
              depthBinding: depthBinding is StackedBinding ? null : depthBinding,
            ));
          }
        }
        return StackedBinding(base: base, modulators: List.unmodifiable(modulators));
      case 'macro':
        final id = json['macro'];
        return id is String && id.isNotEmpty ? MacroBinding(id) : null;
      default:
        return null;
    }
  }

  /// `{paramId: binding}` as JSON.
  static Map<String, Object?> bindingsToJson(Map<String, ParamBinding> bindings) =>
      {for (final MapEntry(:key, :value) in bindings.entries) key: toJson(value)};

  /// The readable bindings of a `{paramId: binding}` JSON object (unreadable
  /// entries dropped; anything but an object gives an empty map).
  static Map<String, ParamBinding> bindingsFromJson(Object? json) {
    if (json is! Map<String, Object?>) return const {};
    return Map.unmodifiable({
      for (final MapEntry(:key, :value) in json.entries)
        if (fromJson(value) case final binding?) key: binding,
    });
  }

  static num _number(double v) => v.isFinite ? v : 0;

  static double? _double(Object? v) => v is num && v.isFinite ? v.toDouble() : null;

  static Duration? _millis(Object? v) =>
      v is num && v.isFinite ? Duration(microseconds: (v * 1000).round().clamp(0, 1 << 40)) : null;

  static T? _enum<T extends Enum>(List<T> values, Object? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}
