import 'dart:math' as math;
import 'dart:typed_data';

import 'package:icicles_animation_dart/icicles_animation_dart.dart';

import '../generator/generator.dart';
import '../generator/generator_info.dart';
import '../generator/localized_text.dart';
import '../params/param_spec.dart';
import '../util/color.dart';
import '../util/noise.dart';
import '../util/palette.dart';
import '../util/panel_mode.dart';
import 'common.dart';

/// Random LEDs fading in and out (WLED Twinkle, xLights Twinkle).
final class TwinkleGenerator implements Generator {
  const TwinkleGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.twinkle',
        version: 1,
        name: LocalizedText('Twinkle', pl: 'Migotanie'),
        description: LocalizedText(
          'Random LEDs softly fading in and out over a background.',
          pl: 'Losowe diody łagodnie rozjaśniające się i gasnące na tle.',
        ),
        category: GeneratorCategory.particles,
      );

  @override
  List<ParamSpec> get params => const [
        NumberParam(
          id: 'density',
          label: LocalizedText('Density', pl: 'Gęstość'),
          description: LocalizedText('Twinkles per LED and second.', pl: 'Rozbłyski na diodę i sekundę.'),
          min: 0.01,
          max: 2,
          defaultValue: 0.2,
          scale: NumberScale.log,
          unit: '/s',
        ),
        NumberParam(
          id: 'speed',
          label: LocalizedText('Fade speed', pl: 'Szybkość gaśnięcia'),
          description: LocalizedText('Twinkle cycles per second.', pl: 'Cykle rozbłysku na sekundę.'),
          min: 0.1,
          max: 5,
          defaultValue: 0.6,
          scale: NumberScale.log,
          unit: '/s',
        ),
        PaletteParam(id: 'palette', label: paletteLabel, defaultValue: Palette.ice),
        ColorParam(id: 'background', label: LocalizedText('Background', pl: 'Tło'), defaultValue: Color(0xFF000000)),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _TwinkleInstance(setup.pixelsCount);
}

final class _TwinkleInstance implements GeneratorInstance {
  /// `0` idle, otherwise the position in the twinkle (`0..1`).
  final Float64List phase;
  final List<Color> colors;

  _TwinkleInstance(int pixels)
      : phase = Float64List(pixels),
        colors = List.filled(pixels, black);

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final random = ctx.random;
    final dt = ctx.deltaSeconds;
    final chance = 1 - math.exp(-p.number('density') * math.max(dt, 1 / 60));
    final step = p.number('speed') * dt;
    final palette = p.palette('palette');
    final background = p.color('background');
    final brightness = p.number('brightness');
    for (var i = 0; i < phase.length; i++) {
      if (phase[i] > 0) {
        phase[i] += step;
        if (phase[i] >= 1) phase[i] = 0;
      } else if (random.nextDouble() < chance) {
        phase[i] = 1e-6;
        colors[i] = palette.sample(random.nextDouble());
      }
      final v = phase[i] > 0 ? math.sin(phase[i] * math.pi) : 0.0;
      out.setPixelColorAtIndex(i, dim(mixColors(background, colors[i], v), brightness));
    }
    applyPanelMode(out, panelModeOf(p));
  }
}

/// Short bright sparkles over a palette (WLED Glitter).
final class GlitterGenerator implements Generator {
  const GlitterGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.glitter',
        version: 1,
        name: LocalizedText('Glitter', pl: 'Brokat'),
        description: LocalizedText(
          'Short white sparkles over a slowly drifting palette.',
          pl: 'Krótkie białe iskierki na wolno płynącej palecie.',
        ),
        category: GeneratorCategory.particles,
      );

  @override
  List<ParamSpec> get params => const [
        PaletteParam(id: 'palette', label: paletteLabel, defaultValue: Palette.party),
        NumberParam(
          id: 'rate',
          label: LocalizedText('Sparkles', pl: 'Iskierki'),
          description: LocalizedText('Sparkles per second.', pl: 'Iskierki na sekundę.'),
          min: 1,
          max: 300,
          defaultValue: 30,
          scale: NumberScale.log,
          unit: '/s',
        ),
        NumberParam(
          id: 'fade',
          label: LocalizedText('Sparkle length', pl: 'Czas iskierki'),
          min: 0.03,
          max: 1,
          defaultValue: 0.12,
          scale: NumberScale.log,
          unit: 's',
        ),
        NumberParam(
          id: 'drift',
          label: LocalizedText('Palette drift', pl: 'Dryf palety'),
          min: 0,
          max: 1,
          defaultValue: 0.1,
          step: 0.01,
          unit: '/s',
        ),
        ColorParam(
            id: 'sparkle',
            label: LocalizedText('Sparkle color', pl: 'Kolor iskierki'),
            defaultValue: Color(0xFFFFFFFF)),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _GlitterInstance(setup.pixelsCount);
}

