import 'dart:math' as math;
import 'dart:typed_data';

import 'audio_feature_key.dart';
import 'audio_features.dart';
import 'fft.dart';

/// Analyses mono PCM into [AudioFeatures] (pure and deterministic).
///
/// Every 10 ms a Hann window ([windowSizeFor] the sample rate: 2048 samples
/// at 44.1/48 kHz) centered on the hop goes through an FFT. Per row:
/// - `level`: the window-weighted RMS;
/// - `bass`/`mid`/`treble`: the amplitude in 20–250 Hz / 250–4000 Hz /
///   4–16 kHz, log-compressed;
/// - `band0…band15`: a triangular mel filterbank from 40 Hz to 16 kHz,
///   log-compressed (bands above the Nyquist frequency stay 0);
/// - `onset`: spectral flux, the mean rise of the log-compressed bins;
/// - `peakFrequency`: the loudest bin between 40 Hz and 16 kHz on a log
///   scale (0 in silence).
///
/// Then the song is normalized: each column is divided by a reference and
/// clamped to `0..1`. The reference is the column's 95th percentile, but at
/// least a quarter of its maximum (so sparse columns such as onsets are not
/// blown up) and at least a fixed floor of about −50 dBFS (so a column
/// without real content stays near 0 instead of being amplified). The 16
/// mel bands share one reference, so the spectrum keeps its shape;
/// `peakFrequency` is already `0..1` and is not normalized.
///
/// Feed samples with [add] in chunks of any size (memory is O(window) plus
/// the output rows) and call [finish] once; [extract] does both.
final class AudioFeatureExtractor {
  /// Lowest mel filterbank frequency.
  static const minBandFrequency = 40.0;

  /// Highest mel filterbank frequency.
  static const maxBandFrequency = 16000.0;

  static const _compression = 1000.0;
  static final _compressionNorm = math.log(1 + _compression);
  static const _quietAmplitude = 0.003; // about −50 dBFS
  static const _onsetFloor = 0.02;

  final int sampleRate;

  /// FFT window length in samples.
  final int windowSize;

  final Fft _fft;
  final Float64List _window;
  final double _windowSum;
  final Float64List _re;
  final Float64List _im;
  final Float64List _amplitudes;
  final Float64List _logAmplitudes;
  final Float64List _previousLog;
  final _BinRanges _ranges;
  final List<_MelFilter> _filters;

  // Pending input: _buffer[0] is absolute sample _bufferStart.
  Float32List _buffer = Float32List(0);
  int _bufferLength = 0;
  int _bufferStart = 0;
  int _received = 0;
  int _nextFrame = 0;
  bool _hasPrevious = false;
  bool _finished = false;

  Float32List _rows = Float32List(AudioFeatureKey.columnCount * 1024);

  /// An extractor for PCM at [sampleRate] Hz (any rate ≥ 1000).
  factory AudioFeatureExtractor(int sampleRate) {
    if (sampleRate < 1000) throw ArgumentError.value(sampleRate, 'sampleRate', 'Must be at least 1000 Hz.');
    final size = windowSizeFor(sampleRate);
    final window = Float64List(size);
    var sum = 0.0;
    for (var i = 0; i < size; i++) {
      window[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / size);
      sum += window[i];
    }
    return AudioFeatureExtractor._(sampleRate, size, window, sum);
  }

  AudioFeatureExtractor._(this.sampleRate, this.windowSize, this._window, this._windowSum)
      : _fft = Fft(windowSize),
        _re = Float64List(windowSize),
        _im = Float64List(windowSize),
        _amplitudes = Float64List(windowSize ~/ 2),
        _logAmplitudes = Float64List(windowSize ~/ 2),
        _previousLog = Float64List(windowSize ~/ 2),
        _ranges = _BinRanges(sampleRate, windowSize),
        _filters = _melFilters(sampleRate, windowSize);

  /// Analyses all of [samples] (mono, `-1..1`) at [sampleRate].
  static AudioFeatures extract(Float32List samples, int sampleRate) {
    final extractor = AudioFeatureExtractor(sampleRate);
    const chunk = 1 << 16;
    for (var start = 0; start < samples.length; start += chunk) {
      extractor.add(Float32List.sublistView(samples, start, math.min(samples.length, start + chunk)));
    }
    return extractor.finish();
  }

  /// The FFT window for [sampleRate]: the power of two nearest to
  /// 2048 · sampleRate / 44100 (2048 at 44.1 and 48 kHz).
  static int windowSizeFor(int sampleRate) {
    final ideal = 2048 * sampleRate / 44100;
    final exponent = (math.log(ideal) / math.ln2).round().clamp(7, 15);
    return 1 << exponent;
  }

  /// Center frequencies (Hz) of the 16 mel bands.
  static List<double> get bandCenters {
    final points = _melPoints();
    return List.unmodifiable([for (var j = 0; j < AudioFeatureKey.bandCount; j++) points[j + 1]]);
  }

