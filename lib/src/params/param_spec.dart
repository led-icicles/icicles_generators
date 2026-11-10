import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:icicles_animation_dart/icicles_animation_dart.dart';

import '../generator/localized_text.dart';
import '../util/palette.dart';
import 'param_binding.dart';

/// How a number slider maps to its range.
enum NumberScale { linear, log }

/// One parameter of a generator: a declarative schema (ISF/LedFx-style)
/// from which the host builds its UI.
///
/// [salvage] turns any stored binding into a valid one for this parameter,
/// so projects survive generator updates.
sealed class ParamSpec extends Equatable {
  /// Unique within the generator; the key of the bindings map.
  final String id;
  final LocalizedText label;
  final LocalizedText? description;

  const ParamSpec({required this.id, required this.label, this.description});

  /// The binding of a new clip: a [ConstantBinding] of the default value.
  ParamBinding get defaultBinding;

  /// Whether the parameter accepts the modulators ([AudioBinding],
  /// [BeatBinding], [RampBinding], [RandomBinding], [StepBinding],
  /// [EnvelopeBinding], [StackedBinding]); number and integer parameters.
  /// [KeyframeBinding] and [MacroBinding] also fit [ColorParam].
  bool get isModulatable => false;

  /// [binding] made valid for this parameter: values clamped to the spec, a
  /// binding of the wrong kind (or `null`) replaced by [defaultBinding].
  ParamBinding salvage(ParamBinding? binding);

  /// The value of a resolved number [raw] for this parameter (clamped,
  /// rounded for integers). Only for modulatable parameters.
  Object numericValue(double raw) => throw UnsupportedError('$runtimeType is not numeric.');

  @override
  List<Object?> get props => [id, label, description];
}

/// A `double` in [min]..[max].
final class NumberParam extends ParamSpec {
  final double min;
  final double max;
  final double defaultValue;

  /// Slider step, `null` for continuous.
  final double? step;
  final NumberScale scale;

  /// Unit shown next to the value (`Hz`, `%`, `s`, `×`…), not translated.
  final String? unit;

  const NumberParam({
    required super.id,
    required super.label,
    super.description,
    required this.min,
    required this.max,
    required this.defaultValue,
    this.step,
    this.scale = NumberScale.linear,
    this.unit,
  });

  /// [value] in [min]..[max] (NaN becomes [defaultValue]).
  double clamp(double value) => value.isNaN ? defaultValue : value.clamp(math.min(min, max), math.max(min, max));

  @override
  ParamBinding get defaultBinding => ConstantBinding(defaultValue);

  @override
  bool get isModulatable => true;

  @override
  Object numericValue(double raw) => clamp(raw);

  @override
  ParamBinding salvage(ParamBinding? binding) => _salvageNumeric(binding, clamp, defaultBinding);

  @override
  List<Object?> get props => [...super.props, min, max, defaultValue, step, scale, unit];
}

/// An `int` in [min]..[max].
final class IntParam extends ParamSpec {
  final int min;
  final int max;
  final int defaultValue;
  final String? unit;

  const IntParam({
    required super.id,
    required super.label,
    super.description,
    required this.min,
    required this.max,
    required this.defaultValue,
    this.unit,
  });

  /// [value] rounded and clamped to [min]..[max].
  int clamp(num value) {
    if (value.isNaN) return defaultValue;
    final rounded = value is int ? value : (value.isFinite ? value.round() : (value > 0 ? max : min));
    return rounded.clamp(math.min(min, max), math.max(min, max));
  }

  @override
  ParamBinding get defaultBinding => ConstantBinding(defaultValue);

  @override
  bool get isModulatable => true;

  @override
  Object numericValue(double raw) => clamp(raw);

  double _clampDouble(double v) => v.isNaN ? defaultValue.toDouble() : v.clamp(min.toDouble(), max.toDouble());

  @override
  ParamBinding salvage(ParamBinding? binding) {
    if (binding case ConstantBinding(:final num value)) return ConstantBinding(clamp(value));
    return _salvageNumeric(binding, _clampDouble, defaultBinding);
  }

  @override
  List<Object?> get props => [...super.props, min, max, defaultValue, unit];
}

/// A `bool` switch.
final class BoolParam extends ParamSpec {
  final bool defaultValue;

  const BoolParam({required super.id, required super.label, super.description, required this.defaultValue});

  @override
  ParamBinding get defaultBinding => ConstantBinding(defaultValue);

  @override
  ParamBinding salvage(ParamBinding? binding) => switch (binding) {
        ConstantBinding(:final bool value) => ConstantBinding(value),
        _ => defaultBinding,
      };

