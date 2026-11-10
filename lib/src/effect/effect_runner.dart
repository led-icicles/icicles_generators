import 'dart:math' as math;

import 'package:icicles_animation_dart/icicles_animation_dart.dart';

import '../bake/bake.dart';
import '../bake/bake_request.dart';
import '../bake/frame_codec.dart';
import '../generator/generator.dart';
import '../generator/generator_exception.dart';
import '../params/param_binding.dart';
import '../params/param_resolver.dart';
import 'effect.dart';
import 'effect_info.dart';

/// Whether an effect with [info] run with [bindings] reads the analysed
/// audio (then the run needs `BakeRequest.audio`).
bool effectNeedsAudioFeatures(EffectInfo info, Map<String, ParamBinding> bindings,
        {Map<String, ParamBinding> macros = const {}}) =>
    info.usesAudio || bindingsUseAudio(bindings, macros);

/// Whether the output depends on the audio clock (audio features or the
/// tempo), so the clip's position relative to the song matters
/// (`audioOrigin`).
bool effectNeedsAudioClock(EffectInfo info, Map<String, ParamBinding> bindings,
        {Map<String, ParamBinding> macros = const {}}) =>
    info.usesAudio || bindingsUseAudio(bindings, macros) || bindingsUseTempo(bindings, macros);

/// Applies an [Effect] frame by frame on the frame grid of a [BakeRequest]:
/// the app's compositor calls [applyAt] for every frame it renders with the
/// layers below the effect clip as the input.
///
/// Sequential like `ParamResolver`: frame `i` is generator time
/// `framerate.frameStart(i)`, the bindings are evaluated in order and the
/// effect instance keeps its state between frames. Call [applyAt] with
/// non-decreasing frame indices; asking for an earlier frame than the last
/// one starts the run over (a fresh instance and random, parameters replayed
/// from frame 0), so the result depends only on the sequence of inputs since
/// the last restart. Deterministic: the same effect, request, seed and
/// inputs give the same views.
///
/// Throws a [GeneratorException]: [GeneratorErrorKind.invalidRequest] /
/// [GeneratorErrorKind.tooLong] for a bad request (at construction) or an
/// input of another layout, [GeneratorErrorKind.renderFailed] when the
/// effect throws.
final class EffectRunner {
  final Effect effect;
  final BakeRequest request;
  final ParamResolver _resolver;
  final Icicles _icicles;
  math.Random _random;
  EffectInstance? _instance;
  int _lastIndex = -1;

  EffectRunner(this.effect, this.request)
      : _resolver = ParamResolver(
          specs: effect.params,
          bindings: request.bindings,
          framerate: request.setup.framerate,
          frameCount: request.frameCount,
          audio: effectNeedsAudioFeatures(effect.info, request.bindings, macros: request.macros) ? request.audio : null,
          tempo: request.tempo,
          audioOrigin: request.audioOrigin,
          macros: request.macros,
          seed: request.setup.seed,
        ),
        _icicles = _scratch(effect, request),
        _random = math.Random(request.setup.seed);

  GeneratorSetup get setup => request.setup;

  /// Frames of the run (`request.frameCount`).
  int get frameCount => request.frameCount;

  /// The index of the last applied frame, `-1` before the first one.
  int get lastFrameIndex => _lastIndex;

  static Icicles _scratch(Effect effect, BakeRequest request) {
    request.validate();
    final setup = request.setup;
    try {
      return Icicles(Animation(
        effect.info.id,
        xCount: setup.xCount,
        yCount: setup.yCount,
        framerate: setup.framerate,
        radioPanelsCount: setup.radioPanelsCount,
        radioPanelPixelCount: setup.radioPanelPixelCount,
      ));
    } on Object catch (e) {
      throw GeneratorException(GeneratorErrorKind.invalidRequest, 'Invalid layout.', e);
    }
  }

  /// Starts the run over: the next [applyAt] gets a fresh instance.
  void reset() {
    _instance = null;
    _lastIndex = -1;
    _random = math.Random(setup.seed);
  }

  /// The effect applied to [input] at grid frame [frameIndex] (`0` ≤ index
  /// < [frameCount]); the output keeps the input frame's duration.
  AnimationView applyAt(int frameIndex, AnimationView input) {
    if (frameIndex < 0 || frameIndex >= frameCount) {
      throw GeneratorException(GeneratorErrorKind.invalidRequest, 'Frame $frameIndex is outside 0..${frameCount - 1}.');
    }
    try {
      FrameCodec.checkView(setup, input);
    } on ArgumentError catch (e) {
      throw GeneratorException(GeneratorErrorKind.invalidRequest, 'The input does not fit the layout.', e);
    }
    if (frameIndex <= _lastIndex) reset();
    var instance = _instance;
    if (instance == null) {
      try {
        instance = _instance = effect.create(setup);
      } on Object catch (e) {
        throw GeneratorException(GeneratorErrorKind.renderFailed, '${effect.info.id} failed to start.', e);
      }
    }
    final ctx = frameContextAt(setup, _resolver, _random, frameIndex);
    _icicles.setView(input);
    try {
      instance.apply(ctx, input, _icicles);
    } on Object catch (e) {
      throw GeneratorException(GeneratorErrorKind.renderFailed, '${effect.info.id} failed at frame $frameIndex.', e);
    }
    _lastIndex = frameIndex;
    return FrameCodec.viewOf(_icicles, input.frame.duration);
  }
}