  /// Appends mono samples.
  void add(List<double> samples) {
    if (_finished) throw StateError('The extractor has finished.');
    final needed = _bufferLength + samples.length;
    if (needed > _buffer.length) {
      final grown = Float32List(math.max(needed, _buffer.length * 2));
      grown.setRange(0, _bufferLength, _buffer);
      _buffer = grown;
    }
    _buffer.setRange(_bufferLength, needed, samples);
    _bufferLength = needed;
    _received += samples.length;
    while (_windowEnd(_nextFrame) <= _received) {
      _computeFrame(_nextFrame++);
    }
    _discardBefore(_windowStart(_nextFrame));
  }

  /// Analyses the remaining rows (zero-padded) and normalizes the song.
  AudioFeatures finish() {
    if (_finished) throw StateError('The extractor has finished.');
    _finished = true;
    final frameCount = (_received * 100 + sampleRate - 1) ~/ sampleRate;
    while (_nextFrame < frameCount) {
      _computeFrame(_nextFrame++);
    }
    final data = Float32List.sublistView(_rows, 0, frameCount * AudioFeatureKey.columnCount);
    _normalize(data, frameCount);
    return AudioFeatures(data);
  }

  int _center(int frame) => (frame * sampleRate + 50) ~/ 100;
  int _windowStart(int frame) => _center(frame) - windowSize ~/ 2;
  int _windowEnd(int frame) => _windowStart(frame) + windowSize;

  void _discardBefore(int absolute) {
    final drop = (absolute - _bufferStart).clamp(0, _bufferLength);
    if (drop == 0) return;
    _buffer.setRange(0, _bufferLength - drop, _buffer, drop);
    _bufferLength -= drop;
    _bufferStart += drop;
  }

  double _sampleAt(int absolute) {
    final i = absolute - _bufferStart;
    return i >= 0 && i < _bufferLength ? _buffer[i] : 0.0;
  }

  double _compress(double amplitude) => math.log(1 + _compression * amplitude) / _compressionNorm;

  void _computeFrame(int frame) {
    const columns = AudioFeatureKey.columnCount;
    final needed = (frame + 1) * columns;
    if (needed > _rows.length) {
      final grown = Float32List(_rows.length * 2);
      grown.setRange(0, _rows.length, _rows);
      _rows = grown;
    }
    final row = frame * columns;
    final start = _windowStart(frame);
    var weightedSquares = 0.0;
    for (var i = 0; i < windowSize; i++) {
      final x = _sampleAt(start + i);
      final w = _window[i];
      weightedSquares += w * x * x;
      _re[i] = x * w;
      _im[i] = 0;
    }
    _fft.transform(_re, _im);
    final scale = 2 / _windowSum;
    final half = windowSize ~/ 2;
    for (var k = 0; k < half; k++) {
      final a = math.sqrt(_re[k] * _re[k] + _im[k] * _im[k]) * scale;
      _amplitudes[k] = a;
      _logAmplitudes[k] = _compress(a);
    }

    _rows[row + AudioFeatureKey.level.index] = math.sqrt(weightedSquares / _windowSum);
    _rows[row + AudioFeatureKey.bass.index] = _compress(_bandAmplitude(_ranges.bassFrom, _ranges.bassTo));
    _rows[row + AudioFeatureKey.mid.index] = _compress(_bandAmplitude(_ranges.midFrom, _ranges.midTo));
    _rows[row + AudioFeatureKey.treble.index] = _compress(_bandAmplitude(_ranges.trebleFrom, _ranges.trebleTo));
    for (var j = 0; j < _filters.length; j++) {
      final filter = _filters[j];
      var power = 0.0;
      for (var i = 0; i < filter.bins.length; i++) {
        final a = _amplitudes[filter.bins[i]];
        power += filter.weights[i] * a * a;
      }
      _rows[row + AudioFeatureKey.firstBand + j] = _compress(math.sqrt(power));
    }

    var flux = 0.0;
    var peak = 0.0;
    var peakBin = -1;
    final from = _ranges.spectrumFrom;
    final to = _ranges.spectrumTo;
    for (var k = from; k < to; k++) {
      if (_hasPrevious) {
        final rise = _logAmplitudes[k] - _previousLog[k];
        if (rise > 0) flux += rise;
      }
      if (_amplitudes[k] > peak) {
        peak = _amplitudes[k];
        peakBin = k;
      }
    }
    _rows[row + AudioFeatureKey.onset.index] = to > from ? flux / (to - from) : 0;
    _rows[row + AudioFeatureKey.peakFrequency.index] =
        peakBin < 0 || peak < 1e-4 ? 0 : _logPosition(peakBin * sampleRate / windowSize);
    _previousLog.setAll(0, _logAmplitudes);
    _hasPrevious = true;
  }