  @override
  List<Object?> get props => [...super.props, defaultValue];
}

/// One option of a [ChoiceParam].
final class ChoiceOption extends Equatable {
  final String id;
  final LocalizedText label;

  const ChoiceOption(this.id, this.label);

  @override
  List<Object?> get props => [id, label];
}

/// One of [options], stored by option id.
final class ChoiceParam extends ParamSpec {
  final List<ChoiceOption> options;
  final String defaultValue;

  const ChoiceParam({
    required super.id,
    required super.label,
    super.description,
    required this.options,
    required this.defaultValue,
  });

  @override
  ParamBinding get defaultBinding => ConstantBinding(defaultValue);

  @override
  ParamBinding salvage(ParamBinding? binding) {
    if (binding case ConstantBinding(:final String value) when options.any((o) => o.id == value)) {
      return ConstantBinding(value);
    }
    return defaultBinding;
  }

  @override
  List<Object?> get props => [...super.props, options, defaultValue];
}

/// A free text of at most [maxLength] characters (e.g. the text of a
/// scrolling-text generator).
///
/// Stored like a choice (`{"type": "constant", "value": "…"}`); the spec
/// decides at salvage time which one a string is.
final class TextParam extends ParamSpec {
  final String defaultValue;

  /// Longest accepted text (longer ones are cut at salvage).
  final int maxLength;

  const TextParam({
    required super.id,
    required super.label,
    super.description,
    required this.defaultValue,
    this.maxLength = 64,
  });

  /// [value] cut to [maxLength] characters.
  String clamp(String value) => value.length <= maxLength ? value : value.substring(0, maxLength);

  @override
  ParamBinding get defaultBinding => ConstantBinding(defaultValue);

  @override
  ParamBinding salvage(ParamBinding? binding) => switch (binding) {
        ConstantBinding(:final String value) => ConstantBinding(clamp(value)),
        _ => defaultBinding,
      };

  @override
  List<Object?> get props => [...super.props, defaultValue, maxLength];
}

/// An opaque [Color].
final class ColorParam extends ParamSpec {
  final Color defaultValue;

  const ColorParam({required super.id, required super.label, super.description, required this.defaultValue});

  @override
  ParamBinding get defaultBinding => ConstantBinding(defaultValue);

  /// Accepts a constant, a [KeyframeBinding] of colors (other keys dropped)
  /// and a [MacroBinding].
  @override
  ParamBinding salvage(ParamBinding? binding) {
    switch (binding) {
      case ConstantBinding(:final Color value):
        return ConstantBinding(_opaque(value));
      case KeyframeBinding():
        final keys = _salvageKeys(binding.keys, (v) => v is Color ? _opaque(v) : null);
        return keys == null
            ? defaultBinding
            : KeyframeBinding(keys: keys, timeBase: binding.timeBase, loop: binding.loop);
      case MacroBinding(:final macroId):
        return macroId.isEmpty ? defaultBinding : binding;
      default:
        return defaultBinding;
    }
  }

  static Color _opaque(Color value) => Color(0xFF000000 | (value.value & 0xFFFFFF));

  @override
  List<Object?> get props => [...super.props, defaultValue];
}

/// A [Palette] (presets in [Palette.presets], or custom stops).
final class PaletteParam extends ParamSpec {
  final Palette defaultValue;

  const PaletteParam({required super.id, required super.label, super.description, required this.defaultValue});

  @override
  ParamBinding get defaultBinding => ConstantBinding(defaultValue);

  @override
  ParamBinding salvage(ParamBinding? binding) {
    if (binding case ConstantBinding(:final Palette value)) {
      final normalized = value.normalized();
      if (normalized != null) return ConstantBinding(normalized);
    }
    return defaultBinding;
  }

  @override
  List<Object?> get props => [...super.props, defaultValue];
}

ParamBinding _salvageNumeric(ParamBinding? binding, double Function(double) clamp, ParamBinding fallback) =>
    _salvageModulator(binding, clamp, allowStacked: true) ?? fallback;

