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

/// Fire2012 on every icicle.
final class FireGenerator implements Generator {
  const FireGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.fire',
        version: 1,
        name: LocalizedText('Fire', pl: 'Ogień'),
        description: LocalizedText(
          'Flames on every icicle (Fire2012), rising from the tip or pouring from the roof.',
          pl: 'Płomienie na każdym soplu (Fire2012), od końca w górę lub od dachu w dół.',
        ),
        category: GeneratorCategory.nature,
      );

  static final _direction = directionParam(
    options: const [Direction.up, Direction.down],
    defaultValue: Direction.up,
    description: const LocalizedText('Up: flames rise from the tips.', pl: 'W górę: płomienie wznoszą się od końców.'),
  );

  @override
  List<ParamSpec> get params => [
        const NumberParam(
          id: 'cooling',
          label: LocalizedText('Cooling', pl: 'Chłodzenie'),
          description: LocalizedText('Higher: shorter flames.', pl: 'Więcej: krótsze płomienie.'),
          min: 10,
          max: 120,
          defaultValue: 55,
          step: 1,
        ),
        const NumberParam(
          id: 'sparking',
          label: LocalizedText('Sparking', pl: 'Iskrzenie'),
          description: LocalizedText('Chance of a new spark per step.', pl: 'Szansa na nową iskrę w kroku.'),
          min: 0.1,
          max: 1,
          defaultValue: 0.5,
          step: 0.01,
        ),
        _direction,
        const PaletteParam(id: 'palette', label: paletteLabel, defaultValue: Palette.fire),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _FireInstance(setup.xCount, setup.yCount);
}

final class _FireInstance implements GeneratorInstance {
  /// Simulation steps per second, as in the original.
  static const stepRate = 30.0;

  final int xCount, yCount;

  /// Heat per cell, `0..255`, cell 0 at the base of the flame.
  final Float64List heat;
  double _pending = 1;

  _FireInstance(this.xCount, this.yCount) : heat = Float64List(xCount * yCount);

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final random = ctx.random;
    final cooling = p.number('cooling');
    final sparking = p.number('sparking');
    _pending += ctx.deltaSeconds * stepRate;
    while (_pending >= 1) {
      _pending -= 1;
      _step(random, cooling, sparking);
    }
    final up = directionOf(p) == Direction.up;
    final palette = p.palette('palette');
    final brightness = p.number('brightness');
    for (var x = 0; x < xCount; x++) {
      for (var k = 0; k < yCount; k++) {
        final y = up ? yCount - 1 - k : k;
        out.setPixelColor(x, y, dim(palette.sample(heat[x * yCount + k] / 255), brightness));
      }
    }
    applyPanelMode(out, panelModeOf(p));
  }

  void _step(math.Random random, double cooling, double sparking) {
    final h = yCount;
    for (var x = 0; x < xCount; x++) {
      final base = x * h;
      for (var k = 0; k < h; k++) {
        heat[base + k] = math.max(0, heat[base + k] - random.nextDouble() * (cooling * 10 / h + 2));
      }
      for (var k = h - 1; k >= 2; k--) {
        heat[base + k] = (heat[base + k - 1] + heat[base + k - 2] * 2) / 3;
      }
      if (random.nextDouble() < sparking) {
        final k = random.nextInt(math.min(3, h));
        heat[base + k] = math.min(255, heat[base + k] + 160 + random.nextDouble() * 95);
      }
    }
  }
}

