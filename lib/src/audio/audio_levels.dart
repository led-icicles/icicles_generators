import 'dart:math' as math;
import 'dart:typed_data';

import 'audio_feature_key.dart';
import 'audio_features.dart';

/// How a clip's audio input is levelled before the program, its bindings
/// and its reactivity read it.
enum AudioLevelMode {
  /// As analysed: every column normalized once over the whole song.
  song,

  /// Normalized again over a moving window ([adaptiveAudioLevels]): a part
  /// that stays loud (a bass line that never lets go) still moves through
  /// `0..1`, like an automatic gain with gentle compression.
  adaptive,

  /// [adaptive] with every mel band levelled on its own: a spectrum whose
  /// bass bands stay loud no longer fills up on the left (the shape of the
  /// spectrum is traded for movement in every band).
  adaptiveBands;

  /// Whether the input is levelled per moving window.
  bool get isAdaptive => this != song;
}

/// The default window of [AudioLevelMode.adaptive].
const defaultLevelWindow = Duration(seconds: 8);

/// The shortest and longest adaptive window.
const minLevelWindow = Duration(seconds: 1);
const maxLevelWindow = Duration(seconds: 60);

/// [window] in [minLevelWindow]..[maxLevelWindow].
Duration clampLevelWindow(Duration window) =>
    window < minLevelWindow ? minLevelWindow : (window > maxLevelWindow ? maxLevelWindow : window);

/// The smallest range a window is stretched across: a nearly constant part
/// keeps its small movements visible without blowing up noise or silence.
const _minSpan = 0.15;

/// The compression exponent applied after the stretch (`< 1` lifts the
/// quiet values a little).
const _compression = 0.8;

/// Spacing of the window estimates (rows); values between are interpolated.
const _blockRows = 50;

final _cache = Expando<Map<int, AudioFeatures>>('adaptiveAudioLevels');

/// [features] levelled per moving [window] (clamped, see
/// [clampLevelWindow]): every column is re-stretched so the window's 10th
/// percentile maps to 0 and its 95th to 1 (at least [_minSpan] wide), then
/// gently compressed. The window is centred — bakes are offline, so it may
/// look ahead. The 16 mel bands share one range (the spectrum keeps its
/// shape) unless [perBand]; the loudest frequency is a position, not a
/// level, and stays as analysed. Pure and cached per instance, window and
/// [perBand].
AudioFeatures adaptiveAudioLevels(AudioFeatures features, Duration window, {bool perBand = false}) {
  final w = clampLevelWindow(window);
  final perWindow = _cache[features] ??= {};
  return perWindow[w.inMicroseconds * 2 + (perBand ? 1 : 0)] ??= _level(features, w, perBand);
}

AudioFeatures _level(AudioFeatures features, Duration window, bool perBand) {
  const columns = AudioFeatureKey.columnCount;
  final rows = features.frameCount;
  final out = Float32List(rows * columns);
  if (rows == 0) return AudioFeatures(out, hopDuration: features.hopDuration);
  final half = math.max(1, window.inMicroseconds ~/ features.hopDuration.inMicroseconds ~/ 2);
  final data = [for (final key in AudioFeatureKey.values.take(columns)) features.column(key)];
  final bands = [
    for (var b = 0; b < AudioFeatureKey.bandCount; b++) data[AudioFeatureKey.firstBand + b],
  ];
  final blocks = (rows + _blockRows - 1) ~/ _blockRows;
  // Rows sampled per window estimate (every `stride`-th row).
  final stride = math.max(1, (2 * half) ~/ 400);

  // The bands share the range of all bands.
  final bandRanges = _ranges(bands, rows, blocks, half, stride);
  for (var c = 0; c < columns; c++) {
    final key = AudioFeatureKey.values[c];
    final column = data[c];
    if (key == AudioFeatureKey.peakFrequency) {
      for (var r = 0; r < rows; r++) {
        out[r * columns + c] = column[r];
      }
      continue;
    }
    final ranges =
        c >= AudioFeatureKey.firstBand && !perBand ? bandRanges : _ranges([column], rows, blocks, half, stride);
    _apply(out, column, c, rows, ranges);
  }
  return AudioFeatures(out, hopDuration: features.hopDuration);
}

/// The (10th, 95th) percentile of [sources] in the window around the centre
/// of every block.
List<(double, double)> _ranges(List<Float32List> sources, int rows, int blocks, int half, int stride) {
  final ranges = <(double, double)>[];
  final sample = <double>[];
  for (var b = 0; b < blocks; b++) {
    final centre = math.min(rows - 1, b * _blockRows + _blockRows ~/ 2);
    final from = math.max(0, centre - half);
    final to = math.min(rows, centre + half);
    sample.clear();
    for (final source in sources) {
      for (var r = from; r < to; r += stride) {
        sample.add(source[r]);
      }
    }
    sample.sort();
    double at(double q) => sample[((sample.length - 1) * q).round()];
    ranges.add((at(0.10), at(0.95)));
  }
  return ranges;
}

void _apply(Float32List out, Float32List column, int c, int rows, List<(double, double)> ranges) {
  const columns = AudioFeatureKey.columnCount;
  for (var r = 0; r < rows; r++) {
    // Interpolate the range between the two nearest block centres.
    final position = (r - _blockRows / 2) / _blockRows;
    final i = position.floor().clamp(0, ranges.length - 1);
    final j = math.min(i + 1, ranges.length - 1);
    final f = (position - i).clamp(0.0, 1.0);
    final lo = ranges[i].$1 * (1 - f) + ranges[j].$1 * f;
    final hi = ranges[i].$2 * (1 - f) + ranges[j].$2 * f;
    final span = math.max(hi - lo, _minSpan);
    final base = hi - lo < _minSpan ? math.max(0.0, hi - _minSpan) : lo;
    final v = ((column[r] - base) / span).clamp(0.0, 1.0);
    out[r * columns + c] = math.pow(v, _compression).toDouble();
  }
}
