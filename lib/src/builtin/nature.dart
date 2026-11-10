import 'dart:math' as math;

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

/// Overlapping sine fields (ported from `plasma_2026` / `plasma_waves`).
final class PlasmaGenerator implements Generator {
  const PlasmaGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.plasma',
        version: 1,
        name: LocalizedText('Plasma', pl: 'Plazma'),
        description: LocalizedText(
          'Flowing color plasma of overlapping waves.',
          pl: 'Płynąca kolorowa plazma z nakładających się fal.',
        ),
        category: GeneratorCategory.nature,
      );

  @override
  List<ParamSpec> get params => const [
        PaletteParam(id: 'palette', label: paletteLabel, defaultValue: Palette.rainbow),
        speedParam,
        scaleParam,
        NumberParam(
          id: 'colorDrift',
          label: LocalizedText('Color drift', pl: 'Dryf kolorów'),
          description: LocalizedText('How fast the palette rotates.', pl: 'Jak szybko obraca się paleta.'),
          min: 0,
          max: 1,
          defaultValue: 0.05,
          step: 0.01,
          unit: '/s',
        ),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => const _PlasmaInstance();
}

final class _PlasmaInstance implements GeneratorInstance {
  const _PlasmaInstance();

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final palette = p.palette('palette');
    final time = ctx.seconds * p.number('speed');
    final scale = p.number('scale');
    final drift = ctx.seconds * p.number('colorDrift');
    final brightness = p.number('brightness');
    for (var x = 0; x < ctx.xCount; x++) {
      for (var y = 0; y < ctx.yCount; y++) {
        final nx = ctx.nx(x) / scale;
        final ny = ctx.ny(y) / scale;
        var v = math.sin(nx * 10 + time * 1.5);
        v += math.sin(ny * 8 + time * 1.2);
        v += math.sin((nx + ny) * 6 + time * 0.8);
        final cx = nx - 0.5 / scale;
        final cy = ny - 0.5 / scale;
        final dist = math.sqrt(cx * cx + cy * cy);
        v += math.sin(dist * 12 - time * 2);
        v += math.sin(math.atan2(cy, cx) * 3 + dist * 8 - time * 1.5) * 0.5;
        v += math.sin(dist * 20 + time * 3) * 0.3;
        v = (v / 4.5 + 1) / 2;
        final light = 0.55 + 0.45 * math.sin(v * math.pi * 2).abs();
        out.setPixelColor(x, y, dim(palette.sample(v + drift, wrap: true), light * brightness));
      }
    }
    applyPanelMode(out, panelModeOf(p));
  }
}

/// Simplex noise through a palette (ported from `noise`).
final class NoiseGenerator implements Generator {
  const NoiseGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.noise',
        version: 1,
        name: LocalizedText('Noise', pl: 'Szum'),
        description: LocalizedText(
          'Slowly evolving clouds of color (simplex noise).',
          pl: 'Powoli zmieniające się chmury kolorów (szum simplex).',
        ),
        category: GeneratorCategory.nature,
      );

  @override
  List<ParamSpec> get params => const [
        PaletteParam(id: 'palette', label: paletteLabel, defaultValue: Palette.ocean),
        scaleParam,
        NumberParam(
          id: 'speed',
          label: LocalizedText('Speed', pl: 'Prędkość'),
          min: 0.05,
          max: 5,
          defaultValue: 0.5,
          scale: NumberScale.log,
          unit: '×',
        ),
        NumberParam(
          id: 'contrast',
          label: LocalizedText('Contrast', pl: 'Kontrast'),
          min: 0.5,
          max: 3,
          defaultValue: 1.2,
          step: 0.01,
        ),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _NoiseInstance(SimplexNoise(setup.seed));
}

final class _NoiseInstance implements GeneratorInstance {
  final SimplexNoise noise;

  _NoiseInstance(this.noise);

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final palette = p.palette('palette');
    final frequency = 2.5 / p.number('scale');
    final z = ctx.seconds * p.number('speed') * 0.6;
    final contrast = p.number('contrast');
    final brightness = p.number('brightness');
    final aspect = ctx.yCount / math.max(1, ctx.xCount);
    for (var x = 0; x < ctx.xCount; x++) {
      for (var y = 0; y < ctx.yCount; y++) {
        final n = noise.simplex3(ctx.nx(x) * frequency, ctx.ny(y) * frequency * aspect, z);
        final v = (0.5 + n * 0.5 * contrast).clamp(0.0, 1.0);
        out.setPixelColor(x, y, dim(palette.sample(v), brightness));
      }
    }
    applyPanelMode(out, panelModeOf(p));
  }
}

