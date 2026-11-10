import 'package:icicles_animation_dart/icicles_animation_dart.dart';

import '../generator/generator.dart';
import '../params/param_spec.dart';
import 'effect_info.dart';

/// A parametric effect written as code: it takes the layers composited
/// below it (an [AnimationView]) and returns a modified view, so the app can
/// place it as an adjustment layer over a track.
///
/// Implementations are usually `const` classes without state: all frame
/// state lives in the [EffectInstance] that [create] returns.
abstract interface class Effect {
  EffectInfo get info;

  /// The parameter schema (the same [ParamSpec]s and bindings as
  /// generators); the host builds its UI from it.
  List<ParamSpec> get params;

  /// A fresh instance for one run over [setup].
  EffectInstance create(GeneratorSetup setup);
}

/// One run of an [Effect]: applies the frames in order.
abstract interface class EffectInstance {
  /// Modifies grid frame [FrameContext.frameIndex]: reads [input] and draws
  /// the result into [out], which is pre-filled with [input] (the runner does
  /// `out.setView(input)` before each call), so an effect only touches what
  /// it changes.
  ///
  /// Called once per frame in order from frame 0, so the instance may keep
  /// state between frames (trails, echoes…); [input] is read-only. Use only
  /// [FrameContext.random] for randomness, so a run is reproducible from its
  /// seed.
  void apply(FrameContext ctx, AnimationView input, Icicles out);
}
