import 'dart:typed_data';

import 'package:icicles_animation_dart/icicles_animation_dart.dart';
import 'package:icicles_generators/icicles_generators.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

Duration ms(int v) => Duration(milliseconds: v);

void main() {
  group('DrumHits', () {
    final drums = DrumHits({
      DrumClass.kick: [DrumHit(ms(1000), 0.5), DrumHit(ms(0), 1), DrumHit(ms(500), 2)],
      DrumClass.hihat: [DrumHit(ms(250), double.nan)],
    }, source: DrumHits.sourceAdtof);

    test('sorts each class and clamps strengths', () {
      expect(drums.of(DrumClass.kick).map((h) => h.time), [ms(0), ms(500), ms(1000)]);
      expect(drums.of(DrumClass.kick)[1].strength, 1, reason: 'clamped');
      expect(drums.of(DrumClass.hihat).single.strength, 1, reason: 'non-finite');
      expect(drums.of(DrumClass.snare), isEmpty);
      expect(drums.count, 4);
      expect(drums.isEmpty, isFalse);
      expect(DrumHits.empty.isEmpty, isTrue);
    });

    test('strongestIn covers (from, to]', () {
      expect(drums.strongestIn(DrumClass.kick, ms(-1), ms(0))?.time, ms(0));
      expect(drums.strongestIn(DrumClass.kick, ms(0), ms(499)), isNull, reason: 'from is exclusive');
      expect(drums.strongestIn(DrumClass.kick, ms(0), ms(500))?.time, ms(500));
      expect(drums.strongestIn(DrumClass.kick, ms(-1), ms(2000))?.strength, 1);
      expect(drums.strongestIn(DrumClass.kick, ms(10), ms(10)), isNull);
      expect(drums.strongestIn(DrumClass.snare, ms(0), ms(2000)), isNull);
    });

    test('lastAtOrBefore', () {
      expect(drums.lastAtOrBefore(DrumClass.kick, ms(-1)), isNull);
      expect(drums.lastAtOrBefore(DrumClass.kick, ms(0))?.time, ms(0));
      expect(drums.lastAtOrBefore(DrumClass.kick, ms(999))?.time, ms(500));
      expect(drums.lastAtOrBefore(DrumClass.kick, ms(5000))?.time, ms(1000));
    });

    test('equality follows the content', () {
      DrumHits make(double s) => DrumHits({
            DrumClass.kick: [DrumHit(ms(0), s)],
          }, source: 'x');
      expect(make(0.5), make(0.5));
      expect(make(0.5) == make(0.6), isFalse);
      expect(DrumHits({}, source: 'x') == DrumHits({}, source: 'y'), isFalse);
    });

    test('JSON round-trips; malformed input decodes to null', () {
      final json = DrumHitsJson.toJson(drums);
      expect(DrumHitsJson.fromJson(json), drums);
      expect(DrumHitsJson.toJson(null), isNull);
      expect(DrumHitsJson.fromJson(null), isNull);
      expect(DrumHitsJson.fromJson('x'), isNull);
      expect(
          DrumHitsJson.fromJson({
            'hits': {
              'kick': {
                'us': [1, 2],
                's': [1],
              },
            },
          }),
          isNull);
      final unknown = DrumHitsJson.fromJson({
        'source': 'future',
        'hits': {
          'cowbell': {
            'us': [1],
            's': [1],
          },
          'snare': {
            'us': [2000],
            's': [0.5],
          },
        },
      })!;
      expect(unknown.of(DrumClass.snare).single, DrumHit(ms(2), 0.5));
      expect(unknown.count, 1);
    });
  });

  group('AudioFrame drum fields', () {
    test('every hit reaches exactly one frame of any frame grid', () {
      final drums = syntheticDrums(seconds: 6);
      final features = syntheticFeatures(seconds: 6);
      for (final framerate in [Framerate.fps24, Framerate.fps30, Framerate.fps45, Framerate.fps60]) {
        final frames = frameCountFor(framerate, const Duration(seconds: 5));
        var kicks = 0;
        var hats = 0;
        for (var i = 0; i < frames; i++) {
          final start = framerate.frameStart(i);
          final span = i == 0 ? framerate.frameDuration(0) : start - framerate.frameStart(i - 1);
          final frame = features.sampleAt(start, drums: drums, span: span);
          if (frame.drumHit(DrumClass.kick) > 0) kicks++;
          if (frame.drumHit(DrumClass.hihat) > 0) hats++;
        }
        final end = framerate.frameStart(frames - 1);
        int expected(DrumClass c) => drums.of(c).where((h) => h.time <= end).length;
        expect(kicks, expected(DrumClass.kick), reason: '$framerate kicks');
        expect(hats, expected(DrumClass.hihat), reason: '$framerate hats');
      }
    });

    test('pulse decays from the last hit; nothing without drums', () {
      final drums = DrumHits({
        DrumClass.kick: [DrumHit(ms(100), 0.8)],
      }, source: 'test');
      final columns = Float32List(AudioFeatureKey.columnCount);
      final at = AudioFrame.fromColumns(columns, drums: drums, time: ms(100), span: ms(25));
      expect(at.hasDrums, isTrue);
      expect(at.drumHit(DrumClass.kick), closeTo(0.8, 1e-6));
      expect(at.anyDrumHit, closeTo(0.8, 1e-6));
      expect(at[AudioFeatureKey.kickPulse], closeTo(0.8, 1e-6));
      final later = AudioFrame.fromColumns(columns, drums: drums, time: ms(180), span: ms(25));
      expect(later.drumHit(DrumClass.kick), 0);
      expect(later.drumPulse(DrumClass.kick), closeTo(0.8 * 0.3679, 1e-3));
      expect(later[AudioFeatureKey.snarePulse], 0);
      final none = AudioFrame.fromColumns(columns, time: ms(100), span: ms(25));
      expect(none.hasDrums, isFalse);
      expect(none.drumHit(DrumClass.kick), 0);
      expect(AudioFrame.fromColumns(columns, drums: DrumHits.empty, time: ms(100)).hasDrums, isFalse);
    });

    test('feature key groups', () {
      expect(AudioFeatureKey.kickPulse.isDrum, isTrue);
      expect(AudioFeatureKey.kickPulse.isBeat, isFalse);
      expect(AudioFeatureKey.kickPulse.isColumn, isFalse);
      expect(AudioFeatureKey.kickPulse.usesAnalysis, isTrue);
      expect(AudioFeatureKey.beatPulse.isBeat, isTrue);
      expect(const AudioBinding(feature: AudioFeatureKey.snarePulse, min: 0, max: 1).usesAudioFeatures, isTrue);
    });
  });

  group('Strobe on drums', () {
    const strobe = StrobeGenerator();

    /// Clip times (ms) where a flash starts, and the blue level of each flash.
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

    List<int> flashStarts(BakeRequest request) => flashes(request).$1;

    test('defaults to the kick and flashes once per kick, weaker kicks dimmer', () {
      expect(strobe.params.whereType<ChoiceParam>().firstWhere((p) => p.id == 'trigger').defaultValue, 'kick');
      // audioOrigin 500 ms: kicks at song 0.5, 1.0 … 2.0 s are at clip 0, 0.5 … 1.5 s.
      final (starts, levels) = flashes(testRequest(seconds: 2));
      expect(starts, [0, 500, 1000, 1500]);
      // Song 0.5 s is beat 1 (strength 0.4), 1.0 s beat 2 (strength 1).
      expect(levels[1], greaterThan(levels[0]));
      expect(levels[0], levels[2]);
    });

    test('the default gap keeps to 3 flashes a second; a lower gap lets fast patterns through', () {
      // Synthetic hats every 250 ms.
      final safe = flashStarts(testRequest(bindings: const {'trigger': ConstantBinding('hihat')}));
      final all = flashStarts(testRequest(bindings: const {
        'trigger': ConstantBinding('hihat'),
        'minGapMs': ConstantBinding(60.0),
      }));
      expect(all, hasLength(8));
      expect(safe, hasLength(4));
      for (var i = 1; i < safe.length; i++) {
        expect(safe[i] - safe[i - 1], greaterThanOrEqualTo(335));
      }
      // Kicks every 500 ms all flash.
      expect(flashStarts(testRequest(seconds: 2)), hasLength(4));
    });

    test('without drum hits a drum trigger follows the beat grid', () {
      BakeRequest without(String trigger) => BakeRequest.forLength(
            setup: testSetup,
            length: const Duration(seconds: 2),
            bindings: {'trigger': ConstantBinding(trigger)},
            audio: syntheticFeatures(),
            tempo: Tempo(bpm: 120),
          );
      expect(bakeBytes(strobe, without('kick')), bakeBytes(strobe, without('beat')));
    });
  });

  group('drum envelope trigger', () {
    test('JSON round-trips', () {
      const binding = EnvelopeBinding(
        trigger: DrumHitTrigger(drum: DrumClass.snare),
        attack: Duration.zero,
        decay: Duration(milliseconds: 100),
        sustain: Duration.zero,
        release: Duration.zero,
        sustainLevel: 0,
        min: 0,
        max: 1,
      );
      expect(ParamBindingJson.fromJson(ParamBindingJson.toJson(binding)), binding);
      const any = EnvelopeBinding(
        trigger: DrumHitTrigger(),
        attack: Duration.zero,
        decay: Duration(milliseconds: 100),
        sustain: Duration.zero,
        release: Duration.zero,
        sustainLevel: 0,
        min: 0,
        max: 1,
      );
      expect(ParamBindingJson.fromJson(ParamBindingJson.toJson(any)), any);
      expect(binding.usesAudioFeatures, isTrue);
    });

    test('fires on the hits of its class', () {
      const spec = NumberParam(id: 'v', label: LocalizedText('v'), min: 0, max: 1, defaultValue: 0);
      final resolver = ParamResolver(
        specs: const [spec],
        bindings: const {
          'v': EnvelopeBinding(
            trigger: DrumHitTrigger(drum: DrumClass.snare),
            attack: Duration.zero,
            decay: Duration(milliseconds: 60),
            sustain: Duration.zero,
            release: Duration.zero,
            sustainLevel: 0,
            min: 0,
            max: 1,
          ),
        },
        framerate: Framerate.fps30,
        frameCount: 60,
        audio: syntheticFeatures(),
        drums: syntheticDrums(),
        tempo: Tempo(bpm: 120),
      );
      // Snares at 0.5 and 1.5 s: frames 15 and 45 jump to 1.
      final peaks = [
        for (var i = 0; i < 60; i++)
          if (resolver.at(i).number('v') > 0.99) i,
      ];
      expect(peaks, [15, 45]);
    });
  });
}