final class _GlitterInstance implements GeneratorInstance {
  final Float64List energy;
  double _pending = 0;

  _GlitterInstance(int pixels) : energy = Float64List(pixels);

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final random = ctx.random;
    final dt = ctx.deltaSeconds;
    final palette = p.palette('palette');
    final offset = ctx.seconds * p.number('drift');
    final decay = decayFactor(p.number('fade'), dt);
    final sparkle = p.color('sparkle');
    final brightness = p.number('brightness');
    _pending += p.number('rate') * math.max(dt, 1 / 60);
    while (_pending >= 1) {
      _pending -= 1;
      energy[random.nextInt(energy.length)] = 1;
    }
    for (var x = 0; x < ctx.xCount; x++) {
      for (var y = 0; y < ctx.yCount; y++) {
        final i = x * ctx.yCount + y;
        energy[i] *= decay;
        final base = palette.sample(ctx.nx(x) * 0.7 + ctx.ny(y) * 0.3 - offset, wrap: true);
        out.setPixelColorAtIndex(i, dim(mixColors(base, sparkle, energy[i]), brightness));
      }
    }
    applyPanelMode(out, panelModeOf(p));
  }
}

/// Candle flicker (WLED Candle multi, xLights Candle).
final class CandleGenerator implements Generator {
  const CandleGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.candle',
        version: 1,
        name: LocalizedText('Candle', pl: 'Świeca'),
        description: LocalizedText(
          'Warm light flickering like candle flames.',
          pl: 'Ciepłe światło migoczące jak płomienie świec.',
        ),
        category: GeneratorCategory.nature,
      );

  @override
  List<ParamSpec> get params => const [
        ColorParam(id: 'color', label: colorLabel, defaultValue: Color(0xFFFFA030)),
        NumberParam(
          id: 'flicker',
          label: LocalizedText('Flicker', pl: 'Migotanie'),
          min: 0,
          max: 1,
          defaultValue: 0.5,
          step: 0.01,
        ),
        NumberParam(
          id: 'speed',
          label: LocalizedText('Speed', pl: 'Prędkość'),
          min: 0.2,
          max: 5,
          defaultValue: 1,
          scale: NumberScale.log,
          unit: '×',
        ),
        ChoiceParam(
          id: 'grain',
          label: LocalizedText('Flames', pl: 'Płomienie'),
          options: [
            ChoiceOption('icicle', LocalizedText('One per icicle', pl: 'Jeden na sopel')),
            ChoiceOption('led', LocalizedText('One per LED', pl: 'Jeden na diodę')),
            ChoiceOption('all', LocalizedText('One for all', pl: 'Jeden wspólny')),
          ],
          defaultValue: 'icicle',
        ),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _CandleInstance(SimplexNoise(setup.seed));
}

final class _CandleInstance implements GeneratorInstance {
  final SimplexNoise noise;

  _CandleInstance(this.noise);

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final color = p.color('color');
    final flicker = p.number('flicker');
    final t = ctx.seconds * p.number('speed') * 4;
    final grain = p.choice('grain');
    final brightness = p.number('brightness');
    double level(double a, double b) {
      final n = noise.simplex3(a, b, t) * 0.6 + noise.simplex3(a + 7, b + 3, t * 2.7) * 0.4;
      // Flames dip more than they flare.
      final dip = (0.5 - 0.5 * n).clamp(0.0, 1.0);
      return 1 - flicker * dip * dip * 1.6;
    }

