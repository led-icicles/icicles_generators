import 'dart:math' as math;
import 'dart:typed_data';

import 'package:icicles_animation_dart/icicles_animation_dart.dart';

import '../generator/generator.dart';
import '../generator/generator_info.dart';
import '../generator/localized_text.dart';
import '../params/param_spec.dart';
import '../util/color.dart';
import '../util/direction.dart';
import '../util/font3x5.dart';
import '../util/noise.dart';
import '../util/palette.dart';
import '../util/panel_mode.dart';
import 'common.dart';

const _thicknessParam = NumberParam(
  id: 'thickness',
  label: LocalizedText('Ring thickness', pl: 'Grubość pierścienia'),
  min: 0.5,
  max: 5,
  defaultValue: 1.5,
  step: 0.1,
  unit: 'px',
);

/// Rings expanding from random points (WLED Ripple).
final class RippleGenerator implements Generator {
  const RippleGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.ripple',
        version: 1,
        name: LocalizedText('Ripples', pl: 'Kręgi na wodzie'),
        description: LocalizedText(
          'Rings expanding from random points, like drops on water.',
          pl: 'Pierścienie rozchodzące się z losowych punktów jak krople na wodzie.',
        ),
        category: GeneratorCategory.geometry,
      );

  @override
  List<ParamSpec> get params => const [
        NumberParam(
          id: 'rate',
          label: LocalizedText('Drops', pl: 'Krople'),
          description: LocalizedText('New rings per second.', pl: 'Nowe pierścienie na sekundę.'),
          min: 0.2,
          max: 10,
          defaultValue: 2,
          scale: NumberScale.log,
          unit: '/s',
        ),
        NumberParam(
          id: 'speed',
          label: LocalizedText('Speed', pl: 'Prędkość'),
          description: LocalizedText('Grid widths per second.', pl: 'Szerokości siatki na sekundę.'),
          min: 0.1,
          max: 5,
          defaultValue: 0.6,
          scale: NumberScale.log,
          unit: '/s',
        ),
        _thicknessParam,
        NumberParam(
          id: 'life',
          label: LocalizedText('Ring life', pl: 'Czas pierścienia'),
          min: 0.3,
          max: 5,
          defaultValue: 1.5,
          scale: NumberScale.log,
          unit: 's',
        ),
        BoolParam(
            id: 'centered',
            label: LocalizedText('Always from the center', pl: 'Zawsze ze środka'),
            defaultValue: false),
        PaletteParam(id: 'palette', label: paletteLabel, defaultValue: Palette.ocean),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _RippleInstance();
}

final class _RippleInstance implements GeneratorInstance {
  final rings = <Ring>[];
  double _pending = 0.999;

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final random = ctx.random;
    final dt = ctx.deltaSeconds;
    final palette = p.palette('palette');
    final centered = p.flag('centered');
    _pending += p.number('rate') * math.max(dt, 1 / 60);
    while (_pending >= 1) {
      _pending -= 1;
      rings.add(Ring(
        x: centered ? (ctx.xCount - 1) / 2 : random.nextDouble() * (ctx.xCount - 1),
        y: centered ? (ctx.yCount - 1) / 2 : random.nextDouble() * (ctx.yCount - 1),
        speed: p.number('speed') * ctx.xCount,
        life: p.number('life'),
        color: palette.sample(0.3 + random.nextDouble() * 0.7),
      ));
    }
    drawRings(ctx, out, rings, dt, p.number('thickness'), p.number('brightness'));
    applyPanelMode(out, panelModeOf(p));
  }
}

/// One ring expanding from a point, on a timer or a (bindable) trigger.
final class ShockwaveGenerator implements Generator {
  const ShockwaveGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.shockwave',
        version: 1,
        name: LocalizedText('Shockwave', pl: 'Fala uderzeniowa'),
        description: LocalizedText(
          'A ring bursting out of a point: on a timer, or when the trigger rises (bind it to the music).',
          pl: 'Pierścień wystrzeliwujący z punktu: co jakiś czas lub gdy wyzwalacz rośnie (podepnij go pod muzykę).',
        ),
        category: GeneratorCategory.geometry,
      );

  @override
  List<ParamSpec> get params => const [
        NumberParam(
          id: 'interval',
          label: LocalizedText('Every', pl: 'Co'),
          description: LocalizedText('Seconds between waves (max: only the trigger).',
              pl: 'Sekundy między falami (maks.: tylko wyzwalacz).'),
          min: 0.1,
          max: 30,
          defaultValue: 1.5,
          scale: NumberScale.log,
          unit: 's',
        ),
        NumberParam(
          id: 'trigger',
          label: LocalizedText('Trigger', pl: 'Wyzwalacz'),
          description:
              LocalizedText('Fires a wave when it rises above ½.', pl: 'Wystrzeliwuje falę, gdy przekroczy ½.'),
          min: 0,
          max: 1,
          defaultValue: 0,
          step: 0.01,
        ),
        NumberParam(
            id: 'centerX',
            label: LocalizedText('Center X', pl: 'Środek X'),
            min: 0,
            max: 1,
            defaultValue: 0.5,
            step: 0.01),
        NumberParam(
            id: 'centerY',
            label: LocalizedText('Center Y', pl: 'Środek Y'),
            min: 0,
            max: 1,
            defaultValue: 0.5,
            step: 0.01),
        NumberParam(
          id: 'speed',
          label: LocalizedText('Speed', pl: 'Prędkość'),
          description: LocalizedText('Grid widths per second.', pl: 'Szerokości siatki na sekundę.'),
          min: 0.2,
          max: 10,
          defaultValue: 2,
          scale: NumberScale.log,
          unit: '/s',
        ),
        NumberParam(
          id: 'width',
          label: LocalizedText('Width', pl: 'Szerokość'),
          min: 0.5,
          max: 6,
          defaultValue: 2,
          step: 0.1,
          unit: 'px',
        ),
        ColorParam(id: 'color', label: colorLabel, defaultValue: Color(0xFFFFFFFF)),
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _ShockwaveInstance();
}

