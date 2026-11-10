import 'dart:math' as math;
import 'dart:typed_data';

import 'package:icicles_animation_dart/icicles_animation_dart.dart';

import '../generator/generator.dart';
import '../generator/generator_info.dart';
import '../generator/localized_text.dart';
import '../params/param_spec.dart';
import '../util/color.dart';
import '../util/direction.dart';
import '../util/palette.dart';
import '../util/panel_mode.dart';
import 'common.dart';

/// A directional fill: the color sweeps over the grid, then (looping) sweeps
/// off again.
final class WipeGenerator implements Generator {
  const WipeGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.wipe',
        version: 1,
        name: LocalizedText('Wipe', pl: 'Przesłona'),
        description: LocalizedText(
          'A color sweeping over the grid in one direction; loops or holds.',
          pl: 'Kolor zalewający siatkę w jednym kierunku; w pętli lub zatrzymany.',
        ),
        category: GeneratorCategory.motion,
      );

  static final _direction = directionParam();

  @override
  List<ParamSpec> get params => [
        _direction,
        const ColorParam(id: 'color', label: colorLabel, defaultValue: Color(0xFF40A0FF)),
        const NumberParam(
          id: 'period',
          label: LocalizedText('Period', pl: 'Okres'),
          description:
              LocalizedText('Seconds of one fill (and one clear).', pl: 'Sekundy jednego zalania (i zgaszenia).'),
          min: 0.25,
          max: 20,
          defaultValue: 2,
          scale: NumberScale.log,
          unit: 's',
        ),
        const NumberParam(
          id: 'softness',
          label: LocalizedText('Soft edge', pl: 'Miękka krawędź'),
          min: 0,
          max: 1,
          defaultValue: 0.2,
          step: 0.01,
        ),
        const ChoiceParam(
          id: 'mode',
          label: LocalizedText('Mode', pl: 'Tryb'),
          options: [
            ChoiceOption('loop', LocalizedText('Fill and clear, looping', pl: 'Zalewaj i gaś w pętli')),
            ChoiceOption('hold', LocalizedText('Fill once and hold', pl: 'Zalej raz i zatrzymaj')),
          ],
          defaultValue: 'loop',
        ),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => const _WipeInstance();
}

final class _WipeInstance implements GeneratorInstance {
  const _WipeInstance();

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final direction = directionOf(p);
    final softness = p.number('softness');
    final progress = ctx.seconds / p.number('period');
    // Where the edge is, in 0..1 + softness, and whether we are clearing.
    final double edge;
    final bool clearing;
    if (p.choice('mode') == 'hold') {
      edge = math.min(1.0, progress) * (1 + softness);
      clearing = false;
    } else {
      final phase = (progress - progress.floor()) * 2;
      clearing = phase >= 1;
      edge = (clearing ? phase - 1 : phase) * (1 + softness);
    }
    final color = dim(p.color('color'), p.number('brightness'));
    for (var x = 0; x < ctx.xCount; x++) {
      for (var y = 0; y < ctx.yCount; y++) {
        final position = directionCoordinate(ctx, direction, x, y);
        var v = softness <= 0 ? (position <= edge ? 1.0 : 0.0) : ((edge - position) / softness).clamp(0.0, 1.0);
        if (clearing) v = 1 - v;
        out.setPixelColor(x, y, dim(color, v));
      }
    }
    applyPanelMode(out, panelModeOf(p));
  }
}

/// Theater chase: short segments running along or across the icicles.
final class ChaseGenerator implements Generator {
  const ChaseGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.chase',
        version: 1,
        name: LocalizedText('Chase', pl: 'Gonitwa'),
        description: LocalizedText(
          'Short segments of light running along or across the icicles.',
          pl: 'Krótkie odcinki światła biegnące wzdłuż lub w poprzek sopli.',
        ),
        category: GeneratorCategory.motion,
      );

  static final _direction = directionParam(options: straightDirections);

  @override
  List<ParamSpec> get params => [
        _direction,
        const IntParam(
            id: 'width', label: LocalizedText('Segment', pl: 'Odcinek'), min: 1, max: 10, defaultValue: 2, unit: 'px'),
        const IntParam(
            id: 'gap', label: LocalizedText('Gap', pl: 'Przerwa'), min: 1, max: 20, defaultValue: 4, unit: 'px'),
        const NumberParam(
          id: 'speed',
          label: LocalizedText('Speed', pl: 'Prędkość'),
          min: 1,
          max: 60,
          defaultValue: 10,
          scale: NumberScale.log,
          unit: 'px/s',
        ),
        const PaletteParam(id: 'palette', label: paletteLabel, defaultValue: Palette.party),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => const _ChaseInstance();
}

