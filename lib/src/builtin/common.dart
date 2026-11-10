import 'dart:math' as math;

import 'package:icicles_animation_dart/icicles_animation_dart.dart';

import '../generator/generator.dart';
import '../generator/localized_text.dart';
import '../params/param_spec.dart';
import '../util/color.dart';
import '../util/direction.dart';

/// Parameters shared by several built-in generators.
const brightnessParam = NumberParam(
  id: 'brightness',
  label: LocalizedText('Brightness', pl: 'Jasność'),
  min: 0,
  max: 1,
  defaultValue: 1,
  step: 0.01,
);

const speedParam = NumberParam(
  id: 'speed',
  label: LocalizedText('Speed', pl: 'Prędkość'),
  min: 0.05,
  max: 5,
  defaultValue: 1,
  scale: NumberScale.log,
  unit: '×',
);

const scaleParam = NumberParam(
  id: 'scale',
  label: LocalizedText('Scale', pl: 'Skala'),
  description: LocalizedText('Size of the pattern.', pl: 'Wielkość wzoru.'),
  min: 0.25,
  max: 4,
  defaultValue: 1,
  scale: NumberScale.log,
  unit: '×',
);

const gainParam = NumberParam(
  id: 'gain',
  label: LocalizedText('Sensitivity', pl: 'Czułość'),
  min: 0.25,
  max: 4,
  defaultValue: 1,
  scale: NumberScale.log,
  unit: '×',
);

const paletteLabel = LocalizedText('Palette', pl: 'Paleta');
const colorLabel = LocalizedText('Color', pl: 'Kolor');

const axisParam = ChoiceParam(
  id: 'direction',
  label: LocalizedText('Direction', pl: 'Kierunek'),
  options: [
    ChoiceOption('horizontal', LocalizedText('Across the icicles', pl: 'Wzdłuż rzędu sopli')),
    ChoiceOption('vertical', LocalizedText('Along the icicles', pl: 'Wzdłuż sopla')),
    ChoiceOption('diagonal', LocalizedText('Diagonal', pl: 'Po skosie')),
  ],
  defaultValue: 'horizontal',
);

/// Black.
const black = Color(0xFF000000);

/// Smooth falloff: 1 at distance 0, 0 at [radius] and beyond.
double falloff(double distance, double radius) {
  if (radius <= 0) return distance <= 0 ? 1 : 0;
  final d = (distance.abs() / radius).clamp(0.0, 1.0);
  return (1 - d * d) * (1 - d * d);
}

/// Hermite step: 0 at [x] ≤ [edge0], 1 at ≥ [edge1], smooth between.
double smoothstep(double edge0, double edge1, double x) {
  if (edge1 <= edge0) return x < edge0 ? 0 : 1;
  final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// `0..1` triangle wave of [phase] (`0` at integers, `1` at halves).
double triangle(double phase) {
  final p = phase - phase.floor();
  return p < 0.5 ? p * 2 : 2 - p * 2;
}

/// The exponential decay factor of a one-pole fade with time constant
/// [seconds] over [dt] (1 for a non-positive constant… 0, i.e. instant).
double decayFactor(double seconds, double dt) => seconds <= 0 ? 0 : math.exp(-dt / seconds);

/// The coordinate of ([x], [y]) along [direction], `0..1`: 0 where the motion
/// starts (e.g. the roof for [Direction.down]), 1 where it ends. Radial
/// directions use the Chebyshev distance from the center.
double directionCoordinate(FrameContext ctx, Direction direction, int x, int y) => switch (direction) {
      Direction.down => ctx.ny(y),
      Direction.up => 1 - ctx.ny(y),
      Direction.right => ctx.nx(x),
      Direction.left => 1 - ctx.nx(x),
      Direction.outward => math.max((2 * ctx.nx(x) - 1).abs(), (2 * ctx.ny(y) - 1).abs()),
      Direction.inward => 1 - math.max((2 * ctx.nx(x) - 1).abs(), (2 * ctx.ny(y) - 1).abs()),
    };

/// Adds [color] scaled by [intensity] to the pixel ([x], [y]) of [out].
void addPixel(Icicles out, int x, int y, Color color, double intensity) {
  if (intensity <= 0) return;
  out.setPixelColor(x, y, addColors(out.getPixelColor(x, y), dim(color, intensity)));
}

/// An expanding ring, drawn by [drawRings].
final class Ring {
  /// Center in pixel units.
  final double x, y;

  /// Radius growth in pixels per second.
  final double speed;

  /// Lifetime in seconds.
  final double life;
  final Color color;

  /// Seconds since the ring was emitted.
  double age = 0;

  Ring({required this.x, required this.y, required this.speed, required this.life, required this.color});
}

/// Ages [rings] by [dt], drops the dead ones and draws the rest additively
/// over [out] (cleared first) as rings of [thickness] pixels fading with
/// age.
void drawRings(FrameContext ctx, Icicles out, List<Ring> rings, double dt, double thickness, double brightness) {
  out.setAllPixelsColor(black);
  for (var i = rings.length - 1; i >= 0; i--) {
    rings[i].age += dt;
    if (rings[i].age >= rings[i].life) rings.removeAt(i);
  }
  for (final ring in rings) {
    final radius = ring.age * ring.speed;
    final fade = 1 - ring.age / ring.life;
    final reach = radius + thickness + 1;
    for (var x = math.max(0, (ring.x - reach).floor()); x <= (ring.x + reach).ceil() && x < ctx.xCount; x++) {
      for (var y = math.max(0, (ring.y - reach).floor()); y <= (ring.y + reach).ceil() && y < ctx.yCount; y++) {
        final d = math.sqrt((x - ring.x) * (x - ring.x) + (y - ring.y) * (y - ring.y));
        addPixel(out, x, y, ring.color, falloff(d - radius, thickness) * fade * brightness);
      }
    }
  }
}
