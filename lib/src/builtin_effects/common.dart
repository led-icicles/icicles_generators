import 'package:icicles_animation_dart/icicles_animation_dart.dart';

import '../generator/generator.dart';
import '../generator/localized_text.dart';
import '../params/param_spec.dart';
import '../params/param_values.dart';

/// The standard "also the radio panels" switch (`panels`) of an effect:
/// whether the effect processes the radio panels as well as the icicles.
const effectPanelsParam = BoolParam(
  id: 'panels',
  label: LocalizedText('Radio panels too', pl: 'Także panele radiowe'),
  defaultValue: true,
);

/// The dry/wet mix of an effect (`mix`): 0 leaves the input, 1 is the full
/// effect.
const mixParam = NumberParam(
  id: 'mix',
  label: LocalizedText('Mix', pl: 'Miks'),
  description:
      LocalizedText('0 leaves the input unchanged, 1 is the full effect.', pl: '0 zostawia wejście, 1 to pełny efekt.'),
  min: 0,
  max: 1,
  defaultValue: 1,
  step: 0.01,
);

/// The value of [effectPanelsParam] in [params].
bool panelsOf(ParamValues params) => params.flag('panels');

/// Black.
const black = Color(0xFF000000);

/// Pixel ([x], [y]) of [input] (column-major).
Color inputPixel(FrameContext ctx, AnimationView input, int x, int y) => input.frame.pixels[x * ctx.yCount + y];

/// Applies [map] to every icicle pixel of [input] into [out], and to every
/// radio panel pixel when [panels] is set.
void mapPixels(FrameContext ctx, AnimationView input, Icicles out, bool panels, Color Function(Color) map) {
  final pixels = input.frame.pixels;
  for (var i = 0; i < pixels.length; i++) {
    out.setPixelColorAtIndex(i, map(pixels[i]));
  }
  if (!panels) return;
  for (final panel in input.radioPanels) {
    final target = out.radioPanels[panel.index - 1];
    for (var i = 0; i < panel.colors.length; i++) {
      target.setPixel(i, map(panel.colors[i]));
    }
  }
}

/// Writes [pixels] (column-major, the whole grid) into [out].
void setGrid(Icicles out, List<Color> pixels) => out.setPixels(pixels);

/// Pixel ([x], [y]) of [input] sampled with wrapping (or black outside the
/// grid when [wrap] is false).
Color sampleGrid(FrameContext ctx, AnimationView input, int x, int y, {required bool wrap}) {
  final w = ctx.xCount, h = ctx.yCount;
  if (wrap) {
    x %= w;
    y %= h;
    if (x < 0) x += w;
    if (y < 0) y += h;
  } else if (x < 0 || y < 0 || x >= w || y >= h) {
    return black;
  }
  return input.frame.pixels[x * h + y];
}

/// Scales each channel of [color] by [factor] (clamped to 0..255).
Color scaleColor(Color color, double factor) {
  if (!factor.isFinite) return black;
  return Color.fromRGB(
    (color.red * factor).round().clamp(0, 255),
    (color.green * factor).round().clamp(0, 255),
    (color.blue * factor).round().clamp(0, 255),
  );
}