final class _ChaseInstance implements GeneratorInstance {
  const _ChaseInstance();

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final direction = directionOf(p);
    final width = p.integer('width');
    final period = width + p.integer('gap');
    final offset = ctx.seconds * p.number('speed');
    final palette = p.palette('palette');
    final brightness = p.number('brightness');
    for (var x = 0; x < ctx.xCount; x++) {
      for (var y = 0; y < ctx.yCount; y++) {
        final coordinate = switch (direction) {
          Direction.down => y.toDouble(),
          Direction.up => (ctx.yCount - 1 - y).toDouble(),
          Direction.right => x.toDouble(),
          _ => (ctx.xCount - 1 - x).toDouble(),
        };
        final along = coordinate - offset;
        final segment = (along / period).floor();
        final within = along - segment * period;
        final lit = within < width;
        out.setPixelColor(x, y, lit ? dim(palette.sample(segment / 7, wrap: true), brightness) : black);
      }
    }
    applyPanelMode(out, panelModeOf(p));
  }
}

/// A Larson/Cylon scanner: a bar sweeping back and forth with a trail.
final class ScannerGenerator implements Generator {
  const ScannerGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.scanner',
        version: 1,
        name: LocalizedText('Scanner', pl: 'Skaner'),
        description: LocalizedText(
          'A bar sweeping back and forth with a fading trail (Cylon eye).',
          pl: 'Pasek jeżdżący tam i z powrotem z gasnącym ogonem (oko Cylona).',
        ),
        category: GeneratorCategory.motion,
      );

  @override
  List<ParamSpec> get params => const [
        ChoiceParam(
          id: 'axis',
          label: LocalizedText('Sweeps', pl: 'Jeździ'),
          options: [
            ChoiceOption('horizontal', LocalizedText('Across the icicles', pl: 'W poprzek sopli')),
            ChoiceOption('vertical', LocalizedText('Along the icicles', pl: 'Wzdłuż sopli')),
          ],
          defaultValue: 'horizontal',
        ),
        NumberParam(
          id: 'width',
          label: LocalizedText('Width', pl: 'Szerokość'),
          min: 0.5,
          max: 8,
          defaultValue: 2,
          step: 0.1,
          unit: 'px',
        ),
        NumberParam(
          id: 'speed',
          label: LocalizedText('Speed', pl: 'Prędkość'),
          description: LocalizedText('Sweeps per second.', pl: 'Przejazdy na sekundę.'),
          min: 0.1,
          max: 5,
          defaultValue: 0.5,
          scale: NumberScale.log,
          unit: '/s',
        ),
        NumberParam(
          id: 'trail',
          label: LocalizedText('Trail', pl: 'Ogon'),
          min: 0,
          max: 2,
          defaultValue: 0.4,
          step: 0.01,
          unit: 's',
        ),
        ColorParam(id: 'color', label: colorLabel, defaultValue: Color(0xFFFF2020)),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _ScannerInstance(setup.pixelsCount);
}

final class _ScannerInstance implements GeneratorInstance {
  final Float64List energy;

  _ScannerInstance(int pixels) : energy = Float64List(pixels);

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final vertical = p.choice('axis') == 'vertical';
    final length = vertical ? ctx.yCount : ctx.xCount;
    final position = triangle(ctx.seconds * p.number('speed')) * (length - 1);
    final width = p.number('width');
    final decay = decayFactor(p.number('trail'), ctx.deltaSeconds);
    final color = p.color('color');
    final brightness = p.number('brightness');
    for (var x = 0; x < ctx.xCount; x++) {
      for (var y = 0; y < ctx.yCount; y++) {
        final i = x * ctx.yCount + y;
        final bar = falloff((vertical ? y : x) - position, width);
        energy[i] = math.max(bar, energy[i] * decay);
        out.setPixelColorAtIndex(i, dim(color, energy[i] * brightness));
      }
    }
    applyPanelMode(out, panelModeOf(p));
  }
}

