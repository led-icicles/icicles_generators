import 'dart:async';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:icicles_animation_dart/icicles_animation_dart.dart';

import '../audio/audio_features.dart';
import '../bake/bake_request.dart';
import '../bake/frame_assembler.dart';
import '../bake/frame_codec.dart';
import '../effect/effect_runner.dart';
import '../generator/generator.dart';
import '../generator/generator_exception.dart';
import '../params/param_binding_json.dart';
import 'manifest_json.dart';
import 'plugin_connection.dart';
import 'plugin_protocol.dart';

/// What a plugin offers, from its `manifest`.
final class PluginManifest extends Equatable {
  final String pluginId;
  final int protocol;
  final List<GeneratorManifestEntry> generators;

  /// The effects the plugin ships (empty for plugins built before effects
  /// existed).
  final List<EffectManifestEntry> effects;

  const PluginManifest({
    required this.pluginId,
    required this.protocol,
    required this.generators,
    this.effects = const [],
  });

  /// The entry of [generatorId], or `null`.
  GeneratorManifestEntry? find(String generatorId) => generators.where((g) => g.info.id == generatorId).firstOrNull;

  /// The entry of [effectId], or `null`.
  EffectManifestEntry? findEffect(String effectId) => effects.where((e) => e.info.id == effectId).firstOrNull;

  @override
  List<Object?> get props => [pluginId, protocol, generators, effects];
}

/// The host side of the plugin protocol over one [PluginConnection]
/// (usually a plugin process's stdout/stdin; the process itself is the
/// host's business).
///
/// Call [handshake] first; then [bake] and [applyEffect] requests run one
/// at a time in call order. Audio features are sent once per content hash
/// and connection. Frames are assembled with [FrameAssembler], so a plugin
/// bake gives the same bytes as an in-process [bakeGenerator]; an effect run
/// gives the same views as an in-process [EffectRunner].
final class GeneratorPluginClient {
  final PluginConnection _connection;
  late final StreamSubscription<PluginMessage> _subscription;
  final _sentAudio = <String>{};
  final _done = Completer<void>();
  Completer<PluginMessage>? _handshake;
  _Pending? _pending;
  Future<void> _queue = Future.value();
  int _nextRequestId = 1;
  PluginManifest? _manifest;
  Object? _failure;

  GeneratorPluginClient(this._connection) {
    _subscription = _connection.messages.listen(
      _onMessage,
      onError: (Object error) => _fail(error is GeneratorException
          ? error
          : GeneratorException(GeneratorErrorKind.pluginFailed, 'The plugin connection failed.', error)),
      onDone: () =>
          _fail(const GeneratorException(GeneratorErrorKind.pluginFailed, 'The plugin closed the connection.')),
    );
  }

  /// The manifest after a successful [handshake].
  PluginManifest? get manifest => _manifest;

  /// Completes when the connection ends (the plugin exited or broke the
  /// protocol).
  Future<void> get done => _done.future;

  /// Sends `hello` and waits for the manifest.
  Future<PluginManifest> handshake({Duration timeout = const Duration(seconds: 5)}) async {
    _throwIfFailed();
    final completer = _handshake = Completer<PluginMessage>();
    _connection.send(const PluginMessage({'type': PluginProtocol.hello, 'protocol': pluginProtocolVersion}));
    final PluginMessage reply;
    try {
      reply = await completer.future.timeout(timeout);
    } on TimeoutException {
      throw const GeneratorException(GeneratorErrorKind.timeout, 'The plugin did not answer hello.');
    } finally {
      _handshake = null;
    }
    if (reply.type == PluginProtocol.error) {
      throw GeneratorException(PluginProtocol.errorKind(reply.header['kind']), '${reply.header['message']}');
    }
    final pluginId = reply.header['pluginId'];
    if (pluginId is! String || reply.header['protocol'] != pluginProtocolVersion) {
      throw const GeneratorException(GeneratorErrorKind.protocolError, 'Malformed manifest.');
    }
    final generators = <GeneratorManifestEntry>[];
    final ids = <String>{};
    if (reply.header['generators'] case final List<Object?> list) {
      for (final item in list) {
        final entry = ManifestJson.entryFromJson(item);
        if (entry != null && ids.add(entry.info.id)) generators.add(entry);
      }
    }
    final effects = <EffectManifestEntry>[];
    final effectIds = <String>{};
    if (reply.header['effects'] case final List<Object?> list) {
      for (final item in list) {
        final entry = ManifestJson.effectEntryFromJson(item);
        if (entry != null && effectIds.add(entry.info.id)) effects.add(entry);
      }
    }
    return _manifest = PluginManifest(
      pluginId: pluginId,
      protocol: pluginProtocolVersion,
      generators: List.unmodifiable(generators),
      effects: List.unmodifiable(effects),
    );
  }

