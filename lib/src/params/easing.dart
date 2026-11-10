import 'package:equatable/equatable.dart';
import 'package:icicles_animation_dart/icicles_animation_dart.dart';

/// The preset easings of a [Keyframe]'s segment.
enum EasingPreset {
  /// The key's value until the next key (a step).
  hold,
  linear,

  /// The library's `Curves.cubicIn`.
  easeIn,

  /// The library's `Curves.cubicOut`.
  easeOut,

  /// The library's `Curves.cubicInOut`.
  easeInOut,
}

/// How a keyframe segment progresses from a key's value to the next key's:
/// a preset ([Easing.hold], [Easing.linear], [Easing.easeIn],
/// [Easing.easeOut], [Easing.easeInOut]) or a CSS-style cubic
/// [Easing.bezier].
sealed class Easing extends Equatable {
  const Easing();

  static const Easing hold = PresetEasing(EasingPreset.hold);
  static const Easing linear = PresetEasing(EasingPreset.linear);
  static const Easing easeIn = PresetEasing(EasingPreset.easeIn);
  static const Easing easeOut = PresetEasing(EasingPreset.easeOut);
  static const Easing easeInOut = PresetEasing(EasingPreset.easeInOut);

  /// A cubic Bézier through `(0,0)`, `(x1,y1)`, `(x2,y2)`, `(1,1)` (the CSS
  /// `cubic-bezier`); `x1`/`x2` are clamped to `0..1` at evaluation so the
  /// curve is a function of time.
  const factory Easing.bezier(double x1, double y1, double x2, double y2) = BezierEasing;

  /// The eased progress (`0` at the key, `1` at the next key) of the linear
  /// progress [p] (`0..1`).
  double transform(double p);

  /// This easing with its fields in their valid ranges.
  Easing normalized() => this;
}

/// One of the [EasingPreset]s.
final class PresetEasing extends Easing {
  final EasingPreset preset;

  const PresetEasing(this.preset);

  @override
  double transform(double p) {
    final t = p.isFinite ? p.clamp(0.0, 1.0) : 0.0;
    return switch (preset) {
      EasingPreset.hold => t < 1 ? 0.0 : 1.0,
      EasingPreset.linear => t,
      EasingPreset.easeIn => Curves.cubicIn.transform(t),
      EasingPreset.easeOut => Curves.cubicOut.transform(t),
      EasingPreset.easeInOut => Curves.cubicInOut.transform(t),
    };
  }

  @override
  List<Object?> get props => [preset];
}

/// A cubic Bézier easing (see [Easing.bezier]).
final class BezierEasing extends Easing {
  /// Range of [y1]/[y2] (overshoot allowed, within reason).
  static const minY = -1.0;
  static const maxY = 2.0;

  final double x1;
  final double y1;
  final double x2;
  final double y2;

  const BezierEasing(this.x1, this.y1, this.x2, this.y2);

  @override
  Easing normalized() => BezierEasing(_x(x1), _y(y1), _x(x2), _y(y2));

  static double _x(double v) => v.isFinite ? v.clamp(0.0, 1.0) : 0.0;

  static double _y(double v) => v.isFinite ? v.clamp(minY, maxY) : 0.0;

  @override
  double transform(double p) {
    final x = p.isFinite ? p.clamp(0.0, 1.0) : 0.0;
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    final ax = _x(x1), bx = _x(x2), ay = _y(y1), by = _y(y2);
    return _bezier(ay, by, _solve(ax, bx, x));
  }

  static double _bezier(double p1, double p2, double t) {
    final u = 1 - t;
    return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t;
  }

  /// The parameter `t` with `x(t) == x`: Newton steps, then bisection when
  /// the derivative is too flat.
  static double _solve(double p1, double p2, double x) {
    var t = x;
    for (var i = 0; i < 8; i++) {
      final error = _bezier(p1, p2, t) - x;
      if (error.abs() < 1e-7) return t;
      final u = 1 - t;
      final slope = 3 * u * u * p1 + 6 * u * t * (p2 - p1) + 3 * t * t * (1 - p2);
      if (slope.abs() < 1e-6) break;
      t -= error / slope;
      if (t < 0 || t > 1) break;
    }
    var lo = 0.0, hi = 1.0;
    t = x;
    for (var i = 0; i < 40; i++) {
      final error = _bezier(p1, p2, t) - x;
      if (error.abs() < 1e-7) return t;
      if (error > 0) {
        hi = t;
      } else {
        lo = t;
      }
      t = (lo + hi) / 2;
    }
    return t;
  }

  @override
  List<Object?> get props => [x1, y1, x2, y2];
}
