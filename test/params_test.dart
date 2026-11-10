import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:icicles_animation_dart/icicles_animation_dart.dart';
import 'package:icicles_generators/icicles_generators.dart';
import 'package:test/test.dart';

const _label = LocalizedText('x');
const number = NumberParam(id: 'n', label: _label, min: 0, max: 10, defaultValue: 2);
const integer = IntParam(id: 'i', label: _label, min: 1, max: 5, defaultValue: 3);
const flag = BoolParam(id: 'b', label: _label, defaultValue: true);
const choice = ChoiceParam(
  id: 'c',
  label: _label,
  options: [ChoiceOption('a', _label), ChoiceOption('b', _label)],
  defaultValue: 'a',
);
const color = ColorParam(id: 'col', label: _label, defaultValue: Color(0xFF112233));
const palette = PaletteParam(id: 'p', label: _label, defaultValue: Palette.fire);
const text = TextParam(id: 't', label: _label, defaultValue: 'HI', maxLength: 5);
const specs = <ParamSpec>[number, integer, flag, choice, color, palette, text];

/// Features whose [key] column is [values] (one per 10 ms row).
AudioFeatures featuresWith(AudioFeatureKey key, List<double> values) {
  final data = Float32List(values.length * AudioFeatureKey.columnCount);
  for (var i = 0; i < values.length; i++) {
    data[i * AudioFeatureKey.columnCount + key.index] = values[i];
  }
  return AudioFeatures(data);
}

ParamResolver resolver(
  ParamBinding binding, {
  AudioFeatures? audio,
  Tempo? tempo,
  int frameCount = 100,
  Framerate framerate = Framerate.fps30,
}) =>
    ParamResolver(
      specs: const [number],
      bindings: {'n': binding},
      framerate: framerate,
      frameCount: frameCount,
      audio: audio,
      tempo: tempo,
    );

