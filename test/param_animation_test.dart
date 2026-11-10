import 'dart:convert';
import 'dart:math' as math;

import 'package:icicles_animation_dart/icicles_animation_dart.dart';
import 'package:icicles_generators/icicles_generators.dart';
import 'package:test/test.dart';

import 'params_test.dart' show featuresWith;

const _label = LocalizedText('x');
const number = NumberParam(id: 'n', label: _label, min: 0, max: 10, defaultValue: 2);
const integer = IntParam(id: 'i', label: _label, min: 0, max: 100, defaultValue: 50);
const color = ColorParam(id: 'col', label: _label, defaultValue: Color(0xFF112233));

const red = Color(0xFFFF0000);
const blue = Color(0xFF0000FF);

ParamResolver resolver(
  ParamBinding binding, {
  AudioFeatures? audio,
  Tempo? tempo,
  int frameCount = 300,
  Framerate framerate = Framerate.fps30,
  Map<String, ParamBinding> macros = const {},
  int seed = 0,
  ParamSpec spec = number,
}) =>
    ParamResolver(
      specs: [spec],
      bindings: {spec.id: binding},
      framerate: framerate,
      frameCount: frameCount,
      audio: audio,
      tempo: tempo,
      macros: macros,
      seed: seed,
    );

double numberAt(ParamResolver r, int frame) => r.at(frame).number('n');

List<double> series(ParamResolver r, int count) => [for (var i = 0; i < count; i++) numberAt(r, i)];