    for (var x = 0; x < ctx.xCount; x++) {
      final column = level(x * 1.7, 0.3);
      for (var y = 0; y < ctx.yCount; y++) {
        final v = switch (grain) {
          'led' => level(x * 1.7, y * 1.3),
          'all' => level(0.3, 0.3),
          _ => column,
        };
        out.setPixelColor(x, y, dim(color, v.clamp(0.0, 1.0) * brightness));
      }
    }
    applyPanelMode(out, panelModeOf(p));
  }
}

/// Random lightning strikes with afterglow (WLED Lightning, xLights
/// Lightning).
final class LightningGenerator implements Generator {
  const LightningGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.lightning',
        version: 1,
        name: LocalizedText('Lightning', pl: 'Błyskawice'),
        description: LocalizedText(
          'Random bursts of flashes over a few icicles, with an afterglow.',
          pl: 'Losowe serie błysków na kilku soplach z poświatą.',
        ),
        category: GeneratorCategory.nature,
      );

  @override
  List<ParamSpec> get params => const [
        NumberParam(
          id: 'frequency',
          label: LocalizedText('Strikes', pl: 'Uderzenia'),
          description: LocalizedText('Strikes per second.', pl: 'Uderzenia na sekundę.'),
          min: 0.1,
          max: 5,
          defaultValue: 0.7,
          scale: NumberScale.log,
          unit: '/s',
        ),
        IntParam(
            id: 'flashes',
            label: LocalizedText('Flashes per strike', pl: 'Błyski na uderzenie'),
            min: 1,
            max: 6,
            defaultValue: 3),
        NumberParam(
          id: 'region',
          label: LocalizedText('Width', pl: 'Szerokość'),
          description:
              LocalizedText('Part of the icicles one strike covers.', pl: 'Część sopli objęta jednym uderzeniem.'),
          min: 0.1,
          max: 1,
          defaultValue: 0.4,
          step: 0.01,
        ),
        NumberParam(
          id: 'afterglow',
          label: LocalizedText('Afterglow', pl: 'Poświata'),
          min: 0.05,
          max: 2,
          defaultValue: 0.4,
          scale: NumberScale.log,
          unit: 's',
        ),
        ColorParam(id: 'color', label: colorLabel, defaultValue: Color(0xFFE0E8FF)),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _LightningInstance(setup.xCount);
}

final class _LightningInstance implements GeneratorInstance {
  final Float64List glow;
  double _nextStrike = -1;
  int _flashesLeft = 0;
  double _flashUntil = 0;
  double _nextFlash = 0;
  int _from = 0;
  int _to = 0;

  _LightningInstance(int xCount) : glow = Float64List(xCount);

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final random = ctx.random;
    final t = ctx.seconds;
    final frequency = p.number('frequency');
    if (_nextStrike < 0) _nextStrike = random.nextDouble() * 0.5 / frequency;
    if (_flashesLeft == 0 && t >= _nextStrike) {
      _flashesLeft = p.integer('flashes');
      final width = math.max(1, (p.number('region') * ctx.xCount).round());
      _from = random.nextInt(math.max(1, ctx.xCount - width + 1));
      _to = math.min(ctx.xCount, _from + width);
      _nextFlash = t;
      _flashUntil = 0;
      // Exponential inter-arrival, at least a bit after this strike.
      _nextStrike = t + 0.3 + -math.log(1 - random.nextDouble()) / frequency;
    }
    var flashing = t < _flashUntil;
    if (!flashing && _flashesLeft > 0 && t >= _nextFlash) {
      _flashesLeft--;
      _flashUntil = t + 0.03 + random.nextDouble() * 0.05;
      _nextFlash = _flashUntil + 0.05 + random.nextDouble() * 0.12;
      flashing = true;
    }
    final decay = decayFactor(p.number('afterglow'), ctx.deltaSeconds);
    final color = p.color('color');
    final brightness = p.number('brightness');
    for (var x = 0; x < ctx.xCount; x++) {
      glow[x] *= decay;
      if (flashing && x >= _from && x < _to) glow[x] = 0.5;
      final v = flashing && x >= _from && x < _to ? 1.0 : glow[x];
      out.setColumnColor(x, dim(color, v * brightness));
    }
    applyPanelMode(out, panelModeOf(p));
  }
}