final class _ShockwaveInstance implements GeneratorInstance {
  final rings = <Ring>[];
  double _sinceWave = double.infinity;
  bool _armed = true;

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final dt = ctx.deltaSeconds;
    final interval = p.number('interval');
    final trigger = p.number('trigger');
    _sinceWave += dt;
    var fire = false;
    if (interval < 30 && _sinceWave >= interval) fire = true;
    if (trigger >= 0.5 && _armed) {
      fire = true;
      _armed = false;
    } else if (trigger < 0.5) {
      _armed = true;
    }
    final speed = p.number('speed') * ctx.xCount;
    if (fire) {
      _sinceWave = 0;
      final reach = math.sqrt(ctx.xCount * ctx.xCount + ctx.yCount * ctx.yCount);
      rings.add(Ring(
        x: p.number('centerX') * (ctx.xCount - 1),
        y: p.number('centerY') * (ctx.yCount - 1),
        speed: speed,
        life: (reach + p.number('width') * 2) / speed,
        color: p.color('color'),
      ));
    }
    drawRings(ctx, out, rings, dt, p.number('width'), 1);
    applyPanelMode(out, panelModeOf(p));
  }
}

/// A pinwheel or spiral turning about the center.
final class RadialGenerator implements Generator {
  const RadialGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.radial',
        version: 1,
        name: LocalizedText('Pinwheel', pl: 'Wiatraczek'),
        description: LocalizedText(
          'Colored arms turning about the center, straight or twisted into a spiral.',
          pl: 'Kolorowe ramiona obracające się wokół środka, proste lub skręcone w spiralę.',
        ),
        category: GeneratorCategory.geometry,
      );

  @override
  List<ParamSpec> get params => const [
        IntParam(id: 'arms', label: LocalizedText('Arms', pl: 'Ramiona'), min: 1, max: 8, defaultValue: 3),
        NumberParam(
          id: 'speed',
          label: LocalizedText('Rotation', pl: 'Obrót'),
          description: LocalizedText('Turns per second.', pl: 'Obroty na sekundę.'),
          min: -2,
          max: 2,
          defaultValue: 0.3,
          step: 0.01,
          unit: '/s',
        ),
        NumberParam(
          id: 'twist',
          label: LocalizedText('Twist', pl: 'Skręt'),
          min: -3,
          max: 3,
          defaultValue: 1,
          step: 0.05,
        ),
        ChoiceParam(
          id: 'style',
          label: LocalizedText('Style', pl: 'Styl'),
          options: [
            ChoiceOption('pinwheel', LocalizedText('Pinwheel (hard edges)', pl: 'Wiatraczek (ostre krawędzie)')),
            ChoiceOption('spiral', LocalizedText('Spiral (smooth)', pl: 'Spirala (gładka)')),
          ],
          defaultValue: 'pinwheel',
        ),
        PaletteParam(id: 'palette', label: paletteLabel, defaultValue: Palette.rainbow),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => const _RadialInstance();
}

final class _RadialInstance implements GeneratorInstance {
  const _RadialInstance();

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final arms = p.integer('arms');
    final rotation = ctx.seconds * p.number('speed');
    final twist = p.number('twist');
    final smooth = p.choice('style') == 'spiral';
    final palette = p.palette('palette');
    final brightness = p.number('brightness');
    final cx = (ctx.xCount - 1) / 2;
    final cy = (ctx.yCount - 1) / 2;
    final radius = math.max(1.0, math.max(cx, cy));
    for (var x = 0; x < ctx.xCount; x++) {
      for (var y = 0; y < ctx.yCount; y++) {
        final dx = x - cx;
        final dy = y - cy;
        final r = math.sqrt(dx * dx + dy * dy) / radius;
        final angle = math.atan2(dy, dx) / (2 * math.pi) + rotation + twist * r;
        final w = angle * arms;
        if (smooth) {
          out.setPixelColor(x, y, dim(palette.sample(w, wrap: true), brightness));
        } else {
          final arm = w.floor();
          final lit = w - arm < 0.5;
          final color = palette.sample(((arm % arms + arms) % arms + 0.5) / arms);
          out.setPixelColor(x, y, dim(color, (lit ? 1 : 0.12) * brightness));
        }
      }
    }
    applyPanelMode(out, panelModeOf(p));
  }
}

