import 'dart:typed_data';

import 'audio_features.dart' show fnv1a64Hex;
import 'deep_audio_features.dart';

/// The binary form of [DeepAudioFeatures] (worker and plugin boundaries,
/// bake cache keys).
///
/// Little endian: magic `"IDF1"`, stem rows, stem hop in microseconds,
/// chroma rows, chroma rows per second (u32 each), then the float32 stem
/// matrix (`rows × 4`) and the float32 chroma matrix (`rows × 12`).
abstract final class DeepAudioFeaturesCodec {
  static const _magic = 0x31464449; // "IDF1"
  static const _headerBytes = 20;

  static final _hashes = Expando<String>('deepAudioFeaturesHash');

  static Uint8List toBytes(DeepAudioFeatures deep) {
    final stems = deep.stems.data;
    final chroma = deep.chroma.data;
    final bytes = Uint8List(_headerBytes + (stems.length + chroma.length) * 4);
    final view = ByteData.sublistView(bytes);
    view.setUint32(0, _magic, Endian.little);
    view.setUint32(4, deep.stems.rows, Endian.little);
    view.setUint32(8, deep.stems.hop.inMicroseconds, Endian.little);
    view.setUint32(12, deep.chroma.rows, Endian.little);
    view.setUint32(16, deep.chroma.rowsPerSecond, Endian.little);
    var offset = _headerBytes;
    for (final v in stems) {
      view.setFloat32(offset, v, Endian.little);
      offset += 4;
    }
    for (final v in chroma) {
      view.setFloat32(offset, v, Endian.little);
      offset += 4;
    }
    return bytes;
  }

  /// Decodes [toBytes]; throws a [FormatException] for anything else.
  static DeepAudioFeatures fromBytes(Uint8List bytes) {
    if (bytes.length < _headerBytes) throw const FormatException('Deep audio features too short.');
    final view = ByteData.sublistView(bytes);
    if (view.getUint32(0, Endian.little) != _magic) throw const FormatException('Not deep audio features.');
    final stemRows = view.getUint32(4, Endian.little);
    final hop = view.getUint32(8, Endian.little);
    final chromaRows = view.getUint32(12, Endian.little);
    final rate = view.getUint32(16, Endian.little);
    final stemCount = stemRows * StemKind.values.length;
    final chromaCount = chromaRows * 12;
    if (hop == 0 || rate == 0 || bytes.length != _headerBytes + (stemCount + chromaCount) * 4) {
      throw const FormatException('Malformed deep audio features.');
    }
    final stems = Float32List(stemCount);
    final chroma = Float32List(chromaCount);
    var offset = _headerBytes;
    for (var i = 0; i < stemCount; i++, offset += 4) {
      stems[i] = view.getFloat32(offset, Endian.little);
    }
    for (var i = 0; i < chromaCount; i++, offset += 4) {
      chroma[i] = view.getFloat32(offset, Endian.little);
    }
    return DeepAudioFeatures(
      stems: StemLevels(stems, rows: stemRows, hop: Duration(microseconds: hop)),
      chroma: Chroma(chroma, rows: chromaRows, rowsPerSecond: rate),
    );
  }

  /// A stable hash of [deep]'s content (`fnv1a64:<16 hex digits>`), a cache
  /// key for bakes; computed once per instance.
  static String contentHash(DeepAudioFeatures deep) => _hashes[deep] ??= 'fnv1a64:${fnv1a64Hex(toBytes(deep))}';
}
