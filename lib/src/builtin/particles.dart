import 'dart:math' as math;
import 'dart:typed_data';

import 'package:icicles_animation_dart/icicles_animation_dart.dart';

import '../generator/generator.dart';
import '../generator/generator_info.dart';
import '../generator/localized_text.dart';
import '../params/param_spec.dart';
import '../util/color.dart';
import '../util/panel_mode.dart';
import 'common.dart';

/// Random twinkling sparks (ported from `sparks` and the firmware's
/// Sparkling).
final class SparksGenerator implements Generator {
  const SparksGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.sparks',
        version: 1,
        name: LocalizedText('Sparks', pl: 'Iskry'),
        description:
            LocalizedText('LEDs flashing at random and fading out.', pl: 'Losowo rozbłyskujące i gasnące diody.'),
        category: GeneratorCategory.particles,
      );

  @override
  List<ParamSpec> get params => const [
        NumberParam(
          id: 'density',
          label: LocalizedText('Density', pl: 'Gęstość'),
          description: LocalizedText('Sparks per LED and second.', pl: 'Iskry na diodę i sekundę.'),
          min: 0.01,
          max: 2,
          defaultValue: 0.15,
          scale: NumberScale.log,
          unit: '/s',
        ),
        NumberParam(
          id: 'fade',
          label: LocalizedText('Fade time', pl: 'Czas gaśnięcia'),
          min: 0.05,
          max: 3,
          defaultValue: 0.5,
          scale: NumberScale.log,
          unit: 's',
        ),
        ColorParam(id: 'color', label: colorLabel, defaultValue: Color(0xFFFFE0A0)),
        BoolParam(id: 'rainbow', label: LocalizedText('Random colors', pl: 'Losowe kolory'), defaultValue: false),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _SparksInstance(setup.pixelsCount);
}

final class _SparksInstance implements GeneratorInstance {
  final Float64List energy;
  final List<Color> colors;

  _SparksInstance(int pixels)
      : energy = Float64List(pixels),
        colors = List.filled(pixels, black);

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final random = ctx.random;
    final dt = ctx.deltaSeconds;
    final decay = math.exp(-dt / p.number('fade'));
    final chance = 1 - math.exp(-p.number('density') * math.max(dt, 1 / 60));
    final rainbow = p.flag('rainbow');
    final color = p.color('color');
    final brightness = p.number('brightness');
    for (var i = 0; i < energy.length; i++) {
      energy[i] *= decay;
      if (random.nextDouble() < chance) {
        energy[i] = 0.6 + random.nextDouble() * 0.4;
        colors[i] = rainbow ? hsv(random.nextDouble(), 1, 1) : color;
      }
      out.setPixelColorAtIndex(i, dim(colors[i], energy[i] * brightness));
    }
    applyPanelMode(out, panelModeOf(p));
  }
}

/// Glowing fireflies wandering and blinking (ported from `fireflies`).
final class FirefliesGenerator implements Generator {
  const FirefliesGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.fireflies',
        version: 1,
        name: LocalizedText('Fireflies', pl: 'Świetliki'),
        description: LocalizedText('Soft lights drifting and pulsing.', pl: 'Miękkie światełka dryfujące i pulsujące.'),
        category: GeneratorCategory.particles,
      );

  @override
  List<ParamSpec> get params => const [
        IntParam(
            id: 'count', label: LocalizedText('Fireflies', pl: 'Liczba świetlików'), min: 1, max: 40, defaultValue: 8),
        speedParam,
        NumberParam(
          id: 'size',
          label: LocalizedText('Glow size', pl: 'Wielkość poświaty'),
          min: 0.5,
          max: 4,
          defaultValue: 1.5,
          step: 0.1,
          unit: 'px',
        ),
        ColorParam(id: 'color', label: colorLabel, defaultValue: Color(0xFFC8FF40)),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _FirefliesInstance();
}

final class _Firefly {
  double x, y, vx, vy, phase, rate;

  _Firefly(this.x, this.y, this.vx, this.vy, this.phase, this.rate);
}

final class _FirefliesInstance implements GeneratorInstance {
  final flies = <_Firefly>[];

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final random = ctx.random;
    final count = p.integer('count');
    final width = ctx.xCount.toDouble();
    final height = ctx.yCount.toDouble();
    while (flies.length < count) {
      flies.add(_Firefly(
        random.nextDouble() * width,
        random.nextDouble() * height,
        random.nextDouble() * 2 - 1,
        random.nextDouble() * 2 - 1,
        random.nextDouble() * math.pi * 2,
        0.6 + random.nextDouble() * 1.2,
      ));
    }
    if (flies.length > count) flies.removeRange(count, flies.length);
    final dt = ctx.deltaSeconds;
    final speed = p.number('speed') * 2;
    final radius = p.number('size');
    final color = p.color('color');
    final brightness = p.number('brightness');
    final glow = Float64List(ctx.xCount * ctx.yCount);
    for (final fly in flies) {
      fly.vx = (fly.vx + (random.nextDouble() - 0.5) * 2 * dt).clamp(-1.0, 1.0);
      fly.vy = (fly.vy + (random.nextDouble() - 0.5) * 2 * dt).clamp(-1.0, 1.0);
      fly.x += fly.vx * speed * dt;
      fly.y += fly.vy * speed * dt;
      if (fly.x < 0 || fly.x > width - 1) fly.vx = -fly.vx;
      if (fly.y < 0 || fly.y > height - 1) fly.vy = -fly.vy;
      fly.x = fly.x.clamp(0, width - 1);
      fly.y = fly.y.clamp(0, height - 1);
      final pulse = math.pow(0.5 + 0.5 * math.sin(ctx.seconds * fly.rate * math.pi * 2 + fly.phase), 2).toDouble();
      final reach = radius.ceil();
      for (var x = (fly.x - reach).floor(); x <= (fly.x + reach).ceil(); x++) {
        if (x < 0 || x >= ctx.xCount) continue;
        for (var y = (fly.y - reach).floor(); y <= (fly.y + reach).ceil(); y++) {
          if (y < 0 || y >= ctx.yCount) continue;
          final d = math.sqrt((x - fly.x) * (x - fly.x) + (y - fly.y) * (y - fly.y));
          glow[x * ctx.yCount + y] += falloff(d, radius) * pulse;
        }
      }
    }
    for (var i = 0; i < glow.length; i++) {
      out.setPixelColorAtIndex(i, dim(color, math.min(1.0, glow[i]) * brightness));
    }
    applyPanelMode(out, panelModeOf(p));
  }
}
