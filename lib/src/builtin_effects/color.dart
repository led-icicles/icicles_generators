import 'dart:math' as math;

import 'package:icicles_animation_dart/icicles_animation_dart.dart';

import '../effect/effect.dart';
import '../effect/effect_info.dart';
import '../generator/generator.dart';
import '../generator/localized_text.dart';
import '../params/param_spec.dart';
import '../util/color.dart';
import '../util/palette.dart';
import 'common.dart';

const _colorLabel = LocalizedText('Color', pl: 'Kolor');
const _amountLabel = LocalizedText('Amount', pl: 'Stopień');

/// Gain, gamma and contrast.
final class BrightnessEffect implements Effect {
  const BrightnessEffect();

  @override
  EffectInfo get info => const EffectInfo(
        id: 'icicles.fx.brightness',
        version: 1,
        name: LocalizedText('Brightness', pl: 'Jasność'),
        description: LocalizedText(
          'Gain, gamma and contrast of the layers below.',
          pl: 'Wzmocnienie, gamma i kontrast warstw poniżej.',
        ),
        category: EffectCategory.color,
      );

  @override
  List<ParamSpec> get params => const [
        NumberParam(
          id: 'gain',
          label: LocalizedText('Gain', pl: 'Wzmocnienie'),
          min: 0,
          max: 4,
          defaultValue: 1,
          step: 0.01,
          unit: '×',
        ),
        NumberParam(
          id: 'gamma',
          label: LocalizedText('Gamma', pl: 'Gamma'),
          description: LocalizedText('Above 1 darkens the mid tones, below 1 lifts them.',
              pl: 'Powyżej 1 przyciemnia półtony, poniżej 1 je rozjaśnia.'),
          min: 0.2,
          max: 5,
          defaultValue: 1,
          scale: NumberScale.log,
        ),
        NumberParam(
          id: 'contrast',
          label: LocalizedText('Contrast', pl: 'Kontrast'),
          min: 0,
          max: 3,
          defaultValue: 1,
          step: 0.01,
          unit: '×',
        ),
        effectPanelsParam,
      ];

  @override
  EffectInstance create(GeneratorSetup setup) => const _BrightnessInstance();
}

final class _BrightnessInstance implements EffectInstance {
  const _BrightnessInstance();

  @override
  void apply(FrameContext ctx, AnimationView input, Icicles out) {
    final p = ctx.params;
    final gain = p.number('gain');
    final gamma = p.number('gamma');
    final contrast = p.number('contrast');
    if (gain == 1 && gamma == 1 && contrast == 1) return;
    final table = List<int>.generate(256, (v) {
      final shaped = math.pow(v / 255, gamma) * gain;
      return (((shaped - 0.5) * contrast + 0.5).clamp(0.0, 1.0) * 255).round();
    });
    mapPixels(ctx, input, out, panelsOf(p), (c) => Color.fromRGB(table[c.red], table[c.green], table[c.blue]));
  }
}

/// Rotates the hue, optionally continuously.
final class HueShiftEffect implements Effect {
  const HueShiftEffect();

  @override
  EffectInfo get info => const EffectInfo(
        id: 'icicles.fx.hue_shift',
        version: 1,
        name: LocalizedText('Hue shift', pl: 'Przesunięcie barwy'),
        description: LocalizedText(
          'Rotates every color around the hue wheel; bind the shift to the beat for a hue cycle per beat.',
          pl: 'Obraca każdy kolor na kole barw; podepnij przesunięcie pod beat, by barwa krążyła co uderzenie.',
        ),
        category: EffectCategory.color,
      );

  @override
  List<ParamSpec> get params => const [
        NumberParam(
          id: 'shift',
          label: LocalizedText('Shift', pl: 'Przesunięcie'),
          description: LocalizedText('Turns of the hue wheel (0.5 = opposite colors).',
              pl: 'Obroty koła barw (0,5 = kolory przeciwne).'),
          min: -1,
          max: 1,
          defaultValue: 0.25,
          step: 0.01,
        ),
        NumberParam(
          id: 'rate',
          label: LocalizedText('Rotation', pl: 'Obrót'),
          description: LocalizedText('Extra continuous rotation, turns per second.',
              pl: 'Dodatkowy ciągły obrót, obroty na sekundę.'),
          min: -2,
          max: 2,
          defaultValue: 0,
          step: 0.01,
          unit: '/s',
        ),
        effectPanelsParam,
      ];

  @override
  EffectInstance create(GeneratorSetup setup) => const _HueShiftInstance();
}

final class _HueShiftInstance implements EffectInstance {
  const _HueShiftInstance();

  @override
  void apply(FrameContext ctx, AnimationView input, Icicles out) {
    final p = ctx.params;
    final shift = p.number('shift') + p.number('rate') * ctx.seconds;
    if (shift % 1.0 == 0) return;
    mapPixels(ctx, input, out, panelsOf(p), (c) {
      final h = hsvOf(c);
      return h.saturation == 0 ? c : hsv(h.hue + shift, h.saturation, h.value);
    });
  }
}