/// Drops running down the icicles, swelling at the tip and dripping off.
final class IcicleDripGenerator implements Generator {
  const IcicleDripGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.icicle_drip',
        version: 1,
        name: LocalizedText('Dripping icicles', pl: 'Kapiące sople'),
        description: LocalizedText(
          'Drops run down the icicles, swell at the tip and drip off.',
          pl: 'Krople spływają po soplach, nabrzmiewają na końcu i kapią.',
        ),
        category: GeneratorCategory.nature,
      );

  @override
  List<ParamSpec> get params => const [
        NumberParam(
          id: 'rate',
          label: LocalizedText('Drops', pl: 'Krople'),
          description: LocalizedText('Drops per icicle and second.', pl: 'Krople na sopel i sekundę.'),
          min: 0.05,
          max: 2,
          defaultValue: 0.3,
          scale: NumberScale.log,
          unit: '/s',
        ),
        NumberParam(
          id: 'grow',
          label: LocalizedText('Swell time', pl: 'Czas nabrzmiewania'),
          min: 0.2,
          max: 5,
          defaultValue: 1.5,
          scale: NumberScale.log,
          unit: 's',
        ),
        NumberParam(
          id: 'gravity',
          label: LocalizedText('Gravity', pl: 'Grawitacja'),
          min: 0.5,
          max: 20,
          defaultValue: 4,
          scale: NumberScale.log,
          unit: '/s²',
        ),
        ColorParam(id: 'color', label: colorLabel, defaultValue: Color(0xFF80C8FF)),
        NumberParam(
          id: 'melt',
          label: LocalizedText('Tip glow', pl: 'Poświata końca'),
          description: LocalizedText('Constant glow at the tips.', pl: 'Stała poświata na końcach.'),
          min: 0,
          max: 1,
          defaultValue: 0.25,
          step: 0.01,
        ),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _IcicleDripInstance(setup.xCount);
}

enum _DripStage { idle, falling, swelling, dripping }

final class _DripState {
  _DripStage stage = _DripStage.idle;
  double timer = 0;
  double y = 0;
  double vy = 0;
}

final class _IcicleDripInstance implements GeneratorInstance {
  final List<_DripState> drips;
  bool _started = false;

  _IcicleDripInstance(int xCount) : drips = List.generate(xCount, (_) => _DripState());

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final random = ctx.random;
    final dt = ctx.deltaSeconds;
    final rate = p.number('rate');
    final grow = p.number('grow');
    final gravity = p.number('gravity') * ctx.yCount;
    final color = p.color('color');
    final melt = p.number('melt');
    final brightness = p.number('brightness');
    final tip = ctx.yCount - 1.0;
    if (!_started) {
      _started = true;
      for (final drip in drips) {
        drip.timer = random.nextDouble() * 2 / rate;
      }
    }
    out.setAllPixelsColor(black);
    for (var x = 0; x < ctx.xCount; x++) {
      final drip = drips[x];
      var swell = 0.0;
      switch (drip.stage) {
        case _DripStage.idle:
          drip.timer -= dt;
          if (drip.timer <= 0) {
            drip.stage = _DripStage.falling;
            drip.y = 0;
            drip.vy = 0;
          }
        case _DripStage.falling:
          drip.vy += gravity * dt;
          drip.y += drip.vy * dt;
          if (drip.y >= tip) {
            drip.y = tip;
            drip.stage = _DripStage.swelling;
            drip.timer = 0;
          }
        case _DripStage.swelling:
          drip.timer += dt;
          swell = (drip.timer / grow).clamp(0.0, 1.0);
          if (drip.timer >= grow) {
            drip.stage = _DripStage.dripping;
            drip.timer = 0;
          }
        case _DripStage.dripping:
          drip.timer += dt;
          swell = 1 - (drip.timer / 0.25).clamp(0.0, 1.0);
          if (drip.timer >= 0.25) {
            drip.stage = _DripStage.idle;
            drip.timer = -math.log(1 - random.nextDouble()) / rate;
          }
      }
      for (var y = 0; y < ctx.yCount; y++) {
        var v = melt * 0.6 * math.pow(ctx.ny(y), 3).toDouble();
        if (drip.stage == _DripStage.falling) v = math.max(v, falloff(y - drip.y, 1.5) * 0.8);
        if (swell > 0) v = math.max(v, falloff(tip - y, 0.6 + swell * 2.4) * (0.4 + 0.6 * swell));
        out.setPixelColor(x, y, dim(color, v.clamp(0.0, 1.0) * brightness));
      }
    }
    applyPanelMode(out, panelModeOf(p));
  }
}

