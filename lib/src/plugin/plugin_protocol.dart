import 'dart:convert';

import 'package:icicles_animation_dart/icicles_animation_dart.dart';

import '../audio/deep_audio_features.dart';
import '../audio/deep_audio_features_codec.dart';
import '../generator/generator.dart';
import '../generator/generator_exception.dart';
import '../reactive/audio_reactivity.dart';
import '../time/beat_grid.dart';
import '../time/cue_hits.dart';
import '../time/drum_hits.dart';
import '../time/tempo.dart';
import 'plugin_connection.dart';

/// Version of the plugin protocol.
const pluginProtocolVersion = 1;

/// Message types and field mapping of the plugin protocol.
///
/// - host → plugin `hello {protocol}`; plugin → host
///   `manifest {protocol, pluginId, generators: [{info, params}], effects:
///   [{info, params}], capabilities: ["reactivity"]}` (`effects` is missing
///   from plugins built before effects existed; `capabilities` — since
///   0.7.0 — lists what the plugin applies itself: [capabilityReactivity]
///   means its bakes honour the `reactivity` header. A manifest without it
///   is a plugin built before reactivity existed: the host then sends the
///   request without `reactivity` and applies the generic brightness / hue /
///   flash post-process to the returned frames itself
///   (`ReactivePostProcessor`), so reactivity keeps working — only the speed,
///   restart and size modes need the plugin's cooperation).
/// - host → plugin `bake {requestId, generatorId, version, setup, frameCount,
///   name, bindings, macros, tempo, beats, drums, audioOriginUs, audioHash}` (`macros`:
///   the composition's macro bindings by id, since 0.5.0 — an older plugin
///   ignores the key and its `MacroBinding`s decode to nothing, so those
///   parameters take their defaults; `beats`: the real beat grid in the
///   `BeatGridJson` form, since 0.6.0, optional — an older plugin ignores it
///   and follows `tempo`; `reactivity`: the `AudioReactivityJson` form of an
///   active `BakeRequest.reactivity`, since 0.7.0, optional; `drums`: the
///   detected drum hits in the `DrumHitsJson` form, since 0.8.0, optional —
///   an older plugin ignores it and its drum triggers follow the beat clock;
///   `cues`: the clip's cues in the `CueHitsJson` form, since 0.9.0,
///   optional — an older plugin ignores it; `deep`: the deep analysis
///   (stems, harmony) as base64 `DeepAudioFeaturesCodec` bytes, since
///   0.10.0, optional and sent only when the request reads it — an older
///   plugin ignores it, and fails to decode bindings with the new keys or
///   a `musical` binding), with the
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
///   bindings, macros, tempo, beats, drums, audioOriginUs, audioHash}` with the input frames as
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

  /// The manifest capability of a plugin that applies the `reactivity`
  /// header itself.
  static const capabilityReactivity = 'reactivity';

  /// The capabilities a plugin built with this version of the package has.
  static const List<String> capabilities = [capabilityReactivity];

  /// The `reactivity` header field: `null` for an inactive reactivity that
  /// levels the audio as analysed (an adaptive level applies even with the
  /// reactivity off, so it is sent then too).
  static Map<String, Object?>? reactivityToJson(AudioReactivity reactivity) =>
      reactivity.isActive || reactivity.level.isAdaptive ? AudioReactivityJson.toJson(reactivity) : null;

  /// Decodes [reactivityToJson]; [AudioReactivity.none] for a missing or
  /// malformed value.
  static AudioReactivity reactivityFromJson(Object? json) => AudioReactivityJson.fromJson(json) ?? AudioReactivity.none;

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

  /// `beatsPerBar` is omitted at the default 4 (older plugins read 4/4).
  static Map<String, Object?>? tempoToJson(Tempo? tempo) => tempo == null
      ? null
      : {
          'bpm': tempo.bpm,
          'firstBeatOffsetUs': tempo.firstBeatOffset.inMicroseconds,
          if (tempo.beatsPerBar != Tempo.defaultBeatsPerBar) 'beatsPerBar': tempo.beatsPerBar,
        };

  static Tempo? tempoFromJson(Object? json) {
    if (json case {'bpm': final num bpm, 'firstBeatOffsetUs': final int offset}) {
      try {
        final meter = json['beatsPerBar'];
        return Tempo(
          bpm: bpm.toDouble(),
          firstBeatOffset: Duration(microseconds: offset),
          beatsPerBar: meter is int ? meter : Tempo.defaultBeatsPerBar,
        );
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

  /// The `drums` header field: [DrumHitsJson.toJson].
  static Map<String, Object?>? drumsToJson(DrumHits? drums) => DrumHitsJson.toJson(drums);

  /// Decodes [drumsToJson]; `null` for a missing or malformed value.
  static DrumHits? drumsFromJson(Object? json) => DrumHitsJson.fromJson(json);

  /// The `cues` header field: [CueHitsJson.toJson].
  static Map<String, Object?>? cuesToJson(CueHits? cues) => CueHitsJson.toJson(cues);

  /// Decodes [cuesToJson]; `null` for a missing or malformed value.
  static CueHits? cuesFromJson(Object? json) => CueHitsJson.fromJson(json);

  /// The `deep` header field: base64 of [DeepAudioFeaturesCodec.toBytes].
  static String deepToJson(DeepAudioFeatures deep) => base64Encode(DeepAudioFeaturesCodec.toBytes(deep));

  /// Decodes [deepToJson]; `null` for a missing or malformed value.
  static DeepAudioFeatures? deepFromJson(Object? json) {
    if (json is! String) return null;
    try {
      return DeepAudioFeaturesCodec.fromBytes(base64Decode(json));
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  static GeneratorErrorKind errorKind(Object? name) =>
      GeneratorErrorKind.values.where((k) => k.name == name).firstOrNull ?? GeneratorErrorKind.pluginFailed;

  static PluginMessage errorMessage(int? requestId, String kind, String message) =>
      PluginMessage({'type': error, if (requestId != null) 'requestId': requestId, 'kind': kind, 'message': message});
}
