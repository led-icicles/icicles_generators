import 'dart:math' as math;
import 'dart:typed_data';

/// Seedable 2D/3D simplex noise (after Stefan Gustavson's public domain
/// reference implementation), deterministic for a seed on every platform.
///
/// Values are in about `-1..1`; use `(n + 1) / 2` for `0..1`.
final class SimplexNoise {
  final Uint8List _perm;
  final Uint8List _permMod12;

  /// A noise field whose permutation table is shuffled from [seed].
  factory SimplexNoise([int seed = 0]) {
    final p = Uint8List(256);
    for (var i = 0; i < 256; i++) {
      p[i] = i;
    }
    // A local 32-bit LCG keeps the table independent of dart:math's Random.
    var state = (seed ^ 0x5DEECE66) & 0xFFFFFFFF;
    int next(int bound) {
      state = (state * 1664525 + 1013904223) & 0xFFFFFFFF;
      return (state >> 8) % bound;
    }

    for (var i = 255; i > 0; i--) {
      final j = next(i + 1);
      final t = p[i];
      p[i] = p[j];
      p[j] = t;
    }
    final perm = Uint8List(512);
    final permMod12 = Uint8List(512);
    for (var i = 0; i < 512; i++) {
      perm[i] = p[i & 255];
      permMod12[i] = perm[i] % 12;
    }
    return SimplexNoise._(perm, permMod12);
  }

  SimplexNoise._(this._perm, this._permMod12);

  static const _grad3 = <int>[
    1, 1, 0, -1, 1, 0, 1, -1, 0, -1, -1, 0, //
    1, 0, 1, -1, 0, 1, 1, 0, -1, -1, 0, -1, //
    0, 1, 1, 0, -1, 1, 0, 1, -1, 0, -1, -1,
  ];

  static final _f2 = 0.5 * (math.sqrt(3.0) - 1.0);
  static final _g2 = (3.0 - math.sqrt(3.0)) / 6.0;
  static const _f3 = 1.0 / 3.0;
  static const _g3 = 1.0 / 6.0;

  static int _floor(double x) {
    final i = x.toInt();
    return x < i ? i - 1 : i;
  }

  double _dot2(int gi, double x, double y) => _grad3[gi * 3] * x + _grad3[gi * 3 + 1] * y;

  double _dot3(int gi, double x, double y, double z) =>
      _grad3[gi * 3] * x + _grad3[gi * 3 + 1] * y + _grad3[gi * 3 + 2] * z;

  /// 2D simplex noise at ([x], [y]).
  double simplex2(double x, double y) {
    final s = (x + y) * _f2;
    final i = _floor(x + s);
    final j = _floor(y + s);
    final t = (i + j) * _g2;
    final x0 = x - (i - t);
    final y0 = y - (j - t);
    final i1 = x0 > y0 ? 1 : 0;
    final j1 = x0 > y0 ? 0 : 1;
    final x1 = x0 - i1 + _g2;
    final y1 = y0 - j1 + _g2;
    final x2 = x0 - 1.0 + 2.0 * _g2;
    final y2 = y0 - 1.0 + 2.0 * _g2;
    final ii = i & 255;
    final jj = j & 255;
    var n = 0.0;
    var t0 = 0.5 - x0 * x0 - y0 * y0;
    if (t0 > 0) {
      t0 *= t0;
      n += t0 * t0 * _dot2(_permMod12[ii + _perm[jj]], x0, y0);
    }
    var t1 = 0.5 - x1 * x1 - y1 * y1;
    if (t1 > 0) {
      t1 *= t1;
      n += t1 * t1 * _dot2(_permMod12[ii + i1 + _perm[jj + j1]], x1, y1);
    }
    var t2 = 0.5 - x2 * x2 - y2 * y2;
    if (t2 > 0) {
      t2 *= t2;
      n += t2 * t2 * _dot2(_permMod12[ii + 1 + _perm[jj + 1]], x2, y2);
    }
    return 70.0 * n;
  }

  /// 3D simplex noise at ([x], [y], [z]); use `z` as time for a 2D field
  /// that evolves smoothly.
  double simplex3(double x, double y, double z) {
    final s = (x + y + z) * _f3;
    final i = _floor(x + s);
    final j = _floor(y + s);
    final k = _floor(z + s);
    final t = (i + j + k) * _g3;
    final x0 = x - (i - t);
    final y0 = y - (j - t);
    final z0 = z - (k - t);
    int i1, j1, k1, i2, j2, k2;
    if (x0 >= y0) {
      if (y0 >= z0) {
        (i1, j1, k1, i2, j2, k2) = (1, 0, 0, 1, 1, 0);
      } else if (x0 >= z0) {
        (i1, j1, k1, i2, j2, k2) = (1, 0, 0, 1, 0, 1);
      } else {
        (i1, j1, k1, i2, j2, k2) = (0, 0, 1, 1, 0, 1);
      }
    } else {
      if (y0 < z0) {
        (i1, j1, k1, i2, j2, k2) = (0, 0, 1, 0, 1, 1);
      } else if (x0 < z0) {
        (i1, j1, k1, i2, j2, k2) = (0, 1, 0, 0, 1, 1);
      } else {
        (i1, j1, k1, i2, j2, k2) = (0, 1, 0, 1, 1, 0);
      }
    }
    final x1 = x0 - i1 + _g3;
    final y1 = y0 - j1 + _g3;
    final z1 = z0 - k1 + _g3;
    final x2 = x0 - i2 + 2.0 * _g3;
    final y2 = y0 - j2 + 2.0 * _g3;
    final z2 = z0 - k2 + 2.0 * _g3;
    final x3 = x0 - 1.0 + 3.0 * _g3;
    final y3 = y0 - 1.0 + 3.0 * _g3;
    final z3 = z0 - 1.0 + 3.0 * _g3;
    final ii = i & 255;
    final jj = j & 255;
    final kk = k & 255;
    var n = 0.0;
    var t0 = 0.6 - x0 * x0 - y0 * y0 - z0 * z0;
    if (t0 > 0) {
      t0 *= t0;
      n += t0 * t0 * _dot3(_permMod12[ii + _perm[jj + _perm[kk]]], x0, y0, z0);
    }
    var t1 = 0.6 - x1 * x1 - y1 * y1 - z1 * z1;
    if (t1 > 0) {
      t1 *= t1;
      n += t1 * t1 * _dot3(_permMod12[ii + i1 + _perm[jj + j1 + _perm[kk + k1]]], x1, y1, z1);
    }
    var t2 = 0.6 - x2 * x2 - y2 * y2 - z2 * z2;
    if (t2 > 0) {
      t2 *= t2;
      n += t2 * t2 * _dot3(_permMod12[ii + i2 + _perm[jj + j2 + _perm[kk + k2]]], x2, y2, z2);
    }
    var t3 = 0.6 - x3 * x3 - y3 * y3 - z3 * z3;
    if (t3 > 0) {
      t3 *= t3;
      n += t3 * t3 * _dot3(_permMod12[ii + 1 + _perm[jj + 1 + _perm[kk + 1]]], x3, y3, z3);
    }
    return 32.0 * n;
  }
}