/// Icicles freezing from the roof to the tip and thawing back.
final class IcicleGrowGenerator implements Generator {
  const IcicleGrowGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.icicle_grow',
        version: 1,
        name: LocalizedText('Growing icicles', pl: 'Rosnące sople'),
        description: LocalizedText(
          'Icicles freeze from the roof down to the tip and thaw back, each at its own pace.',
          pl: 'Sople zamarzają od dachu do końca i topnieją z powrotem, każdy w swoim tempie.',
        ),
        category: GeneratorCategory.nature,
      );

  @override
  List<ParamSpec> get params => const [
        NumberParam(
          id: 'speed',
          label: LocalizedText('Speed', pl: 'Prędkość'),
          description: LocalizedText('Icicle lengths per second.', pl: 'Długości sopla na sekundę.'),
          min: 0.05,
          max: 2,
          defaultValue: 0.3,
          scale: NumberScale.log,
          unit: '/s',
        ),
        NumberParam(
          id: 'randomness',
          label: LocalizedText('Randomness', pl: 'Losowość'),
          description: LocalizedText('Spread of the icicles\' pace and start.', pl: 'Rozrzut tempa i startu sopli.'),
          min: 0,
          max: 1,
          defaultValue: 0.5,
          step: 0.01,
        ),
        ChoiceParam(
          id: 'thaw',
          label: LocalizedText('Thaw', pl: 'Topnienie'),
          options: [
            ChoiceOption('tip', LocalizedText('From the tip', pl: 'Od końca')),
            ChoiceOption('roof', LocalizedText('From the roof', pl: 'Od dachu')),
            ChoiceOption('none', LocalizedText('Vanish and regrow', pl: 'Zniknij i rośnij od nowa')),
          ],
          defaultValue: 'tip',
        ),
        PaletteParam(id: 'palette', label: paletteLabel, defaultValue: Palette.ice),
        NumberParam(
          id: 'tipGlow',
          label: LocalizedText('Tip glow', pl: 'Poświata końca'),
          min: 0,
          max: 1,
          defaultValue: 0.5,
          step: 0.01,
        ),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _IcicleGrowInstance(setup.xCount);
}

final class _IcicleGrowInstance implements GeneratorInstance {
  final Float64List phase;
  final Float64List pace;
  bool _started = false;

  _IcicleGrowInstance(int xCount)
      : phase = Float64List(xCount),
        pace = Float64List(xCount);

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final random = ctx.random;
    final randomness = p.number('randomness');
    if (!_started) {
      _started = true;
      for (var x = 0; x < ctx.xCount; x++) {
        phase[x] = random.nextDouble();
        pace[x] = random.nextDouble();
      }
    }
    final speed = p.number('speed');
    final thaw = p.choice('thaw');
    final palette = p.palette('palette');
    final tipGlow = p.number('tipGlow');
    final brightness = p.number('brightness');
    for (var x = 0; x < ctx.xCount; x++) {
      // Phase 0..2: growing over 0..1, thawing over 1..2 (or restarting).
      final rate = speed * (1 + (pace[x] - 0.5) * randomness);
      var position = (phase[x] * randomness + rate * ctx.seconds) * (thaw == 'none' ? 1 : 0.5);
      position -= position.floor();
      final double from, to;
      if (thaw == 'none') {
        from = 0;
        to = position;
      } else if (position < 0.5) {
        from = 0;
        to = position * 2;
      } else if (thaw == 'tip') {
        from = 0;
        to = 2 - position * 2;
      } else {
        from = position * 2 - 1;
        to = 1;
      }
      final fromY = from * ctx.yCount;
      final toY = to * ctx.yCount;
      for (var y = 0; y < ctx.yCount; y++) {
        final inside = y + 0.5 >= fromY && y + 0.5 <= toY;
        final glow = falloff(y + 0.5 - toY, 1.5) * tipGlow;
        final base = inside ? palette.sample(ctx.ny(y) * 0.8) : black;
        out.setPixelColor(x, y, dim(addColors(base, dim(palette.sample(1), glow)), brightness));
      }
    }
    applyPanelMode(out, panelModeOf(p));
  }
}

