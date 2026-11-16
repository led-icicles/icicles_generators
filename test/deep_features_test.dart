import 'dart:typed_data';

import 'package:icicles_animation_dart/icicles_animation_dart.dart';
import 'package:icicles_generators/plugin.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// 10 s of deep features: vocals only in 2–4 s (level 0.9), the drums stem
/// constant 0.5; chroma: pure A (pitch class 9) before 5 s, pure G after.
DeepAudioFeatures syntheticDeep() {
  const rows = 1000;
  final stems = Float32List(rows * 4);
  for (var r = 0; r < rows; r++) {
    stems[r * 4 + StemKind.drums.index] = 0.5;
    if (r >= 200 && r < 400) stems[r * 4 + StemKind.vocals.index] = 0.9;
  }
  const chromaRows = 100;
  final chroma = Float32List(chromaRows * 12);
  for (var r = 0; r < chromaRows; r++) {
    // A minor-ish triad before 5 s, G major after.
    final notes = r < 50 ? [9, 0, 4] : [7, 11, 2];
    chroma[r * 12 + notes[0]] = 0.6;
    chroma[r * 12 + notes[1]] = 0.2;
    chroma[r * 12 + notes[2]] = 0.2;
  }
  return DeepAudioFeatures(stems: StemLevels(stems, rows: rows), chroma: Chroma(chroma, rows: chromaRows));
}

