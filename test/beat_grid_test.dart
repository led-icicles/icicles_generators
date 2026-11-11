import 'dart:convert';
import 'dart:math' as math;

import 'package:icicles_animation_dart/icicles_animation_dart.dart';
import 'package:icicles_generators/plugin.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

Duration ms(int value) => Duration(milliseconds: value);

/// An irregular grid: beats slowing down from 500 ms to 560 ms intervals,
/// downbeats every 4th beat starting with the second beat.
BeatGrid irregularGrid() {
  final beats = <Duration>[];
  var at = 250;
  for (var i = 0; i < 12; i++) {
    beats.add(ms(at));
    at += 500 + i * 6;
  }
  return BeatGrid(
    beats: beats,
    downbeats: [beats[1], beats[5], beats[9]],
    bpm: 115,
    confidence: 0.8,
    source: BeatGrid.sourceBeatThis,
  );
}

void main() {
  group('BeatGrid', () {
    test('validates its arguments', () {
      expect(() => BeatGrid(beats: const [], bpm: 120, source: 'x'), throwsArgumentError);
      expect(() => BeatGrid(beats: [ms(500), ms(500)], bpm: 120, source: 'x'), throwsArgumentError);
      expect(() => BeatGrid(beats: [ms(500), ms(100)], bpm: 120, source: 'x'), throwsArgumentError);
      expect(() => BeatGrid(beats: [ms(500)], downbeats: [ms(400)], bpm: 120, source: 'x'), throwsArgumentError);
      expect(() => BeatGrid(beats: [ms(500)], bpm: 0, source: 'x'), throwsArgumentError);
      expect(() => BeatGrid(beats: [ms(500)], bpm: 120, confidence: 2, source: 'x'), throwsArgumentError);
      expect(BeatGrid(beats: [ms(500)], bpm: 120, source: 'x').beats, [ms(500)]);
    });

    test('a regular grid lists the tempo\'s beats over the length with downbeats every 4th', () {
      final grid = BeatGrid.regular(Tempo(bpm: 120, firstBeatOffset: ms(250)), length: ms(3000));

      expect(grid.beats, [ms(250), ms(750), ms(1250), ms(1750), ms(2250), ms(2750)]);
      expect(grid.downbeats, [ms(250), ms(2250)]);
      expect(grid.bpm, 120);
      expect(grid.source, BeatGrid.sourceAutocorrelation);
      expect(grid.beatPeriod, ms(500));
      expect(grid.toTempo(), Tempo(bpm: 120, firstBeatOffset: ms(250)));
    });

    test('a regular grid starts at the timeline start for a negative first beat', () {
      final grid = BeatGrid.regular(Tempo(bpm: 120, firstBeatOffset: ms(-100)), length: ms(1000));

      expect(grid.beats, [ms(400), ms(900)]);
      expect(grid.downbeats, isEmpty, reason: 'beats n = 1, 2 of the tempo are not downbeats (n = 4 is past the end)');
    });

    test('a regular grid over a shorter length than one beat still has the first beat', () {
      expect(BeatGrid.regular(Tempo(bpm: 60), length: ms(100)).beats, [Duration.zero]);
    });

    test('beat position interpolates between beats and extrapolates with the mean period', () {
      final grid = irregularGrid();
      // Beats 0 and 1 at 250 and 750 ms.
      expect(grid.beatPositionAt(ms(250)), 0);
      expect(grid.beatPositionAt(ms(500)), closeTo(0.5, 1e-9));
      expect(grid.beatPositionAt(ms(750)), 1);
      expect(grid.beatIndexAt(ms(749)), 0);
      expect(grid.beatIndexAt(ms(750)), 1);
      // Beats 1 and 2 at 750 and 1256 ms.
      expect(grid.beats[2], ms(1256));
      expect(grid.phaseAt(ms(1003)), closeTo(0.5, 1e-9));
      // Before the first beat: the mean period.
      final period = grid.beatPeriod.inMicroseconds;
      expect(grid.beatPositionAt(ms(250) - Duration(microseconds: period)), closeTo(-1, 1e-9));
      expect(grid.beatIndexAt(ms(0)), -1);
      // After the last beat: the mean period from the last beat.
      final last = grid.beats.last;
      expect(grid.beatPositionAt(last + Duration(microseconds: period ~/ 2)), closeTo(11.5, 1e-6));
      expect(grid.beatIndexAt(last + Duration(microseconds: period * 2)), 13);
    });

    test('bar phase runs between downbeats, extrapolating the neighbouring bar', () {
      final grid = irregularGrid();
      final beats = grid.beats;
      expect(grid.barPhaseAt(beats[1]), 0);
      expect(grid.barPhaseAt(beats[3]), closeTo(0.5, 1e-9), reason: 'two of four beats into the bar');
      expect(grid.barPhaseAt(beats[5]), 0);
      expect(grid.barPhaseAt(beats[9]), 0);
      expect(grid.barPhaseAt(beats[11]), closeTo(0.5, 1e-9), reason: 'the last bar continues the last bar length');
      expect(grid.barPhaseAt(beats[0]), closeTo(0.75, 1e-9), reason: 'one beat before the first downbeat');
      expect(grid.barPositionAt(beats[0]), closeTo(-0.25, 1e-9));
      expect(grid.barPositionAt(beats[9]), 2);
      expect(grid.barPositionAt(beats[11]), closeTo(2.5, 1e-9));
      expect(grid.isDownbeat(beats[5]), isTrue);
      expect(grid.isDownbeat(beats[4]), isFalse);
    });

    test('bar phase without downbeats counts 4 beats from the first beat', () {
      final grid = BeatGrid(beats: [for (var i = 0; i < 8; i++) ms(i * 500)], bpm: 120, source: 'x');
      expect(grid.barPhaseAt(ms(1000)), closeTo(0.5, 1e-9));
      expect(grid.barPhaseAt(ms(2000)), 0);
      expect(grid.downbeatsBetween(Duration.zero, ms(4000)), [ms(0), ms(2000)]);
    });

    test('nearest beat and the beats between', () {
      final grid = irregularGrid();
      expect(grid.nearestBeat(ms(0)), ms(250));
      expect(grid.nearestBeat(ms(499)), ms(250));
      expect(grid.nearestBeat(ms(501)), ms(750));
      expect(grid.nearestBeat(ms(99999)), grid.beats.last);
      expect(grid.beatsBetween(ms(700), ms(1300)), [ms(750), ms(1256)]);
      expect(grid.beatsBetween(ms(750), ms(1256)), [ms(750)]);
      expect(grid.beatsBetween(Duration.zero, ms(300)), [ms(250)]);
      expect(grid.beatsBetween(ms(300), ms(300)), isEmpty);
      expect(grid.downbeatsBetween(ms(750), ms(4900)), [grid.beats[1], grid.beats[5]]);
    });

    test('shifted moves every beat; toTempo takes the bpm from the first beat', () {
      final grid = irregularGrid();
      final shifted = grid.shifted(ms(1000));
      expect(shifted.beats.first, ms(1250));
      expect(shifted.downbeats.first, grid.downbeats.first + ms(1000));
      expect(shifted.beatPeriod, grid.beatPeriod);
      expect(shifted.toTempo().firstBeatOffset, ms(1250));
      expect(shifted.toTempo().bpm, closeTo(grid.toTempo().bpm, 1e-9));
      expect(identical(grid.shifted(Duration.zero), grid), isTrue);
      final span = grid.beats.last - grid.beats.first;
      expect(grid.meanBpm, closeTo(60e6 * 11 / span.inMicroseconds, 1e-6));
      expect(grid.toTempo().bpm, 115);
    });

    test('toTempo clamps the bpm to the tempo range', () {
      final slow = BeatGrid(beats: [Duration.zero, const Duration(seconds: 10)], bpm: 6, source: 'x');
      expect(slow.toTempo().bpm, Tempo.minBpm);
    });

    test('equality is by value', () {
      expect(irregularGrid(), irregularGrid());
      expect(irregularGrid(), isNot(irregularGrid().shifted(ms(1))));
    });

    test('JSON round-trips and rejects malformed values', () {
      final grid = irregularGrid();
      final json = jsonDecode(jsonEncode(BeatGridJson.toJson(grid)));
      expect(BeatGridJson.fromJson(json), grid);
      expect(BeatGridJson.toJson(null), isNull);
      expect(BeatGridJson.fromJson(null), isNull);
      expect(BeatGridJson.fromJson('x'), isNull);
      expect(BeatGridJson.fromJson({'beatsUs': 'x', 'bpm': 120}), isNull);
      expect(
          BeatGridJson.fromJson({
            'beatsUs': [1.5],
            'bpm': 120
          }),
          isNull);
      expect(BeatGridJson.fromJson({'beatsUs': <int>[], 'bpm': 120}), isNull, reason: 'an empty grid is invalid');
      expect(
          BeatGridJson.fromJson({
            'beatsUs': [0, 500000],
            'downbeatsUs': [7],
            'bpm': 120
          }),
          isNull);
      final minimal = BeatGridJson.fromJson({
        'beatsUs': [0, 500000],
        'bpm': 120
      })!;
      expect(minimal.downbeats, isEmpty);
      expect(minimal.confidence, 1);
      expect(minimal.source, 'unknown');
    });
  });

  group('beat fields from a grid', () {
    test('AudioFrame.fromColumns prefers the beats over the tempo', () {
      final grid = irregularGrid();
      final columns = List.filled(AudioFeatureKey.columnCount, 0.0);
      final frame = AudioFrame.fromColumns(columns, tempo: Tempo(bpm: 60), beats: grid, time: ms(500));
      expect(frame.beatIndex, 0);
      expect(frame.beatPhase, closeTo(0.5, 1e-9));
      expect(frame.beatPulse, closeTo(math.exp(-3), 1e-9));
      expect(frame.barPhase, closeTo(grid.barPhaseAt(ms(500)), 1e-9));
      expect(frame.bpm, 115);
      expect(frame[AudioFeatureKey.beatPhase], closeTo(0.5, 1e-9));
    });

    test('AudioFeatures.sampleAt passes the beats on', () {
      final frame = syntheticFeatures().sampleAt(ms(750), beats: irregularGrid());
      expect(frame.beatIndex, 1);
      expect(frame.beatPhase, closeTo(0, 1e-9));
    });

    test('a regular grid gives the same beat fields as its tempo', () {
      final tempo = Tempo(bpm: 120, firstBeatOffset: ms(250));
      final grid = BeatGrid.regular(tempo, length: const Duration(seconds: 10));
      final columns = List.filled(AudioFeatureKey.columnCount, 0.0);
      for (final t in [ms(0), ms(250), ms(400), ms(1375), ms(9999), ms(12000)]) {
        final fromTempo = AudioFrame.fromColumns(columns, tempo: tempo, time: t);
        final fromGrid = AudioFrame.fromColumns(columns, beats: grid, time: t);
        expect(fromGrid.beatIndex, fromTempo.beatIndex, reason: '$t');
        expect(fromGrid.beatPhase, closeTo(fromTempo.beatPhase, 1e-6), reason: '$t');
        expect(fromGrid.barPhase, closeTo(fromTempo.barPhase, 1e-6), reason: '$t');
      }
    });
  });

  group('ParamResolver with beats', () {
    const number = NumberParam(id: 'n', label: LocalizedText('n'), min: 0, max: 10, defaultValue: 5);

    ParamResolver resolve(ParamBinding binding, {BeatGrid? beats, Tempo? tempo, Duration origin = Duration.zero}) =>
        ParamResolver(
          specs: const [number],
          bindings: {'n': binding},
          framerate: Framerate.fps30,
          frameCount: 300,
          beats: beats,
          tempo: tempo,
          audioOrigin: origin,
        );

    test('the beat LFO follows the real beats, not the tempo', () {
      final grid = irregularGrid();
      const lfo = BeatBinding(shape: BeatShape.saw, periodBeats: 1, min: 0, max: 10);
      final r = resolve(lfo, beats: grid, tempo: Tempo(bpm: 60));
      // Frame 15 = 500 ms: half way between the beats at 250 and 750 ms.
      expect(r.at(15).number('n'), closeTo(5, 1e-6));
      // Frame 30 = 1000 ms: between 750 and 1256 ms (a 506 ms beat).
      expect(r.at(30).number('n'), closeTo(10 * 250 / 506, 1e-6));
      // Without any clock: min.
      expect(resolve(lfo).at(15).number('n'), 0);
    });

    test('the beat audio keys are available with beats alone', () {
      const pulse = AudioBinding(feature: AudioFeatureKey.beatPulse, min: 0, max: 10);
      expect(resolve(pulse, beats: irregularGrid()).at(0).number('n'), greaterThan(0));
      expect(resolve(pulse).at(0).number('n'), 0);
    });

    test('random and step bindings count beats and bars on the grid', () {
      final grid = irregularGrid();
      const perBeat = RandomBinding(mode: RandomMode.perBeat, min: 0, max: 10, seed: 3);
      final r = resolve(perBeat, beats: grid);
      // Frames 8..22 lie within beat 0 (250..750 ms) → one held value.
      final held = r.at(8).number('n');
      expect(r.at(22).number('n'), held);
      expect(r.at(23).number('n'), isNot(held), reason: 'frame 23 = 766 ms is beat 1');

      const steps = StepBinding(steps: [1, 0, 0.5, 0.25], stepsPerBar: 4, min: 0, max: 10);
      final s = resolve(steps, beats: grid);
      // The first downbeat is beat 1 (750 ms): the bar restarts there.
      expect(s.at(23).number('n'), 10);
      expect(s.at(38).number('n'), 0, reason: '1266 ms is beat 2, the second step');
    });

    test('the envelope fires on every real beat and bar', () {
      final grid = irregularGrid();
      const env = EnvelopeBinding(
        trigger: EnvelopeTrigger.beat,
        attack: Duration.zero,
        decay: Duration(milliseconds: 100),
        min: 0,
        max: 10,
      );
      final r = resolve(env, beats: grid);
      final hits = <int>[];
      var previous = 0.0;
      for (var i = 0; i < 90; i++) {
        final v = r.at(i).number('n');
        if (v > previous + 1) hits.add(i);
        previous = v;
      }
      // Beats at 250, 750, 1256, 1768, 2286, 2810 ms → frames 8, 23, 38, 54, 69, 85.
      expect(hits, [8, 23, 38, 54, 69, 85]);
    });

    test('keyframes in beats use the grid\'s bpm', () {
      const keys =
          KeyframeBinding(keys: [Keyframe(at: 0, value: 0), Keyframe(at: 2, value: 10)], timeBase: KeyTime.beats);
      final grid = irregularGrid();
      // 1 s of clip time = 115 / 60 beats.
      expect(resolve(keys, beats: grid).at(30).number('n'), closeTo(10 * (115 / 60) / 2, 1e-6));
    });

    test('a bake with beats is deterministic and differs from the tempo bake', () {
      final request = testRequest(
        bindings: const {'brightness': BeatBinding(shape: BeatShape.pulse, min: 0, max: 1)},
      );
      final withBeats = BakeRequest(
        setup: request.setup,
        frameCount: request.frameCount,
        bindings: request.bindings,
        audio: request.audio,
        tempo: request.tempo,
        beats: irregularGrid(),
        audioOrigin: request.audioOrigin,
      );
      expect(withBeats, isNot(request));
      expect(bakeBytes(const SolidGenerator(), withBeats), bakeBytes(const SolidGenerator(), withBeats));
      expect(bakeBytes(const SolidGenerator(), withBeats), isNot(bakeBytes(const SolidGenerator(), request)));
    });
  });

  group('plugin protocol', () {
    test('beats round-trip through the header form', () {
      final grid = irregularGrid();
      final json = jsonDecode(jsonEncode(PluginProtocol.beatsToJson(grid)));
      expect(PluginProtocol.beatsFromJson(json), grid);
      expect(PluginProtocol.beatsFromJson(null), isNull);
    });
  });
}