/// The whole grid breathing in and out.
final class BreatheGenerator implements Generator {
  const BreatheGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.breathe',
        version: 1,
        name: LocalizedText('Breathe', pl: 'Oddech'),
        description: LocalizedText(
          'The whole grid slowly brightening and dimming.',
          pl: 'Cała siatka powoli rozjaśnia się i przygasa.',
        ),
        category: GeneratorCategory.basic,
      );

  @override
  List<ParamSpec> get params => const [
        ColorParam(id: 'color', label: colorLabel, defaultValue: Color(0xFF60C0FF)),
        NumberParam(
          id: 'rate',
          label: LocalizedText('Rate', pl: 'Tempo'),
          description: LocalizedText('Breaths per second.', pl: 'Oddechy na sekundę.'),
          min: 0.05,
          max: 4,
          defaultValue: 0.25,
          scale: NumberScale.log,
          unit: '/s',
        ),
        ChoiceParam(
          id: 'shape',
          label: LocalizedText('Shape', pl: 'Kształt'),
          options: [
            ChoiceOption('sine', LocalizedText('Smooth', pl: 'Łagodny')),
            ChoiceOption('exp', LocalizedText('Sharp (exponential)', pl: 'Ostry (wykładniczy)')),
            ChoiceOption('triangle', LocalizedText('Linear', pl: 'Liniowy')),
          ],
          defaultValue: 'sine',
        ),
        NumberParam(
          id: 'floor',
          label: LocalizedText('Minimum', pl: 'Minimum'),
          description: LocalizedText('Brightness at the bottom of a breath.', pl: 'Jasność na dnie oddechu.'),
          min: 0,
          max: 0.9,
          defaultValue: 0,
          step: 0.01,
        ),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => const _BreatheInstance();
}

final class _BreatheInstance implements GeneratorInstance {
  const _BreatheInstance();

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final phase = ctx.seconds * p.number('rate');
    final v = switch (p.choice('shape')) {
      'exp' => (math.exp(math.sin(phase * math.pi * 2 - math.pi / 2)) - math.exp(-1)) / (math.e - math.exp(-1)),
      'triangle' => triangle(phase),
      _ => 0.5 - 0.5 * math.cos(phase * math.pi * 2),
    };
    final floor = p.number('floor');
    final color = dim(p.color('color'), (floor + (1 - floor) * v) * p.number('brightness'));
    out.setAllPixelsColor(color);
    if (panelModeOf(p) == PanelMode.off) {
      applyPanelMode(out, PanelMode.off);
    } else {
      out.setAllRadioPanelsColor(color);
    }
  }
}

/// Comets with glowing tails running along the icicles.
final class MeteorGenerator implements Generator {
  const MeteorGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.meteor',
        version: 1,
        name: LocalizedText('Meteors', pl: 'Meteory'),
        description: LocalizedText(
          'Comets with glowing tails falling down (or rising up) the icicles.',
          pl: 'Komety ze świecącymi ogonami spadające (lub wznoszące się) po soplach.',
        ),
        category: GeneratorCategory.motion,
      );

  static final _direction = directionParam(options: const [Direction.down, Direction.up]);

  @override
  List<ParamSpec> get params => [
        const IntParam(
            id: 'count', label: LocalizedText('Meteors', pl: 'Liczba meteorów'), min: 1, max: 48, defaultValue: 6),
        const NumberParam(
          id: 'speed',
          label: LocalizedText('Speed', pl: 'Prędkość'),
          description: LocalizedText('Icicle lengths per second.', pl: 'Długości sopla na sekundę.'),
          min: 0.2,
          max: 5,
          defaultValue: 1,
          scale: NumberScale.log,
          unit: '/s',
        ),
        const NumberParam(
          id: 'tail',
          label: LocalizedText('Tail', pl: 'Ogon'),
          description: LocalizedText('Tail length as a part of the icicle.', pl: 'Długość ogona jako część sopla.'),
          min: 0.05,
          max: 1,
          defaultValue: 0.4,
          step: 0.01,
        ),
        _direction,
        const PaletteParam(id: 'palette', label: paletteLabel, defaultValue: Palette.ice),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _MeteorInstance();
}

