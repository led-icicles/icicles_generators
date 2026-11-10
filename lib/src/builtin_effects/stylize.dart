import 'dart:math' as math;
import 'dart:typed_data';

import 'package:icicles_animation_dart/icicles_animation_dart.dart';

import '../effect/effect.dart';
import '../effect/effect_info.dart';
import '../generator/generator.dart';
import '../generator/localized_text.dart';
import '../params/param_spec.dart';
import '../util/color.dart';
import '../util/noise.dart';
import 'common.dart';

/// Hermite step: 0 at [x] ≤ [edge0], 1 at ≥ [edge1], smooth between.
double _smoothstep(double edge0, double edge1, double x) {
  if (edge1 <= edge0) return x < edge0 ? 0 : 1;
  final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// Blocks of pixels.
final class PixelateEffect implements Effect {
  const PixelateEffect();

  @override
  EffectInfo get info => const EffectInfo(
        id: 'icicles.fx.pixelate',
        version: 1,
        name: LocalizedText('Pixelate', pl: 'Pikselizacja'),
        description: LocalizedText('Merges the pixels into larger blocks.', pl: 'Łączy piksele w większe bloki.'),
        category: EffectCategory.stylize,
      );

  @override
  List<ParamSpec> get params => const [
        IntParam(
            id: 'blockX',
            label: LocalizedText('Block across', pl: 'Blok w poprzek'),
            min: 1,
            max: 12,
            defaultValue: 2,
            unit: 'px'),
        IntParam(
            id: 'blockY',
            label: LocalizedText('Block along', pl: 'Blok wzdłuż'),
            min: 1,
            max: 12,
            defaultValue: 2,
            unit: 'px'),
        ChoiceParam(
          id: 'mode',
          label: LocalizedText('Block color', pl: 'Kolor bloku'),
          options: [
            ChoiceOption('average', LocalizedText('Average', pl: 'Średnia')),
            ChoiceOption('brightest', LocalizedText('Brightest pixel', pl: 'Najjaśniejszy piksel')),
          ],
          defaultValue: 'average',
        ),
      ];

  @override
  EffectInstance create(GeneratorSetup setup) => const _PixelateInstance();
}

final class _PixelateInstance implements EffectInstance {
  const _PixelateInstance();

  @override
  void apply(FrameContext ctx, AnimationView input, Icicles out) {
    final p = ctx.params;
    final bx = p.integer('blockX');
    final by = p.integer('blockY');
    if (bx == 1 && by == 1) return;
    final brightest = p.choice('mode') == 'brightest';
    final w = ctx.xCount, h = ctx.yCount;
    final grid = List<Color>.filled(w * h, black);
    for (var x0 = 0; x0 < w; x0 += bx) {
      for (var y0 = 0; y0 < h; y0 += by) {
        final x1 = math.min(w, x0 + bx), y1 = math.min(h, y0 + by);
        var r = 0, g = 0, b = 0, n = 0;
        var best = black;
        var bestLuma = -1.0;
        for (var x = x0; x < x1; x++) {
          for (var y = y0; y < y1; y++) {
            final c = inputPixel(ctx, input, x, y);
            r += c.red;
            g += c.green;
            b += c.blue;
            n++;
            final l = luma(c);
            if (l > bestLuma) {
              bestLuma = l;
              best = c;
            }
          }
        }
        final color = brightest ? best : Color.fromRGB((r / n).round(), (g / n).round(), (b / n).round());
        for (var x = x0; x < x1; x++) {
          for (var y = y0; y < y1; y++) {
            grid[x * h + y] = color;
          }
        }
      }
    }
    setGrid(out, grid);
  }
}

/// Per-pixel brightness jitter.
final class ShimmerEffect implements Effect {
  const ShimmerEffect();

  @override
  EffectInfo get info => const EffectInfo(
        id: 'icicles.fx.shimmer',
        version: 1,
        name: LocalizedText('Shimmer', pl: 'Migotanie pikseli'),
        description: LocalizedText(
          'Random pixels dim and brighten, like light on water.',
          pl: 'Losowe piksele przygasają i rozjaśniają się, jak światło na wodzie.',
        ),
        category: EffectCategory.stylize,
      );

  @override
  List<ParamSpec> get params => const [
        NumberParam(
          id: 'amount',
          label: LocalizedText('Amount', pl: 'Stopień'),
          description:
              LocalizedText('How far a pixel\'s brightness may jump.', pl: 'Jak bardzo może skoczyć jasność piksela.'),
          min: 0,
          max: 1,
          defaultValue: 0.5,
          step: 0.01,
        ),
        NumberParam(
          id: 'density',
          label: LocalizedText('Density', pl: 'Gęstość'),
          description:
              LocalizedText('Part of the pixels jittered at a time.', pl: 'Część pikseli, które jednocześnie migoczą.'),
          min: 0,
          max: 1,
          defaultValue: 0.3,
          step: 0.01,
        ),
        NumberParam(
          id: 'rate',
          label: LocalizedText('Rate', pl: 'Częstość'),
          description: LocalizedText('New jitter patterns per second.', pl: 'Nowe wzory migotania na sekundę.'),
          min: 1,
          max: 60,
          defaultValue: 20,
          scale: NumberScale.log,
          unit: '/s',
        ),
        effectPanelsParam,
      ];

  @override
  EffectInstance create(GeneratorSetup setup) => _ShimmerInstance(setup);
}

final class _ShimmerInstance implements EffectInstance {
  final GeneratorSetup setup;
  late final Float32List _factors =
      Float32List(setup.pixelsCount + setup.radioPanelsCount * setup.radioPanelPixelCount);
  double _nextChange = 0;

  _ShimmerInstance(this.setup);

  @override
  void apply(FrameContext ctx, AnimationView input, Icicles out) {
    final p = ctx.params;
    final amount = p.number('amount');
    final density = p.number('density');
    if (ctx.seconds >= _nextChange) {
      for (var i = 0; i < _factors.length; i++) {
        final jitter = ctx.random.nextDouble() < density;
        _factors[i] = jitter ? 1 + amount * (ctx.random.nextDouble() * 2 - 1) : 1;
      }
      _nextChange = ctx.seconds + 1 / p.number('rate');
    }
    if (amount == 0 || density == 0) return;
    var i = 0;
    final pixels = input.frame.pixels;
    for (; i < pixels.length; i++) {
      out.setPixelColorAtIndex(i, scaleColor(pixels[i], _factors[i]));
    }
    if (!panelsOf(p)) return;
    for (final panel in input.radioPanels) {
      final target = out.radioPanels[panel.index - 1];
      final base = setup.pixelsCount + (panel.index - 1) * setup.radioPanelPixelCount;
      for (var k = 0; k < panel.colors.length; k++) {
        target.setPixel(k, scaleColor(panel.colors[k], _factors[base + k]));
      }
    }
  }
}

/// A vignette over the input.
final class FadeEdgesEffect implements Effect {
  const FadeEdgesEffect();

  @override
  EffectInfo get info => const EffectInfo(
        id: 'icicles.fx.fade_edges',
        version: 1,
        name: LocalizedText('Fade edges', pl: 'Ściemnione brzegi'),
        description: LocalizedText(
          'Darkens the layers towards the edges, like a vignette or a spotlight.',
          pl: 'Przyciemnia warstwy ku brzegom, jak winieta lub reflektor.',
        ),
        category: EffectCategory.stylize,
      );

  @override
  List<ParamSpec> get params => const [
        ChoiceParam(
          id: 'shape',
          label: LocalizedText('Shape', pl: 'Kształt'),
          options: [
            ChoiceOption('edges', LocalizedText('All edges', pl: 'Wszystkie brzegi')),
            ChoiceOption('sides', LocalizedText('Left and right', pl: 'Lewy i prawy')),
            ChoiceOption('ends', LocalizedText('Roof and tips', pl: 'Dach i końcówki')),
            ChoiceOption('spotlight', LocalizedText('Spotlight', pl: 'Reflektor')),
          ],
          defaultValue: 'edges',
        ),
        NumberParam(
          id: 'size',
          label: LocalizedText('Size', pl: 'Wielkość'),
          description: LocalizedText('How far the fade reaches in from the edge.',
              pl: 'Jak daleko od brzegu sięga ściemnienie.'),
          min: 0.05,
          max: 1,
          defaultValue: 0.3,
          step: 0.01,
        ),
        NumberParam(
            id: 'softness',
            label: LocalizedText('Softness', pl: 'Miękkość'),
            min: 0,
            max: 1,
            defaultValue: 0.5,
            step: 0.01),
        NumberParam(
          id: 'strength',
          label: LocalizedText('Strength', pl: 'Siła'),
          description: LocalizedText('How dark the edges get.', pl: 'Jak ciemne stają się brzegi.'),
          min: 0,
          max: 1,
          defaultValue: 1,
          step: 0.01,
        ),
        BoolParam(
          id: 'panels',
          label: LocalizedText('Radio panels too', pl: 'Także panele radiowe'),
          description: LocalizedText('Dims the panels by the mask at their share of the icicles.',
              pl: 'Przyciemnia panele maską z ich części sopli.'),
          defaultValue: true,
        ),
      ];

  @override
  EffectInstance create(GeneratorSetup setup) => const _FadeEdgesInstance();
}

final class _FadeEdgesInstance implements EffectInstance {
  const _FadeEdgesInstance();

  /// 1 inside, fading to 0 at the edge: [coordinate] in `0..1`, the fade
  /// reaching [size] in from both ends.
  static double _edge(double coordinate, double size, double softness) {
    final d = math.min(coordinate, 1 - coordinate);
    final feather = math.max(1e-6, softness * size);
    return _smoothstep(size - feather, size, d);
  }

  @override
  void apply(FrameContext ctx, AnimationView input, Icicles out) {
    final p = ctx.params;
    final shape = p.choice('shape');
    final size = p.number('size');
    final softness = p.number('softness');
    final strength = p.number('strength');
    if (strength <= 0) return;
    final w = ctx.xCount, h = ctx.yCount;
    double maskAt(double nx, double ny) {
      final m = switch (shape) {
        'sides' => _edge(nx, size, softness),
        'ends' => _edge(ny, size, softness),
        'spotlight' => 1 -
            _smoothstep(1 - size, 1 - size + math.max(1e-6, softness * size),
                math.sqrt((nx - 0.5) * (nx - 0.5) + (ny - 0.5) * (ny - 0.5)) / 0.5),
        _ => _edge(nx, size, softness) * _edge(ny, size, softness),
      };
      return 1 - strength * (1 - m);
    }

    for (var x = 0; x < w; x++) {
      for (var y = 0; y < h; y++) {
        final m = maskAt(ctx.nx(x), ctx.ny(y));
        if (m < 1) out.setPixelColor(x, y, scaleColor(inputPixel(ctx, input, x, y), m));
      }
    }
    if (!p.flag('panels')) return;
    final count = input.radioPanels.length;
    for (final panel in input.radioPanels) {
      final nx = count <= 1 ? 0.5 : (panel.index - 1) / (count - 1);
      final m = maskAt(nx, 0.5);
      if (m >= 1) continue;
      final target = out.radioPanels[panel.index - 1];
      for (var i = 0; i < panel.colors.length; i++) {
        target.setPixel(i, scaleColor(panel.colors[i], m));
      }
    }
  }
}

/// Pixels pushed around by noise.
final class NoiseDisplaceEffect implements Effect {
  const NoiseDisplaceEffect();

  @override
  EffectInfo get info => const EffectInfo(
        id: 'icicles.fx.noise_displace',
        version: 1,
        name: LocalizedText('Noise displace', pl: 'Zniekształcenie szumem'),
        description: LocalizedText(
          'Pushes the pixels around with drifting noise, like heat haze.',
          pl: 'Przesuwa piksele dryfującym szumem, jak drgania gorącego powietrza.',
        ),
        category: EffectCategory.stylize,
      );

  @override
  List<ParamSpec> get params => const [
        NumberParam(
          id: 'amount',
          label: LocalizedText('Amount', pl: 'Stopień'),
          description: LocalizedText('Largest displacement.', pl: 'Największe przesunięcie.'),
          min: 0,
          max: 10,
          defaultValue: 2,
          step: 0.1,
          unit: 'px',
        ),
        NumberParam(
          id: 'scale',
          label: LocalizedText('Scale', pl: 'Skala'),
          description: LocalizedText('Size of the noise.', pl: 'Wielkość szumu.'),
          min: 0.25,
          max: 4,
          defaultValue: 1,
          scale: NumberScale.log,
          unit: '×',
        ),
        NumberParam(
          id: 'speed',
          label: LocalizedText('Speed', pl: 'Prędkość'),
          min: 0,
          max: 5,
          defaultValue: 0.5,
          step: 0.05,
          unit: '×',
        ),
        BoolParam(
          id: 'wrap',
          label: LocalizedText('Wrap around', pl: 'Zawijanie'),
          defaultValue: true,
        ),
      ];

  @override
  EffectInstance create(GeneratorSetup setup) => _NoiseDisplaceInstance(SimplexNoise(setup.seed));
}

final class _NoiseDisplaceInstance implements EffectInstance {
  final SimplexNoise _noise;

  _NoiseDisplaceInstance(this._noise);

  @override
  void apply(FrameContext ctx, AnimationView input, Icicles out) {
    final p = ctx.params;
    final amount = p.number('amount');
    if (amount == 0) return;
    final frequency = 0.15 / p.number('scale');
    final t = ctx.seconds * p.number('speed');
    final wrap = p.flag('wrap');
    final w = ctx.xCount, h = ctx.yCount;
    final grid = List<Color>.filled(w * h, black);
    for (var x = 0; x < w; x++) {
      for (var y = 0; y < h; y++) {
        final dx = _noise.simplex3(x * frequency, y * frequency, t) * amount;
        final dy = _noise.simplex3(x * frequency + 37.1, y * frequency + 11.7, t) * amount;
        grid[x * h + y] = sampleGrid(ctx, input, (x + dx).round(), (y + dy).round(), wrap: wrap);
      }
    }
    setGrid(out, grid);
  }
}
