import 'package:equatable/equatable.dart';

import '../effect/effect.dart';
import '../effect/effect_info.dart';
import '../generator/generator.dart';
import '../generator/generator_info.dart';
import '../generator/localized_text.dart';
import '../params/param_spec.dart';
import '../reactive/reactive_target.dart';
import '../util/color.dart';
import '../util/palette.dart';

/// A generator as a plugin describes it: its info and parameter schema
/// (without the code, which stays in the plugin process).
final class GeneratorManifestEntry extends Equatable {
  final GeneratorInfo info;
  final List<ParamSpec> params;

  const GeneratorManifestEntry({required this.info, required this.params});

  factory GeneratorManifestEntry.of(Generator generator) =>
      GeneratorManifestEntry(info: generator.info, params: List.unmodifiable(generator.params));

  @override
  List<Object?> get props => [info, params];
}

/// An effect as a plugin describes it: its info and parameter schema.
final class EffectManifestEntry extends Equatable {
  final EffectInfo info;
  final List<ParamSpec> params;

  const EffectManifestEntry({required this.info, required this.params});

  factory EffectManifestEntry.of(Effect effect) =>
      EffectManifestEntry(info: effect.info, params: List.unmodifiable(effect.params));

  @override
  List<Object?> get props => [info, params];
}

/// JSON of generator and effect infos and parameter schemas (the plugin
/// manifest).
///
/// Decoding is lenient: an unreadable parameter is skipped, an unreadable
/// generator is skipped.
abstract final class ManifestJson {
  static Map<String, Object?> textToJson(LocalizedText text) => {'en': text.en, if (text.pl != null) 'pl': text.pl};

  static LocalizedText? textFromJson(Object? json) => switch (json) {
        {'en': final String en} => LocalizedText(en, pl: json['pl'] is String ? json['pl'] as String : null),
        final String en => LocalizedText(en),
        _ => null,
      };

  static Map<String, Object?> infoToJson(GeneratorInfo info) => {
        'id': info.id,
        'version': info.version,
        'name': textToJson(info.name),
        'description': textToJson(info.description),
        'category': info.category.name,
        'usesAudio': info.usesAudio,
        'defaultLengthMs': info.defaultLength.inMilliseconds,
        if (info.reactiveTargets.isNotEmpty) 'reactiveTargets': reactiveTargetsToJson(info.reactiveTargets),
      };

  /// `{"speed": "speed", "size": "radius"}`: the parameter id per target.
  static Map<String, Object?> reactiveTargetsToJson(Map<ReactiveTarget, String> targets) =>
      {for (final MapEntry(:key, :value) in targets.entries) key.name: value};

  /// Decodes [reactiveTargetsToJson]; unknown targets and non-string ids are
  /// skipped, anything else gives an empty map.
  static Map<ReactiveTarget, String> reactiveTargetsFromJson(Object? json) {
    if (json is! Map<String, Object?>) return const {};
    return Map.unmodifiable({
      for (final MapEntry(:key, :value) in json.entries)
        if (ReactiveTarget.fromName(key) case final target? when value is String && value.isNotEmpty) target: value,
    });
  }