/// A pulsing circle, square, diamond or heart.
final class ShapesGenerator implements Generator {
  const ShapesGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.shapes',
        version: 1,
        name: LocalizedText('Shape', pl: 'Kształt'),
        description: LocalizedText(
          'A circle, square, diamond or heart in the middle, outlined or filled, pulsing.',
          pl: 'Koło, kwadrat, romb lub serce pośrodku, obrys lub wypełnione, pulsujące.',
        ),
        category: GeneratorCategory.geometry,
      );

  @override
  List<ParamSpec> get params => const [
        ChoiceParam(
          id: 'shape',
          label: LocalizedText('Shape', pl: 'Kształt'),
          options: [
            ChoiceOption('circle', LocalizedText('Circle', pl: 'Koło')),
            ChoiceOption('square', LocalizedText('Square', pl: 'Kwadrat')),
            ChoiceOption('diamond', LocalizedText('Diamond', pl: 'Romb')),
            ChoiceOption('heart', LocalizedText('Heart', pl: 'Serce')),
          ],
          defaultValue: 'heart',
        ),
        NumberParam(
          id: 'size',
          label: LocalizedText('Size', pl: 'Wielkość'),
          description: LocalizedText('Relative to the grid height.', pl: 'Względem wysokości siatki.'),
          min: 0.1,
          max: 1.5,
          defaultValue: 0.7,
          step: 0.01,
        ),
        NumberParam(
          id: 'thickness',
          label: LocalizedText('Outline', pl: 'Obrys'),
          min: 0.5,
          max: 5,
          defaultValue: 1.5,
          step: 0.1,
          unit: 'px',
        ),
        BoolParam(id: 'filled', label: LocalizedText('Filled', pl: 'Wypełniony'), defaultValue: false),
        NumberParam(
          id: 'pulse',
          label: LocalizedText('Pulse', pl: 'Pulsowanie'),
          description: LocalizedText('Size swing, once per second.', pl: 'Wahanie wielkości, raz na sekundę.'),
          min: 0,
          max: 1,
          defaultValue: 0.25,
          step: 0.01,
        ),
        ColorParam(id: 'color', label: colorLabel, defaultValue: Color(0xFFFF2050)),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => const _ShapesInstance();
}

final class _ShapesInstance implements GeneratorInstance {
  const _ShapesInstance();

  static bool _inside(String shape, double x, double y, double size) {
    if (size <= 0) return false;
    final px = x / size;
    final py = y / size;
    return switch (shape) {
      'square' => math.max(px.abs(), py.abs()) <= 1,
      'diamond' => px.abs() + py.abs() <= 1,
      'heart' => () {
          // Heart curve (x² + y² − 1)³ − x² y³ ≤ 0, y up, scaled to fit.
          final hx = px * 1.25;
          final hy = -py * 1.25 + 0.15;
          final a = hx * hx + hy * hy - 1;
          return a * a * a - hx * hx * hy * hy * hy <= 0;
        }(),
      _ => px * px + py * py <= 1,
    };
  }

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final shape = p.choice('shape');
    final pulse = 1 + p.number('pulse') * 0.5 * math.sin(ctx.seconds * 2 * math.pi);
    final size = p.number('size') * pulse * ctx.yCount / 2;
    final thickness = p.number('thickness');
    final filled = p.flag('filled');
    final color = dim(p.color('color'), p.number('brightness'));
    final cx = (ctx.xCount - 1) / 2;
    final cy = (ctx.yCount - 1) / 2;
    for (var x = 0; x < ctx.xCount; x++) {
      for (var y = 0; y < ctx.yCount; y++) {
        final outer = _inside(shape, x - cx, y - cy, size);
        final lit = outer && (filled || !_inside(shape, x - cx, y - cy, size - thickness));
        out.setPixelColor(x, y, lit ? color : black);
      }
    }
    applyPanelMode(out, panelModeOf(p));
  }
}