void main() {
  group('DeepAudioFeatures', () {
    test('codec round-trips and hashes by content', () {
      final deep = syntheticDeep();
      final back = DeepAudioFeaturesCodec.fromBytes(DeepAudioFeaturesCodec.toBytes(deep));
      expect(back.stems.data, deep.stems.data);
      expect(back.chroma.data, deep.chroma.data);
      expect(DeepAudioFeaturesCodec.contentHash(back), DeepAudioFeaturesCodec.contentHash(deep));
      expect(() => DeepAudioFeaturesCodec.fromBytes(Uint8List(8)), throwsFormatException);
    });

    test('stems, pitch and key reach the audio frame', () {
      final deep = syntheticDeep();
      final features = syntheticFeatures();
      final inVocals = features.sampleAt(const Duration(seconds: 3), deep: deep);
      final noVocals = features.sampleAt(const Duration(seconds: 6), deep: deep);
      expect(inVocals.hasDeep, isTrue);
      expect(inVocals[AudioFeatureKey.vocals], closeTo(0.9, 1e-6));
      expect(noVocals[AudioFeatureKey.vocals], 0);
      expect(inVocals[AudioFeatureKey.drumsStem], closeTo(0.5, 1e-6));
      // A = 9 → 9·7 mod 12 = 3 on the circle of fifths; G = 7 → 1.
      expect(inVocals[AudioFeatureKey.pitchHue], closeTo(3 / 12, 1e-6));
      expect(noVocals[AudioFeatureKey.pitchHue], closeTo(1 / 12, 1e-6));
      expect(inVocals[AudioFeatureKey.pitchClarity], greaterThan(0.3));
      expect(deep.keyAt(const Duration(seconds: 1))?.name, 'A minor');
      expect(deep.keyAt(const Duration(seconds: 9))?.name, 'G major');
      expect(noVocals[AudioFeatureKey.keyHue], closeTo(fifthsHue(7), 1e-6));
    });

    test('without the deep analysis the keys fall back to the mix', () {
      final frame = syntheticFeatures().sampleAt(const Duration(seconds: 3));
      expect(frame.hasDeep, isFalse);
      expect(frame[AudioFeatureKey.vocals], closeTo(frame.energyBetween(300, 3400), 1e-9));
      expect(frame[AudioFeatureKey.bassStem], frame.bass);
      expect(frame[AudioFeatureKey.drumsStem], frame.onset);
      expect(frame[AudioFeatureKey.otherStem], frame.mid);
      expect(frame[AudioFeatureKey.pitchHue], frame.peakFrequency);
      expect(frame[AudioFeatureKey.keyHue], 0);
    });

    test('bindings, generators and reactivity declare their need', () {
      const vocals = AudioBinding(feature: AudioFeatureKey.vocals, min: 0, max: 1);
      const info = GeneratorInfo(
        id: 'x',
        version: 1,
        name: LocalizedText('x'),
        description: LocalizedText('x'),
        category: GeneratorCategory.basic,
      );
      expect(vocals.usesDeepFeatures, isTrue);
      expect(vocals.usesAudioFeatures, isTrue);
      expect(needsDeepFeatures(info, {'brightness': vocals}), isTrue);
      expect(needsDeepFeatures(info, {'brightness': const MacroBinding('m')}, macros: {'m': vocals}), isTrue);
      expect(needsDeepFeatures(info, {'b': const AudioBinding(feature: AudioFeatureKey.mid, min: 0, max: 1)}), isFalse);
      final stemReactivity = AudioReactivity.defaults.copyWith(stem: StemKind.vocals);
      expect(needsDeepFeatures(info, const {}, reactivity: stemReactivity), isTrue);
      expect(needsDeepFeatures(info, const {}, reactivity: AudioReactivity.defaults), isFalse);
    });

    test('a bake reads the stems only when they are passed', () {
      final generator = builtInGenerators.firstWhere((g) => g.info.id == 'icicles.solid');
      final request = testRequest(bindings: {
        'brightness': const AudioBinding(feature: AudioFeatureKey.vocals, min: 0, max: 1, attack: Duration.zero),
      }, seconds: 4);
      final withDeep = BakeRequest.forLength(
        setup: request.setup,
        length: request.length,
        bindings: request.bindings,
        audio: request.audio,
        deep: syntheticDeep(),
      );
      expect(withDeep, isNot(request));
      final frames = <int>[];
      renderGeneratorFrames(generator, withDeep, (_, __, rgb) => frames.add(rgb.fold<int>(0, (a, b) => a + b)));
      // Dark before 2 s, lit within.
      double lit(int frame) => frames[frame].toDouble();
      expect(lit(30), 0);
      expect(lit(75), greaterThan(0));
    });
  });

  group('MusicalBinding', () {
    ParamValues resolve(NumberParam spec, ParamBinding binding, {Tempo? tempo}) => ParamResolver(
          specs: [spec],
          bindings: {spec.id: binding},
          framerate: Framerate.fps30,
          frameCount: 1,
          tempo: tempo,
        ).at(0);

    const seconds = NumberParam(id: 'p', label: LocalizedText('p'), min: 0, max: 10, defaultValue: 1, unit: 's');
    const millis = NumberParam(id: 'p', label: LocalizedText('p'), min: 0, max: 5000, defaultValue: 80, unit: 'ms');
    const rate = NumberParam(id: 'p', label: LocalizedText('p'), min: 0.1, max: 5, defaultValue: 1, unit: '/s');
    const plain = NumberParam(id: 'p', label: LocalizedText('p'), min: 0, max: 10, defaultValue: 1);

    test('turns beats into the unit at the clock tempo', () {
      final tempo = Tempo(bpm: 128);
      expect(resolve(seconds, const MusicalBinding(1), tempo: tempo).number('p'), closeTo(0.46875, 1e-9));
      expect(resolve(millis, const MusicalBinding(0.5), tempo: tempo).number('p'), closeTo(234.375, 1e-6));
      expect(resolve(rate, const MusicalBinding.bars(1), tempo: tempo).number('p'), closeTo(1 / 1.875, 1e-9));
      // Without a clock: 120 BPM.
      expect(resolve(seconds, const MusicalBinding(2)).number('p'), closeTo(1, 1e-9));
    });

    test('is clamped to the range and refused by non-time parameters', () {
      expect(resolve(seconds, const MusicalBinding(100), tempo: Tempo(bpm: 120)).number('p'), 10);
      expect(plain.salvage(const MusicalBinding(1)), plain.defaultBinding);
      expect(seconds.salvage(const MusicalBinding(1)), const MusicalBinding(1));
      expect(const MusicalBinding(1).usesTempo, isTrue);
    });

    test('works as a stack base', () {
      const stack = StackedBinding(base: MusicalBinding(1), modulators: []);
      expect(seconds.salvage(stack), stack);
      expect(resolve(seconds, stack, tempo: Tempo(bpm: 60)).number('p'), closeTo(1, 1e-9));
    });
  });

  group('ParamBindingJson', () {
    test('round-trips the new kinds', () {
      for (final binding in [
        const MusicalBinding(2),
        const AudioBinding(feature: AudioFeatureKey.vocals, min: 0.1, max: 0.9),
        const AudioBinding(feature: AudioFeatureKey.keyHue, min: 0, max: 1),
      ]) {
        expect(ParamBindingJson.fromJson(ParamBindingJson.toJson(binding)), binding);
      }
    });

    test('tryFromJson tells why a binding is unreadable', () {
      expect(ParamBindingJson.tryFromJson({'type': 'audio', 'feature': 'voice', 'min': 0, 'max': 1}).error,
          allOf(contains('"voice"'), contains('vocals')));
      expect(ParamBindingJson.tryFromJson({'type': 'audio', 'feature': 'bass', 'min': 0}).error, contains('max'));
      expect(ParamBindingJson.tryFromJson({'type': 'wobble'}).error, contains('musical'));
      expect(ParamBindingJson.tryFromJson(42).error, contains('object'));
      final ok = ParamBindingJson.tryFromJson({'type': 'musical', 'beats': 1});
      expect(ok.binding, const MusicalBinding(1));
      expect(ok.error, isNull);
    });
  });

  group('adaptive levels', () {
    AudioFeatures constantBass({required double level}) {
      const rows = 3000;
      final data = Float32List(rows * AudioFeatureKey.columnCount);
      for (var r = 0; r < rows; r++) {
        // A bass that never drops below 0.85, wobbling slowly by ±0.07.
        final wobble = (r ~/ 50).isEven ? 0.07 : -0.07;
        data[r * AudioFeatureKey.columnCount + AudioFeatureKey.bass.index] = level + wobble;
      }
      return AudioFeatures(data);
    }

    test('a part that stays loud moves through the range again', () {
      final song = constantBass(level: 0.9);
      final levelled = adaptiveAudioLevels(song, defaultLevelWindow);
      final values = levelled.column(AudioFeatureKey.bass);
      final lo = values.reduce((a, b) => a < b ? a : b);
      final hi = values.reduce((a, b) => a > b ? a : b);
      expect(song.column(AudioFeatureKey.bass).reduce((a, b) => a < b ? a : b), greaterThan(0.8));
      expect(lo, lessThan(0.25));
      expect(hi, greaterThan(0.75));
      expect(identical(adaptiveAudioLevels(song, defaultLevelWindow), levelled), isTrue);
    });

    test('the reactivity levels the request input', () {
      final song = constantBass(level: 0.9);
      final request = BakeRequest.forLength(
        setup: testSetup,
        length: const Duration(seconds: 1),
        audio: song,
        reactivity: AudioReactivity.defaults.copyWith(level: AudioLevelMode.adaptive),
      );
      expect(request.levelledAudio, isNot(same(song)));
      final plain = testRequest();
      expect(plain.levelledAudio, same(plain.audio));
    });
  });

  group('AudioReactivity', () {
    test('stem, level and the new hue sources round-trip', () {
      final r = AudioReactivity.defaults
          .copyWith(stem: StemKind.vocals, level: AudioLevelMode.adaptive, levelWindow: const Duration(seconds: 4))
          .withMode(ReactiveModeKind.hue, const ReactiveMode(min: 0, max: 1, hueSource: ReactiveHueSource.key));
      final json = AudioReactivityJson.toJson(r);
      expect(json['stem'], 'vocals');
      expect(json['level'], 'adaptive');
      expect(AudioReactivityJson.fromJson(json), r);
      expect(AudioReactivityJson.toJson(AudioReactivity.defaults).containsKey('stem'), isFalse);
      expect(AudioReactivityJson.toJson(AudioReactivity.defaults).containsKey('level'), isFalse);
      expect(r.usesDeepFeatures, isTrue);
      expect(r.copyWith(clearStem: true).stem, isNull);
    });

    test('the energy follows the stem', () {
      final deep = syntheticDeep();
      final features = syntheticFeatures();
      final engine = ReactiveEngine(AudioReactivity.defaults.copyWith(stem: StemKind.vocals, attack: Duration.zero));
      final inside = engine.step(features.sampleAt(const Duration(seconds: 3), deep: deep), const Duration(seconds: 1));
      expect(inside.energy, closeTo(0.9, 1e-6));
      final outside =
          engine.step(features.sampleAt(const Duration(seconds: 6), deep: deep), const Duration(seconds: 1));
      expect(outside.energy, lessThan(0.01));
    });
  });

  test('the plugin protocol carries the deep analysis', () {
    final deep = syntheticDeep();
    final back = PluginProtocol.deepFromJson(PluginProtocol.deepToJson(deep));
    expect(back?.stems.data, deep.stems.data);
    expect(PluginProtocol.deepFromJson('not base64!'), isNull);
    expect(PluginProtocol.deepFromJson(null), isNull);
  });
}