/// Aurora curtains hanging from the roof (ported from `aurora`).
final class AuroraGenerator implements Generator {
  const AuroraGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.aurora',
        version: 1,
        name: LocalizedText('Aurora', pl: 'Zorza polarna'),
        description: LocalizedText(
          'Shimmering northern-light curtains with occasional stars.',
          pl: 'Migoczące kurtyny zorzy z pojedynczymi gwiazdami.',
        ),
        category: GeneratorCategory.nature,
      );

  @override
  List<ParamSpec> get params => const [
        PaletteParam(id: 'palette', label: paletteLabel, defaultValue: Palette.aurora),
        speedParam,
        NumberParam(
          id: 'height',
          label: LocalizedText('Curtain length', pl: 'Długość kurtyny'),
          min: 0.2,
          max: 1,
          defaultValue: 0.6,
          step: 0.01,
        ),
        NumberParam(
          id: 'stars',
          label: LocalizedText('Stars', pl: 'Gwiazdy'),
          description:
              LocalizedText('Chance of a star per icicle and frame.', pl: 'Szansa na gwiazdę na sopel i klatkę.'),
          min: 0,
          max: 0.1,
          defaultValue: 0.02,
          step: 0.005,
        ),
        brightnessParam,
        panelModeParamWithOwn,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _AuroraInstance(setup.xCount);
}

final class _AuroraInstance implements GeneratorInstance {
  final List<double> phases;
  final List<double> speeds;
  final List<double> amplitudes;
  bool _initialized = false;

  _AuroraInstance(int xCount)
      : phases = List.filled(xCount, 0),
        speeds = List.filled(xCount, 1),
        amplitudes = List.filled(xCount, 0.5);

  @override
  void render(FrameContext ctx, Icicles out) {
    if (!_initialized) {
      _initialized = true;
      for (var x = 0; x < ctx.xCount; x++) {
        phases[x] = ctx.random.nextDouble() * math.pi * 2;
        speeds[x] = 0.8 + ctx.random.nextDouble() * 0.4;
        amplitudes[x] = 0.3 + ctx.random.nextDouble() * 0.4;
      }
    }
    final p = ctx.params;
    final palette = p.palette('palette');
    final t = ctx.seconds * 2.25 * p.number('speed');
    final baseHeight = p.number('height');
    final stars = p.number('stars');
    final brightness = p.number('brightness');
    final height = ctx.yCount.toDouble();
    out.setAllPixelsColor(black);
    for (var x = 0; x < ctx.xCount; x++) {
      final column = x * 32 / math.max(1, ctx.xCount);
      final wave = math.sin(t * speeds[x] + phases[x]) * 0.5 +
          math.sin(t * 0.7 + column * 0.3 + phases[x] * 0.5) * 0.3 +
          math.sin(t * 0.5 + column * 0.15) * 0.2;
      final curtain = (height * baseHeight + height * amplitudes[x] * wave).clamp(height * 0.2, height * 0.95);
      final color = palette.sample(0.25 + 0.5 * ((t * 0.3 + column * 0.15) % 1.0));
      for (var y = 0; y < curtain.floor(); y++) {
        final row = y * 30 / height;
        final fade = 0.5 + 0.5 * math.cos(math.pi * (y / curtain));
        final shimmer = (math.sin(t * 3 + row * 0.2 + column * 0.5) * 0.15 + 0.85).clamp(0.0, 1.0);
        final horizontal = (0.7 + math.sin(row * 0.1 + t + column * 0.2) * 0.3).clamp(0.0, 1.0);
        final intensity = fade * shimmer * horizontal;
        if (intensity > 0.05) out.setPixelColor(x, y, dim(color, intensity * brightness));
      }
      if (ctx.random.nextDouble() < stars) {
        final y = ctx.random.nextInt(math.max(1, ctx.yCount ~/ 3));
        out.setPixelColor(x, y, dim(const Color(0xFFFFFFFF), (0.5 + ctx.random.nextDouble() * 0.5) * brightness));
      }
    }
    final mode = panelModeOf(p);
    if (mode != PanelMode.own) return applyPanelMode(out, mode);
    final panels = out.radioPanels;
    for (var panel = 0; panel < panels.length; panel++) {
      final count = panels[panel].length;
      for (var i = 0; i < count; i++) {
        final position = (i / count + t * 0.035 + panel * 0.25) % 1.0;
        final wave =
            (math.sin(position * math.pi * 4 + t) * 0.6 + math.sin(position * math.pi * 6 + t * 0.7) * 0.4 + 1) / 2;
        final color = palette.sample(0.25 + 0.5 * ((position + t * 0.045) % 1.0));
        out.setRadioPanelPixelColor(panel, i, dim(color, (wave * 0.6).clamp(0.1, 0.6) * brightness));
      }
    }
  }
}

