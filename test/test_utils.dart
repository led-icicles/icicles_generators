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

/// A bake request of [seconds] on [testSetup] with synthetic audio and a
/// 120 BPM tempo.
BakeRequest testRequest({Map<String, ParamBinding> bindings = const {}, double seconds = 2, int? seed}) =>
    BakeRequest.forLength(
      setup: seed == null ? testSetup : testSetup.copyWith(seed: seed),
      length: Duration(milliseconds: (seconds * 1000).round()),
      bindings: bindings,
      audio: syntheticFeatures(),
      tempo: Tempo(bpm: 120),
      audioOrigin: const Duration(milliseconds: 500),
    );

Uint8List bakeBytes(Generator generator, BakeRequest request) => bakeGenerator(generator, request).toBytes();