/// Rain streaking down the icicles with a splash at the tip.
final class RainGenerator implements Generator {
  const RainGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.rain',
        version: 1,
        name: LocalizedText('Rain', pl: 'Deszcz'),
        description: LocalizedText(
          'Drops streaking down the icicles and splashing at the tips.',
          pl: 'Krople smużące w dół sopli i rozpryskujące się na końcach.',
        ),
        category: GeneratorCategory.nature,
      );

  @override
  List<ParamSpec> get params => const [
        NumberParam(
          id: 'density',
          label: LocalizedText('Density', pl: 'Gęstość'),
          description: LocalizedText('Drops per second.', pl: 'Krople na sekundę.'),
          min: 1,
          max: 100,
          defaultValue: 15,
          scale: NumberScale.log,
          unit: '/s',
        ),
        NumberParam(
          id: 'speed',
          label: LocalizedText('Speed', pl: 'Prędkość'),
          description: LocalizedText('Icicle lengths per second.', pl: 'Długości sopla na sekundę.'),
          min: 0.3,
          max: 6,
          defaultValue: 2,
          scale: NumberScale.log,
          unit: '/s',
        ),
        NumberParam(
          id: 'length',
          label: LocalizedText('Streak length', pl: 'Długość smugi'),
          min: 0.05,
          max: 1,
          defaultValue: 0.25,
          step: 0.01,
        ),
        BoolParam(id: 'splash', label: LocalizedText('Splash', pl: 'Rozprysk'), defaultValue: true),
        ColorParam(id: 'color', label: colorLabel, defaultValue: Color(0xFF60A0FF)),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _RainInstance(setup.xCount);
}

final class _RainDrop {
  final int x;
  double y;
  final double speed;

  _RainDrop(this.x, this.y, this.speed);
}

final class _RainInstance implements GeneratorInstance {
  final drops = <_RainDrop>[];
  final Float64List splash;
  double _pending = 0;

  _RainInstance(int xCount) : splash = Float64List(xCount);

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final random = ctx.random;
    final dt = ctx.deltaSeconds;
    final height = ctx.yCount.toDouble();
    final speed = p.number('speed') * height;
    final tail = math.max(0.5, p.number('length') * height);
    final splashing = p.flag('splash');
    final color = p.color('color');
    final brightness = p.number('brightness');
    _pending += p.number('density') * math.max(dt, 1 / 60);
    while (_pending >= 1) {
      _pending -= 1;
      drops.add(_RainDrop(random.nextInt(ctx.xCount), -random.nextDouble() * 2, 0.7 + random.nextDouble() * 0.6));
    }
    final decay = decayFactor(0.15, dt);
    out.setAllPixelsColor(black);
    for (var i = drops.length - 1; i >= 0; i--) {
      final drop = drops[i];
      final before = drop.y;
      drop.y += drop.speed * speed * dt;
      if (before < height - 1 && drop.y >= height - 1) splash[drop.x] = 1;
      if (drop.y - tail >= height) {
        drops.removeAt(i);
        continue;
      }
      for (var y = math.max(0, (drop.y - tail).floor()); y <= drop.y.floor() && y < ctx.yCount; y++) {
        final behind = drop.y - y;
        final intensity = behind <= 1 ? 1.0 : (1 - (behind - 1) / tail).clamp(0.0, 1.0);
        addPixel(out, drop.x, y, color, intensity * brightness);
      }
    }
    for (var x = 0; x < ctx.xCount; x++) {
      splash[x] *= decay;
      if (!splashing || splash[x] < 0.02) continue;
      final white = mixColors(color, const Color(0xFFFFFFFF), 0.7);
      addPixel(out, x, ctx.yCount - 1, white, splash[x] * brightness);
      if (x > 0) addPixel(out, x - 1, ctx.yCount - 1, white, splash[x] * 0.5 * brightness);
      if (x + 1 < ctx.xCount) addPixel(out, x + 1, ctx.yCount - 1, white, splash[x] * 0.5 * brightness);
    }
    applyPanelMode(out, panelModeOf(p));
  }
}