  double _bandAmplitude(int from, int to) {
    var power = 0.0;
    for (var k = from; k < to; k++) {
      power += _amplitudes[k] * _amplitudes[k];
    }
    return math.sqrt(power);
  }

  static double _logPosition(double frequency) {
    final p =
        (math.log(frequency) - math.log(minBandFrequency)) / (math.log(maxBandFrequency) - math.log(minBandFrequency));
    return p.clamp(0.0, 1.0);
  }

  void _normalize(Float32List data, int frameCount) {
    const columns = AudioFeatureKey.columnCount;
    final quiet = _compress(_quietAmplitude);
    for (var c = 0; c < AudioFeatureKey.firstBand; c++) {
      if (c == AudioFeatureKey.peakFrequency.index) continue;
      final floor = switch (AudioFeatureKey.values[c]) {
        AudioFeatureKey.level => _quietAmplitude,
        AudioFeatureKey.onset => _onsetFloor,
        _ => quiet,
      };
      final values = Float32List(frameCount);
      for (var i = 0; i < frameCount; i++) {
        values[i] = data[i * columns + c];
      }
      final reference = _reference(values, floor);
      for (var i = 0; i < frameCount; i++) {
        data[i * columns + c] = (data[i * columns + c] / reference).clamp(0.0, 1.0);
      }
    }
    final bands = Float32List(frameCount * AudioFeatureKey.bandCount);
    for (var i = 0; i < frameCount; i++) {
      for (var b = 0; b < AudioFeatureKey.bandCount; b++) {
        bands[i * AudioFeatureKey.bandCount + b] = data[i * columns + AudioFeatureKey.firstBand + b];
      }
    }
    final reference = _reference(bands, quiet);
    for (var i = 0; i < frameCount; i++) {
      for (var b = 0; b < AudioFeatureKey.bandCount; b++) {
        final index = i * columns + AudioFeatureKey.firstBand + b;
        data[index] = (data[index] / reference).clamp(0.0, 1.0);
      }
    }
  }

  static double _reference(Float32List values, double floor) {
    if (values.isEmpty) return floor;
    final sorted = Float32List.fromList(values)..sort();
    final p95 = sorted[((sorted.length - 1) * 0.95).round()];
    return math.max(math.max(p95, sorted.last * 0.25), floor);
  }

  static List<double> _melPoints() {
    double mel(double f) => 2595 * math.log(1 + f / 700) / math.ln10;
    double hz(double m) => 700 * (math.pow(10, m / 2595) - 1);
    final low = mel(minBandFrequency);
    final high = mel(maxBandFrequency);
    const count = AudioFeatureKey.bandCount + 2;
    return [for (var i = 0; i < count; i++) hz(low + (high - low) * i / (count - 1))];
  }

  static List<_MelFilter> _melFilters(int sampleRate, int windowSize) {
    final points = _melPoints();
    final binHz = sampleRate / windowSize;
    final half = windowSize ~/ 2;
    final nyquist = sampleRate / 2;
    return [
      for (var j = 0; j < AudioFeatureKey.bandCount; j++)
        _melFilter(points[j], points[j + 1], points[j + 2], binHz, half, nyquist),
    ];
  }

  static _MelFilter _melFilter(double low, double center, double high, double binHz, int half, double nyquist) {
    final bins = <int>[];
    final weights = <double>[];
    if (center < nyquist) {
      for (var k = 1; k < half; k++) {
        final f = k * binHz;
        if (f <= low || f >= high) continue;
        final w = f <= center ? (f - low) / (center - low) : (high - f) / (high - center);
        if (w > 0) {
          bins.add(k);
          weights.add(w);
        }
      }
      if (bins.isEmpty) {
        final nearest = (center / binHz).round().clamp(1, half - 1);
        bins.add(nearest);
        weights.add(1);
      }
    }
    return _MelFilter(Int32List.fromList(bins), Float64List.fromList(weights));
  }
}

final class _MelFilter {
  final Int32List bins;
  final Float64List weights;

  _MelFilter(this.bins, this.weights);
}

/// FFT bin ranges `[from, to)` of the fixed frequency bands.
final class _BinRanges {
  final int bassFrom, bassTo, midFrom, midTo, trebleFrom, trebleTo, spectrumFrom, spectrumTo;

  factory _BinRanges(int sampleRate, int windowSize) {
    final half = windowSize ~/ 2;
    int bin(double hz) => (hz * windowSize / sampleRate).ceil().clamp(1, half);
    return _BinRanges._(
      bin(20),
      bin(250),
      bin(250),
      bin(4000),
      bin(4000),
      bin(16000),
      bin(AudioFeatureExtractor.minBandFrequency),
      bin(AudioFeatureExtractor.maxBandFrequency),
    );
  }

  _BinRanges._(
    this.bassFrom,
    this.bassTo,
    this.midFrom,
    this.midTo,
    this.trebleFrom,
    this.trebleTo,
    this.spectrumFrom,
    this.spectrumTo,
  );
}
