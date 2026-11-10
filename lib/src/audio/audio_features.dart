import 'dart:typed_data';

import '../time/tempo.dart';
import 'audio_feature_key.dart';
import 'audio_frame.dart';

/// Song-wide audio analysis: one row of [AudioFeatureKey.columnCount]
/// values (each `0..1`) every [hopDuration], row `k` describing the audio
/// around `k · hopDuration`.
///
/// Immutable; built by `AudioFeatureExtractor`. Memory is
/// `frameCount × 22 × 4` bytes (about 1.6 MB for 3 minutes).
final class AudioFeatures {
  /// The default hop of the extractor.
  static const defaultHop = Duration(milliseconds: 10);

  static const _magic = 0x31464149; // "IAF1"
  static const _headerBytes = 16;

  /// Time between two rows.
  final Duration hopDuration;

  /// Number of rows.
  final int frameCount;

  final Float32List _data;
  String? _contentHash;

  AudioFeatures._(this.hopDuration, this.frameCount, this._data);

  /// Features from a row-major matrix of [AudioFeatureKey.columnCount]
  /// columns (copied); values are clamped to `0..1` (NaN becomes 0).
  factory AudioFeatures(Float32List data, {Duration hopDuration = defaultHop}) {
    if (data.length % AudioFeatureKey.columnCount != 0) {
      throw ArgumentError.value(data.length, 'data', 'Must be a multiple of ${AudioFeatureKey.columnCount}.');
    }
    if (hopDuration <= Duration.zero) {
      throw ArgumentError.value(hopDuration, 'hopDuration', 'Must be positive.');
    }
    final copy = Float32List(data.length);
    for (var i = 0; i < data.length; i++) {
      final v = data[i];
      copy[i] = v.isNaN ? 0 : v.clamp(0.0, 1.0);
    }
    return AudioFeatures._(hopDuration, data.length ~/ AudioFeatureKey.columnCount, copy);
  }

  /// Decodes [toBytes].
  factory AudioFeatures.fromBytes(Uint8List bytes) {
    if (bytes.length < _headerBytes) throw const FormatException('Audio features too short.');
    final view = ByteData.sublistView(bytes);
    if (view.getUint32(0, Endian.little) != _magic) throw const FormatException('Not audio features.');
    final columns = view.getUint32(4, Endian.little);
    final frames = view.getUint32(8, Endian.little);
    final hop = view.getUint32(12, Endian.little);
    if (columns != AudioFeatureKey.columnCount) {
      throw FormatException('Unsupported audio feature columns: $columns.');
    }
    if (bytes.length != _headerBytes + frames * columns * 4 || hop == 0) {
      throw const FormatException('Malformed audio features.');
    }
    final data = Float32List(frames * columns);
    for (var i = 0; i < data.length; i++) {
      data[i] = view.getFloat32(_headerBytes + i * 4, Endian.little);
    }
    return AudioFeatures(data, hopDuration: Duration(microseconds: hop));
  }

  /// Length covered by the rows.
  Duration get duration => hopDuration * frameCount;

  /// Value of column [key] in row [frame].
  double value(int frame, AudioFeatureKey key) {
    if (!key.isColumn) throw ArgumentError.value(key, 'key', 'Not an audio column.');
    RangeError.checkValidIndex(frame, null, 'frame', frameCount);
    return _data[frame * AudioFeatureKey.columnCount + key.index];
  }

  /// A copy of column [key].
  Float32List column(AudioFeatureKey key) {
    if (!key.isColumn) throw ArgumentError.value(key, 'key', 'Not an audio column.');
    final out = Float32List(frameCount);
    for (var i = 0; i < frameCount; i++) {
      out[i] = _data[i * AudioFeatureKey.columnCount + key.index];
    }
    return out;
  }

  /// The features at song time [time], linearly interpolated between rows;
  /// all zero outside `[0, duration)`. The beat fields come from [tempo].
  AudioFrame sampleAt(Duration time, {Tempo? tempo}) {
    const columns = AudioFeatureKey.columnCount;
    final values = Float32List(columns);
    if (!time.isNegative && time < duration && frameCount > 0) {
      final position = time.inMicroseconds / hopDuration.inMicroseconds;
      final row = position.floor();
      final next = row + 1 < frameCount ? row + 1 : row;
      final f = position - row;
      final a = row * columns;
      final b = next * columns;
      for (var c = 0; c < columns; c++) {
        values[c] = _data[a + c] * (1 - f) + _data[b + c] * f;
      }
    }
    return AudioFrame.fromColumns(values, tempo: tempo, time: time);
  }

  /// A stable hash of the content (`fnv1a64:<16 hex digits>`), a cache key
  /// for bakes and for the plugin protocol.
  String get contentHash => _contentHash ??= _hash();

  String _hash() => 'fnv1a64:${fnv1a64Hex(toBytes())}';

  /// Little-endian binary form: magic, column count, row count, hop in
  /// microseconds (u32 each), then the float32 matrix.
  Uint8List toBytes() {
    final bytes = Uint8List(_headerBytes + _data.length * 4);
    final view = ByteData.sublistView(bytes);
    view.setUint32(0, _magic, Endian.little);
    view.setUint32(4, AudioFeatureKey.columnCount, Endian.little);
    view.setUint32(8, frameCount, Endian.little);
    view.setUint32(12, hopDuration.inMicroseconds, Endian.little);
    for (var i = 0; i < _data.length; i++) {
      view.setFloat32(_headerBytes + i * 4, _data[i], Endian.little);
    }
    return bytes;
  }
}

/// FNV-1a 64-bit of [bytes] as 16 lowercase hex digits.
///
/// Computed in two 32-bit halves so that it is exact on the VM and under
/// dart2js alike (a 64-bit literal such as the FNV offset basis cannot be
/// represented in JavaScript numbers): with `h = hi·2³² + lo` and the prime
/// `2⁴⁰ + 2⁸ + 0xb3`, `h·prime mod 2⁶⁴` is `lo·0x1b3` in the low half and
/// `hi·0x1b3 + lo·2⁸ + carry` in the high half. Every intermediate stays
/// below 2⁵³.
String fnv1a64Hex(Iterable<int> bytes) {
  const base = 0x100000000;
  var hi = 0xcbf29ce4;
  var lo = 0x84222325;
  for (final b in bytes) {
    lo ^= b & 0xff;
    final low = lo * 0x1b3;
    hi = (hi * 0x1b3 + lo * 0x100 + low ~/ base) % base;
    lo = low % base;
  }
  String half(int v) => v.toRadixString(16).padLeft(8, '0');
  return '${half(hi)}${half(lo)}';
}
