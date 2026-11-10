import 'dart:typed_data';

import 'package:icicles_animation_dart/icicles_animation_dart.dart';
import 'package:icicles_generators/icicles_generators.dart';

import 'test_utils.dart';

/// Synthetic input views for [request] on its setup: a hue gradient across
/// the icicles, brightness along them (the two lowest rows black), a white
/// dot circling the grid, and panels of varied colors.
List<AnimationView> syntheticInputs(BakeRequest request) {
  final setup = request.setup;
  final w = setup.xCount, h = setup.yCount;
  return List.generate(request.frameCount, (frame) {
    final pixels = List<Color>.filled(w * h, const Color(0xFF000000));
    for (var x = 0; x < w; x++) {
      for (var y = 0; y < h; y++) {
        pixels[x * h + y] = y >= h - 2 ? const Color(0xFF000000) : hsv(x / w, 0.6, 0.15 + 0.85 * y / (h - 1));
      }
    }
    final dotX = (frame * 7) % w, dotY = (frame * 3) % (h - 2);
    pixels[dotX * h + dotY] = const Color(0xFFFFFFFF);
    final panels = List.generate(
      setup.radioPanelsCount,
      (p) => RadioPanelView(
        p + 1,
        List.generate(setup.radioPanelPixelCount, (i) => hsv((p * 4 + i) / 8 + frame / 60, 0.7, 0.4 + 0.2 * i)),
      ),
    );
    return AnimationView(VisualFrame(duration: setup.framerate.frameDuration(frame), pixels: pixels), panels);
  });
}

/// Inputs of [request] that are all black.
List<AnimationView> blackInputs(BakeRequest request) {
  final setup = request.setup;
  return List.generate(
    request.frameCount,
    (frame) => AnimationView(
      VisualFrame(
        duration: setup.framerate.frameDuration(frame),
        pixels: List.filled(setup.pixelsCount, const Color(0xFF000000)),
      ),
      List.generate(
        setup.radioPanelsCount,
        (p) => RadioPanelView(p + 1, List.filled(setup.radioPanelPixelCount, const Color(0xFF000000))),
      ),
    ),
  );
}

/// [effect] applied to [inputs] frame by frame.
List<AnimationView> applyAll(Effect effect, BakeRequest request, List<AnimationView> inputs) {
  final runner = EffectRunner(effect, request);
  return [for (var i = 0; i < inputs.length; i++) runner.applyAt(i, inputs[i])];
}

/// The RGB bytes of [views] on [setup], one frame after another.
Uint8List viewBytes(GeneratorSetup setup, List<AnimationView> views) {
  final out = Uint8List(setup.frameBytes * views.length);
  for (var i = 0; i < views.length; i++) {
    FrameCodec.encodeView(setup, views[i], out, i * setup.frameBytes);
  }
  return out;
}

/// The bytes of [effect] applied over [request] to [inputs] (the synthetic
/// inputs by default).
Uint8List effectBytes(Effect effect, BakeRequest request, [List<AnimationView>? inputs]) =>
    viewBytes(request.setup, applyAll(effect, request, inputs ?? syntheticInputs(request)));

/// Whether [view] is all black (icicles and panels).
bool isBlack(AnimationView view) =>
    view.frame.pixels.every((c) => c.value & 0xFFFFFF == 0) &&
    view.radioPanels.every((p) => p.colors.every((c) => c.value & 0xFFFFFF == 0));

/// The 2 s test request (see [testRequest]).
BakeRequest effectRequest({Map<String, ParamBinding> bindings = const {}, double seconds = 2}) =>
    testRequest(bindings: bindings, seconds: seconds);
