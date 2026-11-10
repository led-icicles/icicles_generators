import 'dart:async';
import 'dart:typed_data';

import '../audio/audio_features.dart';
import '../bake/bake.dart';
import '../bake/bake_request.dart';
import '../bake/frame_codec.dart';
import '../effect/effect.dart';
import '../effect/effect_registry.dart';
import '../effect/effect_runner.dart';
import '../generator/generator.dart';
import '../generator/generator_exception.dart';
import '../generator/generator_registry.dart';
import '../params/param_binding_json.dart';
import 'manifest_json.dart';
import 'plugin_connection.dart';
import 'plugin_protocol.dart';

/// The plugin side of the protocol over [connection]: answers `hello` with
/// the manifest of [generators] and [effects], bakes `bake` requests and
/// runs `apply` requests one at a time, until the input ends.
/// [runGeneratorPlugin] runs it over stdin/stdout.
Future<void> serveGeneratorPlugin(
  List<Generator> generators, {
  required String pluginId,
  required PluginConnection connection,
  List<Effect> effects = const [],
  int maxFramesBytes = 256 << 10,
  int audioCacheSize = 4,
}) async {
  final registry = GeneratorRegistry(generators);
  final effectRegistry = EffectRegistry(effects);
  final audioCache = _AudioCache(audioCacheSize);
  try {
    await for (final message in connection.messages) {
      switch (message.type) {
        case PluginProtocol.hello:
          final protocol = message.header['protocol'];
          if (protocol != pluginProtocolVersion) {
            connection.send(PluginProtocol.errorMessage(
              null,
              GeneratorErrorKind.protocolError.name,
              'Unsupported protocol $protocol; this plugin speaks $pluginProtocolVersion.',
            ));
            continue;
          }
          connection.send(PluginMessage({
            'type': PluginProtocol.manifest,
            'protocol': pluginProtocolVersion,
            'pluginId': pluginId,
            'generators': [
              for (final generator in registry.generators)
                ManifestJson.entryToJson(GeneratorManifestEntry.of(generator)),
            ],
            'effects': [
              for (final effect in effectRegistry.effects)
                ManifestJson.effectEntryToJson(EffectManifestEntry.of(effect)),
            ],
          }));
        case PluginProtocol.bake:
          _bake(message, registry, audioCache, connection, maxFramesBytes);
        case PluginProtocol.audio:
          final hash = message.header['audioHash'];
          final payload = message.payload;
          if (hash is String && payload != null) {
            try {
              audioCache.put(hash, AudioFeatures.fromBytes(payload));
            } on FormatException catch (e) {
              connection.send(PluginProtocol.errorMessage(null, GeneratorErrorKind.protocolError.name, e.message));
            }
          }
        case PluginProtocol.apply:
          _apply(message, effectRegistry, audioCache, connection, maxFramesBytes);
        default:
          connection.send(
            PluginProtocol.errorMessage(
                null, GeneratorErrorKind.protocolError.name, 'Unknown message "${message.type}".'),
          );
      }
      // Let the output drain between messages.
      await Future<void>.delayed(Duration.zero);
    }
  } on GeneratorException catch (e) {
    connection.send(PluginProtocol.errorMessage(null, e.kind.name, e.message));
  }
}

/// The audio features of the last [size] hashes, most recently used last.
final class _AudioCache {
  final int size;
  final _features = <String, AudioFeatures>{};

  _AudioCache(this.size);

  void put(String hash, AudioFeatures audio) {
    _features.remove(hash);
    _features[hash] = audio;
    while (_features.length > size) {
      _features.remove(_features.keys.first);
    }
  }

  /// The features of [hash] (marked as recently used), or `null`.
  AudioFeatures? get(String hash) {
    final audio = _features.remove(hash);
    if (audio != null) _features[hash] = audio;
    return audio;
  }
}

/// The audio of a request: the payload (cached by hash) when there is one,
/// else the cached features of `audioHash`; `null` without a hash. Throws a
/// [_AudioMissing] when the hash is unknown.
AudioFeatures? _audioOf(Map<String, Object?> header, Uint8List? payload, _AudioCache cache) {
  final hash = header['audioHash'];
  if (hash is! String) return null;
  if (payload != null) {
    final audio = AudioFeatures.fromBytes(payload);
    cache.put(hash, audio);
    return audio;
  }
  return cache.get(hash) ?? (throw _AudioMissing(hash));
}

final class _AudioMissing implements Exception {
  final String hash;

  const _AudioMissing(this.hash);
}

/// The request of a `bake`/`apply` header (its audio from [audio]).
BakeRequest _requestOf(Map<String, Object?> header, AudioFeatures? audio) {
  final frameCount = header['frameCount'];
  if (frameCount is! int) {
    throw const GeneratorException(GeneratorErrorKind.protocolError, 'A request needs a frameCount.');
  }
  final origin = header['audioOriginUs'];
  return BakeRequest(
    setup: PluginProtocol.setupFromJson(header['setup']),
    frameCount: frameCount,
    bindings: ParamBindingJson.bindingsFromJson(header['bindings']),
    macros: ParamBindingJson.bindingsFromJson(header['macros']),
    audio: audio,
    tempo: PluginProtocol.tempoFromJson(header['tempo']),
    audioOrigin: Duration(microseconds: origin is int ? origin : 0),
    name: header['name'] is String ? header['name'] as String : null,
  );
}