  /// Bakes [generatorId] in the plugin for [request] and assembles the
  /// animation (named `request.name`, else the generator's English name).
  ///
  /// Throws a [GeneratorException]: the plugin's error kind,
  /// [GeneratorErrorKind.unknownGenerator] for an id not in the manifest,
  /// [GeneratorErrorKind.timeout] after [timeout] (measured from the
  /// request's turn in the queue), [GeneratorErrorKind.pluginFailed] when the
  /// connection ends.
  Future<Animation> bake(
    String generatorId,
    BakeRequest request, {
    Duration timeout = const Duration(seconds: 60),
  }) =>
      _enqueue(() => _bake(generatorId, request, timeout));

  /// Applies the effect [effectId] in the plugin to [inputs] (one view per
  /// frame of [request], `request.frameCount` of them, in the setup's
  /// layout) and returns the output views (keeping the input durations).
  ///
  /// Throws a [GeneratorException]: the plugin's error kind,
  /// [GeneratorErrorKind.unknownGenerator] for an id not in the manifest,
  /// [GeneratorErrorKind.invalidRequest] when the inputs do not match the
  /// request, [GeneratorErrorKind.timeout] after [timeout],
  /// [GeneratorErrorKind.pluginFailed] when the connection ends.
  Future<List<AnimationView>> applyEffect(
    String effectId,
    BakeRequest request,
    List<AnimationView> inputs, {
    Duration timeout = const Duration(seconds: 60),
  }) =>
      _enqueue(() => _applyEffect(effectId, request, inputs, timeout));