/// Desaturates or boosts the colors.
final class SaturationEffect implements Effect {
  const SaturationEffect();

  @override
  EffectInfo get info => const EffectInfo(
        id: 'icicles.fx.saturation',
        version: 1,
        name: LocalizedText('Saturation', pl: 'Nasycenie'),
        description: LocalizedText(
          'Washes the colors out towards grey (−1) or boosts them (+1).',
          pl: 'Wypłukuje kolory do szarości (−1) albo je wzmacnia (+1).',
        ),
        category: EffectCategory.color,
      );

  @override
  List<ParamSpec> get params => const [
        NumberParam(id: 'amount', label: _amountLabel, min: -1, max: 1, defaultValue: 0.5, step: 0.01),
        effectPanelsParam,
      ];

  @override
  EffectInstance create(GeneratorSetup setup) => const _SaturationInstance();
}

final class _SaturationInstance implements EffectInstance {
  const _SaturationInstance();

  @override
  void apply(FrameContext ctx, AnimationView input, Icicles out) {
    final p = ctx.params;
    final amount = p.number('amount');
    if (amount == 0) return;
    mapPixels(ctx, input, out, panelsOf(p), (c) {
      if (amount < 0) {
        final grey = luma(c) * 255;
        return mixColors(c, Color.fromRGB(grey.round(), grey.round(), grey.round()), -amount);
      }
      final h = hsvOf(c);
      return hsv(h.hue, h.saturation + (1 - h.saturation) * amount * (h.saturation > 0 ? 1 : 0), h.value);
    });
  }
}

/// Inverts the colors.
final class InvertEffect implements Effect {
  const InvertEffect();

  @override
  EffectInfo get info => const EffectInfo(
        id: 'icicles.fx.invert',
        version: 1,
        name: LocalizedText('Invert', pl: 'Negatyw'),
        description: LocalizedText('Inverts every channel: black becomes white.',
            pl: 'Odwraca każdy kanał: czerń staje się bielą.'),
        category: EffectCategory.color,
      );

  @override
  List<ParamSpec> get params => const [
        NumberParam(id: 'amount', label: _amountLabel, min: 0, max: 1, defaultValue: 1, step: 0.01),
        effectPanelsParam,
      ];

  @override
  EffectInstance create(GeneratorSetup setup) => const _InvertInstance();
}

final class _InvertInstance implements EffectInstance {
  const _InvertInstance();

  @override
  void apply(FrameContext ctx, AnimationView input, Icicles out) {
    final p = ctx.params;
    final amount = p.number('amount');
    if (amount == 0) return;
    mapPixels(ctx, input, out, panelsOf(p),
        (c) => mixColors(c, Color.fromRGB(255 - c.red, 255 - c.green, 255 - c.blue), amount));
  }
}

/// Reduces each channel to a few levels.
final class PosterizeEffect implements Effect {
  const PosterizeEffect();

  @override
  EffectInfo get info => const EffectInfo(
        id: 'icicles.fx.posterize',
        version: 1,
        name: LocalizedText('Posterize', pl: 'Posteryzacja'),
        description:
            LocalizedText('Snaps every channel to a few levels.', pl: 'Zaokrągla każdy kanał do kilku poziomów.'),
        category: EffectCategory.color,
      );

  @override
  List<ParamSpec> get params => const [
        IntParam(id: 'levels', label: LocalizedText('Levels', pl: 'Poziomy'), min: 2, max: 16, defaultValue: 4),
        effectPanelsParam,
      ];

  @override
  EffectInstance create(GeneratorSetup setup) => const _PosterizeInstance();
}

final class _PosterizeInstance implements EffectInstance {
  const _PosterizeInstance();

  @override
  void apply(FrameContext ctx, AnimationView input, Icicles out) {
    final p = ctx.params;
    final levels = p.integer('levels');
    final steps = levels - 1;
    int q(int v) => ((v / 255 * steps).round() * 255 / steps).round();
    mapPixels(ctx, input, out, panelsOf(p), (c) => Color.fromRGB(q(c.red), q(c.green), q(c.blue)));
  }
}

/// Two colors by brightness.
final class ThresholdEffect implements Effect {
  const ThresholdEffect();

  @override
  EffectInfo get info => const EffectInfo(
        id: 'icicles.fx.threshold',
        version: 1,
        name: LocalizedText('Threshold', pl: 'Próg'),
        description: LocalizedText(
          'Pixels brighter than the cutoff get one color, the rest another.',
          pl: 'Piksele jaśniejsze niż próg dostają jeden kolor, pozostałe drugi.',
        ),
        category: EffectCategory.color,
      );