/// A curtain opening and closing.
final class CurtainGenerator implements Generator {
  const CurtainGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.curtain',
        version: 1,
        name: LocalizedText('Curtain', pl: 'Kurtyna'),
        description: LocalizedText(
          'A curtain opening from the center or the edges, with a swag that lets the top move first.',
          pl: 'Kurtyna rozsuwana od środka lub od brzegów, z falbaną, która porusza górę jako pierwszą.',
        ),
        category: GeneratorCategory.geometry,
      );

  static final _direction = directionParam(
    options: const [Direction.outward, Direction.inward],
    defaultValue: Direction.outward,
    description: const LocalizedText('Outwards: the gap opens in the middle.',
        pl: 'Na zewnątrz: szczelina otwiera się pośrodku.'),
  );

  @override
  List<ParamSpec> get params => [
        _direction,
        const ChoiceParam(
          id: 'motion',
          label: LocalizedText('Motion', pl: 'Ruch'),
          options: [
            ChoiceOption('cycle', LocalizedText('Open and close', pl: 'Otwieraj i zamykaj')),
            ChoiceOption('open', LocalizedText('Open once', pl: 'Otwórz raz')),
            ChoiceOption('close', LocalizedText('Close once', pl: 'Zamknij raz')),
          ],
          defaultValue: 'cycle',
        ),
        const NumberParam(
          id: 'period',
          label: LocalizedText('Period', pl: 'Okres'),
          description: LocalizedText('Seconds of one opening.', pl: 'Sekundy jednego otwarcia.'),
          min: 0.25,
          max: 20,
          defaultValue: 3,
          scale: NumberScale.log,
          unit: 's',
        ),
        const NumberParam(
            id: 'swag', label: LocalizedText('Swag', pl: 'Falbana'), min: 0, max: 1, defaultValue: 0.4, step: 0.01),
        const PaletteParam(id: 'palette', label: paletteLabel, defaultValue: Palette.fire),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => const _CurtainInstance();
}

final class _CurtainInstance implements GeneratorInstance {
  const _CurtainInstance();

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final progress = ctx.seconds / p.number('period');
    final open = switch (p.choice('motion')) {
      'open' => math.min(1.0, progress),
      'close' => 1 - math.min(1.0, progress),
      _ => triangle(progress / 2),
    };
    final swag = p.number('swag');
    final outward = directionOf(p) == Direction.outward;
    final palette = p.palette('palette');
    final brightness = p.number('brightness');
    for (var x = 0; x < ctx.xCount; x++) {
      final fromCenter = (2 * ctx.nx(x) - 1).abs();
      final color = dim(palette.sample(0.35 + 0.65 * ctx.nx(x)), brightness);
      for (var y = 0; y < ctx.yCount; y++) {
        final gap = (open * (1 + swag) - swag * ctx.ny(y)).clamp(0.0, 1.0);
        final covered = outward ? fromCenter >= gap : fromCenter <= 1 - gap;
        out.setPixelColor(x, y, covered ? color : black);
      }
    }
    applyPanelMode(out, panelModeOf(p));
  }
}

/// Noise mirrored into symmetric wedges.
final class KaleidoscopeGenerator implements Generator {
  const KaleidoscopeGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.kaleidoscope',
        version: 1,
        name: LocalizedText('Kaleidoscope', pl: 'Kalejdoskop'),
        description: LocalizedText(
          'Flowing colors mirrored into symmetric wedges around the center.',
          pl: 'Płynące kolory odbite w symetryczne kliny wokół środka.',
        ),
        category: GeneratorCategory.geometry,
      );

  @override
  List<ParamSpec> get params => const [
        IntParam(id: 'segments', label: LocalizedText('Wedges', pl: 'Kliny'), min: 2, max: 12, defaultValue: 6),
        speedParam,
        scaleParam,
        NumberParam(
          id: 'rotation',
          label: LocalizedText('Rotation', pl: 'Obrót'),
          min: -1,
          max: 1,
          defaultValue: 0.1,
          step: 0.01,
          unit: '/s',
        ),
        PaletteParam(id: 'palette', label: paletteLabel, defaultValue: Palette.party),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _KaleidoscopeInstance(SimplexNoise(setup.seed));
}

final class _KaleidoscopeInstance implements GeneratorInstance {
  final SimplexNoise noise;

  _KaleidoscopeInstance(this.noise);

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final segments = p.integer('segments');
    final wedge = 2 * math.pi / segments;
    final t = ctx.seconds * p.number('speed') * 0.5;
    final frequency = 0.12 / p.number('scale');
    final rotation = ctx.seconds * p.number('rotation') * 2 * math.pi;
    final palette = p.palette('palette');
    final brightness = p.number('brightness');
    final cx = (ctx.xCount - 1) / 2;
    final cy = (ctx.yCount - 1) / 2;
    for (var x = 0; x < ctx.xCount; x++) {
      for (var y = 0; y < ctx.yCount; y++) {
        final dx = x - cx;
        final dy = y - cy;
        final r = math.sqrt(dx * dx + dy * dy);
        var a = (math.atan2(dy, dx) + rotation) % wedge;
        if (a < 0) a += wedge;
        if (a > wedge / 2) a = wedge - a;
        final sx = r * math.cos(a);
        final sy = r * math.sin(a);
        final n = noise.simplex3(sx * frequency, sy * frequency, t);
        out.setPixelColor(x, y, dim(palette.sample(n * 0.5 + 0.5 + t * 0.1, wrap: true), brightness));
      }
    }
    applyPanelMode(out, panelModeOf(p));
  }
}