/// Rockets rising from the tips and bursting into sparks.
final class FireworksGenerator implements Generator {
  const FireworksGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.fireworks',
        version: 1,
        name: LocalizedText('Fireworks', pl: 'Fajerwerki'),
        description: LocalizedText(
          'Rockets rising from the tips and bursting into falling sparks.',
          pl: 'Rakiety wznoszące się od końców sopli i wybuchające w opadające iskry.',
        ),
        category: GeneratorCategory.particles,
      );

  @override
  List<ParamSpec> get params => const [
        NumberParam(
          id: 'rate',
          label: LocalizedText('Launches', pl: 'Wystrzały'),
          description: LocalizedText('Rockets per second.', pl: 'Rakiety na sekundę.'),
          min: 0.2,
          max: 5,
          defaultValue: 1,
          scale: NumberScale.log,
          unit: '/s',
        ),
        IntParam(
            id: 'burst',
            label: LocalizedText('Sparks per burst', pl: 'Iskry na wybuch'),
            min: 4,
            max: 60,
            defaultValue: 20),
        NumberParam(
          id: 'gravity',
          label: LocalizedText('Gravity', pl: 'Grawitacja'),
          min: 0.5,
          max: 20,
          defaultValue: 3,
          scale: NumberScale.log,
          unit: '/s²',
        ),
        NumberParam(
          id: 'fade',
          label: LocalizedText('Spark life', pl: 'Czas iskry'),
          min: 0.2,
          max: 3,
          defaultValue: 1,
          scale: NumberScale.log,
          unit: 's',
        ),
        PaletteParam(id: 'palette', label: paletteLabel, defaultValue: Palette.party),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _FireworksInstance();
}

final class _Spark {
  double x, y, vx, vy, age;
  final Color color;
  final bool rocket;

  _Spark(this.x, this.y, this.vx, this.vy, this.color, {this.rocket = false}) : age = 0;
}

final class _FireworksInstance implements GeneratorInstance {
  final sparks = <_Spark>[];
  double _pending = 0.9;

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final random = ctx.random;
    final dt = ctx.deltaSeconds;
    final height = ctx.yCount.toDouble();
    final gravity = p.number('gravity') * height;
    final life = p.number('fade');
    final burst = p.integer('burst');
    final palette = p.palette('palette');
    final brightness = p.number('brightness');
    _pending += p.number('rate') * math.max(dt, 1 / 60);
    while (_pending >= 1) {
      _pending -= 1;
      final x = 1 + random.nextDouble() * math.max(1, ctx.xCount - 2);
      // Enough speed to reach 30–80 % of the way up.
      final apex = height * (0.2 + random.nextDouble() * 0.5);
      sparks.add(_Spark(
          x, height - 1, 0, -math.sqrt(2 * gravity * (height - 1 - apex)), palette.sample(random.nextDouble()),
          rocket: true));
    }
    out.setAllPixelsColor(black);
    for (var i = sparks.length - 1; i >= 0; i--) {
      final s = sparks[i];
      s.age += dt;
      s.vy += gravity * dt;
      s.x += s.vx * dt;
      s.y += s.vy * dt;
      if (s.rocket) {
        if (s.vy >= 0) {
          sparks.removeAt(i);
          final speed = height * 0.35;
          for (var k = 0; k < burst; k++) {
            final angle = random.nextDouble() * math.pi * 2;
            final v = speed * (0.3 + random.nextDouble() * 0.7);
            sparks.add(_Spark(s.x, s.y, math.cos(angle) * v, math.sin(angle) * v, s.color));
          }
          continue;
        }
        s.vx = 0;
      } else if (s.age >= life || s.y > height + 1) {
        sparks.removeAt(i);
        continue;
      }
      final intensity = s.rocket ? 0.7 : math.pow(1 - s.age / life, 1.5).toDouble();
      final x0 = s.x.round();
      final y0 = s.y.round();
      for (var x = x0 - 1; x <= x0 + 1; x++) {
        if (x < 0 || x >= ctx.xCount) continue;
        for (var y = y0 - 1; y <= y0 + 1; y++) {
          if (y < 0 || y >= ctx.yCount) continue;
          final d = math.sqrt((x - s.x) * (x - s.x) + (y - s.y) * (y - s.y));
          addPixel(out, x, y, s.color, falloff(d, 1.2) * intensity * brightness);
        }
      }
    }
    applyPanelMode(out, panelModeOf(p));
  }
}