final class _Meteor {
  final int x;
  double position;
  final double speed;
  final Color color;

  _Meteor(this.x, this.position, this.speed, this.color);
}

final class _MeteorInstance implements GeneratorInstance {
  final meteors = <_Meteor>[];

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final random = ctx.random;
    final dt = ctx.deltaSeconds;
    final height = ctx.yCount.toDouble();
    final tail = math.max(1.0, p.number('tail') * height);
    final palette = p.palette('palette');
    final speed = p.number('speed') * height;
    final count = p.integer('count');
    final up = directionOf(p) == Direction.up;
    final brightness = p.number('brightness');
    while (meteors.length < count) {
      meteors.add(_Meteor(
        random.nextInt(ctx.xCount),
        -random.nextDouble() * (height + tail) * 2,
        0.7 + random.nextDouble() * 0.6,
        palette.sample(0.3 + random.nextDouble() * 0.7),
      ));
    }
    if (meteors.length > count) meteors.removeRange(count, meteors.length);
    out.setAllPixelsColor(black);
    for (var i = 0; i < meteors.length; i++) {
      var meteor = meteors[i];
      meteor.position += meteor.speed * speed * dt;
      if (meteor.position - tail > height) {
        meteor = meteors[i] = _Meteor(
          random.nextInt(ctx.xCount),
          -random.nextDouble() * (height + tail),
          0.7 + random.nextDouble() * 0.6,
          palette.sample(0.3 + random.nextDouble() * 0.7),
        );
      }
      for (var k = 0; k < ctx.yCount; k++) {
        final behind = meteor.position - k;
        if (behind < -0.5 || behind > tail) continue;
        final intensity = behind <= 0.5 ? 1.0 : math.pow(1 - behind / tail, 2).toDouble();
        final y = up ? ctx.yCount - 1 - k : k;
        addPixel(out, meteor.x, y, meteor.color, intensity * brightness);
      }
    }
    applyPanelMode(out, panelModeOf(p));
  }
}

/// Balls bouncing on the tips of the icicles.
final class BounceGenerator implements Generator {
  const BounceGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.bounce',
        version: 1,
        name: LocalizedText('Bouncing balls', pl: 'Odbijające się kulki'),
        description: LocalizedText(
          'A ball on every icicle dropping and bouncing off the tip.',
          pl: 'Kulka na każdym soplu spadająca i odbijająca się od końca.',
        ),
        category: GeneratorCategory.motion,
      );

  @override
  List<ParamSpec> get params => const [
        NumberParam(
          id: 'gravity',
          label: LocalizedText('Gravity', pl: 'Grawitacja'),
          min: 1,
          max: 30,
          defaultValue: 8,
          scale: NumberScale.log,
          unit: '/s²',
        ),
        NumberParam(
          id: 'damping',
          label: LocalizedText('Bounciness', pl: 'Sprężystość'),
          description: LocalizedText('Speed kept after a bounce.', pl: 'Część prędkości zachowana po odbiciu.'),
          min: 0.5,
          max: 0.98,
          defaultValue: 0.85,
          step: 0.01,
        ),
        NumberParam(
          id: 'size',
          label: LocalizedText('Ball size', pl: 'Wielkość kulki'),
          min: 0.5,
          max: 3,
          defaultValue: 1,
          step: 0.1,
          unit: 'px',
        ),
        NumberParam(
          id: 'density',
          label: LocalizedText('Icicles with balls', pl: 'Sople z kulkami'),
          min: 0.1,
          max: 1,
          defaultValue: 1,
          step: 0.05,
        ),
        PaletteParam(id: 'palette', label: paletteLabel, defaultValue: Palette.rainbow),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _BounceInstance(setup.xCount);
}