/// [binding] made valid as a numeric source whose values [clamp] maps into
/// the parameter's range, `null` when it cannot be one. Stacked bindings
/// are accepted only with [allowStacked] (never nested); their base and
/// sources are salvaged the same way, the modulators' own-range kinds
/// (audio, beat, ramp, random, step, envelope) keeping their ranges.
ParamBinding? _salvageModulator(ParamBinding? binding, double Function(double) clamp, {required bool allowStacked}) {
  switch (binding) {
    case ConstantBinding(:final num value):
      return ConstantBinding(clamp(value.toDouble()));
    case ConstantBinding() || null:
      return null;
    case AudioBinding():
      final b = binding.normalized();
      return b.copyWith(min: clamp(b.min), max: clamp(b.max));
    case BeatBinding():
      final b = binding.normalized();
      return BeatBinding(
          shape: b.shape, periodBeats: b.periodBeats, phase: b.phase, min: clamp(b.min), max: clamp(b.max));
    case RampBinding(:final from, :final to, :final curve):
      return RampBinding(from: clamp(from.isFinite ? from : 0), to: clamp(to.isFinite ? to : 0), curve: curve);
    case KeyframeBinding():
      final keys = _salvageKeys(binding.keys, (v) => v is num ? clamp(v.toDouble()) : null);
      return keys == null ? null : KeyframeBinding(keys: keys, timeBase: binding.timeBase, loop: binding.loop);
    case RandomBinding():
      final b = binding.normalized();
      return b.copyWith(min: clamp(b.min), max: clamp(b.max));
    case StepBinding():
      if (binding.steps.length < StepBinding.minSteps) return null;
      final b = binding.normalized();
      return b.copyWith(min: clamp(b.min), max: clamp(b.max));
    case EnvelopeBinding():
      final b = binding.normalized();
      return b.copyWith(min: clamp(b.min), max: clamp(b.max));
    case MacroBinding(:final macroId):
      return macroId.isEmpty ? null : binding;
    case StackedBinding(:final base, :final modulators):
      if (!allowStacked) return null;
      final salvagedBase = _salvageModulator(base, clamp, allowStacked: false);
      if (salvagedBase == null) return null;
      final kept = <Modulator>[];
      for (final m in modulators) {
        if (kept.length == StackedBinding.maxModulators) break;
        // Constant, keyframe and macro sources are normalized across the
        // parameter's range, so they are clamped to it; the other kinds keep
        // their own range.
        final sourceClamp = switch (m.source) {
          ConstantBinding() || KeyframeBinding() || MacroBinding() => clamp,
          _ => _ownRange,
        };
        final source = _salvageModulator(m.source, sourceClamp, allowStacked: false);
        if (source == null) continue;
        final depth =
            m.depthBinding == null ? null : _salvageModulator(m.depthBinding, _depthRange, allowStacked: false);
        kept.add(Modulator(
          source: source,
          depth: m.depth.isFinite ? m.depth.clamp(-1.0, 1.0) : 0.0,
          mode: m.mode,
          depthBinding: depth,
        ));
      }
      return StackedBinding(base: salvagedBase, modulators: List.unmodifiable(kept));
  }
}

/// The identity clamp of a modulator source: it keeps its own range.
double _ownRange(double v) => v.isFinite ? v : 0.0;

double _depthRange(double v) => v.isFinite ? v.clamp(-1.0, 1.0) : 0.0;

/// [keys] with the values [convert] accepts (`null` = drop the key), times
/// made finite and non-negative, easings normalized, at most
/// [KeyframeBinding.maxKeys] of them, stably sorted by time; `null` when
/// none is left.
List<Keyframe>? _salvageKeys(List<Keyframe> keys, Object? Function(Object value) convert) {
  final kept = <Keyframe>[];
  for (final key in keys) {
    if (kept.length == KeyframeBinding.maxKeys) break;
    final value = convert(key.value);
    if (value == null) continue;
    kept.add(Keyframe(
      at: key.at.isFinite ? math.max(0.0, key.at) : 0.0,
      value: value,
      easing: key.easing.normalized(),
    ));
  }
  if (kept.isEmpty) return null;
  // A stable sort, so of two keys at the same time the later one stays last.
  final indexed = kept.asMap().entries.toList()
    ..sort((a, b) {
      final byTime = a.value.at.compareTo(b.value.at);
      return byTime != 0 ? byTime : a.key.compareTo(b.key);
    });
  return List.unmodifiable([for (final e in indexed) e.value]);
}

/// [bindings] made valid for [specs]: one entry per spec (missing ones get
/// the default, invalid ones are salvaged), unknown ids dropped.
Map<String, ParamBinding> salvageBindings(List<ParamSpec> specs, Map<String, ParamBinding> bindings) =>
    Map.unmodifiable({for (final spec in specs) spec.id: spec.salvage(bindings[spec.id])});

/// The default bindings of [specs].
Map<String, ParamBinding> defaultBindings(List<ParamSpec> specs) =>
    Map.unmodifiable({for (final spec in specs) spec.id: spec.defaultBinding});