/// A double heartbeat pulse.
final class HeartbeatGenerator implements Generator {
  const HeartbeatGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.heartbeat',
        version: 1,
        name: LocalizedText('Heartbeat', pl: 'Bicie serca'),
        description: LocalizedText(
          'A double pulse of light at a heart rate.',
          pl: 'Podwójny puls światła w rytmie serca.',
        ),
        category: GeneratorCategory.basic,
      );

  @override
  List<ParamSpec> get params => const [
        NumberParam(
          id: 'bpm',
          label: LocalizedText('Heart rate', pl: 'Tętno'),
          min: 30,
          max: 200,
          defaultValue: 60,
          step: 1,
          unit: 'bpm',
        ),
        ColorParam(id: 'color', label: colorLabel, defaultValue: Color(0xFFFF1030)),
        NumberParam(
          id: 'decay',
          label: LocalizedText('Decay', pl: 'Wygaszanie'),
          min: 0.05,
          max: 1,
          defaultValue: 0.25,
          scale: NumberScale.log,
          unit: 's',
        ),
        ChoiceParam(
          id: 'shape',
          label: LocalizedText('Shape', pl: 'Kształt'),
          options: [
            ChoiceOption('glow', LocalizedText('Glow in the middle', pl: 'Poświata pośrodku')),
            ChoiceOption('fill', LocalizedText('Whole grid', pl: 'Cała siatka')),
          ],
          defaultValue: 'glow',
        ),
        brightnessParam,
        panelModeParamWithOwn,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => const _HeartbeatInstance();
}

final class _HeartbeatInstance implements GeneratorInstance {
  const _HeartbeatInstance();

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final period = 60 / p.number('bpm');
    final decay = p.number('decay');
    final t = ctx.seconds % period;
    var pulse = math.exp(-t / decay);
    final second = t - period * 0.22;
    if (second >= 0) pulse = math.max(pulse, 0.65 * math.exp(-second / decay));
    final color = p.color('color');
    final brightness = p.number('brightness');
    if (p.choice('shape') == 'fill') {
      out.setAllPixelsColor(dim(color, pulse * brightness));
    } else {
      final aspect = ctx.xCount / math.max(1, ctx.yCount);
      final radius = 0.45 + 0.75 * pulse;
      for (var x = 0; x < ctx.xCount; x++) {
        for (var y = 0; y < ctx.yCount; y++) {
          final dx = (ctx.nx(x) - 0.5) * 2;
          final dy = (ctx.ny(y) - 0.5) * 2 / math.max(1.0, aspect / 2);
          final d = math.sqrt(dx * dx + dy * dy);
          out.setPixelColor(x, y, dim(color, falloff(d, radius) * (0.1 + 0.9 * pulse) * brightness));
        }
      }
    }
    final mode = panelModeOf(p);
    if (mode != PanelMode.own) return applyPanelMode(out, mode);
    out.setAllRadioPanelsColor(dim(color, pulse * brightness));
  }
}