  Future<T> _enqueue<T>(Future<T> Function() run) {
    final result = _queue.then((_) => run());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<Animation> _bake(String generatorId, BakeRequest request, Duration timeout) async {
    _throwIfFailed();
    final entry = _manifest?.find(generatorId);
    if (entry == null) {
      throw GeneratorException(GeneratorErrorKind.unknownGenerator, 'The plugin has no generator "$generatorId".');
    }
    request.validate();
    final audio = needsAudioFeatures(entry.info, request.bindings, macros: request.macros) ? request.audio : null;
    return _run<Animation>(
      timeout: timeout,
      audio: audio,
      pending: (requestId) => _PendingBake(
        requestId,
        FrameAssembler(request.setup, name: request.name ?? entry.info.name.en),
        request.frameCount,
      ),
      send: (requestId, hash, sendAudio) => PluginMessage(
        {
          'type': PluginProtocol.bake,
          'requestId': requestId,
          'generatorId': generatorId,
          'version': entry.info.version,
          'setup': PluginProtocol.setupToJson(request.setup),
          'frameCount': request.frameCount,
          if (request.name != null) 'name': request.name,
          'bindings': ParamBindingJson.bindingsToJson(request.bindings),
          'macros': ParamBindingJson.bindingsToJson(request.macros),
          'tempo': PluginProtocol.tempoToJson(request.tempo),
          'audioOriginUs': request.audioOrigin.inMicroseconds,
          'audioHash': hash,
        },
        sendAudio ? audio!.toBytes() : null,
      ),
      what: 'bake "$generatorId"',
    );
  }

  Future<List<AnimationView>> _applyEffect(
    String effectId,
    BakeRequest request,
    List<AnimationView> inputs,
    Duration timeout,
  ) async {
    _throwIfFailed();
    final entry = _manifest?.findEffect(effectId);
    if (entry == null) {
      throw GeneratorException(GeneratorErrorKind.unknownGenerator, 'The plugin has no effect "$effectId".');
    }
    request.validate();
    if (inputs.length != request.frameCount) {
      throw GeneratorException(
        GeneratorErrorKind.invalidRequest,
        'Expected ${request.frameCount} input views, got ${inputs.length}.',
      );
    }
    final setup = request.setup;
    final perFrame = 2 + setup.frameBytes;
    final payload = Uint8List(perFrame * inputs.length);
    final view = ByteData.sublistView(payload);
    for (var i = 0; i < inputs.length; i++) {
      final o = i * perFrame;
      view.setUint16(o, inputs[i].frame.duration.inMilliseconds.clamp(0, 0xFFFF), Endian.little);
      try {
        FrameCodec.encodeView(setup, inputs[i], payload, o + 2);
      } on ArgumentError catch (e) {
        throw GeneratorException(GeneratorErrorKind.invalidRequest, 'Input view $i does not fit the layout.', e);
      }
    }
    final audio = effectNeedsAudioFeatures(entry.info, request.bindings, macros: request.macros) ? request.audio : null;
    return _run<List<AnimationView>>(
      timeout: timeout,
      audio: audio,
      pending: (requestId) => _PendingApply(requestId, setup, inputs),
      send: (requestId, hash, sendAudio) {
        if (sendAudio) {
          _connection.send(PluginMessage({'type': PluginProtocol.audio, 'audioHash': hash}, audio!.toBytes()));
        }
        return PluginMessage(
          {
            'type': PluginProtocol.apply,
            'requestId': requestId,
            'effectId': effectId,
            'version': entry.info.version,
            'setup': PluginProtocol.setupToJson(setup),
            'frameCount': request.frameCount,
            'bindings': ParamBindingJson.bindingsToJson(request.bindings),
            'macros': ParamBindingJson.bindingsToJson(request.macros),
            'tempo': PluginProtocol.tempoToJson(request.tempo),
            'audioOriginUs': request.audioOrigin.inMicroseconds,
            'audioHash': hash,
          },
          payload,
        );
      },
      what: 'apply "$effectId"',
    );
  }

  /// Sends one request (built by [send], with the audio features when the
  /// plugin has not seen [audio]'s hash yet) and awaits its result, retrying
  /// once with the audio when the plugin reports it missing.
  Future<T> _run<T>({
    required Duration timeout,
    required AudioFeatures? audio,
    required _Pending Function(int requestId) pending,
    required PluginMessage Function(int requestId, String? hash, bool sendAudio) send,
    required String what,
  }) async {
    for (var attempt = 0;; attempt++) {
      final requestId = _nextRequestId++;
      final current = _pending = pending(requestId);
      final hash = audio?.contentHash;
      final sendAudio = hash != null && !_sentAudio.contains(hash);
      _connection.send(send(requestId, hash, sendAudio));
      if (sendAudio) _sentAudio.add(hash);
      try {
        return await current.completer.future.timeout(timeout) as T;
      } on TimeoutException {
        throw GeneratorException(GeneratorErrorKind.timeout, 'The plugin did not $what in time.');
      } on _AudioMissing {
        _sentAudio.remove(hash);
        if (attempt > 0) {
          throw const GeneratorException(GeneratorErrorKind.protocolError, 'The plugin keeps losing the audio.');
        }
      } finally {
        if (identical(_pending, current)) _pending = null;
      }
    }
  }

  void _onMessage(PluginMessage message) {
    switch (message.type) {
      case PluginProtocol.manifest:
        _handshake?.complete(message);
        return;
      case PluginProtocol.error when message.header['requestId'] == null:
        if (_handshake case final handshake?) return handshake.complete(message);
        _pending?.completer.completeError(
          GeneratorException(PluginProtocol.errorKind(message.header['kind']), '${message.header['message']}'),
        );
        return;
    }
    final pending = _pending;
    if (pending == null || message.header['requestId'] != pending.requestId || pending.completer.isCompleted) return;
    try {
      switch (message.type) {
        case PluginProtocol.frames:
          pending.addFrames(message.payload ?? Uint8List(0));
        case PluginProtocol.done:
          if (pending.received != pending.frameCount) {
            throw GeneratorException(
              GeneratorErrorKind.protocolError,
              'Expected ${pending.frameCount} frames, got ${pending.received}.',
            );
          }
          pending.completer.complete(pending.build());
        case PluginProtocol.error:
          final kind = message.header['kind'];
          pending.completer.completeError(kind == PluginProtocol.audioMissing
              ? const _AudioMissing()
              : GeneratorException(PluginProtocol.errorKind(kind), '${message.header['message']}'));
      }
    } on GeneratorException catch (e) {
      pending.completer.completeError(e);
    } on Object catch (e) {
      pending.completer.completeError(GeneratorException(GeneratorErrorKind.protocolError, 'Malformed frames.', e));
    }
  }

  void _fail(GeneratorException error) {
    _failure ??= error;
    final pending = _pending;
    if (pending != null && !pending.completer.isCompleted) pending.completer.completeError(error);
    if (_handshake case final handshake? when !handshake.isCompleted) handshake.completeError(error);
    if (!_done.isCompleted) _done.complete();
  }

  void _throwIfFailed() {
    if (_failure case final failure?) throw failure;
  }

  /// Stops listening and closes the output (a plugin ends when its input
  /// ends).
  Future<void> close() async {
    _fail(const GeneratorException(GeneratorErrorKind.pluginFailed, 'The client was closed.'));
    await _subscription.cancel();
    await _connection.close();
  }
}

final class _AudioMissing implements Exception {
  const _AudioMissing();
}

/// A request in flight: collects the `frames` payloads and builds the
/// result on `done`.
abstract base class _Pending {
  final int requestId;
  final GeneratorSetup setup;
  final int frameCount;
  final completer = Completer<Object>();
  int _received = 0;

  _Pending(this.requestId, this.setup, this.frameCount);

  /// Frames received so far.
  int get received => _received;

  /// Takes frame [_received] from [payload] at [offset] (after its duration).
  void takeFrame(Duration duration, Uint8List payload, int offset);

  /// The result of all frames.
  Object build();

  void addFrames(Uint8List payload) {
    final perFrame = 2 + setup.frameBytes;
    if (payload.length % perFrame != 0) {
      throw const GeneratorException(GeneratorErrorKind.protocolError, 'Truncated frames.');
    }
    final view = ByteData.sublistView(payload);
    for (var o = 0; o < payload.length; o += perFrame) {
      if (_received >= frameCount) {
        throw const GeneratorException(GeneratorErrorKind.protocolError, 'Too many frames.');
      }
      takeFrame(Duration(milliseconds: view.getUint16(o, Endian.little)), payload, o + 2);
      _received++;
    }
  }
}

final class _PendingBake extends _Pending {
  final FrameAssembler assembler;

  _PendingBake(int requestId, this.assembler, int frameCount) : super(requestId, assembler.setup, frameCount);

  @override
  void takeFrame(Duration duration, Uint8List payload, int offset) => assembler.add(duration, payload, offset);

  @override
  Animation build() => assembler.build();
}

final class _PendingApply extends _Pending {
  final List<AnimationView> inputs;
  final List<AnimationView> outputs = [];

  _PendingApply(int requestId, GeneratorSetup setup, this.inputs) : super(requestId, setup, inputs.length);

  @override
  void takeFrame(Duration duration, Uint8List payload, int offset) {
    outputs.add(FrameCodec.decodeView(setup, payload, offset: offset, duration: inputs[received].frame.duration));
  }

  @override
  List<AnimationView> build() => List.unmodifiable(outputs);
}
