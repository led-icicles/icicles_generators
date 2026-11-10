import 'package:collection/collection.dart';
import 'package:icicles_animation_dart/icicles_animation_dart.dart';
import 'package:icicles_generators/icicles_generators.dart';
import 'package:test/test.dart';

import 'effect_test_utils.dart';
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

/// Bindings that make an effect whose defaults leave the input unchanged
/// do something; applied to the base and the changed run of every
/// parameter of that effect.
const activations = <String, Map<String, ParamBinding>>{
  'icicles.fx.brightness': {'gain': ConstantBinding(0.5)},
  'icicles.fx.offset': {'dx': ConstantBinding(3.0)},
};

/// Parameters that only matter with another parameter set first.
const companions = <String, Map<String, Map<String, ParamBinding>>>{
  'icicles.fx.mirror': {
    'segments': {'mode': ConstantBinding('kaleidoscope')},
  },
  'icicles.fx.zoom': {
    'wrap': {'scale': ConstantBinding(0.5)},
  },
  // The fire palette starts at black, so keeping black changes nothing there.
  'icicles.fx.palette_remap': {
    'keepBlack': {'palette': ConstantBinding(Palette.ice)},
  },
};

/// Test values for parameters whose automatic [alternative] legitimately
/// leaves the output unchanged.
const overrides = <String, Map<String, ParamBinding>>{
  // A full palette turn is the same palette; 100 LEDs along is 5 wraps of 20.
  'icicles.fx.palette_remap': {'offset': ConstantBinding(0.5)},
  'icicles.fx.offset': {'dy': ConstantBinding(5.0)},
};

Map<String, ParamBinding> companionsOf(Effect effect, ParamSpec spec) {
  final explicit = companions[effect.info.id]?[spec.id];
  if (explicit != null) return explicit;
  for (final suffix in ['LowHz', 'HighHz']) {
    if (spec.id.endsWith(suffix)) {
      final prefix = spec.id.substring(0, spec.id.length - suffix.length);
      if (effect.params.any((p) => p.id == prefix && p is ChoiceParam)) {
        return {prefix: const ConstantBinding('custom')};
      }
    }
  }
  return const {};
}

