import 'dart:typed_data';

import 'package:icicles_animation_dart/icicles_animation_dart.dart';
import 'package:icicles_generators/icicles_generators.dart';
import 'package:icicles_generators/plugin.dart' show ManifestJson;
import 'package:test/test.dart';

import 'test_utils.dart';

Duration ms(int v) => Duration(milliseconds: v);

/// Cues at 0.3 s (1.0), 0.9 s (0.5) and 1.5 s (1.0).
final _cues = CueHits(const [
  CueHit(Duration(milliseconds: 900), 0.5),
  CueHit(Duration(milliseconds: 300)),
  CueHit(Duration(milliseconds: 1500))
]);

/// A request without a soundtrack or tempo: only the cues.
BakeRequest _cueRequest(Map<String, ParamBinding> bindings, {CueHits? cues, double seconds = 2}) =>
    BakeRequest.forLength(
      setup: testSetup,
      length: Duration(milliseconds: (seconds * 1000).round()),
      bindings: bindings,
      cues: cues,
    );

void main() {
  group('CueHits', () {
    test('sorts, clamps and answers span queries', () {
      expect(_cues.hits.map((h) => h.time), [ms(300), ms(900), ms(1500)]);
      expect(CueHits(const [CueHit(Duration.zero, 3)]).hits.single.strength, 1);
      expect(CueHits(const [CueHit(Duration.zero, double.nan)]).hits.single.strength, 1);
      expect(_cues.strongestIn(ms(299), ms(300))?.time, ms(300));
      expect(_cues.strongestIn(ms(300), ms(899)), isNull, reason: 'from is exclusive');
      expect(_cues.strongestIn(ms(0), ms(2000))?.strength, 1);
      expect(_cues.lastAtOrBefore(ms(1000))?.time, ms(900));
      expect(_cues.lastAtOrBefore(ms(100)), isNull);
      expect(_cues.shifted(ms(100)).hits.first.time, ms(400));
      expect(CueHits.empty.isEmpty, isTrue);
    });

    test('equality follows the content; JSON round-trips; malformed input decodes to null', () {
      expect(CueHits(const [CueHit(Duration.zero, 0.5)]), CueHits(const [CueHit(Duration.zero, 0.5)]));
      expect(CueHits(const [CueHit(Duration.zero, 0.5)]) == CueHits(const [CueHit(Duration.zero, 0.6)]), isFalse);
      expect(CueHitsJson.fromJson(CueHitsJson.toJson(_cues)), _cues);
      expect(CueHitsJson.toJson(null), isNull);
      expect(CueHitsJson.fromJson('x'), isNull);
      expect(
          CueHitsJson.fromJson({
            'us': [1, 2],
            's': [1],
          }),
          isNull);
    });
  });

  group('AudioFrame cue fields', () {
    test('every cue reaches exactly one frame of any frame grid, with or without features', () {
      final cues = CueHits([for (var i = 0; i < 40; i++) CueHit(Duration(milliseconds: 37 + i * 123), 0.8)]);
      final columns = Float32List(AudioFeatureKey.columnCount);
      for (final framerate in [Framerate.fps24, Framerate.fps30, Framerate.fps45, Framerate.fps60]) {
        final frames = frameCountFor(framerate, const Duration(seconds: 5));
        var fired = 0;
        for (var i = 0; i < frames; i++) {
          final start = framerate.frameStart(i);
          final span = i == 0 ? framerate.frameDuration(0) : start - framerate.frameStart(i - 1);
          final frame = AudioFrame.fromColumns(columns, time: start, cues: cues, span: span);
          if (frame.cueHit > 0) fired++;
        }
        final end = framerate.frameStart(frames - 1);
        expect(fired, cues.hits.where((h) => h.time <= end).length, reason: '$framerate');
      }
      final sampled = syntheticFeatures(seconds: 2).sampleAt(ms(300), cues: _cues, span: ms(33));
      expect(sampled.cueHit, 1);
      expect(sampled[AudioFeatureKey.cuePulse], closeTo(1, 1e-6));
    });

    test('the pulse decays from the last cue; nothing without cues', () {
      final columns = Float32List(AudioFeatureKey.columnCount);
      final later = AudioFrame.fromColumns(columns, time: ms(380), cues: _cues, span: ms(25));
      expect(later.hasCues, isTrue);
      expect(later.cueHit, 0);
      expect(later.cuePulse, closeTo(0.3679, 1e-3));
      final none = AudioFrame.fromColumns(columns, time: ms(300), span: ms(25));
      expect(none.hasCues, isFalse);
      expect(none.cueHit, 0);
      expect(AudioFeatureKey.cuePulse.usesCues, isTrue);
      expect(AudioFeatureKey.cuePulse.usesAnalysis, isFalse);
    });
  });

  group('Strobe on cues', () {
    const strobe = StrobeGenerator();

    (List<int>, List<int>) flashes(BakeRequest request) {
      final views = bakeGenerator(strobe, request).toIndex().views;
      final starts = <int>[];
      final levels = <int>[];
      var wasOn = false;
      var t = Duration.zero;
      for (final view in views) {
        final blue = view.frame.pixels.first.value & 0xFF;
        final on = blue != 0;
        if (on && !wasOn) {
          starts.add(t.inMilliseconds);
          levels.add(blue);
        }
        wasOn = on;
        t += view.frame.duration;
      }
      return (starts, levels);
    }

    test('flashes on every cue without a soundtrack or tempo, weaker cues dimmer', () {
      final (starts, levels) = flashes(_cueRequest(const {'trigger': ConstantBinding('cues')}, cues: _cues));
      // 30 fps: each cue lands on the first frame at or after it.
      expect(starts, hasLength(3));
      for (final (i, cue) in [300, 900, 1500].indexed) {
        expect(starts[i], inInclusiveRange(cue, cue + 34));
      }
      expect(levels[1], lessThan(levels[0]), reason: 'the 0.5 cue with accent 0.5');
      expect(levels[0], levels[2]);
    });

    test('no cues, no flashes (no beat fallback)', () {
      expect(flashes(_cueRequest(const {'trigger': ConstantBinding('cues')})).$1, isEmpty);
      expect(flashes(_cueRequest(const {'trigger': ConstantBinding('cues')}, cues: CueHits.empty)).$1, isEmpty);
    });

    test('needsCues follows the info, the chosen options, bindings and reactivity', () {
      const plain = GeneratorInfo(
        id: 'x',
        version: 1,
        name: LocalizedText('x'),
        description: LocalizedText(''),
        category: GeneratorCategory.basic,
      );
      expect(needsCues(plain, const {}), isFalse);
      expect(needsCues(strobe.info, const {}, params: strobe.params), isFalse, reason: 'defaults to the kick');
      expect(needsCues(strobe.info, const {'trigger': ConstantBinding('beat')}, params: strobe.params), isFalse);
      expect(needsCues(strobe.info, const {'trigger': ConstantBinding('cues')}, params: strobe.params), isTrue);
      expect(needsCues(strobe.info, const {'trigger': ConstantBinding('cues')}), isFalse, reason: 'needs the params');
      expect(paramsUseCues(strobe.params, const {'trigger': ConstantBinding('nonsense')}), isFalse);
      expect(needsCues(plain, const {'v': AudioBinding(feature: AudioFeatureKey.cuePulse, min: 0, max: 1)}), isTrue);
      expect(
          needsAudioClock(plain, const {'v': AudioBinding(feature: AudioFeatureKey.cuePulse, min: 0, max: 1)}), isTrue);
      final reactive = AudioReactivity.defaults
          .withMode(ReactiveModeKind.flash, const ReactiveMode(min: 0, max: 1, trigger: ReactiveTrigger.cues));
      expect(reactive.usesCues, isTrue);
      expect(needsCues(plain, const {}, reactivity: reactive), isTrue);
    });
  });

  group('manifest and drum queries', () {
    test('a choice option reading cues round-trips through the plugin manifest', () {
      final trigger = const StrobeGenerator().params.whereType<ChoiceParam>().firstWhere((p) => p.id == 'trigger');
      final decoded = ManifestJson.paramFromJson(ManifestJson.paramToJson(trigger))! as ChoiceParam;
      expect(decoded, trigger);
      expect(decoded.options.where((o) => o.usesCues).map((o) => o.id), ['cues']);
      expect((ManifestJson.paramToJson(trigger)['options']! as List).where((o) => (o as Map).containsKey('usesCues')),
          hasLength(1));
    });

    test('DrumHits.nearest finds the nearest hit of a class', () {
      final drums = DrumHits({
        DrumClass.kick: [DrumHit(ms(100), 1), DrumHit(ms(300), 1)],
      }, source: 'test');
      expect(drums.nearest(DrumClass.kick, ms(0))?.time, ms(100));
      expect(drums.nearest(DrumClass.kick, ms(190))?.time, ms(100));
      expect(drums.nearest(DrumClass.kick, ms(200))?.time, ms(100), reason: 'earlier on a tie');
      expect(drums.nearest(DrumClass.kick, ms(260))?.time, ms(300));
      expect(drums.nearest(DrumClass.kick, ms(900))?.time, ms(300));
      expect(drums.nearest(DrumClass.snare, ms(100)), isNull);
    });
  });

  group('cue envelope trigger', () {
    const binding = EnvelopeBinding(
      trigger: EnvelopeTrigger.cue,
      attack: Duration.zero,
      decay: Duration(milliseconds: 60),
      sustain: Duration.zero,
      release: Duration.zero,
      sustainLevel: 0,
      min: 0,
      max: 1,
    );

    test('JSON round-trips', () {
      expect(ParamBindingJson.fromJson(ParamBindingJson.toJson(binding)), binding);
      expect(binding.usesCues, isTrue);
      expect(binding.usesAudioFeatures, isFalse);
      expect(
        const StackedBinding(base: ConstantBinding(0.0), modulators: [Modulator(source: binding, depth: 1)]).usesCues,
        isTrue,
      );
    });

    test('fires on the cues, also without audio; an audio binding on the cue pulse follows them', () {
      const spec = NumberParam(id: 'v', label: LocalizedText('v'), min: 0, max: 1, defaultValue: 0);
      final resolver = ParamResolver(
        specs: const [spec],
        bindings: const {'v': binding},
        framerate: Framerate.fps30,
        frameCount: 60,
        cues: _cues,
      );
      final peaks = [
        for (var i = 0; i < 60; i++)
          if (resolver.at(i).number('v') > 0.99) i,
      ];
      expect(peaks, [9, 27, 45]);
      final pulse = ParamResolver(
        specs: const [spec],
        bindings: const {'v': AudioBinding(feature: AudioFeatureKey.cuePulse, min: 0, max: 1)},
        framerate: Framerate.fps30,
        frameCount: 60,
        cues: _cues,
      );
      expect(pulse.at(9).number('v'), greaterThan(0.9));
      expect(pulse.at(8).number('v'), 0);
    });
  });
}