  static GeneratorInfo? infoFromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final id = json['id'];
    final version = json['version'];
    final name = textFromJson(json['name']);
    if (id is! String || id.isEmpty || version is! int || name == null) return null;
    final length = json['defaultLengthMs'];
    return GeneratorInfo(
      id: id,
      version: version,
      name: name,
      description: textFromJson(json['description']) ?? const LocalizedText(''),
      category: GeneratorCategory.values.firstWhere(
        (c) => c.name == json['category'],
        orElse: () => GeneratorCategory.basic,
      ),
      usesAudio: json['usesAudio'] == true,
      defaultLength: length is int && length > 0 ? Duration(milliseconds: length) : const Duration(seconds: 10),
      reactiveTargets: reactiveTargetsFromJson(json['reactiveTargets']),
    );
  }

  static Map<String, Object?> effectInfoToJson(EffectInfo info) => {
        'id': info.id,
        'version': info.version,
        'name': textToJson(info.name),
        'description': textToJson(info.description),
        'category': info.category.name,
        'usesAudio': info.usesAudio,
        'defaultLengthMs': info.defaultLength.inMilliseconds,
        if (info.reactiveTargets.isNotEmpty) 'reactiveTargets': reactiveTargetsToJson(info.reactiveTargets),
      };

  static EffectInfo? effectInfoFromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final id = json['id'];
    final version = json['version'];
    final name = textFromJson(json['name']);
    if (id is! String || id.isEmpty || version is! int || name == null) return null;
    final length = json['defaultLengthMs'];
    return EffectInfo(
      id: id,
      version: version,
      name: name,
      description: textFromJson(json['description']) ?? const LocalizedText(''),
      category: EffectCategory.values.firstWhere(
        (c) => c.name == json['category'],
        orElse: () => EffectCategory.color,
      ),
      usesAudio: json['usesAudio'] == true,
      defaultLength: length is int && length > 0 ? Duration(milliseconds: length) : const Duration(seconds: 10),
      reactiveTargets: reactiveTargetsFromJson(json['reactiveTargets']),
    );
  }

  static Map<String, Object?> paramToJson(ParamSpec spec) => {
        'id': spec.id,
        'label': textToJson(spec.label),
        if (spec.description case final description?) 'description': textToJson(description),
        ...switch (spec) {
          NumberParam() => {
              'kind': 'number',
              'min': spec.min,
              'max': spec.max,
              'default': spec.defaultValue,
              if (spec.step != null) 'step': spec.step,
              'scale': spec.scale.name,
              if (spec.unit != null) 'unit': spec.unit,
            },
          IntParam() => {
              'kind': 'int',
              'min': spec.min,
              'max': spec.max,
              'default': spec.defaultValue,
              if (spec.unit != null) 'unit': spec.unit,
            },
          BoolParam() => {'kind': 'bool', 'default': spec.defaultValue},
          ChoiceParam() => {
              'kind': 'choice',
              'options': [
                for (final option in spec.options) {'id': option.id, 'label': textToJson(option.label)},
              ],
              'default': spec.defaultValue,
            },
          TextParam() => {'kind': 'text', 'default': spec.defaultValue, 'maxLength': spec.maxLength},
          ColorParam() => {'kind': 'color', 'default': colorToHex(spec.defaultValue)},
          PaletteParam() => {'kind': 'palette', 'default': _paletteToJson(spec.defaultValue)},
        },
      };

  static ParamSpec? paramFromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final id = json['id'];
    final label = textFromJson(json['label']);
    if (id is! String || id.isEmpty || label == null) return null;
    final description = textFromJson(json['description']);
    final fallback = json['default'];
    switch (json['kind']) {
      case 'number':
        final min = _double(json['min']);
        final max = _double(json['max']);
        final value = _double(fallback);
        if (min == null || max == null || value == null || min > max) return null;
        return NumberParam(
          id: id,
          label: label,
          description: description,
          min: min,
          max: max,
          defaultValue: value.clamp(min, max),
          step: _double(json['step']),
          scale: json['scale'] == 'log' && min > 0 ? NumberScale.log : NumberScale.linear,
          unit: json['unit'] is String ? json['unit'] as String : null,
        );
      case 'int':
        final min = json['min'];
        final max = json['max'];
        if (min is! int || max is! int || fallback is! int || min > max) return null;
        return IntParam(
          id: id,
          label: label,
          description: description,
          min: min,
          max: max,
          defaultValue: fallback.clamp(min, max),
          unit: json['unit'] is String ? json['unit'] as String : null,
        );
      case 'bool':
        if (fallback is! bool) return null;
        return BoolParam(id: id, label: label, description: description, defaultValue: fallback);
      case 'choice':
        final options = [
          if (json['options'] case final List<Object?> list)
            for (final option in list)
              if (option case {'id': final String optionId, 'label': final Object? optionLabel})
                if (textFromJson(optionLabel) case final text?) ChoiceOption(optionId, text),
        ];
        if (options.isEmpty) return null;
        return ChoiceParam(
          id: id,
          label: label,
          description: description,
          options: List.unmodifiable(options),
          defaultValue: options.any((o) => o.id == fallback) ? fallback as String : options.first.id,
        );
      case 'text':
        if (fallback is! String) return null;
        final maxLength = json['maxLength'];
        final spec = TextParam(
          id: id,
          label: label,
          description: description,
          defaultValue: fallback,
          maxLength: maxLength is int && maxLength > 0 ? maxLength : 64,
        );
        return spec.clamp(fallback) == fallback ? spec : null;
      case 'color':
        final color = fallback is String ? colorFromHex(fallback) : null;
        if (color == null) return null;
        return ColorParam(id: id, label: label, description: description, defaultValue: color);
      case 'palette':
        final palette = _paletteFromJson(fallback);
        if (palette == null) return null;
        return PaletteParam(id: id, label: label, description: description, defaultValue: palette);
      default:
        return null;
    }
  }

  static Map<String, Object?> entryToJson(GeneratorManifestEntry entry) => {
        'info': infoToJson(entry.info),
        'params': [for (final spec in entry.params) paramToJson(spec)],
      };

  static GeneratorManifestEntry? entryFromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final info = infoFromJson(json['info']);
    if (info == null) return null;
    return GeneratorManifestEntry(info: info, params: _paramsFromJson(json['params']));
  }

  static Map<String, Object?> effectEntryToJson(EffectManifestEntry entry) => {
        'info': effectInfoToJson(entry.info),
        'params': [for (final spec in entry.params) paramToJson(spec)],
      };

  static EffectManifestEntry? effectEntryFromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final info = effectInfoFromJson(json['info']);
    if (info == null) return null;
    return EffectManifestEntry(info: info, params: _paramsFromJson(json['params']));
  }

  static List<ParamSpec> _paramsFromJson(Object? json) {
    final params = <ParamSpec>[];
    final ids = <String>{};
    if (json case final List<Object?> list) {
      for (final item in list) {
        final spec = paramFromJson(item);
        if (spec != null && ids.add(spec.id)) params.add(spec);
      }
    }
    return List.unmodifiable(params);
  }

  static List<Object?> _paletteToJson(Palette palette) => [
        for (final stop in palette.stops) {'at': stop.position, 'color': colorToHex(stop.color)},
      ];

  static Palette? _paletteFromJson(Object? json) {
    if (json is! List<Object?>) return null;
    final stops = <PaletteStop>[];
    for (final stop in json) {
      if (stop case {'at': final num at, 'color': final String hex}) {
        final color = colorFromHex(hex);
        if (color != null && at.isFinite) stops.add(PaletteStop(at.toDouble(), color));
      }
    }
    return Palette(stops).normalized();
  }

  static double? _double(Object? v) => v is num && v.isFinite ? v.toDouble() : null;
}