void main() {
  group('Easing', () {
    test('presets at the ends and the middle', () {
      for (final easing in [Easing.linear, Easing.easeIn, Easing.easeOut, Easing.easeInOut]) {
        expect(easing.transform(0), 0, reason: '$easing');
        expect(easing.transform(1), 1, reason: '$easing');
      }
      expect(Easing.linear.transform(0.25), 0.25);
      expect(Easing.easeIn.transform(0.5), lessThan(0.5));
      expect(Easing.easeOut.transform(0.5), greaterThan(0.5));
      expect(Easing.easeInOut.transform(0.5), closeTo(0.5, 1e-9));
      expect(Easing.easeIn.transform(0.5), closeTo(Curves.cubicIn.transform(0.5), 1e-12));
      expect(Easing.hold.transform(0.999), 0);
      expect(Easing.hold.transform(1), 1);
      expect(Easing.linear.transform(double.nan), 0);
    });

    test('bezier solves the cubic and is monotonic for monotonic control points', () {
      const ease = Easing.bezier(0.25, 0.1, 0.25, 1.0);
      const straight = Easing.bezier(0, 0, 1, 1);
      const steep = Easing.bezier(0.42, 0, 0.58, 1);
      for (final curve in [ease, straight, steep, const Easing.bezier(1, 0, 0, 1), const Easing.bezier(0, 1, 1, 0)]) {
        var previous = 0.0;
        for (var i = 0; i <= 200; i++) {
          final v = curve.transform(i / 200);
          expect(v, greaterThanOrEqualTo(previous - 1e-9), reason: '$curve at ${i / 200}');
          previous = v;
        }
        expect(curve.transform(0), 0);
        expect(curve.transform(1), 1);
      }
      for (var i = 0; i <= 20; i++) {
        expect(straight.transform(i / 20), closeTo(i / 20, 1e-6));
      }
      expect(steep.transform(0.5), closeTo(0.5, 1e-6));
      expect(ease.transform(0.5), closeTo(0.8024, 1e-3), reason: 'CSS "ease" at 0.5');
      // Overshoot: y outside 0..1 is allowed within BezierEasing.minY..maxY.
      const back = Easing.bezier(0.3, 1.5, 0.7, 1.5);
      expect(back.transform(0.5), greaterThan(1));
    });

    test('bezier normalizes its control points', () {
      expect(
        const BezierEasing(-1, 5, 2, double.nan).normalized(),
        const BezierEasing(0, BezierEasing.maxY, 1, 0),
      );
      expect(const Easing.bezier(2, 0, -1, 1).transform(0.5),
          closeTo(const Easing.bezier(1, 0, 0, 1).transform(0.5), 1e-9));
    });
  });

  group('KeyframeBinding', () {
    const rise = KeyframeBinding(keys: [Keyframe(at: 0, value: 0), Keyframe(at: 1, value: 10)]);

    test('interpolates between keys and holds outside them', () {
      final r = resolver(const KeyframeBinding(keys: [Keyframe(at: 1, value: 2), Keyframe(at: 2, value: 8)]));
      expect(numberAt(r, 0), 2, reason: 'before the first key');
      expect(numberAt(r, 30), 2);
      expect(numberAt(r, 45), closeTo(5, 1e-9), reason: 'halfway at 1.5 s');
      expect(numberAt(r, 60), 8);
      expect(numberAt(r, 200), 8, reason: 'after the last key');
    });

    test('uses the first key\'s easing per segment (Premiere style)', () {
      final linear = resolver(rise);
      expect(numberAt(linear, 15), closeTo(5, 1e-9));
      final eased = resolver(const KeyframeBinding(keys: [
        Keyframe(at: 0, value: 0, easing: Easing.easeIn),
        Keyframe(at: 1, value: 10, easing: Easing.hold),
        Keyframe(at: 2, value: 0),
      ]));
      expect(numberAt(eased, 15), closeTo(10 * Curves.cubicIn.transform(0.5), 1e-9));
      expect(numberAt(eased, 45), 10, reason: 'hold keeps the key value until the next key');
      expect(numberAt(eased, 60), 0);
      final bezier = resolver(const KeyframeBinding(keys: [
        Keyframe(at: 0, value: 0, easing: Easing.bezier(0.42, 0, 0.58, 1)),
        Keyframe(at: 1, value: 10),
      ]));
      expect(numberAt(bezier, 15), closeTo(5, 1e-5));
      expect(numberAt(bezier, 3), lessThan(1), reason: 'slow start');
    });

    test('loops over the span of the keys', () {
      final r =
          resolver(const KeyframeBinding(keys: [Keyframe(at: 0, value: 0), Keyframe(at: 1, value: 10)], loop: true));
      expect(numberAt(r, 15), closeTo(5, 1e-9));
      expect(numberAt(r, 45), closeTo(5, 1e-9), reason: '1.5 s wraps to 0.5 s');
      expect(numberAt(r, 30), closeTo(0, 1e-9), reason: '1 s wraps to 0 s');
      final shifted = resolver(
        const KeyframeBinding(keys: [Keyframe(at: 1, value: 0), Keyframe(at: 2, value: 10)], loop: true),
      );
      expect(numberAt(shifted, 15), closeTo(5, 1e-9), reason: '0.5 s wraps to 1.5 s');
      // A single key never wraps and is a constant.
      expect(numberAt(resolver(const KeyframeBinding(keys: [Keyframe(at: 3, value: 7)], loop: true)), 10), 7);
    });

    test('beats time base counts clip beats at the tempo\'s BPM, 120 without one', () {
      const beats = KeyframeBinding(
        keys: [Keyframe(at: 0, value: 0), Keyframe(at: 4, value: 10)],
        timeBase: KeyTime.beats,
      );
      expect(beats.usesTempo, isTrue);
      expect(rise.usesTempo, isFalse);
      // 120 BPM: 4 beats = 2 s; frame 30 is 1 s.
      expect(numberAt(resolver(beats, tempo: Tempo(bpm: 120)), 30), closeTo(5, 1e-9));
      expect(numberAt(resolver(beats), 30), closeTo(5, 1e-9), reason: 'fallback 120 BPM');
      // 60 BPM: 4 beats = 4 s.
      expect(numberAt(resolver(beats, tempo: Tempo(bpm: 60)), 30), closeTo(2.5, 1e-9));
      // The tempo's grid offset does not move clip-local keys.
      expect(
        numberAt(resolver(beats, tempo: Tempo(bpm: 120, firstBeatOffset: const Duration(milliseconds: 300))), 30),
        closeTo(5, 1e-9),
      );
    });

    test('color keys interpolate in HSV along the shortest hue path', () {
      const binding = KeyframeBinding(keys: [Keyframe(at: 0, value: red), Keyframe(at: 1, value: blue)]);
      final r = resolver(binding, spec: color);
      expect(r.at(0).color('col'), red);
      expect(r.at(30).color('col'), blue);
      final mid = r.at(15).color('col');
      // Red (hue 0) to blue (hue 2/3) is shorter backwards through magenta (5/6).
      expect(hsvOf(mid).hue, closeTo(5 / 6, 0.01));
      expect(mid.green, 0);
      expect(lerpHsv(red, const Color(0xFF00FF00), 0.5).blue, 0, reason: 'red to green goes through yellow');
      expect(hsvOf(lerpHsv(red, const Color(0xFF00FF00), 0.5)).hue, closeTo(1 / 6, 0.01));
      // A grey takes the other color's hue: red fading to black keeps red.
      final dark = lerpHsv(red, const Color(0xFF000000), 0.5);
      expect(dark.red, closeTo(128, 1));
      expect(dark.green, 0);
      // Integer parameters round keyframed values.
      final ints =
          resolver(const KeyframeBinding(keys: [Keyframe(at: 0, value: 0), Keyframe(at: 1, value: 9)]), spec: integer);
      expect(ints.at(15).integer('i'), 5);
      expect(ints.at(15).toMap()['i'], isA<int>());
    });

    test('salvage keeps the keys of the right type, sorted, clamped', () {
      final salvaged = number.salvage(const KeyframeBinding(keys: [
        Keyframe(at: 2, value: 50),
        Keyframe(at: -1, value: 1, easing: Easing.bezier(3, 0, -1, 1)),
        Keyframe(at: 0.5, value: red),
        Keyframe(at: 2, value: 3),
        Keyframe(at: double.nan, value: 4),
      ]));
      expect(
        salvaged,
        const KeyframeBinding(keys: [
          Keyframe(at: 0, value: 1.0, easing: Easing.bezier(1, 0, 0, 1)),
          Keyframe(at: 0, value: 4.0),
          Keyframe(at: 2, value: 10.0),
          Keyframe(at: 2, value: 3.0),
        ]),
      );
      expect(number.salvage(const KeyframeBinding(keys: [Keyframe(at: 0, value: red)])), number.defaultBinding);
      expect(
        color.salvage(
            const KeyframeBinding(keys: [Keyframe(at: 1, value: 3), Keyframe(at: 0, value: Color(0x80FF0000))])),
        const KeyframeBinding(keys: [Keyframe(at: 0, value: red)]),
      );
      expect(color.salvage(const KeyframeBinding(keys: [Keyframe(at: 0, value: 3)])), color.defaultBinding);
      expect(integer.salvage(const KeyframeBinding(keys: [Keyframe(at: 0, value: 500)])),
          const KeyframeBinding(keys: [Keyframe(at: 0, value: 100.0)]));
      // Two keys at the same time: the later one wins at that time.
      final r = resolver(const KeyframeBinding(keys: [
        Keyframe(at: 0, value: 1),
        Keyframe(at: 1, value: 5),
        Keyframe(at: 1, value: 9),
        Keyframe(at: 2, value: 9),
      ]));
      expect(numberAt(r, 30), 9);
      expect(numberAt(r, 15), closeTo(3, 1e-9));
    });
  });

  group('RandomBinding', () {
    final tempo = Tempo(bpm: 120);
    const perBeat = RandomBinding(mode: RandomMode.perBeat, min: 0, max: 10);

    test('is deterministic from the seed and the hold index', () {
      final a = series(resolver(perBeat, tempo: tempo, seed: 5), 90);
      final b = series(resolver(perBeat, tempo: tempo, seed: 5), 90);
      expect(a, b);
      expect(series(resolver(perBeat, tempo: tempo, seed: 6), 90), isNot(a), reason: 'the resolver seed');
      expect(series(resolver(perBeat.copyWith(seed: 5), tempo: tempo, seed: 6), 90), a, reason: 'own seed wins');
      expect(a.every((v) => v >= 0 && v < 10), isTrue);
      // Replaying from an earlier frame gives the same values.
      final r = resolver(perBeat, tempo: tempo, seed: 5);
      final late = numberAt(r, 80);
      numberAt(r, 2);
      expect(numberAt(r, 80), late);
    });

    test('holds per beat, bar, time or frame', () {
      final beat = series(resolver(perBeat, tempo: tempo), 45);
      expect(beat.sublist(0, 15).toSet(), hasLength(1), reason: 'a beat is 15 frames');
      expect(beat.sublist(15, 30).toSet(), hasLength(1));
      expect(beat[0], isNot(beat[15]));
      expect(beat[15], isNot(beat[30]));
      final bar = series(resolver(perBeat.copyWith(mode: RandomMode.perBar), tempo: tempo), 120);
      expect(bar.sublist(0, 60).toSet(), hasLength(1), reason: 'a bar is 4 beats');
      expect(bar[0], isNot(bar[60]));
      final timed = series(
        resolver(perBeat.copyWith(mode: RandomMode.perTime, interval: const Duration(milliseconds: 200))),
        18,
      );
      expect(timed.sublist(0, 6).toSet(), hasLength(1));
      expect(timed.sublist(6, 12).toSet(), hasLength(1));
      expect(timed[0], isNot(timed[6]));
      final frames = series(resolver(perBeat.copyWith(mode: RandomMode.perFrame)), 30);
      expect(frames.toSet().length, greaterThan(25));
      // Without a tempo the beat modes count 120 BPM on clip time.
      final fallback = series(resolver(perBeat), 45);
      expect(fallback.sublist(0, 15).toSet(), hasLength(1));
      expect(fallback[0], isNot(fallback[15]));
      // On the song grid: the audio origin shifts the holds.
      final shifted = ParamResolver(
        specs: const [number],
        bindings: const {'n': perBeat},
        framerate: Framerate.fps30,
        frameCount: 100,
        tempo: tempo,
        audioOrigin: const Duration(milliseconds: 250),
      );
      expect(numberAt(shifted, 7), isNot(numberAt(shifted, 8)), reason: 'the beat falls at 0.25 s');
      expect(perBeat.usesTempo, isTrue);
      expect(perBeat.copyWith(mode: RandomMode.perFrame).usesTempo, isFalse);
    });

    test('smooth glides between the holds', () {
      final stepped = series(resolver(perBeat, tempo: tempo), 45);
      final smooth = series(resolver(perBeat.copyWith(smooth: 0.5), tempo: tempo), 45);
      expect(smooth[0], stepped[0], reason: 'the first frame starts at its target');
      expect(smooth[15], isNot(stepped[15]), reason: 'glides instead of jumping');
      // Each frame of the hold moves monotonically towards the target.
      final target = stepped[15];
      for (var i = 15; i < 29; i++) {
        expect((target - smooth[i + 1]).abs(), lessThan((target - smooth[i]).abs()));
      }
      // One time constant = smooth × hold: after 7.5 frames ~63 % of the way.
      final progress = (smooth[22] - smooth[14]) / (target - smooth[14]);
      expect(progress, closeTo(1 - math.exp(-8 / 7.5), 0.05));
      expect(number.salvage(perBeat.copyWith(smooth: 3, min: -4, max: 40, interval: Duration.zero)),
          perBeat.copyWith(smooth: 1, min: 0, max: 10, interval: RandomBinding.minInterval));
    });

    test('uniformHash is platform-stable', () {
      expect(uniformHash(0, 0), closeTo(uniformHash(0, 0), 0));
      expect(uniformHash(1, 0), isNot(uniformHash(0, 0)));
      expect(uniformHash(0, -1), isNot(uniformHash(0, 1)));
      expect(uniformHash(0, 1 << 40), isNot(uniformHash(0, 0)));
      final values = [for (var i = 0; i < 1000; i++) uniformHash(3, i)];
      expect(values.every((v) => v >= 0 && v < 1), isTrue);
      expect(values.reduce((a, b) => a + b) / 1000, closeTo(0.5, 0.05));
    });
  });

  group('StepBinding', () {
    final tempo = Tempo(bpm: 120);
    // 4 steps per bar at 120 BPM: one step per beat = 15 frames.
    const steps = StepBinding(steps: [1, 0, 0.5, 0], stepsPerBar: 4, min: 0, max: 10);

    test('plays the steps in bar time, cycling', () {
      final r = resolver(steps, tempo: tempo);
      expect(numberAt(r, 0), 10);
      expect(numberAt(r, 14), 10);
      expect(numberAt(r, 15), 0);
      expect(numberAt(r, 30), 5);
      expect(numberAt(r, 45), 0);
      expect(numberAt(r, 60), 10, reason: 'the bar repeats');
      // 16 steps per bar (the default) at 120 BPM: a step every 3.75 frames.
      final sixteenth = resolver(const StepBinding(steps: [1, 0], min: 0, max: 10), tempo: tempo);
      expect(numberAt(sixteenth, 0), 10);
      expect(numberAt(sixteenth, 4), 0);
      expect(numberAt(sixteenth, 8), 10);
      // Three steps over 4 per bar: the pattern does not align with the bar.
      final three = resolver(const StepBinding(steps: [1, 0, 0.5], stepsPerBar: 4, min: 0, max: 10), tempo: tempo);
      expect([for (var i = 0; i < 6; i++) numberAt(three, i * 15)], [10, 0, 5, 10, 0, 5]);
      // Without a tempo: 120 BPM.
      expect(numberAt(resolver(steps), 30), 5);
      expect(steps.usesTempo, isTrue);
    });

    test('gate holds the value for a fraction of the step, then min', () {
      final r = resolver(steps.copyWith(gate: 0.5), tempo: tempo);
      expect(numberAt(r, 7), 10, reason: 'phase 0.47');
      expect(numberAt(r, 8), 0, reason: 'phase 0.53');
      expect(numberAt(r, 30), 5);
      expect(numberAt(r, 38), 0);
    });

    test('smooth slides from each step to the next', () {
      final r = resolver(steps.copyWith(smooth: true), tempo: tempo);
      expect(numberAt(r, 0), 10);
      expect(numberAt(r, 7), closeTo(10 - 10 * 7 / 15, 0.02), reason: 'frame 7 is 233 ms on the ms grid');
      expect(numberAt(r, 15), 0);
      expect(numberAt(r, 52), closeTo(0 + 10 * 7 / 15, 0.02), reason: 'the last step slides into the first');
    });

    test('salvage clamps the levels and counts, rejects fewer than 2 steps', () {
      expect(
        number.salvage(const StepBinding(steps: [2, -1, 0.5], stepsPerBar: 1000, min: -1, max: 99, gate: 4)),
        const StepBinding(steps: [1, 0, 0.5], stepsPerBar: 64, min: 0, max: 10, gate: 1),
      );
      expect(number.salvage(const StepBinding(steps: [1], min: 0, max: 1)), number.defaultBinding);
      final long = number.salvage(StepBinding(steps: List.filled(100, 0.5), min: 0, max: 1)) as StepBinding;
      expect(long.steps, hasLength(StepBinding.maxSteps));
    });
  });

  group('EnvelopeBinding', () {
    const adsr = EnvelopeBinding(
      trigger: EnvelopeTrigger.beat,
      attack: Duration(milliseconds: 100),
      decay: Duration(milliseconds: 100),
      sustain: Duration(milliseconds: 100),
      release: Duration(milliseconds: 200),
      sustainLevel: 0.5,
      min: 0,
      max: 10,
    );

    test('has the ADSR shape from a beat trigger', () {
      // 60 BPM: a beat every second; frame 3 at 30 fps is 100 ms.
      final r = resolver(adsr, tempo: Tempo(bpm: 60));
      expect(numberAt(r, 0), 0, reason: 'the attack starts at the beat');
      expect(numberAt(r, 1), closeTo(10 / 3, 0.05), reason: 'frame 1 is 33 ms on the ms grid');
      expect(numberAt(r, 3), closeTo(10, 1e-6), reason: 'attack done');
      expect(numberAt(r, 6), closeTo(5, 1e-6), reason: 'decayed to the sustain level');
      expect(numberAt(r, 8), closeTo(5, 1e-6), reason: 'sustain');
      expect(numberAt(r, 9), closeTo(5, 1e-6), reason: 'release starts');
      expect(numberAt(r, 12), closeTo(2.5, 1e-6));
      expect(numberAt(r, 15), closeTo(0, 1e-6));
      expect(numberAt(r, 20), 0);
      expect(numberAt(r, 33), closeTo(10, 1e-6), reason: 'the next beat');
      // Bars: once every 4 beats.
      final bar = resolver(adsr.copyWith(trigger: EnvelopeTrigger.bar), tempo: Tempo(bpm: 120));
      expect(numberAt(bar, 3), greaterThan(0));
      expect(numberAt(bar, 18), 0, reason: 'the second beat is not a bar');
      expect(numberAt(bar, 63), greaterThan(0), reason: 'the fifth beat starts a bar');
      // Without a tempo the beat trigger runs at 120 BPM on clip time.
      expect(numberAt(resolver(adsr), 18), greaterThan(0));
      expect(adsr.usesTempo, isTrue);
      expect(adsr.usesAudioFeatures, isFalse);
    });

    test('onset and range triggers fire on rising edges and retrigger or not', () {
      // Hits at 0 ms and 100 ms (frames 0 and 3 at 30 fps), then silence.
      final onsets = featuresWith(AudioFeatureKey.onset, [
        1.0,
        for (var i = 1; i < 10; i++) 0.0,
        1.0,
        1.0,
        for (var i = 12; i < 300; i++) 0.0,
      ]);
      const onset = EnvelopeBinding(
        trigger: EnvelopeTrigger.onset(),
        attack: Duration(milliseconds: 100),
        decay: Duration(milliseconds: 100),
        release: Duration(milliseconds: 200),
        sustainLevel: 0.5,
        min: 0,
        max: 10,
      );
      expect(onset.usesAudioFeatures, isTrue);
      expect(onset.usesTempo, isFalse);
      final retriggered = resolver(onset, audio: onsets);
      final held = resolver(onset.copyWith(retrigger: false), audio: onsets);
      expect(numberAt(retriggered, 3), closeTo(10, 1e-6), reason: 'retriggered from the current level (1)');
      expect(numberAt(retriggered, 9), closeTo(5, 1e-6), reason: 'release starts 200 ms after the retrigger');
      expect(numberAt(held, 9), closeTo(2.5, 1e-6), reason: 'the second hit was ignored');
      expect(numberAt(held, 12), closeTo(0, 1e-6));
      expect(numberAt(retriggered, 12), closeTo(2.5, 1e-6));
      // A level below the threshold never fires.
      final quiet = featuresWith(AudioFeatureKey.onset, [for (var i = 0; i < 100; i++) 0.4]);
      expect(series(resolver(onset, audio: quiet), 30).every((v) => v == 0), isTrue);
      // Without audio: min.
      expect(numberAt(resolver(onset), 3), 0);
      // A range hit on the bass bands.
      final bass = featuresWith(AudioFeatureKey.band0, [for (var i = 0; i < 100; i++) i >= 30 ? 1.0 : 0.0]);
      final range = resolver(
        onset.copyWith(trigger: const EnvelopeTrigger.rangeHit(lowHz: 20, highHz: 60, threshold: 0.5)),
        audio: bass,
      );
      expect(numberAt(range, 8), 0);
      expect(numberAt(range, 12), closeTo(10, 1e-6), reason: 'band0 rose at 300 ms = frame 9');
    });

    test('salvage clamps the stages, level, range and trigger', () {
      expect(
        number.salvage(const EnvelopeBinding(
          trigger: EnvelopeTrigger.rangeHit(lowHz: 50000, highHz: -3, threshold: 2),
          attack: Duration(minutes: 1),
          decay: Duration(seconds: -1),
          sustainLevel: 3,
          min: -1,
          max: 11,
        )),
        const EnvelopeBinding(
          trigger: EnvelopeTrigger.rangeHit(lowHz: 20, highHz: 16000, threshold: 1),
          attack: EnvelopeBinding.maxStage,
          decay: Duration.zero,
          sustainLevel: 1,
          min: 0,
          max: 10,
        ),
      );
      expect(color.salvage(adsr), color.defaultBinding);
    });
  });

  group('StackedBinding', () {
    test('add and multiply with normalized sources, clamped to the parameter', () {
      // The source is a constant 10 = the top of the 0..10 range → norm 1.
      final add = resolver(const StackedBinding(
        base: ConstantBinding(2),
        modulators: [Modulator(source: ConstantBinding(10), depth: 0.5)],
      ));
      expect(numberAt(add, 0), closeTo(7, 1e-9), reason: '2 + 0.5 · 10 · 1');
      // An audio source normalizes across its own range: level 0.5 of 0..1.
      final audio = featuresWith(AudioFeatureKey.level, [for (var i = 0; i < 100; i++) 0.5]);
      const follower = AudioBinding(feature: AudioFeatureKey.level, min: 0, max: 1, attack: Duration.zero);
      final multiply = resolver(
        const StackedBinding(
          base: ConstantBinding(8),
          modulators: [Modulator(source: follower, depth: 1, mode: ModulatorMode.multiply)],
        ),
        audio: audio,
      );
      expect(numberAt(multiply, 0), closeTo(4, 1e-9), reason: '8 · (1 − 1 · (1 − 0.5))');
      final negative = resolver(
        const StackedBinding(base: ConstantBinding(8), modulators: [Modulator(source: follower, depth: -0.5)]),
        audio: audio,
      );
      expect(numberAt(negative, 0), closeTo(5.5, 1e-9), reason: '8 − 0.5 · 10 · 0.5');
      final clamped = resolver(const StackedBinding(
        base: ConstantBinding(9),
        modulators: [Modulator(source: ConstantBinding(10), depth: 1)],
      ));
      expect(numberAt(clamped, 0), 10);
      // The modulators stack in order: (2 + 5) · (1 − 0.5) = 3.5.
      final both = resolver(const StackedBinding(
        base: ConstantBinding(2),
        modulators: [
          Modulator(source: ConstantBinding(10), depth: 0.5),
          Modulator(source: ConstantBinding(0), depth: 0.5, mode: ModulatorMode.multiply),
        ],
      ));
      expect(numberAt(both, 0), closeTo(3.5, 1e-9));
      // A ramp normalizes across from..to.
      final ramp = resolver(
        const StackedBinding(
          base: ConstantBinding(0),
          modulators: [Modulator(source: RampBinding(from: 4, to: 2), depth: 1)],
        ),
        frameCount: 3,
      );
      expect(numberAt(ramp, 0), closeTo(10, 1e-9));
      expect(numberAt(ramp, 2), closeTo(0, 1e-9));
    });

    test('a depth binding animates the depth, clamped to −1..1', () {
      final r = resolver(const StackedBinding(
        base: ConstantBinding(2),
        modulators: [
          Modulator(
            source: ConstantBinding(10),
            depth: 0.9,
            depthBinding: KeyframeBinding(keys: [Keyframe(at: 0, value: 0), Keyframe(at: 1, value: 0.4)]),
          ),
        ],
      ));
      expect(numberAt(r, 0), closeTo(2, 1e-9));
      expect(numberAt(r, 15), closeTo(4, 1e-9), reason: 'depth 0.2 at 0.5 s');
      expect(numberAt(r, 30), closeTo(6, 1e-9));
      final big = resolver(const StackedBinding(
        base: ConstantBinding(0),
        modulators: [Modulator(source: ConstantBinding(10), depth: 0, depthBinding: ConstantBinding(5))],
      ));
      expect(numberAt(big, 0), 10, reason: 'depth clamped to 1');
      const stacked = StackedBinding(
        base: AudioBinding(feature: AudioFeatureKey.bass, min: 0, max: 1),
        modulators: [
          Modulator(
            source: BeatBinding(shape: BeatShape.sine, min: 0, max: 1),
            depth: 1,
            depthBinding: AudioBinding(feature: AudioFeatureKey.onset, min: 0, max: 1),
          ),
        ],
      );
      expect(stacked.usesAudioFeatures, isTrue);
      expect(stacked.usesTempo, isTrue);
      expect(const StackedBinding(base: ConstantBinding(1), modulators: []).usesTempo, isFalse);
    });

    test('salvage: base and sources salvaged, nested stacks dropped, at most 8 modulators', () {
      final salvaged = number.salvage(StackedBinding(
        base: const ConstantBinding(50),
        modulators: [
          const Modulator(source: ConstantBinding(50), depth: 3),
          const Modulator(source: AudioBinding(feature: AudioFeatureKey.bass, min: -5, max: 50), depth: 0.5),
          const Modulator(source: StackedBinding(base: ConstantBinding(1), modulators: []), depth: 1),
          const Modulator(source: ConstantBinding('x'), depth: 1),
          const Modulator(
            source: ConstantBinding(1),
            depth: 0.5,
            depthBinding: StackedBinding(base: ConstantBinding(1), modulators: []),
          ),
          for (var i = 0; i < 10; i++) Modulator(source: ConstantBinding(i.toDouble()), depth: 0.1),
        ],
      )) as StackedBinding;
      expect(salvaged.base, const ConstantBinding(10.0));
      expect(salvaged.modulators, hasLength(8));
      expect(salvaged.modulators[0], const Modulator(source: ConstantBinding(10.0), depth: 1));
      expect(salvaged.modulators[1].source, const AudioBinding(feature: AudioFeatureKey.bass, min: -5, max: 50),
          reason: 'an own-range source keeps its range');
      expect(salvaged.modulators[2], const Modulator(source: ConstantBinding(1.0), depth: 0.5),
          reason: 'a stacked depth binding is dropped');
      expect(
        number.salvage(
            const StackedBinding(base: StackedBinding(base: ConstantBinding(1), modulators: []), modulators: [])),
        number.defaultBinding,
      );
      expect(number.salvage(const StackedBinding(base: ConstantBinding('x'), modulators: [])), number.defaultBinding);
      expect(color.salvage(const StackedBinding(base: ConstantBinding(1), modulators: [])), color.defaultBinding);
      // Int parameters: the result is rounded.
      final ints = resolver(
        const StackedBinding(
            base: ConstantBinding(10), modulators: [Modulator(source: ConstantBinding(50), depth: 0.5)]),
        spec: integer,
      );
      expect(ints.at(0).integer('i'), 35);
    });
  });

  group('Macros', () {
    test('a macro binding reads the request\'s macro, else the default', () {
      expect(numberAt(resolver(const MacroBinding('a'), macros: const {'a': ConstantBinding(3)}), 0), 3);
      expect(numberAt(resolver(const MacroBinding('a')), 0), 2, reason: 'unknown macro → default');
      expect(numberAt(resolver(const MacroBinding('a'), macros: const {'a': ConstantBinding('x')}), 0), 2);
      expect(numberAt(resolver(const MacroBinding('a'), macros: const {'a': ConstantBinding(99)}), 0), 10,
          reason: 'clamped to the parameter');
      final keyed = resolver(
        const MacroBinding('a'),
        macros: const {
          'a': KeyframeBinding(keys: [Keyframe(at: 0, value: 0), Keyframe(at: 1, value: 10)]),
        },
      );
      expect(numberAt(keyed, 15), closeTo(5, 1e-9));
      final colored = resolver(const MacroBinding('c'), macros: const {'c': ConstantBinding(red)}, spec: color);
      expect(colored.at(0).color('col'), red);
      expect(resolver(const MacroBinding('c'), macros: const {'c': ConstantBinding(1)}, spec: color).at(0).color('col'),
          color.defaultValue);
      // One level: a macro reading a macro resolves to nothing.
      final nested = resolver(
        const MacroBinding('a'),
        macros: const {'a': MacroBinding('b'), 'b': ConstantBinding(7)},
      );
      expect(numberAt(nested, 0), 2);
      // Audio-driven macros keep their follower state like a parameter.
      final audio = featuresWith(AudioFeatureKey.level, [for (var i = 0; i < 100; i++) 1.0]);
      final followed = resolver(
        const MacroBinding('a'),
        macros: const {
          'a': AudioBinding(feature: AudioFeatureKey.level, min: 0, max: 10, attack: Duration(milliseconds: 100)),
        },
        audio: audio,
      );
      expect(numberAt(followed, 0), lessThan(5));
      expect(numberAt(followed, 20), closeTo(10, 0.1));
    });

    test('macros are modulator sources normalized across the parameter range', () {
      final r = resolver(
        const StackedBinding(base: ConstantBinding(0), modulators: [Modulator(source: MacroBinding('a'), depth: 1)]),
        macros: const {'a': ConstantBinding(5)},
      );
      expect(numberAt(r, 0), closeTo(5, 1e-9), reason: 'norm 0.5 of 0..10');
      final missing = resolver(
        const StackedBinding(base: ConstantBinding(3), modulators: [Modulator(source: MacroBinding('zz'), depth: 1)]),
      );
      expect(numberAt(missing, 0), 3, reason: 'a missing macro source contributes nothing');
      // A stacked macro uses the unit range.
      final stackedMacro = resolver(
        const MacroBinding('a'),
        macros: const {
          'a': StackedBinding(
              base: ConstantBinding(0.2), modulators: [Modulator(source: ConstantBinding(1), depth: 0.5)]),
        },
      );
      expect(numberAt(stackedMacro, 0), closeTo(0.7, 1e-9));
    });

    test('needsAudioFeatures / needsAudioClock follow macros', () {
      const info = GeneratorInfo(
        id: 'x',
        version: 1,
        name: LocalizedText('x'),
        description: LocalizedText(''),
        category: GeneratorCategory.basic,
      );
      const bindings = {'n': MacroBinding('a')};
      expect(needsAudioFeatures(info, bindings), isFalse);
      expect(needsAudioClock(info, bindings), isFalse);
      expect(
        needsAudioFeatures(info, bindings,
            macros: const {'a': AudioBinding(feature: AudioFeatureKey.bass, min: 0, max: 1)}),
        isTrue,
      );
      expect(needsAudioClock(info, bindings, macros: const {'a': BeatBinding(shape: BeatShape.saw, min: 0, max: 1)}),
          isTrue);
      expect(needsAudioFeatures(info, bindings, macros: const {'a': BeatBinding(shape: BeatShape.saw, min: 0, max: 1)}),
          isFalse);
      // Through a stack's depth binding.
      const stacked = {
        'n': StackedBinding(
          base: ConstantBinding(1),
          modulators: [Modulator(source: ConstantBinding(1), depth: 1, depthBinding: MacroBinding('a'))],
        ),
      };
      expect(
        needsAudioFeatures(info, stacked,
            macros: const {'a': AudioBinding(feature: AudioFeatureKey.bass, min: 0, max: 1)}),
        isTrue,
      );
      const setup = GeneratorSetup(xCount: 4, yCount: 3, radioPanelsCount: 1, radioPanelPixelCount: 2, seed: 1);
      final request = BakeRequest.forLength(
        setup: setup,
        length: const Duration(seconds: 1),
        bindings: bindings,
        macros: const {'a': AudioBinding(feature: AudioFeatureKey.bass, min: 0, max: 1)},
      );
      expect(request.bindingsUseAudioFeatures, isTrue);
      expect(request.bindingsUseAudioClock, isTrue);
      expect(
          request, isNot(BakeRequest.forLength(setup: setup, length: const Duration(seconds: 1), bindings: bindings)),
          reason: 'macros are part of the request\'s identity');
    });

    test('a bake sees the macros and the setup seed', () {
      const setup = GeneratorSetup(xCount: 4, yCount: 3, radioPanelsCount: 0, radioPanelPixelCount: 1, seed: 11);
      final macroed = bakeGenerator(
        const SolidGenerator(),
        BakeRequest.forLength(
          setup: setup,
          length: const Duration(seconds: 1),
          bindings: const {'color': MacroBinding('tint')},
          macros: const {'tint': ConstantBinding(red)},
        ),
      );
      expect(macroed.toIndex().viewAt(Duration.zero).frame.pixels.first, red);
      final random = BakeRequest.forLength(
        setup: setup,
        length: const Duration(seconds: 1),
        bindings: const {'brightness': RandomBinding(mode: RandomMode.perFrame, min: 0, max: 1)},
      );
      final a = bakeGenerator(const SolidGenerator(), random).toBytes();
      final b = bakeGenerator(const SolidGenerator(), random).toBytes();
      expect(a, b);
      final other = bakeGenerator(const SolidGenerator(), random.copyWithSeed(12)).toBytes();
      expect(other, isNot(a), reason: 'the setup seed seeds the random binding');
    });
  });

  group('ParamResolver.reset', () {
    test('replays the stepped state from frame 0', () {
      final audio = featuresWith(AudioFeatureKey.level, [for (var i = 0; i < 100; i++) 1.0]);
      final r = resolver(
        const AudioBinding(feature: AudioFeatureKey.level, min: 0, max: 10, attack: Duration(milliseconds: 100)),
        audio: audio,
      );
      final first = numberAt(r, 0);
      numberAt(r, 10);
      r.reset();
      expect(numberAt(r, 0), first);
    });
  });

  group('ParamBindingJson (animation kinds)', () {
    final bindings = <String, ParamBinding>{
      'k': const KeyframeBinding(
        keys: [
          Keyframe(at: 0, value: 0.5, easing: Easing.easeInOut),
          Keyframe(at: 1.5, value: 2.0, easing: Easing.bezier(0.42, 0, 0.58, 1)),
          Keyframe(at: 2, value: 1.0, easing: Easing.hold),
        ],
        timeBase: KeyTime.beats,
        loop: true,
      ),
      'kc': const KeyframeBinding(keys: [Keyframe(at: 0, value: red), Keyframe(at: 1, value: blue)]),
      'r': const RandomBinding(
        mode: RandomMode.perTime,
        interval: Duration(milliseconds: 250),
        min: 0.1,
        max: 0.9,
        smooth: 0.3,
        seed: 42,
      ),
      'r2': const RandomBinding(mode: RandomMode.perBar, min: 0, max: 1),
      's': const StepBinding(steps: [1, 0, 0.5, 0.25], stepsPerBar: 8, min: 0, max: 2, smooth: true, gate: 0.5),
      'e': const EnvelopeBinding(
        trigger: EnvelopeTrigger.rangeHit(lowHz: 40, highHz: 200, threshold: 0.6),
        attack: Duration(milliseconds: 20),
        decay: Duration(milliseconds: 80),
        sustain: Duration(milliseconds: 100),
        release: Duration(milliseconds: 400),
        sustainLevel: 0.7,
        min: 0,
        max: 1,
        retrigger: false,
      ),
      'e2': const EnvelopeBinding(trigger: EnvelopeTrigger.onset(threshold: 0.3), min: 0, max: 1),
      'e3': const EnvelopeBinding(trigger: EnvelopeTrigger.beat, min: 0, max: 1),
      'e4': const EnvelopeBinding(trigger: EnvelopeTrigger.bar, min: 0, max: 1),
      'st': const StackedBinding(
        base: KeyframeBinding(keys: [Keyframe(at: 0, value: 0.2)]),
        modulators: [
          Modulator(source: AudioBinding(feature: AudioFeatureKey.bass, min: 0, max: 1), depth: 0.5),
          Modulator(
            source: BeatBinding(shape: BeatShape.sine, min: 0, max: 1),
            depth: -0.25,
            mode: ModulatorMode.multiply,
            depthBinding: MacroBinding('wobble'),
          ),
        ],
      ),
      'm': const MacroBinding('intensity'),
    };

    test('round-trips every kind through JSON text', () {
      final text = jsonEncode(ParamBindingJson.bindingsToJson(bindings));
      expect(ParamBindingJson.bindingsFromJson(jsonDecode(text)), bindings);
    });

    test('has the documented shapes', () {
      expect(ParamBindingJson.toJson(bindings['kc']!), {
        'type': 'keyframes',
        'timeBase': 'seconds',
        'loop': false,
        'keys': [
          {'at': 0, 'color': '#ff0000', 'easing': 'linear'},
          {'at': 1, 'color': '#0000ff', 'easing': 'linear'},
        ],
      });
      expect(ParamBindingJson.toJson(bindings['k']!)['keys'], [
        {'at': 0, 'value': 0.5, 'easing': 'easeInOut'},
        {
          'at': 1.5,
          'value': 2.0,
          'easing': {
            'bezier': [0.42, 0, 0.58, 1],
          },
        },
        {'at': 2, 'value': 1.0, 'easing': 'hold'},
      ]);
      expect(ParamBindingJson.toJson(bindings['r']!), {
        'type': 'random',
        'mode': 'perTime',
        'intervalMs': 250.0,
        'min': 0.1,
        'max': 0.9,
        'smooth': 0.3,
        'seed': 42,
      });
      expect(ParamBindingJson.toJson(bindings['s']!), {
        'type': 'steps',
        'steps': [1, 0, 0.5, 0.25],
        'stepsPerBar': 8,
        'min': 0,
        'max': 2,
        'smooth': true,
        'gate': 0.5,
      });
      expect(ParamBindingJson.toJson(bindings['e']!), {
        'type': 'envelope',
        'trigger': 'rangeHit',
        'lowHz': 40,
        'highHz': 200,
        'threshold': 0.6,
        'attackMs': 20.0,
        'decayMs': 80.0,
        'sustainMs': 100.0,
        'releaseMs': 400.0,
        'sustainLevel': 0.7,
        'min': 0,
        'max': 1,
        'retrigger': false,
      });
      expect(ParamBindingJson.toJson(bindings['e3']!)['trigger'], 'beat');
      expect(ParamBindingJson.toJson(bindings['e2']!), containsPair('threshold', 0.3));
      final stack = ParamBindingJson.toJson(bindings['st']!);
      expect(stack['type'], 'stack');
      expect(stack['base'], {
        'type': 'keyframes',
        'timeBase': 'seconds',
        'loop': false,
        'keys': [
          {'at': 0, 'value': 0.2, 'easing': 'linear'},
        ],
      });
      expect((stack['modulators'] as List<Object?>)[1], {
        'source': {'type': 'beat', 'shape': 'sine', 'periodBeats': 1, 'phase': 0, 'min': 0, 'max': 1},
        'depth': -0.25,
        'mode': 'multiply',
        'depthBinding': {'type': 'macro', 'macro': 'wobble'},
      });
      expect(ParamBindingJson.toJson(bindings['m']!), {'type': 'macro', 'macro': 'intensity'});
    });

    test('decodes leniently and drops unreadable bindings', () {
      final decoded = ParamBindingJson.bindingsFromJson({
        'noKeys': {'type': 'keyframes', 'keys': <Object?>[]},
        'badKeys': {
          'type': 'keyframes',
          'keys': [
            {'at': 'x', 'value': 1},
            {'at': 1, 'value': 'x'},
            {'at': 1, 'color': '#zz'},
          ],
        },
        'okKeys': {
          'type': 'keyframes',
          'keys': [
            {'at': 1, 'value': 3, 'easing': 'wobble'},
            {'at': 'x'},
            {
              'at': 2,
              'value': 4,
              'easing': {
                'bezier': [1, 2]
              }
            },
          ],
        },
        'random': {'type': 'random', 'min': 0, 'max': 1},
        'fewSteps': {
          'type': 'steps',
          'steps': [1],
          'min': 0,
          'max': 1
        },
        'steps': {
          'type': 'steps',
          'steps': [1, 'x', 0.5],
          'min': 0,
          'max': 1
        },
        'noTrigger': {'type': 'envelope', 'trigger': 'thunder', 'min': 0, 'max': 1},
        'envelope': {'type': 'envelope', 'trigger': 'beat', 'min': 0, 'max': 1},
        'nestedStack': {
          'type': 'stack',
          'base': {
            'type': 'stack',
            'base': {'type': 'constant', 'value': 1},
            'modulators': <Object?>[],
          },
        },
        'stack': {
          'type': 'stack',
          'base': {'type': 'constant', 'value': 1},
          'modulators': [
            {
              'source': {
                'type': 'stack',
                'base': {'type': 'constant', 'value': 1}
              },
              'depth': 1
            },
            {
              'source': {'type': 'constant', 'value': 2}
            },
            'junk',
          ],
        },
        'emptyMacro': {'type': 'macro', 'macro': ''},
        'macro': {'type': 'macro', 'macro': 'speed'},
      });
      expect(decoded.keys, unorderedEquals(['okKeys', 'random', 'steps', 'envelope', 'stack', 'macro']));
      expect(decoded['okKeys'], const KeyframeBinding(keys: [Keyframe(at: 1, value: 3), Keyframe(at: 2, value: 4)]));
      expect(decoded['random'], const RandomBinding(min: 0, max: 1));
      expect(decoded['steps'], const StepBinding(steps: [1, 0, 0.5], min: 0, max: 1));
      expect(decoded['envelope'], const EnvelopeBinding(trigger: EnvelopeTrigger.beat, min: 0, max: 1));
      expect(
          decoded['stack'],
          const StackedBinding(
              base: ConstantBinding(1), modulators: [Modulator(source: ConstantBinding(2), depth: 0)]));
      expect(decoded['macro'], const MacroBinding('speed'));
    });

    test('salvage after decoding keeps old projects working', () {
      final json = ParamBindingJson.bindingsToJson({
        'n': const StackedBinding(
          base: RandomBinding(mode: RandomMode.perBeat, min: 0, max: 20),
          modulators: [
            Modulator(source: StepBinding(steps: [1, 0], min: 0, max: 1), depth: 0.5)
          ],
        ),
        'col': const KeyframeBinding(keys: [Keyframe(at: 0, value: red)]),
      });
      final salvaged = salvageBindings(const [number, color], ParamBindingJson.bindingsFromJson(json));
      expect(
        salvaged['n'],
        const StackedBinding(
          base: RandomBinding(mode: RandomMode.perBeat, min: 0, max: 10),
          modulators: [
            Modulator(source: StepBinding(steps: [1, 0], min: 0, max: 1), depth: 0.5)
          ],
        ),
      );
      expect(salvaged['col'], const KeyframeBinding(keys: [Keyframe(at: 0, value: red)]));
    });
  });
}

extension on BakeRequest {
  BakeRequest copyWithSeed(int seed) => BakeRequest(
        setup: setup.copyWith(seed: seed),
        frameCount: frameCount,
        bindings: bindings,
        audio: audio,
        tempo: tempo,
        audioOrigin: audioOrigin,
        name: name,
        macros: macros,
      );
}