/// Layered sine curtains (ported from `waves` and the firmware's Sinus).
final class WavesGenerator implements Generator {
  const WavesGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.waves',
        version: 1,
        name: LocalizedText('Waves', pl: 'Fale'),
        description: LocalizedText(
          'Overlapping sine waves rolling across the icicles.',
          pl: 'Nakładające się fale sinusoidalne przetaczające się przez sople.',
        ),
        category: GeneratorCategory.nature,
      );

  @override
  List<ParamSpec> get params => const [
        PaletteParam(id: 'palette', label: paletteLabel, defaultValue: Palette.ocean),
        IntParam(id: 'layers', label: LocalizedText('Waves', pl: 'Liczba fal'), min: 1, max: 6, defaultValue: 4),
        speedParam,
        NumberParam(
          id: 'amplitude',
          label: LocalizedText('Height', pl: 'Wysokość'),
          min: 0.1,
          max: 1,
          defaultValue: 0.8,
          step: 0.01,
        ),
        NumberParam(
          id: 'wavelength',
          label: LocalizedText('Wavelength', pl: 'Długość fali'),
          description:
              LocalizedText('Width of one wave, in row widths.', pl: 'Szerokość jednej fali (w szerokościach rzędu).'),
          min: 0.25,
          max: 4,
          defaultValue: 1,
          scale: NumberScale.log,
          unit: '×',
        ),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => const _WavesInstance();
}

final class _WavesInstance implements GeneratorInstance {
  const _WavesInstance();

  static const _speeds = [1.2, 0.75, 0.9, 1.05, 0.6, 1.35];
  static const _heights = [1.0, 0.9, 0.95, 0.85, 0.8, 0.92];

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final palette = p.palette('palette');
    final layers = p.integer('layers');
    final t = ctx.seconds * p.number('speed');
    final amplitude = p.number('amplitude');
    final wavelength = p.number('wavelength');
    final brightness = p.number('brightness');
    out.setAllPixelsColor(black);
    for (var layer = 0; layer < layers; layer++) {
      final color = dim(palette.sample(layers == 1 ? 0.75 : 0.35 + 0.65 * layer / (layers - 1)), brightness);
      for (var x = 0; x < ctx.xCount; x++) {
        final phase = t * _speeds[layer] * 1.35 + ctx.nx(x) * math.pi * 2 / wavelength + layer * 1.7;
        final depth = (math.sin(phase) * 0.5 + 0.5) * amplitude * _heights[layer] * ctx.yCount;
        for (var y = 0; y < depth.round() && y < ctx.yCount; y++) {
          out.setPixelColor(x, y, color);
        }
      }
    }
    applyPanelMode(out, panelModeOf(p));
  }
}

/// Snowflakes drifting down in the wind (ported from `falling_snow`).
final class SnowGenerator implements Generator {
  const SnowGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.snow',
        version: 1,
        name: LocalizedText('Falling snow', pl: 'Padający śnieg'),
        description: LocalizedText('Twinkling snowflakes in a gusty wind.', pl: 'Migoczące płatki śniegu na wietrze.'),
        category: GeneratorCategory.nature,
      );

  @override
  List<ParamSpec> get params => const [
        NumberParam(
          id: 'density',
          label: LocalizedText('Density', pl: 'Gęstość'),
          min: 0.05,
          max: 1,
          defaultValue: 0.4,
          step: 0.01,
        ),
        speedParam,
        NumberParam(
          id: 'wind',
          label: LocalizedText('Wind', pl: 'Wiatr'),
          description:
              LocalizedText('Negative blows left, positive right.', pl: 'Ujemny wieje w lewo, dodatni w prawo.'),
          min: -1,
          max: 1,
          defaultValue: 0.2,
          step: 0.01,
        ),
        ColorParam(id: 'color', label: colorLabel, defaultValue: Color(0xFFC8DCFF)),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _SnowInstance();
}

final class _Flake {
  double x;
  double y;
  final double speed;
  final double brightness;
  final double twinklePhase;
  final double twinkleSpeed;

  _Flake(this.x, this.y, this.speed, this.brightness, this.twinklePhase, this.twinkleSpeed);
}