void main() {
  test('ids are unique and namespaced apart from the generators', () {
    final ids = builtInEffects.map((e) => e.info.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
    expect(ids, everyElement(startsWith('icicles.fx.')));
    expect(ids.toSet().intersection(builtInGenerators.map((g) => g.info.id).toSet()), isEmpty);
    expect(builtInEffectRegistry().find('icicles.fx.trail'), isA<TrailEffect>());
    expect(builtInEffectRegistry().contains('icicles.plasma'), isFalse);
    expect(builtInEffects, hasLength(26));
  });

  test('every category is used and only known ones', () {
    expect(builtInEffects.map((e) => e.info.category).toSet(), EffectCategory.values.toSet());
  });

  test('the audio effects declare it', () {
    for (final id in ['icicles.fx.strobe_gate', 'icicles.fx.gate_audio']) {
      expect(builtInEffectRegistry().find(id)!.info.usesAudio, isTrue, reason: id);
    }
    expect(effectNeedsAudioFeatures(const GateAudioEffect().info, const {}), isTrue);
    expect(effectNeedsAudioFeatures(const FlipEffect().info, const {}), isFalse);
    expect(
      effectNeedsAudioClock(const FlipEffect().info, const {'x': BeatBinding(shape: BeatShape.saw, min: 0, max: 1)}),
      isTrue,
    );
  });

  for (final effect in builtInEffects) {
    group(effect.info.id, () {
      test('has a valid schema with en + pl texts', () {
        final params = effect.params;
        expect(params.length, inInclusiveRange(2, 8));
        expect(params.map((p) => p.id).toSet(), hasLength(params.length));
        expect(effect.info.name.pl, isNotNull);
        expect(effect.info.description.pl, isNotNull);
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

      test('applies over 2 s on 24×20 + 2 panels, deterministically, changing the input', () {
        final activation = activations[effect.info.id] ?? const {};
        final request = effectRequest(bindings: activation);
        final inputs = syntheticInputs(request);
        final outputs = applyAll(effect, request, inputs);
        expect(outputs, hasLength(60));
        for (var i = 0; i < outputs.length; i++) {
          expect(outputs[i].frame.duration, inputs[i].frame.duration);
          expect(outputs[i].frame.pixels, hasLength(testSetup.pixelsCount));
          expect(outputs[i].radioPanels.map((p) => p.index), [1, 2]);
        }
        final bytes = viewBytes(testSetup, outputs);
        expect(bytes, effectBytes(effect, effectRequest(bindings: activation)), reason: 'deterministic');
        expect(const ListEquality<int>().equals(bytes, viewBytes(testSetup, inputs)), isFalse, reason: 'no change');
        expect(outputs.any((v) => !isBlack(v)), isTrue, reason: 'all black');
      });

      test('changes with each of its parameters', () {
        final activation = activations[effect.info.id] ?? const {};
        for (final spec in effect.params) {
          final binding = overrides[effect.info.id]?[spec.id] ?? alternative(spec);
          final companion = {...activation, ...companionsOf(effect, spec)};
          final reference = effectBytes(effect, effectRequest(bindings: companion));
          final changed = effectBytes(effect, effectRequest(bindings: {...companion, spec.id: binding}));
          expect(const ListEquality<int>().equals(changed, reference), isFalse, reason: '${spec.id} has no effect');
        }
      });
    });
  }

  group('identities', () {
    test('brightness at gain 1, gamma 1, contrast 1 leaves the input', () {
      final request = effectRequest();
      final inputs = syntheticInputs(request);
      expect(effectBytes(const BrightnessEffect(), request, inputs), viewBytes(testSetup, inputs));
    });

    test('offset 0 leaves the input', () {
      final request = effectRequest();
      final inputs = syntheticInputs(request);
      expect(effectBytes(const OffsetEffect(), request, inputs), viewBytes(testSetup, inputs));
    });

    test('flipping twice is the identity, for every axis', () {
      for (final axis in ['horizontal', 'vertical', 'both']) {
        final request = effectRequest(bindings: {'axis': ConstantBinding(axis)});
        final inputs = syntheticInputs(request);
        final once = applyAll(const FlipEffect(), request, inputs);
        expect(viewBytes(testSetup, once), isNot(viewBytes(testSetup, inputs)), reason: axis);
        expect(effectBytes(const FlipEffect(), request, once), viewBytes(testSetup, inputs), reason: axis);
      }
    });

    test('rotate 180° twice is the identity', () {
      final request = effectRequest();
      final inputs = syntheticInputs(request);
      final once = applyAll(const Rotate180Effect(), request, inputs);
      expect(effectBytes(const Rotate180Effect(), request, once), viewBytes(testSetup, inputs));
    });

    test('invert twice is the identity', () {
      final request = effectRequest();
      final inputs = syntheticInputs(request);
      final once = applyAll(const InvertEffect(), request, inputs);
      expect(effectBytes(const InvertEffect(), request, once), viewBytes(testSetup, inputs));
    });

    test('a hue shift of a full turn leaves the input', () {
      final request = effectRequest(bindings: const {'shift': ConstantBinding(1.0)});
      final inputs = syntheticInputs(request);
      expect(effectBytes(const HueShiftEffect(), request, inputs), viewBytes(testSetup, inputs));
    });
  });

  group('stateful effects', () {
    test('trail decays to black after the input goes black', () {
      final request = effectRequest(bindings: const {'fade': ConstantBinding(0.2)}, seconds: 4);
      final lit = syntheticInputs(request);
      final dark = blackInputs(request);
      final inputs = [...lit.sublist(0, 30), ...dark.sublist(30)];
      final outputs = applyAll(const TrailEffect(), request, inputs);
      expect(isBlack(outputs[30]), isFalse, reason: 'still trailing right after the input goes black');
      expect(isBlack(outputs[31]), isFalse);
      expect(outputs.skip(90).every(isBlack), isTrue, reason: 'faded out 2 s later');
      // Keeps the trail brighter than a plain fade would: the last lit frame
      // decays, it never comes back.
      final afterward = outputs.sublist(31, 90);
      for (var i = 1; i < afterward.length; i++) {
        final previous = afterward[i - 1].frame.pixels.fold(0, (sum, c) => sum + c.red + c.green + c.blue);
        final current = afterward[i].frame.pixels.fold(0, (sum, c) => sum + c.red + c.green + c.blue);
        expect(current, lessThanOrEqualTo(previous));
      }
    });

    test('echo repeats a flash after the delay and fades it', () {
      final request = effectRequest(
        bindings: const {'delay': ConstantBinding(0.5), 'taps': ConstantBinding(2), 'decay': ConstantBinding(0.5)},
      );
      final black = blackInputs(request);
      final flash = syntheticInputs(request)[0];
      final inputs = [flash, ...black.sublist(1)];
      final outputs = applyAll(const EchoEffect(), request, inputs);
      expect(isBlack(outputs[1]), isTrue);
      expect(isBlack(outputs[15]), isFalse, reason: 'first echo after 15 frames');
      expect(isBlack(outputs[16]), isTrue);
      expect(isBlack(outputs[30]), isFalse, reason: 'second echo');
      expect(isBlack(outputs[45]), isTrue, reason: 'only two taps');
      final white = flash.frame.pixels.indexWhere((c) => c.value == 0xFFFFFFFF);
      expect(outputs[15].frame.pixels[white].red, closeTo(128, 1));
      expect(outputs[30].frame.pixels[white].red, closeTo(64, 1));
    });
  });

  group('EffectRunner', () {
    test('rejects inputs of another layout and frames outside the request', () {
      final runner = EffectRunner(const FlipEffect(), effectRequest());
      final other = BakeRequest.forLength(setup: testSetup.copyWith(xCount: 10), length: const Duration(seconds: 1));
      Matcher kind(GeneratorErrorKind k) => throwsA(isA<GeneratorException>().having((e) => e.kind, 'kind', k));
      expect(() => runner.applyAt(0, syntheticInputs(other)[0]), kind(GeneratorErrorKind.invalidRequest));
      expect(() => runner.applyAt(60, syntheticInputs(effectRequest())[0]), kind(GeneratorErrorKind.invalidRequest));
      expect(() => runner.applyAt(-1, syntheticInputs(effectRequest())[0]), kind(GeneratorErrorKind.invalidRequest));
      expect(
        () => EffectRunner(const FlipEffect(), const BakeRequest(setup: testSetup, frameCount: 0)),
        kind(GeneratorErrorKind.invalidRequest),
      );
    });

    test('an effect that throws is a render failure with its cause', () {
      final runner = EffectRunner(const _Broken(), effectRequest());
      expect(
        () => runner.applyAt(0, syntheticInputs(effectRequest())[0]),
        throwsA(isA<GeneratorException>()
            .having((e) => e.kind, 'kind', GeneratorErrorKind.renderFailed)
            .having((e) => e.cause, 'cause', isA<StateError>())),
      );
    });

    test('going back to an earlier frame starts the run over', () {
      final request = effectRequest();
      final inputs = syntheticInputs(request);
      final runner = EffectRunner(const TrailEffect(), request);
      final fresh = runner.applyAt(0, inputs[0]);
      runner.applyAt(1, inputs[1]);
      runner.applyAt(2, inputs[2]);
      expect(runner.lastFrameIndex, 2);
      final again = runner.applyAt(0, inputs[0]);
      expect(viewBytes(testSetup, [again]), viewBytes(testSetup, [fresh]));
      expect(runner.lastFrameIndex, 0);
      // Skipping forward keeps the state (the trail of frame 0 is still there).
      final skipped = runner.applyAt(5, blackInputs(request)[5]);
      expect(isBlack(skipped), isFalse);
    });

    test('bindings follow the frame grid: a ramp changes the output over time', () {
      final request = effectRequest(bindings: const {'gain': RampBinding(from: 0, to: 1)});
      final inputs = syntheticInputs(request);
      final outputs = applyAll(const BrightnessEffect(), request, inputs);
      expect(isBlack(outputs.first), isTrue);
      expect(viewBytes(testSetup, [outputs.last]), viewBytes(testSetup, [inputs.last]));
    });

    test('the default bindings of an unknown parameter id are salvaged', () {
      final request = effectRequest(bindings: const {'nope': ConstantBinding(3.0)});
      expect(EffectRunner(const FlipEffect(), request).applyAt(0, syntheticInputs(request)[0]), isNotNull);
    });
  });
}

final class _Broken implements Effect {
  const _Broken();

  @override
  EffectInfo get info => const EffectInfo(
        id: 'test/broken',
        version: 1,
        name: LocalizedText('Broken'),
        description: LocalizedText(''),
        category: EffectCategory.color,
      );

  @override
  List<ParamSpec> get params => const [];

  @override
  EffectInstance create(GeneratorSetup setup) => const _BrokenInstance();
}

final class _BrokenInstance implements EffectInstance {
  const _BrokenInstance();

  @override
  void apply(FrameContext ctx, AnimationView input, Icicles out) => throw StateError('no');
}