final class _BounceInstance implements GeneratorInstance {
  final Float64List y;
  final Float64List vy;
  final Float64List wait;
  bool _started = false;

  _BounceInstance(int xCount)
      : y = Float64List(xCount),
        vy = Float64List(xCount),
        wait = Float64List(xCount);

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final random = ctx.random;
    final dt = ctx.deltaSeconds;
    if (!_started) {
      _started = true;
      for (var x = 0; x < ctx.xCount; x++) {
        wait[x] = random.nextDouble() * 1.5;
      }
    }
    final gravity = p.number('gravity') * ctx.yCount;
    final damping = p.number('damping');
    final size = p.number('size');
    final active = (p.number('density') * ctx.xCount).round().clamp(1, ctx.xCount);
    final palette = p.palette('palette');
    final brightness = p.number('brightness');
    final floor = ctx.yCount - 1.0;
    out.setAllPixelsColor(black);
    for (var x = 0; x < ctx.xCount; x++) {
      // Spread the active icicles evenly.
      if ((x * active) % ctx.xCount >= active) continue;
      if (wait[x] > 0) {
        wait[x] -= dt;
        continue;
      }
      vy[x] += gravity * dt;
      y[x] += vy[x] * dt;
      if (y[x] >= floor) {
        y[x] = floor;
        vy[x] = -vy[x].abs() * damping;
        if (vy[x].abs() < gravity * 0.08) {
          y[x] = 0;
          vy[x] = 0;
          wait[x] = 0.3 + random.nextDouble() * 1.2;
        }
      }
      final color = palette.sample(ctx.nx(x));
      for (var k = 0; k < ctx.yCount; k++) {
        addPixel(out, x, k, color, falloff(k - y[x], size) * brightness);
      }
    }
    applyPanelMode(out, panelModeOf(p));
  }
}

/// Alternating bands of two colors scrolling over the grid.
final class MarqueeGenerator implements Generator {
  const MarqueeGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.marquee',
        version: 1,
        name: LocalizedText('Marquee', pl: 'Pasy'),
        description: LocalizedText(
          'Alternating bands of two colors scrolling over the grid.',
          pl: 'Naprzemienne pasy dwóch kolorów przesuwające się po siatce.',
        ),
        category: GeneratorCategory.motion,
      );

  static final _direction = directionParam(options: straightDirections, defaultValue: Direction.right);

  @override
  List<ParamSpec> get params => [
        const ColorParam(id: 'colorA', label: LocalizedText('Color A', pl: 'Kolor A'), defaultValue: Color(0xFFFF2000)),
        const ColorParam(id: 'colorB', label: LocalizedText('Color B', pl: 'Kolor B'), defaultValue: Color(0xFFFFFFFF)),
        const IntParam(
            id: 'band',
            label: LocalizedText('Band size', pl: 'Szerokość pasa'),
            min: 1,
            max: 10,
            defaultValue: 3,
            unit: 'px'),
        const NumberParam(
          id: 'speed',
          label: LocalizedText('Speed', pl: 'Prędkość'),
          min: 0.5,
          max: 30,
          defaultValue: 4,
          scale: NumberScale.log,
          unit: 'px/s',
        ),
        _direction,
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => const _MarqueeInstance();
}

final class _MarqueeInstance implements GeneratorInstance {
  const _MarqueeInstance();

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final direction = directionOf(p);
    final band = p.integer('band');
    final offset = ctx.seconds * p.number('speed');
    final brightness = p.number('brightness');
    final a = dim(p.color('colorA'), brightness);
    final b = dim(p.color('colorB'), brightness);
    for (var x = 0; x < ctx.xCount; x++) {
      for (var y = 0; y < ctx.yCount; y++) {
        final coordinate = switch (direction) {
          Direction.down => y.toDouble(),
          Direction.up => (ctx.yCount - 1 - y).toDouble(),
          Direction.right => x.toDouble(),
          _ => (ctx.xCount - 1 - x).toDouble(),
        };
        final index = ((coordinate - offset) / band).floor();
        out.setPixelColor(x, y, index.isEven ? a : b);
      }
    }
    applyPanelMode(out, panelModeOf(p));
  }
}

