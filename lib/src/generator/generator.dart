import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:icicles_animation_dart/icicles_animation_dart.dart';

import '../audio/audio_frame.dart';
import '../params/param_spec.dart';
import '../params/param_values.dart';
import 'generator_info.dart';

/// A parametric animation written as code.
///
/// Implementations are usually `const` classes without state: all frame
/// state lives in the [GeneratorInstance] that [create] returns, so one
/// generator can bake many clips (also concurrently, in other isolates).
abstract interface class Generator {
  GeneratorInfo get info;

  /// The parameter schema; the host builds its UI from it.
  List<ParamSpec> get params;

  /// A fresh instance for one bake over [setup].
  GeneratorInstance create(GeneratorSetup setup);
}

/// One bake of a [Generator]: renders the frames in order.
abstract interface class GeneratorInstance {
  /// Draws grid frame [FrameContext.frameIndex] into [out].
  ///
  /// Called once per frame, in order from frame 0, so the instance may keep
  /// state between frames (particles, followers…). [out] keeps the previous
  /// frame's pixels and radio panels; whatever is not drawn stays as it was.
  /// Use only [FrameContext.random] for randomness, so a bake is
  /// reproducible from its seed.
  void render(FrameContext ctx, Icicles out);
}

/// The layout and seed of one bake.
final class GeneratorSetup extends Equatable {
  /// Icicles (columns).
  final int xCount;

  /// LEDs per icicle (rows); `y = 0` is the top (the roof).
  final int yCount;

  final int radioPanelsCount;
  final int radioPanelPixelCount;
  final Framerate framerate;

  /// Seed of [FrameContext.random].
  final int seed;

  const GeneratorSetup({
    required this.xCount,
    required this.yCount,
    this.radioPanelsCount = 0,
    this.radioPanelPixelCount = 1,
    this.framerate = Framerate.fps30,
    this.seed = 0,
  });

  /// Pixels of the icicles.
  int get pixelsCount => xCount * yCount;

  /// RGB bytes of one frame: the icicle pixels (column-major) followed by
  /// the radio panels.
  int get frameBytes => 3 * (pixelsCount + radioPanelsCount * radioPanelPixelCount);

  GeneratorSetup copyWith({
    int? xCount,
    int? yCount,
    int? radioPanelsCount,
    int? radioPanelPixelCount,
    Framerate? framerate,
    int? seed,
  }) =>
      GeneratorSetup(
        xCount: xCount ?? this.xCount,
        yCount: yCount ?? this.yCount,
        radioPanelsCount: radioPanelsCount ?? this.radioPanelsCount,
        radioPanelPixelCount: radioPanelPixelCount ?? this.radioPanelPixelCount,
        framerate: framerate ?? this.framerate,
        seed: seed ?? this.seed,
      );

  @override
  List<Object?> get props => [xCount, yCount, radioPanelsCount, radioPanelPixelCount, framerate, seed];
}

/// Everything a [GeneratorInstance] gets for one frame (Pixelblaze-like).
final class FrameContext {
  final GeneratorSetup setup;

  /// Index of the grid frame, from 0.
  final int frameIndex;

  /// Generator time of the frame start (`framerate.frameStart(frameIndex)`).
  final Duration time;

  /// Time since the previous frame start (zero for frame 0).
  final Duration delta;

  /// Parameter values resolved at this frame (bindings evaluated).
  final ParamValues params;

  /// Audio features at this frame; [AudioFrame.silent] without a soundtrack.
  final AudioFrame audio;

  /// The bake's seeded random generator, shared by all frames.
  final math.Random random;

  const FrameContext({
    required this.setup,
    required this.frameIndex,
    required this.time,
    required this.delta,
    required this.params,
    required this.audio,
    required this.random,
  });

  int get xCount => setup.xCount;
  int get yCount => setup.yCount;

  /// [time] in seconds.
  double get seconds => time.inMicroseconds / Duration.microsecondsPerSecond;

  /// [delta] in seconds.
  double get deltaSeconds => delta.inMicroseconds / Duration.microsecondsPerSecond;

  /// Column [x] normalized to `0..1` (0.5 for a single column).
  double nx(int x) => setup.xCount <= 1 ? 0.5 : x / (setup.xCount - 1);

  /// Row [y] normalized to `0..1` from the top (0.5 for a single row).
  double ny(int y) => setup.yCount <= 1 ? 0.5 : y / (setup.yCount - 1);
}
