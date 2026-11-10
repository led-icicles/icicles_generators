import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:icicles_animation_dart/icicles_animation_dart.dart';
import 'package:icicles_generators/plugin.dart';
import 'package:test/test.dart';

// The example plugin's generator, for the in-process side of the comparisons.
// ignore: avoid_relative_lib_imports
import '../example/fire_plugin/lib/fire_generator.dart';
import 'effect_test_utils.dart';
import 'test_utils.dart';

/// A host client wired to an in-memory plugin; [sent] records what the host
/// sent.
final class _Pipe {
  final hostToPlugin = StreamController<List<int>>();
  final pluginToHost = StreamController<List<int>>();
  final sent = <PluginMessage>[];
  late final GeneratorPluginClient client;
  late final Future<void> served;

  _Pipe(List<Generator> generators, {List<Effect> effects = const [], int audioCacheSize = 4}) {
    final split = hostToPlugin.stream.asBroadcastStream();
    split.transform(const PluginMessageDecoder()).listen(sent.add, onError: (Object _) {});
    final pluginInput = StreamController<List<int>>();
    split.listen(pluginInput.add, onDone: pluginInput.close);
    served = serveGeneratorPlugin(
      generators,
      pluginId: 'test.plugin',
      effects: effects,
      connection: PluginConnection(pluginInput.stream, pluginToHost.sink),
      audioCacheSize: audioCacheSize,
    ).then((_) => pluginToHost.close());
    client = GeneratorPluginClient(PluginConnection(pluginToHost.stream, hostToPlugin.sink));
  }
}

final class _Broken implements Generator {
  const _Broken();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'test.plugin/broken',
        version: 2,
        name: LocalizedText('Broken'),
        description: LocalizedText(''),
        category: GeneratorCategory.basic,
      );

  @override
  List<ParamSpec> get params => const [];

  @override
  GeneratorInstance create(GeneratorSetup setup) => throw StateError('no');
}

final class _BrokenEffect implements Effect {
  const _BrokenEffect();

  @override
  EffectInfo get info => const EffectInfo(
        id: 'test.plugin/broken_fx',
        version: 1,
        name: LocalizedText('Broken'),
        description: LocalizedText(''),
        category: EffectCategory.color,
      );

  @override
  List<ParamSpec> get params => const [];

  @override
  EffectInstance create(GeneratorSetup setup) => throw StateError('no');
}