final class _SnowInstance implements GeneratorInstance {
  final flakes = <_Flake>[];

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final dt = ctx.deltaSeconds;
    final random = ctx.random;
    final density = p.number('density');
    final speed = p.number('speed');
    final wind = p.number('wind') * 2 + math.sin(ctx.seconds * 0.6) * 0.5;
    final color = p.color('color');
    final brightness = p.number('brightness');
    final width = ctx.xCount.toDouble();
    final height = ctx.yCount.toDouble();
    // Expected new flakes per second, scaled with the row width.
    final rate = density * width * 0.6 * speed;
    var spawn = rate * dt;
    while (spawn > 0) {
      if (random.nextDouble() < math.min(1, spawn)) {
        flakes.add(_Flake(
          random.nextDouble() * width,
          -1,
          (0.5 + random.nextDouble() * 0.8) * height / 2.5 * speed,
          0.5 + random.nextDouble() * 0.5,
          random.nextDouble() * math.pi * 2,
          3 + random.nextDouble() * 4,
        ));
      }
      spawn -= 1;
    }
    out.setAllPixelsColor(black);
    for (var i = flakes.length - 1; i >= 0; i--) {
      final flake = flakes[i];
      flake.y += flake.speed * dt;
      flake.x = (flake.x + wind * dt * (0.7 + 0.3 * math.sin(flake.twinklePhase))) % width;
      if (flake.y >= height + 1) {
        flakes.removeAt(i);
        continue;
      }
      final py = flake.y.round();
      if (py < 0 || py >= ctx.yCount) continue;
      final px = flake.x.floor() % ctx.xCount;
      final twinkle = math.sin(ctx.seconds * flake.twinkleSpeed + flake.twinklePhase) * 0.2 + 0.8;
      out.setPixelColor(px, py, dim(color, flake.brightness * twinkle * brightness));
    }
    applyPanelMode(out, panelModeOf(p));
  }
}

/// Drops bouncing to the bottom of each icicle (ported from the firmware's
/// WaterDrops / `kropelki`).
final class WaterDropsGenerator implements Generator {
  const WaterDropsGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.water_drops',
        version: 1,
        name: LocalizedText('Water drops', pl: 'Kropelki'),
        description: LocalizedText(
          'Drops falling down each icicle, bouncing and fading.',
          pl: 'Krople spadające po soplach, odbijające się i gasnące.',
        ),
        category: GeneratorCategory.nature,
      );

  @override
  List<ParamSpec> get params => const [
        ColorParam(id: 'color', label: colorLabel, defaultValue: Color(0xFF40A0FF)),
        BoolParam(
          id: 'rainbow',
          label: LocalizedText('Random colors', pl: 'Losowe kolory'),
          defaultValue: false,
        ),
        speedParam,
        NumberParam(
          id: 'fade',
          label: LocalizedText('Fade time', pl: 'Czas gaśnięcia'),
          min: 0.05,
          max: 2,
          defaultValue: 0.3,
          scale: NumberScale.log,
          unit: 's',
        ),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _WaterDropsInstance(setup.xCount);
}

final class _WaterDropsInstance implements GeneratorInstance {
  final List<double> progress;
  final List<double> fade;
  final List<double> hues;
  bool _initialized = false;

  _WaterDropsInstance(int xCount)
      : progress = List.filled(xCount, 0),
        fade = List.filled(xCount, 0),
        hues = List.filled(xCount, 0);

  @override
  void render(FrameContext ctx, Icicles out) {
    final random = ctx.random;
    if (!_initialized) {
      _initialized = true;
      for (var x = 0; x < ctx.xCount; x++) {
        progress[x] = random.nextDouble();
        hues[x] = random.nextDouble();
      }
    }
    final p = ctx.params;
    final dt = ctx.deltaSeconds;
    // The firmware moved a drop by 1 % every 10 ms frame: one fall per second.
    final fall = dt * 0.9 * p.number('speed');
    final fadeTime = p.number('fade');
    final rainbow = p.flag('rainbow');
    final color = p.color('color');
    final brightness = p.number('brightness');
    out.setAllPixelsColor(black);
    for (var x = 0; x < ctx.xCount; x++) {
      progress[x] += fall;
      if (progress[x] >= 1) {
        progress[x] = 1;
        fade[x] += dt / fadeTime;
        if (fade[x] >= 1) {
          fade[x] = 0;
          progress[x] = -random.nextDouble();
          hues[x] = random.nextDouble();
        }
      }
      if (progress[x] < 0) continue;
      final y = (Curves.bounceOut.transform(progress[x]) * ctx.yCount).floor().clamp(0, ctx.yCount - 1);
      final base = rainbow ? hsv(hues[x], 1, 1) : color;
      out.setPixelColor(x, y, dim(base, (1 - fade[x]) * brightness));
    }
    applyPanelMode(out, panelModeOf(p));
  }
}
