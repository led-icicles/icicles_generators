import 'dart:math' as math;
import 'dart:typed_data';

import 'package:icicles_animation_dart/icicles_animation_dart.dart';

import '../effect/effect.dart';
import '../effect/effect_info.dart';
import '../generator/generator.dart';
import '../generator/localized_text.dart';
import '../params/param_spec.dart';
import '../util/color.dart';
import 'common.dart';

/// A box blur of [radius] along `y` (within each icicle) of [src] (column
/// major floats, 3 per pixel) into [dst].
void _blurAlong(Float32List src, Float32List dst, int w, int h, double radius) {
  final r = radius.round();
  if (r <= 0) {
    dst.setAll(0, src);
    return;
  }
  for (var x = 0; x < w; x++) {
    for (var y = 0; y < h; y++) {
      var sr = 0.0, sg = 0.0, sb = 0.0, n = 0;
      for (var k = math.max(0, y - r); k <= math.min(h - 1, y + r); k++) {
        final i = (x * h + k) * 3;
        sr += src[i];
        sg += src[i + 1];
        sb += src[i + 2];
        n++;
      }
      final o = (x * h + y) * 3;
      dst[o] = sr / n;
      dst[o + 1] = sg / n;
      dst[o + 2] = sb / n;
    }
  }
}

/// A box blur of [radius] across `x` (over the icicles) of [src] into [dst].
void _blurAcross(Float32List src, Float32List dst, int w, int h, double radius) {
  final r = radius.round();
  if (r <= 0) {
    dst.setAll(0, src);
    return;
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var sr = 0.0, sg = 0.0, sb = 0.0, n = 0;
      for (var k = math.max(0, x - r); k <= math.min(w - 1, x + r); k++) {
        final i = (k * h + y) * 3;
        sr += src[i];
        sg += src[i + 1];
        sb += src[i + 2];
        n++;
      }
      final o = (x * h + y) * 3;
      dst[o] = sr / n;
      dst[o + 1] = sg / n;
      dst[o + 2] = sb / n;
    }
  }
}

Float32List _toFloats(List<Color> pixels) {
  final out = Float32List(pixels.length * 3);
  for (var i = 0; i < pixels.length; i++) {
    final c = pixels[i];
    out[i * 3] = c.red / 255;
    out[i * 3 + 1] = c.green / 255;
    out[i * 3 + 2] = c.blue / 255;
  }
  return out;
}

/// Writes [floats] mixed with the input by [mix] into [out].
void _writeMixed(Icicles out, List<Color> input, Float32List floats, double mix) {
  for (var i = 0; i < input.length; i++) {
    final blurred = colorFromUnit(floats[i * 3], floats[i * 3 + 1], floats[i * 3 + 2]);
    out.setPixelColorAtIndex(i, mix >= 1 ? blurred : mixColors(input[i], blurred, mix));
  }
}

const _radiusLabel = LocalizedText('Radius', pl: 'Promień');

/// A blur along the icicles.
final class BlurVerticalEffect implements Effect {
  const BlurVerticalEffect();

  @override
  EffectInfo get info => const EffectInfo(
        id: 'icicles.fx.blur_vertical',
        version: 1,
        name: LocalizedText('Blur along', pl: 'Rozmycie wzdłuż'),
        description: LocalizedText('Smears every icicle along its LEDs.', pl: 'Rozmywa każdy sopel wzdłuż jego diod.'),
        category: EffectCategory.blur,
      );

  @override
  List<ParamSpec> get params => const [
        NumberParam(id: 'radius', label: _radiusLabel, min: 0, max: 10, defaultValue: 2, step: 0.5, unit: 'px'),
        mixParam,
      ];

  @override
  EffectInstance create(GeneratorSetup setup) => const _BlurVerticalInstance();
}

final class _BlurVerticalInstance implements EffectInstance {
  const _BlurVerticalInstance();

  @override
  void apply(FrameContext ctx, AnimationView input, Icicles out) {
    final p = ctx.params;
    final radius = p.number('radius');
    final mix = p.number('mix');
    if (radius.round() == 0 || mix <= 0) return;
    final src = _toFloats(input.frame.pixels);
    final dst = Float32List(src.length);
    _blurAlong(src, dst, ctx.xCount, ctx.yCount, radius);
    _writeMixed(out, input.frame.pixels, dst, mix);
  }
}

/// A 2-D box blur.
final class BlurBoxEffect implements Effect {
  const BlurBoxEffect();

  @override
  EffectInfo get info => const EffectInfo(
        id: 'icicles.fx.blur_box',
        version: 1,
        name: LocalizedText('Blur', pl: 'Rozmycie'),
        description: LocalizedText('A box blur across and along the icicles.',
            pl: 'Rozmycie pudełkowe w poprzek i wzdłuż sopli.'),
        category: EffectCategory.blur,
      );

