import 'package:icicles_animation_dart/icicles_animation_dart.dart';

/// An opaque color from HSV components.
///
/// [hue] is in turns (`0..1`, wrapped, so `1.25` is `0.25`), [saturation]
/// and [value] in `0..1` (clamped). A wrapper over [Color.fromAHSL], whose
/// "lightness" is the HSV value.
Color hsv(double hue, double saturation, double value) {
  var h = hue.isFinite ? hue % 1.0 : 0.0;
  if (h < 0) h += 1.0;
  final s = saturation.isFinite ? saturation.clamp(0.0, 1.0) : 0.0;
  final v = value.isFinite ? value.clamp(0.0, 1.0) : 0.0;
  return Color.fromAHSL(1.0, h * 360.0, s, v);
}

/// [color] with its RGB channels scaled by [factor] (clamped to `0..1`),
/// opaque.
Color dim(Color color, double factor) {
  final f = factor.isFinite ? factor.clamp(0.0, 1.0) : 0.0;
  return Color.fromRGB((color.red * f).round(), (color.green * f).round(), (color.blue * f).round());
}

/// Channel-wise sum of [a] and [b], clamped to `255`, opaque.
Color addColors(Color a, Color b) => Color.fromRGB(
      (a.red + b.red).clamp(0, 255),
      (a.green + b.green).clamp(0, 255),
      (a.blue + b.blue).clamp(0, 255),
    );

/// Linear RGB interpolation from [a] to [b] by [t] (clamped), opaque.
Color mixColors(Color a, Color b, double t) {
  final f = t.isFinite ? t.clamp(0.0, 1.0) : 0.0;
  return Color.fromRGB(
    (a.red + (b.red - a.red) * f).round(),
    (a.green + (b.green - a.green) * f).round(),
    (a.blue + (b.blue - a.blue) * f).round(),
  );
}

/// `#rrggbb` of [color] (alpha dropped).
String colorToHex(Color color) => '#${(color.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// An opaque color from `#rrggbb` (or `rrggbb`), `null` when malformed.
Color? colorFromHex(String text) {
  final hex = text.startsWith('#') ? text.substring(1) : text;
  if (hex.length != 6) return null;
  final value = int.tryParse(hex, radix: 16);
  if (value == null || value < 0) return null;
  return Color(0xFF000000 | value);
}

/// The HSV components of [color]: `hue` in turns (`0..1`), `saturation` and
/// `value` in `0..1` (the inverse of [hsv]; the hue of a grey is 0).
({double hue, double saturation, double value}) hsvOf(Color color) {
  final r = color.red / 255, g = color.green / 255, b = color.blue / 255;
  final max = r > g ? (r > b ? r : b) : (g > b ? g : b);
  final min = r < g ? (r < b ? r : b) : (g < b ? g : b);
  final delta = max - min;
  var hue = 0.0;
  if (delta > 0) {
    if (max == r) {
      hue = ((g - b) / delta) % 6;
    } else if (max == g) {
      hue = (b - r) / delta + 2;
    } else {
      hue = (r - g) / delta + 4;
    }
    hue /= 6;
    if (hue < 0) hue += 1;
  }
  return (hue: hue, saturation: max <= 0 ? 0.0 : delta / max, value: max);
}

/// The relative luminance of [color] (`0..1`, Rec. 709 weights on the gamma
/// encoded channels — a perceptual brightness, not a linear-light one).
double luma(Color color) => (0.2126 * color.red + 0.7152 * color.green + 0.0722 * color.blue) / 255;

/// An opaque color from channel values in `0..1` (clamped, rounded).
Color colorFromUnit(double r, double g, double b) => Color.fromRGB(_channel(r), _channel(g), _channel(b));

int _channel(double v) => v.isFinite ? (v * 255).round().clamp(0, 255) : 0;