/// Wide colored bars moving over the grid.
final class BarsGenerator implements Generator {
  const BarsGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.bars',
        version: 1,
        name: LocalizedText('Bars', pl: 'Belki'),
        description: LocalizedText(
          'Wide palette-colored bars moving over the grid, optionally shaded.',
          pl: 'Szerokie belki w kolorach palety przesuwające się po siatce, opcjonalnie cieniowane.',
        ),
        category: GeneratorCategory.motion,
      );

  static final _direction = directionParam();

  @override
  List<ParamSpec> get params => [
        const IntParam(id: 'count', label: LocalizedText('Bars', pl: 'Liczba belek'), min: 1, max: 8, defaultValue: 3),
        _direction,
        const NumberParam(
          id: 'speed',
          label: LocalizedText('Speed', pl: 'Prędkość'),
          description: LocalizedText('Grid lengths per second.', pl: 'Długości siatki na sekundę.'),
          min: 0.05,
          max: 3,
          defaultValue: 0.3,
          scale: NumberScale.log,
          unit: '/s',
        ),
        const PaletteParam(id: 'palette', label: paletteLabel, defaultValue: Palette.party),
        const BoolParam(
          id: 'shading',
          label: LocalizedText('3D shading', pl: 'Cieniowanie 3D'),
          description:
              LocalizedText('Each bar fades across its width.', pl: 'Każda belka przygasa na swojej szerokości.'),
          defaultValue: true,
        ),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => const _BarsInstance();
}

final class _BarsInstance implements GeneratorInstance {
  const _BarsInstance();

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final direction = directionOf(p);
    final count = p.integer('count');
    final offset = ctx.seconds * p.number('speed');
    final palette = p.palette('palette');
    final shading = p.flag('shading');
    final brightness = p.number('brightness');
    for (var x = 0; x < ctx.xCount; x++) {
      for (var y = 0; y < ctx.yCount; y++) {
        final c = directionCoordinate(ctx, direction, x, y) * count - offset * count;
        final index = c.floor();
        final within = c - index;
        final bar = ((index % count) + count) % count;
        final shade = shading ? 0.35 + 0.65 * (1 - within) : 1.0;
        out.setPixelColor(x, y, dim(palette.sample((bar + 0.5) / count), shade * brightness));
      }
    }
    applyPanelMode(out, panelModeOf(p));
  }
}

/// Snakes crawling along the strip, icicle after icicle (ported from the
/// firmware's Snake).
final class SnakeGenerator implements Generator {
  const SnakeGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.snake',
        version: 1,
        name: LocalizedText('Snake', pl: 'Wąż'),
        description: LocalizedText(
          'Snakes crawling down one icicle and up the next.',
          pl: 'Węże pełznące w dół jednego sopla i w górę następnego.',
        ),
        category: GeneratorCategory.motion,
      );

  @override
  List<ParamSpec> get params => const [
        IntParam(id: 'count', label: LocalizedText('Snakes', pl: 'Liczba węży'), min: 1, max: 8, defaultValue: 2),
        IntParam(
            id: 'length', label: LocalizedText('Length', pl: 'Długość'), min: 2, max: 80, defaultValue: 24, unit: 'px'),
        NumberParam(
          id: 'speed',
          label: LocalizedText('Speed', pl: 'Prędkość'),
          min: 5,
          max: 300,
          defaultValue: 60,
          scale: NumberScale.log,
          unit: 'px/s',
        ),
        BoolParam(
          id: 'serpentine',
          label: LocalizedText('Serpentine', pl: 'Serpentyna'),
          description: LocalizedText('Alternate down and up; off: always down.',
              pl: 'Na przemian w dół i w górę; wyłączone: zawsze w dół.'),
          defaultValue: true,
        ),
        PaletteParam(id: 'palette', label: paletteLabel, defaultValue: Palette.rainbow),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => const _SnakeInstance();
}