  @override
  List<ParamSpec> get params => const [
        NumberParam(
          id: 'radiusX',
          label: LocalizedText('Radius across', pl: 'Promień w poprzek'),
          min: 0,
          max: 10,
          defaultValue: 1,
          step: 0.5,
          unit: 'px',
        ),
        NumberParam(
          id: 'radiusY',
          label: LocalizedText('Radius along', pl: 'Promień wzdłuż'),
          min: 0,
          max: 10,
          defaultValue: 2,
          step: 0.5,
          unit: 'px',
        ),
        mixParam,
      ];

  @override
  EffectInstance create(GeneratorSetup setup) => const _BlurBoxInstance();
}

final class _BlurBoxInstance implements EffectInstance {
  const _BlurBoxInstance();

  @override
  void apply(FrameContext ctx, AnimationView input, Icicles out) {
    final p = ctx.params;
    final rx = p.number('radiusX');
    final ry = p.number('radiusY');
    final mix = p.number('mix');
    if ((rx.round() == 0 && ry.round() == 0) || mix <= 0) return;
    final src = _toFloats(input.frame.pixels);
    final tmp = Float32List(src.length);
    final dst = Float32List(src.length);
    _blurAcross(src, tmp, ctx.xCount, ctx.yCount, rx);
    _blurAlong(tmp, dst, ctx.xCount, ctx.yCount, ry);
    _writeMixed(out, input.frame.pixels, dst, mix);
  }
}

/// Bright parts bloom.
final class GlowEffect implements Effect {
  const GlowEffect();

  @override
  EffectInfo get info => const EffectInfo(
        id: 'icicles.fx.glow',
        version: 1,
        name: LocalizedText('Glow', pl: 'Poświata'),
        description: LocalizedText(
          'Bright parts bleed into their surroundings: threshold, blur, add.',
          pl: 'Jasne fragmenty rozlewają się na otoczenie: próg, rozmycie, dodanie.',
        ),
        category: EffectCategory.blur,
      );

  @override
  List<ParamSpec> get params => const [
        NumberParam(
          id: 'threshold',
          label: LocalizedText('Threshold', pl: 'Próg'),
          description:
              LocalizedText('Only pixels brighter than this glow.', pl: 'Świecą tylko piksele jaśniejsze niż próg.'),
          min: 0,
          max: 1,
          defaultValue: 0.5,
          step: 0.01,
        ),
        NumberParam(id: 'radius', label: _radiusLabel, min: 0.5, max: 10, defaultValue: 2, step: 0.5, unit: 'px'),
        NumberParam(
          id: 'amount',
          label: LocalizedText('Amount', pl: 'Stopień'),
          min: 0,
          max: 4,
          defaultValue: 1,
          step: 0.05,
          unit: '×',
        ),
        BoolParam(
          id: 'panels',
          label: LocalizedText('Radio panels too', pl: 'Także panele radiowe'),
          description: LocalizedText('Panels brighter than the threshold get the glow of their own color.',
              pl: 'Panele jaśniejsze niż próg dostają poświatę własnego koloru.'),
          defaultValue: true,
        ),
      ];

  @override
  EffectInstance create(GeneratorSetup setup) => const _GlowInstance();
}

final class _GlowInstance implements EffectInstance {
  const _GlowInstance();

  @override
  void apply(FrameContext ctx, AnimationView input, Icicles out) {
    final p = ctx.params;
    final threshold = p.number('threshold');
    final radius = p.number('radius');
    final amount = p.number('amount');
    if (amount <= 0) return;
    final pixels = input.frame.pixels;
    final bright = Float32List(pixels.length * 3);
    for (var i = 0; i < pixels.length; i++) {
      final c = pixels[i];
      final l = luma(c);
      if (l <= threshold) continue;
      final k = (l - threshold) / math.max(1e-6, 1 - threshold) / l;
      bright[i * 3] = c.red / 255 * k;
      bright[i * 3 + 1] = c.green / 255 * k;
      bright[i * 3 + 2] = c.blue / 255 * k;
    }
    final tmp = Float32List(bright.length);
    final blurred = Float32List(bright.length);
    _blurAcross(bright, tmp, ctx.xCount, ctx.yCount, radius);
    _blurAlong(tmp, blurred, ctx.xCount, ctx.yCount, radius);
    for (var i = 0; i < pixels.length; i++) {
      final c = pixels[i];
      out.setPixelColorAtIndex(
        i,
        colorFromUnit(
          c.red / 255 + blurred[i * 3] * amount,
          c.green / 255 + blurred[i * 3 + 1] * amount,
          c.blue / 255 + blurred[i * 3 + 2] * amount,
        ),
      );
    }
    if (!p.flag('panels')) return;
    for (final panel in input.radioPanels) {
      final target = out.radioPanels[panel.index - 1];
      for (var i = 0; i < panel.colors.length; i++) {
        final c = panel.colors[i];
        final l = luma(c);
        if (l <= threshold) continue;
        final k = 1 + (l - threshold) / math.max(1e-6, 1 - threshold) * amount;
        target.setPixel(i, scaleColor(c, k));
      }
    }
  }
}