/// A dot tracing a Lissajous curve with a trail.
final class LissajousGenerator implements Generator {
  const LissajousGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.lissajous',
        version: 1,
        name: LocalizedText('Lissajous', pl: 'Lissajous'),
        description: LocalizedText(
          'A glowing dot tracing a Lissajous figure, leaving a fading trail.',
          pl: 'Świecący punkt kreślący figurę Lissajous i zostawiający gasnący ślad.',
        ),
        category: GeneratorCategory.geometry,
      );

  @override
  List<ParamSpec> get params => const [
        IntParam(id: 'a', label: LocalizedText('Frequency X', pl: 'Częstotliwość X'), min: 1, max: 8, defaultValue: 3),
        IntParam(id: 'b', label: LocalizedText('Frequency Y', pl: 'Częstotliwość Y'), min: 1, max: 8, defaultValue: 2),
        NumberParam(
          id: 'speed',
          label: LocalizedText('Speed', pl: 'Prędkość'),
          min: 0.05,
          max: 2,
          defaultValue: 0.3,
          scale: NumberScale.log,
          unit: '/s',
        ),
        NumberParam(
          id: 'trail',
          label: LocalizedText('Trail', pl: 'Ślad'),
          min: 0.1,
          max: 4,
          defaultValue: 1,
          scale: NumberScale.log,
          unit: 's',
        ),
        PaletteParam(id: 'palette', label: paletteLabel, defaultValue: Palette.rainbow),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _LissajousInstance(setup.pixelsCount);
}

final class _LissajousInstance implements GeneratorInstance {
  final Float64List energy;
  final List<Color> colors;

  _LissajousInstance(int pixels)
      : energy = Float64List(pixels),
        colors = List.filled(pixels, black);

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final t = ctx.seconds * p.number('speed') * 2 * math.pi;
    final px = (ctx.xCount - 1) / 2 * (1 + math.sin(p.integer('a') * t));
    final py = (ctx.yCount - 1) / 2 * (1 + math.sin(p.integer('b') * t + math.pi / 2));
    final decay = decayFactor(p.number('trail'), ctx.deltaSeconds);
    final color = p.palette('palette').sample(ctx.seconds * 0.1, wrap: true);
    final brightness = p.number('brightness');
    for (var x = 0; x < ctx.xCount; x++) {
      for (var y = 0; y < ctx.yCount; y++) {
        final i = x * ctx.yCount + y;
        final d = math.sqrt((x - px) * (x - px) + (y - py) * (y - py));
        final dot = falloff(d, 1.4);
        energy[i] *= decay;
        if (dot > energy[i]) {
          energy[i] = dot;
          colors[i] = color;
        }
        out.setPixelColorAtIndex(i, dim(colors[i], energy[i] * brightness));
      }
    }
    applyPanelMode(out, panelModeOf(p));
  }
}

/// Conway's Game of Life with fading cells.
final class LifeGenerator implements Generator {
  const LifeGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.life',
        version: 1,
        name: LocalizedText('Game of Life', pl: 'Gra w życie'),
        description: LocalizedText(
          'Conway\'s Game of Life: cells colored by age, dying ones fading out; reseeds when it settles.',
          pl: 'Gra w życie Conwaya: komórki kolorowane wiekiem, umierające gasną; zasiewa się na nowo, gdy zastygnie.',
        ),
        category: GeneratorCategory.geometry,
      );

  @override
  List<ParamSpec> get params => const [
        NumberParam(
          id: 'density',
          label: LocalizedText('Seed density', pl: 'Gęstość zasiewu'),
          min: 0.1,
          max: 0.7,
          defaultValue: 0.3,
          step: 0.01,
        ),
        NumberParam(
          id: 'speed',
          label: LocalizedText('Speed', pl: 'Prędkość'),
          description: LocalizedText('Generations per second.', pl: 'Pokolenia na sekundę.'),
          min: 1,
          max: 30,
          defaultValue: 8,
          scale: NumberScale.log,
          unit: '/s',
        ),
        NumberParam(
          id: 'fade',
          label: LocalizedText('Fade', pl: 'Gaśnięcie'),
          description: LocalizedText('Seconds a dead cell glows on.', pl: 'Sekundy poświaty martwej komórki.'),
          min: 0,
          max: 2,
          defaultValue: 0.3,
          step: 0.01,
          unit: 's',
        ),
        BoolParam(id: 'wrap', label: LocalizedText('Wrap around', pl: 'Zawijanie brzegów'), defaultValue: true),
        PaletteParam(id: 'palette', label: paletteLabel, defaultValue: Palette.aurora),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _LifeInstance(setup.xCount, setup.yCount);
}

