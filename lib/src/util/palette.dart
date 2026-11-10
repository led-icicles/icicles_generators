import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:icicles_animation_dart/icicles_animation_dart.dart';

import 'color.dart';

/// One color of a [Palette] at [position] (`0..1`).
final class PaletteStop extends Equatable {
  final double position;
  final Color color;

  const PaletteStop(this.position, this.color);

  @override
  List<Object?> get props => [position, color];
}

/// A color gradient sampled by generators (WLED/LedFx-style palettes).
final class Palette extends Equatable {
  /// Stops sorted by position; at least one.
  final List<PaletteStop> stops;

  const Palette(this.stops);

  static const rainbow = Palette([
    PaletteStop(0.0, Color(0xFFFF0000)),
    PaletteStop(1 / 6, Color(0xFFFFFF00)),
    PaletteStop(2 / 6, Color(0xFF00FF00)),
    PaletteStop(3 / 6, Color(0xFF00FFFF)),
    PaletteStop(4 / 6, Color(0xFF0000FF)),
    PaletteStop(5 / 6, Color(0xFFFF00FF)),
    PaletteStop(1.0, Color(0xFFFF0000)),
  ]);

  static const ice = Palette([
    PaletteStop(0.0, Color(0xFF000820)),
    PaletteStop(0.4, Color(0xFF0040C0)),
    PaletteStop(0.75, Color(0xFF60C8FF)),
    PaletteStop(1.0, Color(0xFFFFFFFF)),
  ]);

  static const fire = Palette([
    PaletteStop(0.0, Color(0xFF000000)),
    PaletteStop(0.35, Color(0xFFC00000)),
    PaletteStop(0.6, Color(0xFFFF5000)),
    PaletteStop(0.85, Color(0xFFFFC000)),
    PaletteStop(1.0, Color(0xFFFFFFC0)),
  ]);

  static const ocean = Palette([
    PaletteStop(0.0, Color(0xFF000030)),
    PaletteStop(0.35, Color(0xFF0030A0)),
    PaletteStop(0.65, Color(0xFF0090A0)),
    PaletteStop(1.0, Color(0xFF40FFE0)),
  ]);

  static const aurora = Palette([
    PaletteStop(0.0, Color(0xFF002010)),
    PaletteStop(0.3, Color(0xFF20B450)),
    PaletteStop(0.6, Color(0xFF30C8A0)),
    PaletteStop(0.85, Color(0xFF6040C0)),
    PaletteStop(1.0, Color(0xFFB040A0)),
  ]);

  static const party = Palette([
    PaletteStop(0.0, Color(0xFF5500AB)),
    PaletteStop(0.25, Color(0xFFFF0080)),
    PaletteStop(0.5, Color(0xFFFF8000)),
    PaletteStop(0.75, Color(0xFF00C0FF)),
    PaletteStop(1.0, Color(0xFF5500AB)),
  ]);

  /// The built-in palettes by id.
  static const presets = <String, Palette>{
    'rainbow': rainbow,
    'ice': ice,
    'fire': fire,
    'ocean': ocean,
    'aurora': aurora,
    'party': party,
  };

  /// The color at [t]: clamped to `0..1`, or wrapped when [wrap] is set.
  Color sample(double t, {bool wrap = false}) {
    if (stops.isEmpty) return const Color(0xFF000000);
    var p = t.isFinite ? t : 0.0;
    if (wrap) {
      p %= 1.0;
      if (p < 0) p += 1.0;
    } else {
      p = p.clamp(0.0, 1.0);
    }
    final first = stops.first;
    if (p <= first.position) return first.color;
    for (var i = 1; i < stops.length; i++) {
      final stop = stops[i];
      if (p <= stop.position) {
        final previous = stops[i - 1];
        final span = stop.position - previous.position;
        return span <= 0 ? stop.color : mixColors(previous.color, stop.color, (p - previous.position) / span);
      }
    }
    return stops.last.color;
  }

  /// This palette with stops clamped to `0..1` and sorted, or `null` when it
  /// has no stops.
  Palette? normalized() {
    if (stops.isEmpty) return null;
    final sorted = [
      for (final stop in stops) PaletteStop(stop.position.isFinite ? stop.position.clamp(0.0, 1.0) : 0.0, stop.color),
    ];
    mergeSort(sorted, compare: (a, b) => a.position.compareTo(b.position));
    return Palette(List.unmodifiable(sorted));
  }

  @override
  List<Object?> get props => [stops];
}
