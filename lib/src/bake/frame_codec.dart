import 'dart:typed_data';

import 'package:icicles_animation_dart/icicles_animation_dart.dart';

import '../generator/generator.dart';

/// The RGB layout of one frame of a bake / an effect run: the icicle pixels
/// column-major, then the radio panels (`GeneratorSetup.frameBytes` bytes).
abstract final class FrameCodec {
  /// Writes the current state of [icicles] into [rgb] from [offset].
  static void encodeIcicles(Icicles icicles, Uint8List rgb, [int offset = 0]) {
    var o = offset;
    for (final color in icicles.strip) {
      rgb[o++] = color.red;
      rgb[o++] = color.green;
      rgb[o++] = color.blue;
    }
    for (final panel in icicles.radioPanels) {
      for (final color in panel) {
        rgb[o++] = color.red;
        rgb[o++] = color.green;
        rgb[o++] = color.blue;
      }
    }
  }

  /// Writes [view] (of the layout of [setup]) into [rgb] from [offset].
  ///
  /// Throws an [ArgumentError] when the view does not fit the layout.
  static void encodeView(GeneratorSetup setup, AnimationView view, Uint8List rgb, [int offset = 0]) {
    checkView(setup, view);
    var o = offset;
    for (final color in view.frame.pixels) {
      rgb[o++] = color.red;
      rgb[o++] = color.green;
      rgb[o++] = color.blue;
    }
    for (var p = 1; p <= setup.radioPanelsCount; p++) {
      for (final color in view.radioPanels.firstWhere((panel) => panel.index == p).colors) {
        rgb[o++] = color.red;
        rgb[o++] = color.green;
        rgb[o++] = color.blue;
      }
    }
  }

  /// The view of the layout of [setup] encoded in [rgb] from [offset], shown
  /// for [duration].
  static AnimationView decodeView(GeneratorSetup setup, Uint8List rgb, {int offset = 0, required Duration duration}) {
    if (rgb.length - offset < setup.frameBytes) {
      throw ArgumentError.value(rgb.length, 'rgb', 'Expected ${setup.frameBytes} bytes from $offset.');
    }
    var o = offset;
    Color next() => Color.fromRGB(rgb[o++], rgb[o++], rgb[o++]);
    final pixels = List.generate(setup.pixelsCount, (_) => next(), growable: false);
    final panels = List.generate(
      setup.radioPanelsCount,
      (p) => RadioPanelView(p + 1, List.generate(setup.radioPanelPixelCount, (_) => next(), growable: false)),
      growable: false,
    );
    return AnimationView(VisualFrame(duration: duration, pixels: pixels), panels);
  }

  /// The current state of [icicles] as a view shown for [duration].
  static AnimationView viewOf(Icicles icicles, Duration duration) => AnimationView(
        VisualFrame(duration: duration, pixels: icicles.strip.toList()),
        [for (final (index, panel) in icicles.radioPanels.indexed) RadioPanelView(index + 1, panel.toList())],
      );

  /// Throws an [ArgumentError] unless [view] has the layout of [setup]
  /// (pixel count, radio panels 1…n each of the panel pixel count).
  static void checkView(GeneratorSetup setup, AnimationView view) {
    if (view.frame.pixels.length != setup.pixelsCount) {
      throw ArgumentError.value(view.frame.pixels.length, 'view', 'Expected ${setup.pixelsCount} pixels.');
    }
    if (view.radioPanels.length != setup.radioPanelsCount) {
      throw ArgumentError.value(view.radioPanels.length, 'view', 'Expected ${setup.radioPanelsCount} radio panels.');
    }
    final seen = <int>{};
    for (final panel in view.radioPanels) {
      if (panel.index < 1 || panel.index > setup.radioPanelsCount || !seen.add(panel.index)) {
        throw ArgumentError.value(panel.index, 'view', 'Bad radio panel index.');
      }
      if (panel.colors.length != setup.radioPanelPixelCount) {
        throw ArgumentError.value(panel.colors.length, 'view', 'Expected ${setup.radioPanelPixelCount} panel pixels.');
      }
    }
  }
}
