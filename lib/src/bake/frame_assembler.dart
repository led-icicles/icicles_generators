import 'dart:typed_data';

import 'package:icicles_animation_dart/icicles_animation_dart.dart';

import '../generator/generator.dart';

/// Builds an animation from baked RGB frames, the way [bakeGenerator] does,
/// so frames received from a plugin give the same bytes as an in-process
/// bake.
final class FrameAssembler {
  final GeneratorSetup setup;
  final Animation _animation;
  late final Icicles _icicles = Icicles(_animation);
  final List<Color> _pixels;
  final List<List<Color>> _panels;
  int _frames = 0;

  FrameAssembler(this.setup, {required String name})
      : _animation = Animation(
          name,
          xCount: setup.xCount,
          yCount: setup.yCount,
          optimize: true,
          useRgb565: false,
          framerate: setup.framerate,
          loopsCount: 1,
          version: AnimationVersion.v2,
          radioPanelsCount: setup.radioPanelsCount,
          radioPanelPixelCount: setup.radioPanelPixelCount,
        ),
        _pixels = List.filled(setup.pixelsCount, const Color(0xFF000000)),
        _panels = List.generate(
          setup.radioPanelsCount,
          (_) => List.filled(setup.radioPanelPixelCount, const Color(0xFF000000)),
        );

  /// Frames added so far.
  int get frameCount => _frames;

  /// Appends a frame shown for [duration]: [setup].frameBytes RGB bytes of
  /// [rgb] from [offset].
  void add(Duration duration, Uint8List rgb, [int offset = 0]) {
    if (rgb.length - offset < setup.frameBytes) {
      throw ArgumentError.value(rgb.length, 'rgb', 'Expected ${setup.frameBytes} bytes from $offset.');
    }
    var o = offset;
    Color next() => Color.fromRGB(rgb[o++], rgb[o++], rgb[o++]);
    for (var i = 0; i < _pixels.length; i++) {
      _pixels[i] = next();
    }
    _icicles.setPixels(_pixels);
    for (var p = 0; p < _panels.length; p++) {
      final panel = _panels[p];
      for (var i = 0; i < panel.length; i++) {
        panel[i] = next();
      }
      _icicles.radioPanels[p].setPixels(panel);
    }
    _icicles.show(duration);
    _frames++;
  }

  /// The animation of the frames added so far.
  Animation build() => _animation;
}