final class _SnakeInstance implements GeneratorInstance {
  const _SnakeInstance();

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final count = p.integer('count');
    final length = p.integer('length');
    final serpentine = p.flag('serpentine');
    final palette = p.palette('palette');
    final brightness = p.number('brightness');
    final total = ctx.setup.pixelsCount;
    final head = ctx.seconds * p.number('speed');
    out.setAllPixelsColor(black);
    for (var s = 0; s < count; s++) {
      final color = palette.sample((s + 0.5) / count);
      final offset = head + s * total / count;
      for (var k = 0; k < length; k++) {
        final index = ((offset - k).floor() % total + total) % total;
        final x = index ~/ ctx.yCount;
        var y = index % ctx.yCount;
        if (serpentine && x.isOdd) y = ctx.yCount - 1 - y;
        addPixel(out, x, y, color, (1 - k / length) * brightness);
      }
    }
    applyPanelMode(out, panelModeOf(p));
  }
}

/// Two-color blocks sliding one icicle at a time, with easing (ported from
/// the firmware's Slide).
final class SlideGenerator implements Generator {
  const SlideGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.slide',
        version: 1,
        name: LocalizedText('Slide', pl: 'Przesuwanie'),
        description: LocalizedText(
          'Blocks of two colors sliding over by one icicle at a time, with a springy easing.',
          pl: 'Bloki dwóch kolorów przeskakujące co jeden sopel ze sprężystym wygładzeniem.',
        ),
        category: GeneratorCategory.motion,
      );

  static final _direction =
      directionParam(options: const [Direction.right, Direction.left], defaultValue: Direction.right);

  @override
  List<ParamSpec> get params => [
        const ColorParam(id: 'colorA', label: LocalizedText('Color A', pl: 'Kolor A'), defaultValue: Color(0xFF2040FF)),
        const ColorParam(id: 'colorB', label: LocalizedText('Color B', pl: 'Kolor B'), defaultValue: Color(0xFFFF2020)),
        const IntParam(
            id: 'block',
            label: LocalizedText('Block size', pl: 'Wielkość bloku'),
            min: 1,
            max: 8,
            defaultValue: 2,
            unit: 'icicles'),
        const NumberParam(
          id: 'period',
          label: LocalizedText('Step time', pl: 'Czas kroku'),
          min: 0.2,
          max: 5,
          defaultValue: 1,
          scale: NumberScale.log,
          unit: 's',
        ),
        const ChoiceParam(
          id: 'easing',
          label: LocalizedText('Easing', pl: 'Wygładzenie'),
          options: [
            ChoiceOption('elastic', LocalizedText('Elastic', pl: 'Sprężyste')),
            ChoiceOption('bounce', LocalizedText('Bounce', pl: 'Odbicie')),
            ChoiceOption('smooth', LocalizedText('Smooth', pl: 'Łagodne')),
            ChoiceOption('linear', LocalizedText('Linear', pl: 'Liniowe')),
          ],
          defaultValue: 'elastic',
        ),
        _direction,
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => const _SlideInstance();
}

final class _SlideInstance implements GeneratorInstance {
  const _SlideInstance();

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final progress = ctx.seconds / p.number('period');
    final step = progress.floor();
    final fraction = progress - step;
    final eased = switch (p.choice('easing')) {
      'elastic' => Curves.elasticOut.transform(fraction),
      'bounce' => Curves.bounceOut.transform(fraction),
      'smooth' => Curves.cubicInOut.transform(fraction),
      _ => fraction,
    };
    final shift = (step + eased) * (directionOf(p) == Direction.left ? -1 : 1);
    final blockPixels = p.integer('block') * ctx.yCount;
    final brightness = p.number('brightness');
    final a = dim(p.color('colorA'), brightness);
    final b = dim(p.color('colorB'), brightness);
    // The firmware shifts in strip-index space, so a fractional shift moves
    // the block boundary down the icicle.
    for (var x = 0; x < ctx.xCount; x++) {
      for (var y = 0; y < ctx.yCount; y++) {
        final index = x * ctx.yCount + y - shift * ctx.yCount;
        final block = (index / blockPixels).floor();
        out.setPixelColor(x, y, block.isEven ? a : b);
      }
    }
    applyPanelMode(out, panelModeOf(p));
  }
}