/// Batches frames of a setup into `frames` messages of at most
/// `maxFramesBytes` for a request, then `done`.
final class _FrameSender {
  final PluginConnection connection;
  final int requestId;
  final int perFrame;
  final int batch;
  Uint8List _buffer;
  int _count = 0;
  int _first = 0;

  _FrameSender(this.connection, this.requestId, GeneratorSetup setup, int maxFramesBytes)
      : perFrame = 2 + setup.frameBytes,
        batch = (maxFramesBytes ~/ (2 + setup.frameBytes)).clamp(1, 1 << 16),
        _buffer = Uint8List((maxFramesBytes ~/ (2 + setup.frameBytes)).clamp(1, 1 << 16) * (2 + setup.frameBytes));

  void add(Duration duration, Uint8List rgb) {
    final o = _count * perFrame;
    ByteData.sublistView(_buffer).setUint16(o, duration.inMilliseconds, Endian.little);
    _buffer.setRange(o + 2, o + perFrame, rgb);
    if (++_count == batch) flush();
  }

  void flush() {
    if (_count == 0) return;
    connection.send(PluginMessage(
      {'type': PluginProtocol.frames, 'requestId': requestId, 'first': _first, 'count': _count},
      Uint8List.sublistView(_buffer, 0, _count * perFrame),
    ));
    _first += _count;
    _count = 0;
    _buffer = Uint8List(batch * perFrame);
  }

  void done() {
    flush();
    connection.send(PluginMessage({'type': PluginProtocol.done, 'requestId': requestId, 'frameCount': _first}));
  }
}

void _bake(
  PluginMessage message,
  GeneratorRegistry registry,
  _AudioCache audioCache,
  PluginConnection connection,
  int maxFramesBytes,
) {
  final header = message.header;
  final requestId = header['requestId'] is int ? header['requestId'] as int : null;
  void error(String kind, String text) => connection.send(PluginProtocol.errorMessage(requestId, kind, text));
  if (requestId == null) return error(GeneratorErrorKind.protocolError.name, 'A bake needs a requestId.');
  final generatorId = header['generatorId'];
  final generator = generatorId is String ? registry.find(generatorId) : null;
  if (generator == null) return error(GeneratorErrorKind.unknownGenerator.name, 'No generator "$generatorId".');
  try {
    final request = _requestOf(header, _audioOf(header, message.payload, audioCache));
    final sender = _FrameSender(connection, requestId, request.setup, maxFramesBytes);
    renderGeneratorFrames(generator, request, (index, duration, rgb) => sender.add(duration, rgb));
    sender.done();
  } on _AudioMissing catch (e) {
    error(PluginProtocol.audioMissing, 'No audio features "${e.hash}".');
  } on GeneratorException catch (e) {
    error(e.kind.name, e.message);
  } on FormatException catch (e) {
    error(GeneratorErrorKind.protocolError.name, e.message);
  }
}

void _apply(
  PluginMessage message,
  EffectRegistry registry,
  _AudioCache audioCache,
  PluginConnection connection,
  int maxFramesBytes,
) {
  final header = message.header;
  final requestId = header['requestId'] is int ? header['requestId'] as int : null;
  void error(String kind, String text) => connection.send(PluginProtocol.errorMessage(requestId, kind, text));
  if (requestId == null) return error(GeneratorErrorKind.protocolError.name, 'An apply needs a requestId.');
  final effectId = header['effectId'];
  final effect = effectId is String ? registry.find(effectId) : null;
  if (effect == null) return error(GeneratorErrorKind.unknownGenerator.name, 'No effect "$effectId".');
  try {
    // The payload carries the input frames; the audio comes from `audio`.
    final request = _requestOf(header, _audioOf(header, null, audioCache));
    final runner = EffectRunner(effect, request);
    final setup = request.setup;
    final perFrame = 2 + setup.frameBytes;
    final input = message.payload ?? Uint8List(0);
    if (input.length != perFrame * request.frameCount) {
      throw GeneratorException(
        GeneratorErrorKind.protocolError,
        'Expected ${perFrame * request.frameCount} bytes of input frames, got ${input.length}.',
      );
    }
    final view = ByteData.sublistView(input);
    final sender = _FrameSender(connection, requestId, setup, maxFramesBytes);
    final rgb = Uint8List(setup.frameBytes);
    for (var index = 0; index < request.frameCount; index++) {
      final o = index * perFrame;
      final duration = Duration(milliseconds: view.getUint16(o, Endian.little));
      final output = runner.applyAt(index, FrameCodec.decodeView(setup, input, offset: o + 2, duration: duration));
      FrameCodec.encodeView(setup, output, rgb);
      sender.add(duration, rgb);
    }
    sender.done();
  } on _AudioMissing catch (e) {
    error(PluginProtocol.audioMissing, 'No audio features "${e.hash}".');
  } on GeneratorException catch (e) {
    error(e.kind.name, e.message);
  } on FormatException catch (e) {
    error(GeneratorErrorKind.protocolError.name, e.message);
  }
}
