import 'dart:math' as math;
import 'dart:typed_data';

/// An in-place iterative radix-2 complex FFT of a fixed power-of-two size.
final class Fft {
  final int size;
  final Float64List _cos;
  final Float64List _sin;
  final Int32List _reversed;

  factory Fft(int size) {
    if (size < 2 || size & (size - 1) != 0) {
      throw ArgumentError.value(size, 'size', 'Must be a power of two ≥ 2.');
    }
    final half = size ~/ 2;
    final cos = Float64List(half);
    final sin = Float64List(half);
    for (var i = 0; i < half; i++) {
      final angle = -2 * math.pi * i / size;
      cos[i] = math.cos(angle);
      sin[i] = math.sin(angle);
    }
    final bits = size.bitLength - 1;
    final reversed = Int32List(size);
    for (var i = 0; i < size; i++) {
      var r = 0;
      for (var b = 0; b < bits; b++) {
        r |= ((i >> b) & 1) << (bits - 1 - b);
      }
      reversed[i] = r;
    }
    return Fft._(size, cos, sin, reversed);
  }

  Fft._(this.size, this._cos, this._sin, this._reversed);

  /// Transforms ([re], [im]) of length [size] in place.
  void transform(Float64List re, Float64List im) {
    final n = size;
    for (var i = 0; i < n; i++) {
      final j = _reversed[i];
      if (j > i) {
        final tr = re[i];
        re[i] = re[j];
        re[j] = tr;
        final ti = im[i];
        im[i] = im[j];
        im[j] = ti;
      }
    }
    for (var length = 2; length <= n; length <<= 1) {
      final halfLength = length >> 1;
      final step = n ~/ length;
      for (var start = 0; start < n; start += length) {
        for (var k = 0; k < halfLength; k++) {
          final wr = _cos[k * step];
          final wi = _sin[k * step];
          final a = start + k;
          final b = a + halfLength;
          final xr = re[b] * wr - im[b] * wi;
          final xi = re[b] * wi + im[b] * wr;
          re[b] = re[a] - xr;
          im[b] = im[a] - xi;
          re[a] += xr;
          im[a] += xi;
        }
      }
    }
  }
}
