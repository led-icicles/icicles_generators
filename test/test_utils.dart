import 'dart:math' as math;
import 'dart:typed_data';

import 'package:icicles_animation_dart/icicles_animation_dart.dart';
import 'package:icicles_generators/icicles_generators.dart';

/// 24×20 icicles with 2 radio panels of 4 pixels at 30 fps.
const testSetup = GeneratorSetup(
  xCount: 24,
  yCount: 20,
  radioPanelsCount: 2,
  radioPanelPixelCount: 4,
  framerate: Framerate.fps30,
  seed: 7,
);

/// Synthetic features of [seconds]: every column a different slow wave, with
/// onset hits every 250 ms (strong ones every second).
AudioFeatures syntheticFeatures({double seconds = 10}) {
  final frames = (seconds * 100).round();
  final data = Float32List(frames * AudioFeatureKey.columnCount);
  for (var i = 0; i < frames; i++) {
    final t = i / 100;
    for (var c = 0; c < AudioFeatureKey.columnCount; c++) {
      final v = 0.5 + 0.5 * math.sin(t * (1.3 + c * 0.37) * math.pi + c);
      data[i * AudioFeatureKey.columnCount + c] = v;
    }
    data[i * AudioFeatureKey.columnCount + AudioFeatureKey.onset.index] =
        i % 25 == 0 ? (i % 100 == 0 ? 1.0 : 0.5) : 0.0;
  }
  return AudioFeatures(data);
}

/// Synthetic drum hits of [seconds] at 120 BPM: a kick on every beat
/// (strength alternating 1 / 0.4), a snare on beats 2 and 4, hi-hats on
/// eighths.
DrumHits syntheticDrums({double seconds = 10}) {
  final beats = (seconds * 2).floor();
  return DrumHits({
    DrumClass.kick: [for (var b = 0; b < beats; b++) DrumHit(Duration(milliseconds: 500 * b), b.isEven ? 1 : 0.4)],
    DrumClass.snare: [for (var b = 1; b < beats; b += 2) DrumHit(Duration(milliseconds: 500 * b), 0.8)],
    DrumClass.hihat: [for (var e = 0; e < 2 * beats; e++) DrumHit(Duration(milliseconds: 250 * e + 5), 0.5)],
  }, source: 'test');
}

/// A bake request of [seconds] on [testSetup] with synthetic audio, drum
/// hits and a 120 BPM tempo.
BakeRequest testRequest({Map<String, ParamBinding> bindings = const {}, double seconds = 2, int? seed}) =>
    BakeRequest.forLength(
      setup: seed == null ? testSetup : testSetup.copyWith(seed: seed),
      length: Duration(milliseconds: (seconds * 1000).round()),
      bindings: bindings,
      audio: syntheticFeatures(),
      drums: syntheticDrums(),
      tempo: Tempo(bpm: 120),
      audioOrigin: const Duration(milliseconds: 500),
    );

Uint8List bakeBytes(Generator generator, BakeRequest request) => bakeGenerator(generator, request).toBytes();
