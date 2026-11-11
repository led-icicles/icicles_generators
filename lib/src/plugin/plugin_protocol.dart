import 'package:icicles_animation_dart/icicles_animation_dart.dart';

import '../generator/generator.dart';
import '../generator/generator_exception.dart';
import '../time/beat_grid.dart';
import '../time/tempo.dart';
import 'plugin_connection.dart';

/// Version of the plugin protocol.
const pluginProtocolVersion = 1;

/// Message types and field mapping of the plugin protocol.
///
/// - host → plugin `hello {protocol}`; plugin → host
///   `manifest {protocol, pluginId, generators: [{info, params}], effects:
///   [{info, params}]}` (`effects` is missing from plugins built before
///   effects existed).
/// - host → plugin `bake {requestId, generatorId, version, setup, frameCount,
///   name, bindings, macros, tempo, beats, audioOriginUs, audioHash}` (`macros`:
///   the composition's macro bindings by id, since 0.5.0 — an older plugin
///   ignores the key and its `MacroBinding`s decode to nothing, so those
///   parameters take their defaults; `beats`: the real beat grid in the
///   `BeatGridJson` form, since 0.6.0, optional — an older plugin ignores it
///   and follows `tempo`), with the
///   `AudioFeatures` bytes as payload the first time a hash is used on the
///   connection (the plugin caches them by `audioHash`).
/// - plugin → host `frames {requestId, first, count}` with a payload of
///   `count` frames, each `u16 durationMs` (little endian) and the RGB bytes
///   (icicle pixels column-major, then the radio panels); then
///   `done {requestId, frameCount}`, or `error {requestId, kind, message}`
///   (`kind` a [GeneratorErrorKind] name, or `audioMissing` when the plugin
///   lacks the features of `audioHash`).
/// - host → plugin `audio {audioHash}` with the `AudioFeatures` bytes as
///   payload: hands the plugin features for a later `apply` (no reply; the
///   plugin caches them by hash like a bake's).
/// - host → plugin `apply {requestId, effectId, version, setup, frameCount,
///   bindings, macros, tempo, beats, audioOriginUs, audioHash}` with the input frames as
///   payload in the layout of `frames` (`u16 durationMs` + RGB per frame,
///   `frameCount` of them); answered like a bake with `frames` of the output
///   and `done`, or `error`.
abstract final class PluginProtocol {
  static const hello = 'hello';
  static const manifest = 'manifest';
  static const bake = 'bake';
  static const frames = 'frames';
  static const done = 'done';
  static const error = 'error';
  static const audio = 'audio';
  static const apply = 'apply';

  /// Error kind of a bake whose audio hash the plugin does not have.
  static const audioMissing = 'audioMissing';

  static Map<String, Object?> setupToJson(GeneratorSetup setup) => {
        'xCount': setup.xCount,
        'yCount': setup.yCount,
        'radioPanelsCount': setup.radioPanelsCount,
        'radioPanelPixelCount': setup.radioPanelPixelCount,
        'fps': setup.framerate.framesPerSecond,
        'seed': setup.seed,
      };

  static GeneratorSetup setupFromJson(Object? json) {
    if (json
        case {
          'xCount': final int x,
          'yCount': final int y,
          'radioPanelsCount': final int panels,
          'radioPanelPixelCount': final int panelPixels,
          'fps': final int fps,
          'seed': final int seed,
        }) {
      final framerate = Framerate.values.where((f) => f.framesPerSecond == fps).firstOrNull;
      if (framerate != null) {
        return GeneratorSetup(
          xCount: x,
          yCount: y,
          radioPanelsCount: panels,
          radioPanelPixelCount: panelPixels,
          framerate: framerate,
          seed: seed,
        );
      }
    }
    throw const GeneratorException(GeneratorErrorKind.protocolError, 'Malformed setup.');
  }

  static Map<String, Object?>? tempoToJson(Tempo? tempo) =>
      tempo == null ? null : {'bpm': tempo.bpm, 'firstBeatOffsetUs': tempo.firstBeatOffset.inMicroseconds};

  static Tempo? tempoFromJson(Object? json) {
    if (json case {'bpm': final num bpm, 'firstBeatOffsetUs': final int offset}) {
      try {
        return Tempo(bpm: bpm.toDouble(), firstBeatOffset: Duration(microseconds: offset));
      } on ArgumentError {
        return null;
      }
    }
    return null;
  }

  /// The `beats` header field: [BeatGridJson.toJson].
  static Map<String, Object?>? beatsToJson(BeatGrid? beats) => BeatGridJson.toJson(beats);

  /// Decodes [beatsToJson]; `null` for a missing or malformed value.
  static BeatGrid? beatsFromJson(Object? json) => BeatGridJson.fromJson(json);

  static GeneratorErrorKind errorKind(Object? name) =>
      GeneratorErrorKind.values.where((k) => k.name == name).firstOrNull ?? GeneratorErrorKind.pluginFailed;

  static PluginMessage errorMessage(int? requestId, String kind, String message) =>
      PluginMessage({'type': error, if (requestId != null) 'requestId': requestId, 'kind': kind, 'message': message});
}