  @override
  List<ParamSpec> get params => const [
        NumberParam(
          id: 'cutoff',
          label: LocalizedText('Cutoff', pl: 'Próg'),
          min: 0,
          max: 1,
          defaultValue: 0.5,
          step: 0.01,
        ),
        ColorParam(id: 'above', label: LocalizedText('Above', pl: 'Powyżej'), defaultValue: Color(0xFFFFFFFF)),
        ColorParam(id: 'below', label: LocalizedText('Below', pl: 'Poniżej'), defaultValue: Color(0xFF000000)),
        BoolParam(
          id: 'keepColor',
          label: LocalizedText('Keep the color above', pl: 'Zachowaj kolor powyżej'),
          description: LocalizedText('Bright pixels keep their own color instead of "Above".',
              pl: 'Jasne piksele zachowują własny kolor zamiast „Powyżej”.'),
          defaultValue: false,
        ),
        effectPanelsParam,
      ];

  @override
  EffectInstance create(GeneratorSetup setup) => const _ThresholdInstance();
}

final class _ThresholdInstance implements EffectInstance {
  const _ThresholdInstance();

  @override
  void apply(FrameContext ctx, AnimationView input, Icicles out) {
    final p = ctx.params;
    final cutoff = p.number('cutoff');
    final above = p.color('above');
    final below = p.color('below');
    final keep = p.flag('keepColor');
    mapPixels(ctx, input, out, panelsOf(p), (c) => luma(c) > cutoff ? (keep ? c : above) : below);
  }
}

/// Brightness through a palette.
final class PaletteRemapEffect implements Effect {
  const PaletteRemapEffect();

  @override
  EffectInfo get info => const EffectInfo(
        id: 'icicles.fx.palette_remap',
        version: 1,
        name: LocalizedText('Palette remap', pl: 'Mapowanie palety'),
        description: LocalizedText(
          'Recolors the layers by brightness through a palette.',
          pl: 'Przebarwia warstwy według jasności przez paletę.',
        ),
        category: EffectCategory.color,
      );

  @override
  List<ParamSpec> get params => const [
        PaletteParam(id: 'palette', label: LocalizedText('Palette', pl: 'Paleta'), defaultValue: Palette.fire),
        NumberParam(
          id: 'offset',
          label: LocalizedText('Offset', pl: 'Przesunięcie'),
          description: LocalizedText('Shifts the palette (wraps around).', pl: 'Przesuwa paletę (zawija).'),
          min: 0,
          max: 1,
          defaultValue: 0,
          step: 0.01,
        ),
        BoolParam(
          id: 'keepBlack',
          label: LocalizedText('Keep black', pl: 'Zachowaj czerń'),
          description: LocalizedText('Unlit pixels stay off instead of taking the palette start.',
              pl: 'Zgaszone piksele pozostają zgaszone zamiast przyjąć początek palety.'),
          defaultValue: true,
        ),
        effectPanelsParam,
      ];

  @override
  EffectInstance create(GeneratorSetup setup) => const _PaletteRemapInstance();
}

final class _PaletteRemapInstance implements EffectInstance {
  const _PaletteRemapInstance();

  @override
  void apply(FrameContext ctx, AnimationView input, Icicles out) {
    final p = ctx.params;
    final palette = p.palette('palette');
    final offset = p.number('offset');
    final keepBlack = p.flag('keepBlack');
    final wrap = offset != 0;
    mapPixels(ctx, input, out, panelsOf(p), (c) {
      if (keepBlack && c.value & 0xFFFFFF == 0) return black;
      return palette.sample(luma(c) + offset, wrap: wrap);
    });
  }
}

/// Multiplies by a color.
final class TintEffect implements Effect {
  const TintEffect();

  @override
  EffectInfo get info => const EffectInfo(
        id: 'icicles.fx.tint',
        version: 1,
        name: LocalizedText('Tint', pl: 'Zabarwienie'),
        description: LocalizedText('Multiplies the layers by a color, like a gel.',
            pl: 'Mnoży warstwy przez kolor, jak filtr barwny.'),
        category: EffectCategory.color,
      );

  @override
  List<ParamSpec> get params => const [
        ColorParam(id: 'color', label: _colorLabel, defaultValue: Color(0xFFFF8000)),
        NumberParam(id: 'amount', label: _amountLabel, min: 0, max: 1, defaultValue: 1, step: 0.01),
        effectPanelsParam,
      ];

  @override
  EffectInstance create(GeneratorSetup setup) => const _TintInstance();
}

final class _TintInstance implements EffectInstance {
  const _TintInstance();

  @override
  void apply(FrameContext ctx, AnimationView input, Icicles out) {
    final p = ctx.params;
    final tint = p.color('color');
    final amount = p.number('amount');
    if (amount == 0) return;
    mapPixels(ctx, input, out, panelsOf(p), (c) {
      final tinted = Color.fromRGB(c.red * tint.red ~/ 255, c.green * tint.green ~/ 255, c.blue * tint.blue ~/ 255);
      return amount >= 1 ? tinted : mixColors(c, tinted, amount);
    });
  }
}