final class _LifeInstance implements GeneratorInstance {
  final int xCount, yCount;

  /// Age of a live cell (0 = dead).
  final Int32List age;
  final Int32List _next;
  final Float64List glow;
  double _pending = 1;
  int _population = -1;
  int _stableFor = 0;
  bool _seeded = false;

  _LifeInstance(this.xCount, this.yCount)
      : age = Int32List(xCount * yCount),
        _next = Int32List(xCount * yCount),
        glow = Float64List(xCount * yCount);

  void _seed(math.Random random, double density) {
    for (var i = 0; i < age.length; i++) {
      age[i] = random.nextDouble() < density ? 1 : 0;
    }
    _stableFor = 0;
    _population = -1;
  }

  void _step(bool wrap) {
    var population = 0;
    for (var x = 0; x < xCount; x++) {
      for (var y = 0; y < yCount; y++) {
        var neighbours = 0;
        for (var dx = -1; dx <= 1; dx++) {
          for (var dy = -1; dy <= 1; dy++) {
            if (dx == 0 && dy == 0) continue;
            var nx = x + dx;
            var ny = y + dy;
            if (wrap) {
              nx = (nx + xCount) % xCount;
              ny = (ny + yCount) % yCount;
            } else if (nx < 0 || ny < 0 || nx >= xCount || ny >= yCount) {
              continue;
            }
            if (age[nx * yCount + ny] > 0) neighbours++;
          }
        }
        final i = x * yCount + y;
        final alive = age[i] > 0;
        final lives = alive ? (neighbours == 2 || neighbours == 3) : neighbours == 3;
        _next[i] = lives ? age[i] + 1 : 0;
        if (lives) population++;
      }
    }
    age.setAll(0, _next);
    _stableFor = population == _population ? _stableFor + 1 : 0;
    _population = population;
  }

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final random = ctx.random;
    final density = p.number('density');
    final wrap = p.flag('wrap');
    if (!_seeded) {
      _seeded = true;
      _seed(random, density);
    }
    _pending += ctx.deltaSeconds * p.number('speed');
    while (_pending >= 1) {
      _pending -= 1;
      _step(wrap);
      if (_population == 0 || _stableFor >= 12) _seed(random, density);
    }
    final decay = decayFactor(p.number('fade'), ctx.deltaSeconds);
    final palette = p.palette('palette');
    final brightness = p.number('brightness');
    for (var i = 0; i < age.length; i++) {
      glow[i] *= decay;
      if (age[i] > 0) glow[i] = 1;
      final v = age[i] > 0 ? math.min(1.0, 0.2 + age[i] / 12) : glow[i] * 0.5;
      out.setPixelColorAtIndex(i, dim(palette.sample(age[i] > 0 ? v : 0.1), (age[i] > 0 ? 1 : glow[i]) * brightness));
    }
    applyPanelMode(out, panelModeOf(p));
  }
}

/// Text scrolling over the grid in a 3×5 font.
final class TextGenerator implements Generator {
  const TextGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.text',
        version: 1,
        name: LocalizedText('Text', pl: 'Tekst'),
        description: LocalizedText(
          'Scrolling text in a tiny 3×5 font; up/down turns the letters to read down the icicles.',
          pl: 'Przewijany tekst drobną czcionką 3×5; w górę/w dół obraca litery, by czytać je wzdłuż sopli.',
        ),
        category: GeneratorCategory.geometry,
      );

  static final _direction = directionParam(options: straightDirections, defaultValue: Direction.left);

  @override
  List<ParamSpec> get params => [
        const TextParam(id: 'text', label: LocalizedText('Text', pl: 'Tekst'), defaultValue: 'HELLO', maxLength: 64),
        _direction,
        const NumberParam(
          id: 'speed',
          label: LocalizedText('Speed', pl: 'Prędkość'),
          min: 1,
          max: 30,
          defaultValue: 6,
          scale: NumberScale.log,
          unit: 'px/s',
        ),
        const ColorParam(id: 'color', label: colorLabel, defaultValue: Color(0xFFFFD040)),
        const NumberParam(
          id: 'position',
          label: LocalizedText('Position', pl: 'Położenie'),
          description:
              LocalizedText('Where the line sits across the scroll.', pl: 'Gdzie leży linia w poprzek przewijania.'),
          min: 0,
          max: 1,
          defaultValue: 0.5,
          step: 0.01,
        ),
        const BoolParam(
            id: 'rainbow', label: LocalizedText('Rainbow letters', pl: 'Tęczowe litery'), defaultValue: false),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _TextInstance();
}

