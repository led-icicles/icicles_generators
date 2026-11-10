import 'package:collection/collection.dart';
import 'package:icicles_animation_dart/icicles_animation_dart.dart';
import 'package:icicles_generators/icicles_generators.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// A value of [spec] different from its default.
ParamBinding alternative(ParamSpec spec) => switch (spec) {
      NumberParam(:final min, :final max, :final defaultValue) => ConstantBinding(defaultValue == max ? min : max),
      IntParam(:final min, :final max, :final defaultValue) => ConstantBinding(defaultValue == max ? min : max),
      BoolParam(:final defaultValue) => ConstantBinding(!defaultValue),
      ChoiceParam(:final options, :final defaultValue) =>
        ConstantBinding(options.firstWhere((o) => o.id != defaultValue).id),
      TextParam(:final defaultValue) => ConstantBinding(defaultValue == 'X' ? 'Y' : 'X'),
      ColorParam() => const ConstantBinding(Color(0xFF10FF20)),
      PaletteParam(:final defaultValue) => ConstantBinding(defaultValue == Palette.fire ? Palette.ice : Palette.fire),
    };

/// Test values for parameters whose automatic [alternative] legitimately
/// leaves 2 s of output unchanged.
/// Parameters that only matter with another parameter set first: the base
/// bake and the changed bake both get [companions] applied.
const companions = <String, Map<String, Map<String, ParamBinding>>>{
  // Threshold and flash length are read only by the audio triggers; the
  // range only by the range trigger.
  'icicles.strobe': {
    'threshold': {'trigger': ConstantBinding('bass')},
    'flashMs': {'trigger': ConstantBinding('bass')},
    'range': {'trigger': ConstantBinding('range')},
    'rangeLowHz': {'trigger': ConstantBinding('range'), 'range': ConstantBinding('custom')},
    'rangeHighHz': {'trigger': ConstantBinding('range'), 'range': ConstantBinding('custom')},
  },
};

/// The companions of [spec] in [generator]: the explicit ones, else the
/// custom preset for the `…LowHz`/`…HighHz` parameters of [audioRangeParams].
Map<String, ParamBinding> companionsOf(Generator generator, ParamSpec spec) {
  final explicit = companions[generator.info.id]?[spec.id];
  if (explicit != null) return explicit;
  for (final suffix in ['LowHz', 'HighHz']) {
    if (spec.id.endsWith(suffix)) {
      final prefix = spec.id.substring(0, spec.id.length - suffix.length);
      if (generator.params.any((p) => p.id == prefix && p is ChoiceParam)) {
        return {prefix: const ConstantBinding('custom')};
      }
    }
  }
  return const {};
}

const overrides = <String, Map<String, ParamBinding>>{
  // A constant trigger rises only at frame 0, where the interval timer fires
  // the same wave; a ramp crosses ½ at 1 s and adds one.
  'icicles.shockwave': {'trigger': RampBinding(from: 0, to: 1)},
  // "Open once" equals the first half of "open and close" (3 s period).
  'icicles.curtain': {'motion': ConstantBinding('close')},
  // A full turn of the hue wheel is the same hue.
  'icicles.freq_color': {'hueOffset': ConstantBinding(0.5)},
};

void main() {
  test('ids are unique and namespaced', () {
    final ids = builtInGenerators.map((g) => g.info.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
    expect(ids, everyElement(startsWith('icicles.')));
    expect(builtInGeneratorRegistry().find('icicles.plasma'), isA<PlasmaGenerator>());
    expect(builtInGeneratorRegistry().find('icicles.text'), isA<TextGenerator>());
    expect(builtInGenerators, hasLength(52));
  });

  test('every audio generator that follows the spectrum has the shared range params', () {
    const ranged = [
      'icicles.vu_meter',
      'icicles.spectrum',
      'icicles.bass_pulse',
      'icicles.onset_drops',
      'icicles.spectrum_mirror',
      'icicles.waveform_scroll',
      'icicles.freq_color',
      'icicles.ripple_peak',
      'icicles.strobe',
    ];
    final registry = builtInGeneratorRegistry();
    for (final id in ranged) {
      final ids = registry.find(id)!.params.map((p) => p.id).toList();
      expect(ids, containsAll(['range', 'rangeLowHz', 'rangeHighHz']), reason: id);
    }
    expect(
        registry
            .find('icicles.bass_pulse')!
            .params
            .whereType<ChoiceParam>()
            .firstWhere((p) => p.id == 'range')
            .defaultValue,
        'lows');
    expect(
        registry
            .find('icicles.spectrum')!
            .params
            .whereType<ChoiceParam>()
            .firstWhere((p) => p.id == 'range')
            .defaultValue,
        'full');
  });

  test('every category is used and only known ones', () {
    final used = builtInGenerators.map((g) => g.info.category).toSet();
    expect(used, GeneratorCategory.values.toSet());
  });

  for (final generator in builtInGenerators) {
    group(generator.info.id, () {
      test('has a valid schema with en + pl texts', () {
        final params = generator.params;
        expect(params.length, inInclusiveRange(3, 11));
        expect(params.map((p) => p.id).toSet(), hasLength(params.length));
        expect(generator.info.name.pl, isNotNull);
        expect(generator.info.description.pl, isNotNull);
        for (final spec in params) {
          expect(spec.label.pl, isNotNull, reason: spec.id);
          expect(spec.salvage(spec.defaultBinding), spec.defaultBinding, reason: spec.id);
          if (spec is ChoiceParam) {
            expect(spec.options.map((o) => o.id), contains(spec.defaultValue));
            for (final option in spec.options) {
              expect(option.label.pl, isNotNull);
            }
          }
        }
      });

      test('renders 2 s on 24×20 + 2 panels, deterministically', () {
        final request = testRequest();
        final animation = bakeGenerator(generator, request);
        expect(animation.duration, testSetup.framerate.frameStart(60));
        final index = animation.toIndex();
        expect(index.duration, const Duration(seconds: 2));
        final lit = index.views.any((v) => v.frame.pixels.any((c) => c.value & 0xFFFFFF != 0));
        expect(lit, isTrue, reason: 'draws something');
        expect(bakeBytes(generator, testRequest()), animation.toBytes());
      });

      test('changes with each of its parameters', () {
        final base = bakeBytes(generator, testRequest());
        for (final spec in generator.params) {
          final binding = overrides[generator.info.id]?[spec.id] ?? alternative(spec);
          final companion = companionsOf(generator, spec);
          final reference = companion.isEmpty ? base : bakeBytes(generator, testRequest(bindings: companion));
          final changed = bakeBytes(generator, testRequest(bindings: {...companion, spec.id: binding}));
          expect(const ListEquality<int>().equals(changed, reference), isFalse, reason: '${spec.id} has no effect');
        }
      });
    });
  }
}