void main() {
  group('LocalizedText', () {
    test('falls back to English', () {
      const text = LocalizedText('Speed', pl: 'Prędkość');
      expect(text.of('pl'), 'Prędkość');
      expect(text.of('de'), 'Speed');
      expect(const LocalizedText('Only').of('pl'), 'Only');
    });
  });

  group('ParamSpec salvage', () {
    test('clamps constants to the spec', () {
      expect(number.salvage(const ConstantBinding(42)), const ConstantBinding(10.0));
      expect(number.salvage(const ConstantBinding(-1)), const ConstantBinding(0.0));
      expect(integer.salvage(const ConstantBinding(2.6)), const ConstantBinding(3));
      expect(integer.salvage(const ConstantBinding(99)), const ConstantBinding(5));
      expect(palette.salvage(const ConstantBinding(Palette([PaletteStop(2, Color(0xFF000000))]))),
          const ConstantBinding(Palette([PaletteStop(1, Color(0xFF000000))])));
      expect(color.salvage(const ConstantBinding(Color(0x80FF0000))), const ConstantBinding(Color(0xFFFF0000)));
    });

    test('replaces missing or mistyped bindings by the default', () {
      expect(number.salvage(null), const ConstantBinding(2.0));
      expect(number.salvage(const ConstantBinding('fast')), const ConstantBinding(2.0));
      expect(flag.salvage(const ConstantBinding(0)), const ConstantBinding(true));
      expect(choice.salvage(const ConstantBinding('zzz')), const ConstantBinding('a'));
      expect(choice.salvage(const ConstantBinding('b')), const ConstantBinding('b'));
      expect(color.salvage(const ConstantBinding('#ff0000')), color.defaultBinding);
      expect(flag.salvage(const RampBinding(from: 0, to: 1)), flag.defaultBinding);
      expect(palette.salvage(const ConstantBinding(Palette([]))), palette.defaultBinding);
    });

    test('text: strings are cut to maxLength, anything else is the default', () {
      expect(text.salvage(const ConstantBinding('Hello, world')), const ConstantBinding('Hello'));
      expect(text.salvage(const ConstantBinding('')), const ConstantBinding(''));
      expect(text.salvage(const ConstantBinding(3)), const ConstantBinding('HI'));
      expect(text.salvage(const RampBinding(from: 0, to: 1)), const ConstantBinding('HI'));
      expect(text.isModulatable, isFalse);
      // The same stored string is a choice or a text depending on the spec.
      expect(choice.salvage(const ConstantBinding('b')), const ConstantBinding('b'));
      expect(choice.salvage(const ConstantBinding('HI')), const ConstantBinding('a'));
      expect(text.salvage(const ConstantBinding('b')), const ConstantBinding('b'));
    });

    test('clamps modulator ranges and fields', () {
      final audio = number.salvage(const AudioBinding(
        feature: AudioFeatureKey.bass,
        min: -5,
        max: 50,
        attack: Duration(seconds: -1),
        release: Duration(minutes: 5),
        curve: 100,
      ));
      expect(
        audio,
        const AudioBinding(
          feature: AudioFeatureKey.bass,
          min: 0,
          max: 10,
          attack: Duration.zero,
          release: AudioBinding.maxSmoothing,
          curve: AudioBinding.maxCurve,
        ),
      );
      expect(
        number.salvage(const BeatBinding(shape: BeatShape.sine, periodBeats: 64, phase: 1.25, min: 1, max: 20)),
        const BeatBinding(shape: BeatShape.sine, periodBeats: 16, phase: 0.25, min: 1, max: 10),
      );
      expect(number.salvage(const RampBinding(from: -3, to: 3)), const RampBinding(from: 0, to: 3));
    });

    test('salvageBindings keeps one valid binding per spec and drops unknown ids', () {
      final salvaged = salvageBindings(specs, {'n': const ConstantBinding(5), 'gone': const ConstantBinding(1)});
      expect(salvaged.keys, unorderedEquals(['n', 'i', 'b', 'c', 'col', 'p', 't']));
      expect(salvaged['n'], const ConstantBinding(5.0));
      expect(salvaged['i'], const ConstantBinding(3));
      expect(defaultBindings(specs)['p'], const ConstantBinding(Palette.fire));
    });
  });

  group('ParamBindingJson', () {
    final bindings = <String, ParamBinding>{
      'n': const ConstantBinding(0.25),
      'i': const ConstantBinding(4),
      'b': const ConstantBinding(false),
      'c': const ConstantBinding('b'),
      't': const ConstantBinding('Zażółć ♥'),
      'col': const ConstantBinding(Color(0xFFFF8800)),
      'p': const ConstantBinding(Palette.ocean),
      'a': const AudioBinding(
        feature: AudioFeatureKey.band3,
        min: 0.2,
        max: 0.8,
        attack: Duration(milliseconds: 15),
        release: Duration(milliseconds: 250),
        curve: 2,
        invert: true,
      ),
      'beat': const BeatBinding(shape: BeatShape.square, periodBeats: 0.5, phase: 0.25, min: 0, max: 1),
      'r': const RampBinding(from: 1, to: 0, curve: RampCurve.sinInOut),
    };

    test('round-trips every binding through JSON text', () {
      final text = jsonEncode(ParamBindingJson.bindingsToJson(bindings));
      expect(ParamBindingJson.bindingsFromJson(jsonDecode(text)), bindings);
    });

    test('has the documented shape', () {
      expect(
          ParamBindingJson.toJson(const ConstantBinding(Color(0xFFFF8800))), {'type': 'constant', 'color': '#ff8800'});
      expect(ParamBindingJson.toJson(const ConstantBinding('HELLO')), {'type': 'constant', 'value': 'HELLO'});
      expect(ParamBindingJson.toJson(bindings['a']!), {
        'type': 'audio',
        'feature': 'band3',
        'min': 0.2,
        'max': 0.8,
        'attackMs': 15.0,
        'releaseMs': 250.0,
        'curve': 2.0,
        'invert': true,
      });
    });

    test('drops unreadable bindings and normalizes fields', () {
      final decoded = ParamBindingJson.bindingsFromJson({
        'bad': {'type': 'audio', 'feature': 'nope', 'min': 0, 'max': 1},
        'worse': 'x',
        'unknown': {'type': 'lfo3000'},
        'color': {'type': 'constant', 'color': '#12'},
        'beat': {'type': 'beat', 'shape': 'saw', 'min': 0, 'max': 1, 'periodBeats': 100},
      });
      expect(decoded, {'beat': const BeatBinding(shape: BeatShape.saw, periodBeats: 16, min: 0, max: 1)});
      expect(ParamBindingJson.bindingsFromJson('nope'), isEmpty);
    });
  });

  group('ParamResolver', () {
    test('constant', () {
      final r = ParamResolver(
        specs: specs,
        bindings: const {'n': ConstantBinding(7)},
        framerate: Framerate.fps30,
        frameCount: 10,
      );
      final values = r.at(3);
      expect(values.number('n'), 7);
      expect(values.integer('i'), 3);
      expect(values.flag('b'), isTrue);
      expect(values.choice('c'), 'a');
      expect(values.color('col'), const Color(0xFF112233));
      expect(values.palette('p'), Palette.fire);
      expect(() => values.number('zzz'), throwsArgumentError);
      expect(() => values.flag('n'), throwsArgumentError);
    });

    test('audio follower: attack and release are one-pole time constants', () {
      // 0 for 1 s, then 1 for 2 s, then 0 for 2 s.
      final audio = featuresWith(AudioFeatureKey.bass, [
        for (var i = 0; i < 100; i++) 0.0,
        for (var i = 0; i < 200; i++) 1.0,
        for (var i = 0; i < 200; i++) 0.0,
      ]);
      const binding = AudioBinding(
        feature: AudioFeatureKey.bass,
        min: 0,
        max: 10,
        attack: Duration(milliseconds: 100),
        release: Duration(milliseconds: 500),
      );
      final r = resolver(binding, audio: audio, framerate: Framerate.fps60, frameCount: 300);
      // Frame 66 starts at 1.1 s: 100 ms (one attack constant) after the rise
      // (7 steps of 1/60 s, as the rise is seen at frame 60).
      expect(r.at(66).number('n'), closeTo(10 * (1 - math.exp(-7 / 6)), 0.05));
      expect(r.at(150).number('n'), closeTo(10, 0.01));
      // Frame 210 starts at 3.5 s: 500 ms (one release constant, 31 steps)
      // after the fall.
      expect(r.at(210).number('n'), closeTo(10 * math.exp(-31 / 30), 0.05));
      // Asking for an earlier frame replays from the start: same results.
      final again = r.at(66).number('n');
      expect(again, resolver(binding, audio: audio, framerate: Framerate.fps60, frameCount: 300).at(66).number('n'));
    });

    test('audio binding: instant follower, curve and invert', () {
      final audio = featuresWith(AudioFeatureKey.level, [for (var i = 0; i < 100; i++) 0.5]);
      final plain = resolver(
        const AudioBinding(feature: AudioFeatureKey.level, min: 2, max: 6, attack: Duration.zero),
        audio: audio,
      );
      expect(plain.at(0).number('n'), closeTo(4, 1e-6));
      final shaped = resolver(
        const AudioBinding(
            feature: AudioFeatureKey.level, min: 0, max: 8, attack: Duration.zero, curve: 2, invert: true),
        audio: audio,
      );
      expect(shaped.at(0).number('n'), closeTo(8 * (1 - 0.25), 1e-6));
    });

    test('audio binding evaluates to min without audio', () {
      final r = resolver(const AudioBinding(feature: AudioFeatureKey.bass, min: 3, max: 9, invert: true));
      expect(r.at(5).number('n'), 3);
      final beat = resolver(const AudioBinding(feature: AudioFeatureKey.beatPulse, min: 1, max: 9));
      expect(beat.at(5).number('n'), 1);
    });

    test('beat shapes against a known tempo', () {
      // 120 BPM: a beat every 500 ms = 15 frames at 30 fps.
      final tempo = Tempo(bpm: 120);
      double at(BeatShape shape, int frame, {double period = 1, double phase = 0}) => resolver(
            BeatBinding(shape: shape, periodBeats: period, phase: phase, min: 0, max: 1),
            tempo: tempo,
          ).at(frame).number('n');
      expect(at(BeatShape.pulse, 15), closeTo(1, 1e-9));
      expect(at(BeatShape.pulse, 22), lessThan(0.1));
      expect(at(BeatShape.saw, 15), closeTo(0, 1e-9));
      expect(at(BeatShape.saw, 9), closeTo(0.6, 0.01));
      expect(at(BeatShape.sine, 30), closeTo(1, 1e-9));
      expect(at(BeatShape.sine, 37), closeTo(0.0, 0.02));
      expect(at(BeatShape.square, 3), 1);
      expect(at(BeatShape.square, 12), 0);
      expect(at(BeatShape.saw, 15, period: 2), closeTo(0.5, 1e-9));
      expect(at(BeatShape.saw, 0, phase: 0.25), closeTo(0.25, 1e-9));
      // Without a tempo: min.
      expect(resolver(const BeatBinding(shape: BeatShape.sine, min: 4, max: 9)).at(0).number('n'), 4);
    });

    test('beat fields follow the tempo on the audio clock', () {
      final r = ParamResolver(
        specs: const [number],
        bindings: const {},
        framerate: Framerate.fps30,
        frameCount: 100,
        tempo: Tempo(bpm: 120, firstBeatOffset: const Duration(milliseconds: 250)),
        audioOrigin: const Duration(seconds: 1),
      );
      // Frame 15 is generator 0.5 s = song 1.5 s = 2.5 beats after 0.25 s.
      final frame = r.audioAt(15);
      expect(frame.beatIndex, 2);
      expect(frame.beatPhase, closeTo(0.5, 1e-9));
      expect(frame.barPhase, closeTo(2.5 / 4, 1e-9));
      expect(frame.beatPulse, closeTo(math.exp(-3), 1e-9));
      expect(frame.bpm, 120);
    });

    test('ramp goes from the first to the last frame', () {
      final r = resolver(const RampBinding(from: 10, to: 0), frameCount: 11);
      expect(r.at(0).number('n'), 10);
      expect(r.at(5).number('n'), closeTo(5, 1e-9));
      expect(r.at(10).number('n'), 0);
      final eased = resolver(const RampBinding(from: 0, to: 10, curve: RampCurve.quadIn), frameCount: 11);
      expect(eased.at(5).number('n'), closeTo(2.5, 1e-9));
    });

    test('integer parameters round modulated values', () {
      final r = ParamResolver(
        specs: const [integer],
        bindings: const {'i': RampBinding(from: 1, to: 5)},
        framerate: Framerate.fps30,
        frameCount: 9,
      );
      expect(r.at(3).integer('i'), 3);
      expect(r.at(3).toMap()['i'], isA<int>());
    });
  });
}