final class _TextInstance implements GeneratorInstance {
  String? _text;
  List<List<int>> _glyphs = const [];

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final text = p.text('text');
    if (text != _text) {
      _text = text;
      _glyphs = Font3x5.glyphs(text);
    }
    final direction = directionOf(p);
    final width = Font3x5.textWidth(_glyphs);
    final offset = ctx.seconds * p.number('speed');
    final color = p.color('color');
    final rainbow = p.flag('rainbow');
    final brightness = p.number('brightness');
    final vertical = direction.isVertical;
    final along = vertical ? ctx.yCount : ctx.xCount;
    final across = vertical ? ctx.xCount : ctx.yCount;
    final lineStart = ((across - Font3x5.height) * p.number('position')).round();
    // The text enters from the far edge and leaves at the other, then wraps.
    final span = along + width;
    final scroll = offset % span;
    final forward = direction == Direction.right || direction == Direction.down;
    out.setAllPixelsColor(black);
    for (var a = 0; a < along; a++) {
      final column = forward ? (a - (scroll - width)).floor() : (a + scroll - along).floor();
      if (column < 0 || column >= width) continue;
      final glyphColor = rainbow ? hsv(column / width, 1, 1) : color;
      for (var row = 0; row < Font3x5.height; row++) {
        if (!Font3x5.pixel(_glyphs, column, row)) continue;
        final c = lineStart + row;
        if (c < 0 || c >= across) continue;
        if (vertical) {
          // Letters are turned: rows run across the icicles, reading down.
          out.setPixelColor(forward ? across - 1 - c : c, a, dim(glyphColor, brightness));
        } else {
          out.setPixelColor(a, c, dim(glyphColor, brightness));
        }
      }
    }
    applyPanelMode(out, panelModeOf(p));
  }
}

/// Wandering heat sources diffusing over the grid (after the firmware's
/// Heatmap).
final class HeatmapGenerator implements Generator {
  const HeatmapGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.heatmap',
        version: 1,
        name: LocalizedText('Heatmap', pl: 'Mapa ciepła'),
        description: LocalizedText(
          'Wandering heat sources whose warmth spreads and cools over the grid.',
          pl: 'Wędrujące źródła ciepła, których żar rozchodzi się i stygnie na siatce.',
        ),
        category: GeneratorCategory.nature,
      );

  @override
  List<ParamSpec> get params => const [
        IntParam(id: 'sources', label: LocalizedText('Sources', pl: 'Źródła'), min: 1, max: 8, defaultValue: 3),
        speedParam,
        NumberParam(
          id: 'diffusion',
          label: LocalizedText('Spread', pl: 'Rozchodzenie'),
          min: 0,
          max: 1,
          defaultValue: 0.5,
          step: 0.01,
        ),
        NumberParam(
          id: 'cooling',
          label: LocalizedText('Cooling', pl: 'Stygnięcie'),
          min: 0.1,
          max: 5,
          defaultValue: 1,
          scale: NumberScale.log,
          unit: '/s',
        ),
        PaletteParam(id: 'palette', label: paletteLabel, defaultValue: Palette.fire),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _HeatmapInstance(setup.xCount, setup.yCount);
}

final class _HeatSource {
  final double fx, fy, px, py;

  _HeatSource(this.fx, this.fy, this.px, this.py);
}

final class _HeatmapInstance implements GeneratorInstance {
  final int xCount, yCount;
  final Float64List heat;
  final Float64List _next;
  final sources = <_HeatSource>[];

  _HeatmapInstance(this.xCount, this.yCount)
      : heat = Float64List(xCount * yCount),
        _next = Float64List(xCount * yCount);

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final random = ctx.random;
    final dt = ctx.deltaSeconds;
    final count = p.integer('sources');
    while (sources.length < count) {
      sources.add(_HeatSource(
        0.05 + random.nextDouble() * 0.2,
        0.05 + random.nextDouble() * 0.2,
        random.nextDouble() * math.pi * 2,
        random.nextDouble() * math.pi * 2,
      ));
    }
    if (sources.length > count) sources.removeRange(count, sources.length);
    final t = ctx.seconds * p.number('speed');
    final cooling = math.exp(-p.number('cooling') * dt);
    final diffusion = (p.number('diffusion') * math.min(1.0, dt * 12)).clamp(0.0, 0.5);
    for (var x = 0; x < xCount; x++) {
      for (var y = 0; y < yCount; y++) {
        final i = x * yCount + y;
        var sum = 0.0;
        var n = 0;
        if (x > 0) {
          sum += heat[i - yCount];
          n++;
        }
        if (x + 1 < xCount) {
          sum += heat[i + yCount];
          n++;
        }
        if (y > 0) {
          sum += heat[i - 1];
          n++;
        }
        if (y + 1 < yCount) {
          sum += heat[i + 1];
          n++;
        }
        final blurred = n == 0 ? heat[i] : heat[i] + (sum / n - heat[i]) * diffusion;
        _next[i] = blurred * cooling;
      }
    }
    heat.setAll(0, _next);
    for (final s in sources) {
      final sx = (xCount - 1) * (0.5 + 0.45 * math.sin(t * s.fx * 2 * math.pi + s.px));
      final sy = (yCount - 1) * (0.5 + 0.45 * math.sin(t * s.fy * 2 * math.pi + s.py));
      for (var x = math.max(0, sx.floor() - 1); x <= sx.ceil() + 1 && x < xCount; x++) {
        for (var y = math.max(0, sy.floor() - 1); y <= sy.ceil() + 1 && y < yCount; y++) {
          final d = math.sqrt((x - sx) * (x - sx) + (y - sy) * (y - sy));
          final i = x * yCount + y;
          heat[i] = math.min(1.0, heat[i] + falloff(d, 1.6) * math.max(dt, 1 / 60) * 6);
        }
      }
    }
    final palette = p.palette('palette');
    final brightness = p.number('brightness');
    for (var i = 0; i < heat.length; i++) {
      out.setPixelColorAtIndex(i, dim(palette.sample(heat[i]), brightness));
    }
    applyPanelMode(out, panelModeOf(p));
  }
}

