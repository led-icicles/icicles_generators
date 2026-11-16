import 'dart:typed_data';

import 'package:icicles_generators/plugin.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('meter', () {
    test('a 3/4 tempo counts bars of three beats', () {
      final tempo = Tempo(bpm: 60, beatsPerBar: 3);
      final features = AudioFeatures(Float32List(AudioFeatureKey.columnCount * 100));
      // 1.5 beats in: half a 3-beat bar.
      final frame = features.sampleAt(const Duration(milliseconds: 1500), tempo: tempo);
      expect(frame.barPhase, closeTo(0.5, 1e-9));
      expect(tempo.barPosition(const Duration(seconds: 6)), 2);
      expect(Tempo(bpm: 60).barPosition(const Duration(seconds: 6)), 1.5);
    });

    test('rejects a meter out of range and copies it', () {
      expect(() => Tempo(bpm: 120, beatsPerBar: 0), throwsArgumentError);
      expect(() => Tempo(bpm: 120, beatsPerBar: 17), throwsArgumentError);
      final t = Tempo(bpm: 120, beatsPerBar: 3);
      expect(t.copyWith(bpm: 100).beatsPerBar, 3);
      expect(t, isNot(Tempo(bpm: 120)));
    });

    test('bars convert with the meter', () {
      expect(const MusicalBinding.bars(2, beatsPerBar: 3).beats, 6);
      expect(const MusicalBinding.bars(2).beats, 8);
    });

    test('the plugin protocol carries the meter, omitted at 4/4', () {
      final waltz = Tempo(bpm: 150, firstBeatOffset: const Duration(milliseconds: 20), beatsPerBar: 3);
      expect(PluginProtocol.tempoFromJson(PluginProtocol.tempoToJson(waltz)), waltz);
      final plain = Tempo(bpm: 150);
      expect(PluginProtocol.tempoToJson(plain)!.containsKey('beatsPerBar'), isFalse);
      expect(PluginProtocol.tempoFromJson({'bpm': 150, 'firstBeatOffsetUs': 0}), plain);
    });

    test('bar-counting bindings follow the meter of the tempo', () {
      // A step binding advancing once per bar: at 60 bpm in 3/4 the third
      // bar starts at 6 s, in 4/4 at 8 s.
      final r = BakeRequest.forLength(
        setup: testSetup,
        length: const Duration(seconds: 1),
        tempo: Tempo(bpm: 60, beatsPerBar: 3),
      );
      expect(r.tempo!.barPosition(const Duration(seconds: 6)), 2);
    });
  });

  group('adaptive bands', () {
    AudioFeatures loudBass() {
      const rows = 3000;
      const columns = AudioFeatureKey.columnCount;
      final data = Float32List(rows * columns);
      for (var r = 0; r < rows; r++) {
        final wobble = (r ~/ 50).isEven ? 0.08 : -0.08;
        // The lowest band stays near the top, the highest one near the bottom.
        data[r * columns + AudioFeatureKey.firstBand] = 0.9 + wobble;
        data[r * columns + AudioFeatureKey.firstBand + AudioFeatureKey.bandCount - 1] = 0.1 + wobble;
      }
      return AudioFeatures(data);
    }

    double max(Float32List values) => values.reduce((a, b) => a > b ? a : b);
    double min(Float32List values) => values.reduce((a, b) => a < b ? a : b);

    test('every band moves through the range on its own', () {
      final song = loudBass();
      final shared = adaptiveAudioLevels(song, defaultLevelWindow);
      final perBand = adaptiveAudioLevels(song, defaultLevelWindow, perBand: true);
      final low = AudioFeatureKey.values[AudioFeatureKey.firstBand];
      // Shared: the loud band never leaves the top.
      expect(min(shared.column(low)), greaterThan(0.6));
      // Per band: it drops to the bottom between its peaks.
      expect(min(perBand.column(low)), lessThan(0.25));
      expect(max(perBand.column(low)), greaterThan(0.75));
      expect(identical(adaptiveAudioLevels(song, defaultLevelWindow, perBand: true), perBand), isTrue);
    });

    test('the request levels per band when asked', () {
      final song = loudBass();
      final request = BakeRequest.forLength(
        setup: testSetup,
        length: const Duration(seconds: 1),
        audio: song,
        reactivity: AudioReactivity.defaults.copyWith(level: AudioLevelMode.adaptiveBands),
      );
      expect(request.levelledAudio, same(adaptiveAudioLevels(song, defaultLevelWindow, perBand: true)));
      expect(AudioReactivityJson.fromJson(AudioReactivityJson.toJson(request.reactivity)), request.reactivity);
    });

    test('an adaptive level reaches a plugin with the reactivity off', () {
      final off = AudioReactivity.none.copyWith(level: AudioLevelMode.adaptive);
      expect(off.isActive, isFalse);
      final json = PluginProtocol.reactivityToJson(off);
      expect(json, isNotNull);
      expect(PluginProtocol.reactivityFromJson(json).level, AudioLevelMode.adaptive);
      expect(PluginProtocol.reactivityToJson(AudioReactivity.none), isNull);
    });
  });
}
