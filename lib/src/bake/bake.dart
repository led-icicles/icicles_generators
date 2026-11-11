import 'dart:math' as math;
import 'dart:typed_data';

import 'package:icicles_animation_dart/icicles_animation_dart.dart';

import '../generator/generator.dart';
import '../generator/generator_exception.dart';
import '../params/param_resolver.dart';
import 'bake_request.dart';
import 'frame_assembler.dart';
import 'frame_codec.dart';

/// Receives frame [index] of a bake: its [duration] and its RGB bytes (the
/// icicle pixels column-major, then the radio panels; valid only during the
/// call).
typedef BakedFrameCallback = void Function(int index, Duration duration, Uint8List rgb);

/// Bakes [generator] into an animation on the frame grid of [request].
///
/// The animation has the setup's layout (version 2), plays once, is
/// optimized and uses 24-bit colors, like the compositor's export; call
/// `toIndex()` for random access. Deterministic: the same generator,
/// request and seed give the same bytes, in process or in a plugin.
///
/// Throws a [GeneratorException]: [GeneratorErrorKind.invalidRequest] /
/// [GeneratorErrorKind.tooLong] for a bad request,
/// [GeneratorErrorKind.renderFailed] when the generator throws.
Animation bakeGenerator(Generator generator, BakeRequest request) {
  request.validate();
  final assembler = FrameAssembler(request.setup, name: request.name ?? generator.info.name.en);
  renderGeneratorFrames(generator, request, (_, duration, rgb) => assembler.add(duration, rgb));
  return assembler.build();
}

/// Renders the frames of [generator] for [request] without building an
/// animation, calling [onFrame] after each frame (the plugin side of the
/// protocol; [bakeGenerator] assembles the same frames).
///
/// The audio features are passed to the generator only when it or a binding
/// uses them ([needsAudioFeatures]), so a bake does not depend on audio it
/// does not read.
void renderGeneratorFrames(Generator generator, BakeRequest request, BakedFrameCallback onFrame) {
  request.validate();
  final setup = request.setup;
  final framerate = setup.framerate;
  final resolver = ParamResolver(
    specs: generator.params,
    bindings: request.bindings,
    framerate: framerate,
    frameCount: request.frameCount,
    audio: needsAudioFeatures(generator.info, request.bindings, macros: request.macros) ? request.audio : null,
    tempo: request.tempo,
    beats: request.beats,
    audioOrigin: request.audioOrigin,
    macros: request.macros,
    seed: setup.seed,
  );
  final Icicles icicles;
  try {
    icicles = Icicles(Animation(
      generator.info.id,
      xCount: setup.xCount,
      yCount: setup.yCount,
      framerate: framerate,
      radioPanelsCount: setup.radioPanelsCount,
      radioPanelPixelCount: setup.radioPanelPixelCount,
    ));
  } on Object catch (e) {
    throw GeneratorException(GeneratorErrorKind.invalidRequest, 'Invalid layout.', e);
  }
  final random = math.Random(setup.seed);
  final GeneratorInstance instance;
  try {
    instance = generator.create(setup);
  } on Object catch (e) {
    throw GeneratorException(GeneratorErrorKind.renderFailed, '${generator.info.id} failed to start.', e);
  }
  final rgb = Uint8List(setup.frameBytes);
  for (var index = 0; index < request.frameCount; index++) {
    final ctx = frameContextAt(setup, resolver, random, index);
    try {
      instance.render(ctx, icicles);
    } on Object catch (e) {
      throw GeneratorException(GeneratorErrorKind.renderFailed, '${generator.info.id} failed at frame $index.', e);
    }
    FrameCodec.encodeIcicles(icicles, rgb);
    onFrame(index, framerate.frameDuration(index), rgb);
  }
}

/// The [FrameContext] of grid frame [index] of a bake or an effect run over
/// [setup]: time and delta from the setup's frame grid, parameters and audio
/// from [resolver] (stepped to [index]), [random] shared by all frames.
FrameContext frameContextAt(GeneratorSetup setup, ParamResolver resolver, math.Random random, int index) {
  final framerate = setup.framerate;
  final start = framerate.frameStart(index);
  return FrameContext(
    setup: setup,
    frameIndex: index,
    time: start,
    delta: index == 0 ? Duration.zero : start - framerate.frameStart(index - 1),
    params: resolver.at(index),
    audio: resolver.audioAt(index),
    random: random,
  );
}