/// A brightness mask: a gradient, edge fade or spotlight, meant for the
/// Multiply blend on an upper track.
final class VignetteGenerator implements Generator {
  const VignetteGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.vignette',
        version: 1,
        name: LocalizedText('Mask', pl: 'Maska'),
        description: LocalizedText(
          'A soft brightness mask (gradient, edge fade or spotlight) to multiply over another track.',
          pl: 'Miękka maska jasności (gradient, ściemnione brzegi lub reflektor) do mnożenia z inną ścieżką.',
        ),
        category: GeneratorCategory.geometry,
      );

  @override
  List<ParamSpec> get params => const [
        ChoiceParam(
          id: 'shape',
          label: LocalizedText('Shape', pl: 'Kształt'),
          options: [
            ChoiceOption('spotlight', LocalizedText('Spotlight', pl: 'Reflektor')),
            ChoiceOption('vertical', LocalizedText('Band along the icicles', pl: 'Pas wzdłuż sopli')),
            ChoiceOption('horizontal', LocalizedText('Band across the icicles', pl: 'Pas w poprzek sopli')),
            ChoiceOption('edges', LocalizedText('Edge fade', pl: 'Ściemnione brzegi')),
          ],
          defaultValue: 'spotlight',
        ),
        NumberParam(
          id: 'position',
          label: LocalizedText('Position', pl: 'Położenie'),
          description: LocalizedText('Center of the spotlight or band.', pl: 'Środek reflektora lub pasa.'),
          min: 0,
          max: 1,
          defaultValue: 0.5,
          step: 0.01,
        ),
        NumberParam(
            id: 'size',
            label: LocalizedText('Size', pl: 'Wielkość'),
            min: 0.05,
            max: 1.5,
            defaultValue: 0.5,
            step: 0.01),
        NumberParam(
            id: 'softness',
            label: LocalizedText('Softness', pl: 'Miękkość'),
            min: 0,
            max: 1,
            defaultValue: 0.5,
            step: 0.01),
        BoolParam(id: 'invert', label: LocalizedText('Invert', pl: 'Odwróć'), defaultValue: false),
        ColorParam(id: 'color', label: colorLabel, defaultValue: Color(0xFFFFFFFF)),
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => const _VignetteInstance();
}

final class _VignetteInstance implements GeneratorInstance {
  const _VignetteInstance();

  /// 1 within [size] of [center], fading to 0 over `softness · size`.
  static double _profile(double coordinate, double center, double size, double softness) {
    final d = (coordinate - center).abs();
    final edge = size / 2;
    final feather = math.max(1e-6, softness * size);
    return 1 - smoothstep(edge - feather / 2, edge + feather / 2, d);
  }

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final shape = p.choice('shape');
    final position = p.number('position');
    final size = p.number('size');
    final softness = p.number('softness');
    final invert = p.flag('invert');
    final color = p.color('color');
    for (var x = 0; x < ctx.xCount; x++) {
      for (var y = 0; y < ctx.yCount; y++) {
        final nx = ctx.nx(x);
        final ny = ctx.ny(y);
        var m = switch (shape) {
          'vertical' => _profile(nx, position, size, softness),
          'horizontal' => _profile(ny, position, size, softness),
          'edges' => _profile(nx, 0.5, 1 + size, softness) * _profile(ny, 0.5, 1 + size, softness),
          _ => _profile(math.sqrt((nx - position) * (nx - position) + (ny - 0.5) * (ny - 0.5)), 0, size, softness),
        };
        if (invert) m = 1 - m;
        out.setPixelColor(x, y, dim(color, m));
      }
    }
    applyPanelMode(out, panelModeOf(p));
  }
}