void main() {
  group('PluginMessage', () {
    test('encodes and decodes across arbitrary chunking', () async {
      final messages = [
        const PluginMessage({'type': 'hello', 'protocol': 1}),
        PluginMessage({'type': 'frames', 'n': 'ż'}, Uint8List.fromList(List.generate(1000, (i) => i % 256))),
        const PluginMessage({'type': 'done'}),
      ];
      final bytes = [for (final m in messages) ...m.encode()];
      final chunks = <List<int>>[];
      for (var i = 0; i < bytes.length; i += 7) {
        chunks.add(bytes.sublist(i, i + 7 > bytes.length ? bytes.length : i + 7));
      }
      final decoded = await Stream.fromIterable(chunks).transform(const PluginMessageDecoder()).toList();
      expect(decoded.map((m) => m.header), messages.map((m) => m.header));
      expect(decoded[1].payload, messages[1].payload);
      expect(decoded[0].payload, isNull);
    });

    test('a truncated stream is a protocol error', () {
      final bytes = const PluginMessage({'type': 'hello'}).encode();
      expect(
        Stream<List<int>>.value(bytes.sublist(0, bytes.length - 1)).transform(const PluginMessageDecoder()).toList(),
        throwsA(isA<GeneratorException>().having((e) => e.kind, 'kind', GeneratorErrorKind.protocolError)),
      );
    });
  });

  group('ManifestJson', () {
    test('round-trips every built-in generator', () {
      for (final generator in builtInGenerators) {
        final entry = GeneratorManifestEntry.of(generator);
        expect(ManifestJson.entryFromJson(ManifestJson.entryToJson(entry)), entry, reason: generator.info.id);
      }
    });

    test('round-trips every built-in effect', () {
      for (final effect in builtInEffects) {
        final entry = EffectManifestEntry.of(effect);
        expect(ManifestJson.effectEntryFromJson(ManifestJson.effectEntryToJson(entry)), entry, reason: effect.info.id);
      }
      expect(ManifestJson.effectEntryFromJson({'info': 'nope'}), isNull);
      expect(ManifestJson.effectInfoFromJson({'id': 'x', 'version': 1, 'name': 'X', 'category': 'teleport'})!.category,
          EffectCategory.color);
    });

    test('skips unreadable parameters', () {
      final json = ManifestJson.entryToJson(GeneratorManifestEntry.of(const PlasmaGenerator()));
      (json['params'] as List<Object?>).add({'kind': 'teleport', 'id': 'x', 'label': 'X'});
      expect(ManifestJson.entryFromJson(json)!.params, hasLength(const PlasmaGenerator().params.length));
      expect(ManifestJson.entryFromJson({'info': 'nope'}), isNull);
    });
  });

  group('in-memory plugin', () {
    test('handshake lists the generators', () async {
      final pipe = _Pipe(const [ExampleFireGenerator(), _Broken()]);
      final manifest = await pipe.client.handshake();
      expect(manifest.pluginId, 'test.plugin');
      expect(manifest.generators.map((g) => g.info.id), ['example.fire/fire', 'test.plugin/broken']);
      expect(manifest.find('example.fire/fire'), GeneratorManifestEntry.of(const ExampleFireGenerator()));
      await pipe.client.close();
    });

    test('bakes byte-identically to an in-process bake, sending audio once per hash', () async {
      final pipe = _Pipe(const [SpectrumGenerator(), ExampleFireGenerator()]);
      await pipe.client.handshake();
      final request = testRequest(bindings: const {'gain': ConstantBinding(2.0)});
      final results = await Future.wait([
        pipe.client.bake('icicles.spectrum', request),
        pipe.client.bake('icicles.spectrum', testRequest(seed: 9)),
        pipe.client.bake('example.fire/fire', testRequest()),
      ]);
      expect(results[0].toBytes(), bakeBytes(const SpectrumGenerator(), request));
      expect(results[1].toBytes(), bakeBytes(const SpectrumGenerator(), testRequest(seed: 9)));
      expect(results[2].toBytes(), bakeBytes(const ExampleFireGenerator(), testRequest()));
      final bakes = pipe.sent.where((m) => m.type == PluginProtocol.bake).toList();
      expect(bakes, hasLength(3));
      expect(bakes[0].payload, isNotNull, reason: 'first use of the audio');
      expect(bakes[1].payload, isNull, reason: 'cached by hash');
      expect(bakes[2].payload, isNull, reason: 'fire does not use audio');
      expect(bakes[2].header['audioHash'], isNull);
      await pipe.client.close();
    });

    test('bakes and applies with stacked, animated bindings and macros byte-identically', () async {
      final pipe = _Pipe(const [SolidGenerator()], effects: const [BrightnessEffect()]);
      await pipe.client.handshake();
      const macros = {
        'intensity': KeyframeBinding(keys: [Keyframe(at: 0, value: 0.2), Keyframe(at: 2, value: 1.0)]),
        'bass': AudioBinding(feature: AudioFeatureKey.bass, min: 0, max: 1),
        'tint': KeyframeBinding(
          keys: [Keyframe(at: 0, value: Color(0xFFFF0000)), Keyframe(at: 1, value: Color(0xFF0000FF))],
          loop: true,
        ),
      };
      const stacked = StackedBinding(
        base: MacroBinding('intensity'),
        modulators: [
          Modulator(source: MacroBinding('bass'), depth: 0.5),
          Modulator(
              source: BeatBinding(shape: BeatShape.sine, min: 0, max: 1), depth: -0.3, mode: ModulatorMode.multiply),
          Modulator(
            source: RandomBinding(mode: RandomMode.perBeat, min: 0, max: 1, smooth: 0.5),
            depth: 0.2,
            depthBinding: StepBinding(steps: [1, 0, 0.5, 0.25], min: 0, max: 1, gate: 0.5),
          ),
          Modulator(
            source: EnvelopeBinding(trigger: EnvelopeTrigger.onset(), min: 0, max: 1),
            depth: 0.4,
          ),
        ],
      );
      final bakeRequest = BakeRequest.forLength(
        setup: testSetup,
        length: const Duration(seconds: 2),
        bindings: const {'brightness': stacked, 'color': MacroBinding('tint')},
        macros: macros,
        audio: syntheticFeatures(),
        tempo: Tempo(bpm: 120),
        audioOrigin: const Duration(milliseconds: 500),
      );
      final baked = await pipe.client.bake('icicles.solid', bakeRequest);
      expect(baked.toBytes(), bakeBytes(const SolidGenerator(), bakeRequest));
      final inProcess = bakeGenerator(const SolidGenerator(), bakeRequest).toIndex();
      expect(inProcess.viewAt(Duration.zero).frame.pixels.first,
          isNot(inProcess.viewAt(const Duration(milliseconds: 500)).frame.pixels.first),
          reason: 'the macros animate the output');
      final bake = pipe.sent.singleWhere((m) => m.type == PluginProtocol.bake);
      expect(bake.header['macros'], ParamBindingJson.bindingsToJson(macros));
      expect(bake.payload, isNotNull, reason: 'the audio is sent because a macro reads it');

      final applyRequest = BakeRequest.forLength(
        setup: testSetup,
        length: const Duration(seconds: 2),
        bindings: const {'gain': stacked},
        macros: macros,
        audio: syntheticFeatures(),
        tempo: Tempo(bpm: 120),
      );
      final inputs = syntheticInputs(applyRequest);
      final applied = await pipe.client.applyEffect('icicles.fx.brightness', applyRequest, inputs);
      expect(viewBytes(testSetup, applied), effectBytes(const BrightnessEffect(), applyRequest, inputs));
      expect(pipe.sent.singleWhere((m) => m.type == PluginProtocol.apply).header['macros'],
          ParamBindingJson.bindingsToJson(macros));
      await pipe.client.close();
    });

    test('resends audio the plugin evicted', () async {
      final pipe = _Pipe(const [SpectrumGenerator()], audioCacheSize: 1);
      await pipe.client.handshake();
      final other = BakeRequest.forLength(
        setup: testSetup,
        length: const Duration(milliseconds: 300),
        audio: syntheticFeatures(seconds: 3),
      );
      await pipe.client.bake('icicles.spectrum', testRequest());
      await pipe.client.bake('icicles.spectrum', other);
      final animation = await pipe.client.bake('icicles.spectrum', testRequest());
      expect(animation.toBytes(), bakeBytes(const SpectrumGenerator(), testRequest()));
      expect(pipe.sent.where((m) => m.type == PluginProtocol.bake && m.payload != null), hasLength(3));
      await pipe.client.close();
    });

    test('reports failures with their kind and keeps serving', () async {
      final pipe = _Pipe(const [ExampleFireGenerator(), _Broken()]);
      await pipe.client.handshake();
      Matcher kind(GeneratorErrorKind k) => throwsA(isA<GeneratorException>().having((e) => e.kind, 'kind', k));
      await expectLater(pipe.client.bake('test.plugin/broken', testRequest()), kind(GeneratorErrorKind.renderFailed));
      await expectLater(pipe.client.bake('nope', testRequest()), kind(GeneratorErrorKind.unknownGenerator));
      await expectLater(
        pipe.client.bake('example.fire/fire', const BakeRequest(setup: testSetup, frameCount: 0)),
        kind(GeneratorErrorKind.invalidRequest),
      );
      final ok = await pipe.client.bake('example.fire/fire', testRequest());
      expect(ok.toBytes(), bakeBytes(const ExampleFireGenerator(), testRequest()));
      await pipe.client.close();
    });

    test('a plugin that goes away fails the pending bake', () async {
      final input = StreamController<List<int>>();
      final client = GeneratorPluginClient(PluginConnection(input.stream, StreamController<List<int>>().sink));
      final handshake = client.handshake();
      await input.close();
      await expectLater(
        handshake,
        throwsA(isA<GeneratorException>().having((e) => e.kind, 'kind', GeneratorErrorKind.pluginFailed)),
      );
      await client.done;
    });

    test('a silent plugin times out', () async {
      final client = GeneratorPluginClient(
        PluginConnection(StreamController<List<int>>().stream, StreamController<List<int>>().sink),
      );
      await expectLater(
        client.handshake(timeout: const Duration(milliseconds: 50)),
        throwsA(isA<GeneratorException>().having((e) => e.kind, 'kind', GeneratorErrorKind.timeout)),
      );
    });
  });

  group('in-memory plugin effects', () {
    Matcher kind(GeneratorErrorKind k) => throwsA(isA<GeneratorException>().having((e) => e.kind, 'kind', k));

    test('the manifest lists the effects', () async {
      final pipe = _Pipe(const [ExampleFireGenerator()], effects: const [FlipEffect(), GateAudioEffect()]);
      final manifest = await pipe.client.handshake();
      expect(manifest.generators.map((g) => g.info.id), ['example.fire/fire']);
      expect(manifest.effects.map((e) => e.info.id), ['icicles.fx.flip', 'icicles.fx.gate_audio']);
      expect(manifest.findEffect('icicles.fx.flip'), EffectManifestEntry.of(const FlipEffect()));
      expect(manifest.findEffect('icicles.fx.trail'), isNull);
      await pipe.client.close();
    });

    test('a plugin built before effects has none', () async {
      final input = StreamController<List<int>>();
      final output = StreamController<List<int>>();
      output.stream.transform(const PluginMessageDecoder()).listen((message) {
        if (message.type == PluginProtocol.hello) {
          input.add(
              const PluginMessage({'type': 'manifest', 'protocol': 1, 'pluginId': 'old', 'generators': []}).encode());
        }
      });
      final client = GeneratorPluginClient(PluginConnection(input.stream, output.sink));
      final manifest = await client.handshake();
      expect(manifest.effects, isEmpty);
      await expectLater(
        client.applyEffect('icicles.fx.flip', testRequest(), syntheticInputs(testRequest())),
        kind(GeneratorErrorKind.unknownGenerator),
      );
      await client.close();
    });

    test('applies identically to the in-process runner, sending audio once per hash', () async {
      final pipe = _Pipe(const [], effects: const [TrailEffect(), GateAudioEffect()]);
      await pipe.client.handshake();
      final gated = testRequest(bindings: const {'gain': ConstantBinding(2.0)});
      final trailed = testRequest(bindings: const {'fade': ConstantBinding(1.0)}, seed: 3);
      final inputs = syntheticInputs(gated);
      final results = await Future.wait([
        pipe.client.applyEffect('icicles.fx.gate_audio', gated, inputs),
        pipe.client.applyEffect('icicles.fx.gate_audio', testRequest(), inputs),
        pipe.client.applyEffect('icicles.fx.trail', trailed, inputs),
      ]);
      expect(viewBytes(testSetup, results[0]), effectBytes(const GateAudioEffect(), gated, inputs));
      expect(viewBytes(testSetup, results[1]), effectBytes(const GateAudioEffect(), testRequest(), inputs));
      expect(viewBytes(testSetup, results[2]), effectBytes(const TrailEffect(), trailed, inputs));
      expect(results[0].map((v) => v.frame.duration), inputs.map((v) => v.frame.duration));
      final audio = pipe.sent.where((m) => m.type == PluginProtocol.audio).toList();
      expect(audio, hasLength(1), reason: 'once per hash');
      expect(audio.single.payload, isNotNull);
      final applies = pipe.sent.where((m) => m.type == PluginProtocol.apply).toList();
      expect(applies, hasLength(3));
      expect(applies[0].header['audioHash'], isNotNull);
      expect(applies[2].header['audioHash'], isNull, reason: 'trail does not use audio');
      expect(applies.every((m) => m.payload!.length == 60 * (2 + testSetup.frameBytes)), isTrue);
      await pipe.client.close();
    });

    test('resends audio the plugin evicted, also between bakes and applies', () async {
      final pipe = _Pipe(const [SpectrumGenerator()], effects: const [GateAudioEffect()], audioCacheSize: 1);
      await pipe.client.handshake();
      final other = BakeRequest.forLength(
        setup: testSetup,
        length: const Duration(milliseconds: 300),
        audio: syntheticFeatures(seconds: 3),
      );
      final inputs = syntheticInputs(testRequest());
      await pipe.client.applyEffect('icicles.fx.gate_audio', testRequest(), inputs);
      await pipe.client.bake('icicles.spectrum', other);
      final views = await pipe.client.applyEffect('icicles.fx.gate_audio', testRequest(), inputs);
      expect(viewBytes(testSetup, views), effectBytes(const GateAudioEffect(), testRequest(), inputs));
      final animation = await pipe.client.bake('icicles.spectrum', testRequest());
      expect(animation.toBytes(), bakeBytes(const SpectrumGenerator(), testRequest()));
      expect(pipe.sent.where((m) => m.type == PluginProtocol.audio), hasLength(2), reason: 'resent for the apply');
      expect(pipe.sent.where((m) => m.type == PluginProtocol.bake && m.payload != null), hasLength(1),
          reason: 'only the other song; the last bake reuses the resent features');
      await pipe.client.close();
    });

    test('reports failures with their kind and keeps serving', () async {
      final pipe = _Pipe(const [], effects: const [FlipEffect(), _BrokenEffect()]);
      await pipe.client.handshake();
      final inputs = syntheticInputs(testRequest());
      await expectLater(
        pipe.client.applyEffect('test.plugin/broken_fx', testRequest(), inputs),
        kind(GeneratorErrorKind.renderFailed),
      );
      await expectLater(
          pipe.client.applyEffect('nope', testRequest(), inputs), kind(GeneratorErrorKind.unknownGenerator));
      await expectLater(
        pipe.client.applyEffect('icicles.fx.flip', testRequest(), inputs.sublist(1)),
        kind(GeneratorErrorKind.invalidRequest),
      );
      await expectLater(
        pipe.client.applyEffect('icicles.fx.flip', const BakeRequest(setup: testSetup, frameCount: 0), const []),
        kind(GeneratorErrorKind.invalidRequest),
      );
      final views = await pipe.client.applyEffect('icicles.fx.flip', testRequest(), inputs);
      expect(viewBytes(testSetup, views), effectBytes(const FlipEffect(), testRequest(), inputs));
      await pipe.client.close();
    });
  });

  test(
    'the example plugin as a process bakes the same bytes as in process',
    () async {
      final process = await Process.start(
        Platform.resolvedExecutable,
        ['run', 'bin/fire.dart'],
        workingDirectory: 'example/fire_plugin',
      );
      final stderrLines = <String>[];
      process.stderr.transform(const SystemEncoding().decoder).listen(stderrLines.add);
      final client = GeneratorPluginClient(PluginConnection(process.stdout, process.stdin));
      try {
        final manifest = await client.handshake(timeout: const Duration(seconds: 90));
        expect(manifest.pluginId, 'example.fire');
        final request =
            testRequest(bindings: const {'cooling': AudioBinding(feature: AudioFeatureKey.bass, min: 0.2, max: 0.9)});
        final animation = await client.bake('example.fire/fire', request);
        expect(animation.toBytes(), bakeBytes(const ExampleFireGenerator(), request));
        expect(animation.duration, testSetup.framerate.frameStart(60));
      } finally {
        await client.close();
        final code = await process.exitCode.timeout(const Duration(seconds: 10), onTimeout: () {
          process.kill();
          return -1;
        });
        expect(code, 0, reason: stderrLines.join());
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
