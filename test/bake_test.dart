import 'package:collection/collection.dart';
import 'package:icicles_animation_dart/icicles_animation_dart.dart';
import 'package:icicles_generators/icicles_generators.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// Draws column `frameIndex % xCount` red on even frames only, leaves the
/// rest untouched; records what it saw.
final class _Probe implements Generator {
  final bool usesAudio;
  final bool fail;
  final List<FrameContext> seen;

  _Probe({this.usesAudio = false, this.fail = false}) : seen = [];

  @override
  GeneratorInfo get info => GeneratorInfo(
        id: 'test.probe',
        version: 1,
        name: const LocalizedText('Probe'),
        description: const LocalizedText('Test'),
        category: GeneratorCategory.basic,
        usesAudio: usesAudio,
      );

  @override
  List<ParamSpec> get params => const [
        NumberParam(id: 'n', label: LocalizedText('n'), min: 0, max: 1, defaultValue: 0.5),
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _ProbeInstance(this);
}

final class _ProbeInstance implements GeneratorInstance {
  final _Probe probe;

  _ProbeInstance(this.probe);

  @override
  void render(FrameContext ctx, Icicles out) {
    probe.seen.add(ctx);
    if (probe.fail && ctx.frameIndex == 3) throw StateError('boom');
    if (ctx.frameIndex.isEven) out.setColumnColor(ctx.frameIndex % ctx.xCount, const Color(0xFFFF0000));
  }
}

void main() {
  const setup = GeneratorSetup(xCount: 4, yCount: 3, radioPanelsCount: 1, radioPanelPixelCount: 2, seed: 1);

  test('frames follow the frame grid', () {
    final probe = _Probe();
    final request = BakeRequest.forLength(setup: setup, length: const Duration(milliseconds: 1010));
    expect(request.frameCount, 31);
    final animation = bakeGenerator(probe, request);
    expect(animation.duration, Framerate.fps30.frameStart(31));
    expect(animation.header.xCount, 4);
    expect(animation.header.radioPanelsCount, 1);
    expect(animation.header.loopsCount, 1);
    expect(probe.seen.map((c) => c.frameIndex), List.generate(31, (i) => i));
    expect(probe.seen[1].time, const Duration(milliseconds: 33));
    expect(probe.seen[2].delta, const Duration(milliseconds: 34));
    expect(probe.seen[0].delta, Duration.zero);
    expect(probe.seen[0].nx(3), 1);
    expect(probe.seen[0].ny(1), 0.5);
    expect(probe.seen[5].params.number('n'), 0.5);
  });

  test('a frame the generator did not touch keeps its last state', () {
    final animation = bakeGenerator(_Probe(), const BakeRequest(setup: setup, frameCount: 4));
    final views = animation.play().toList();
    // Frames 0 and 1 show column 0 red; frame 2 adds column 2.
    final last = views.lastWhere((v) => v.frame.duration > Duration.zero);
    final pixels = last.frame.pixels;
    expect(pixels[0], const Color(0xFFFF0000));
    expect(pixels[2 * 3], const Color(0xFFFF0000));
    expect(pixels[3], const Color(0xFF000000));
  });

  test('same seed gives the same bytes; another seed changes stateful output', () {
    const snow = SnowGenerator();
    final a = bakeBytes(snow, testRequest(seed: 3));
    expect(bakeBytes(snow, testRequest(seed: 3)), a);
    expect(const ListEquality<int>().equals(bakeBytes(snow, testRequest(seed: 4)), a), isFalse);
  });

  test('audio reaches only generators or bindings that use it', () {
    final deaf = _Probe();
    bakeGenerator(deaf, testRequest());
    expect(deaf.seen.every((c) => c.audio.level == 0), isTrue);
    // The tempo always reaches the beat fields.
    expect(deaf.seen.any((c) => c.audio.bpm == 120), isTrue);

    final listening = _Probe(usesAudio: true);
    bakeGenerator(listening, testRequest());
    expect(listening.seen.any((c) => c.audio.level > 0), isTrue);

    final bound = _Probe();
    bakeGenerator(
        bound, testRequest(bindings: const {'n': AudioBinding(feature: AudioFeatureKey.bass, min: 0, max: 1)}));
    expect(bound.seen.any((c) => c.audio.level > 0), isTrue);
  });

  test('needsAudioFeatures / needsAudioClock', () {
    final info = _Probe().info;
    expect(needsAudioFeatures(info, const {}), isFalse);
    expect(needsAudioClock(info, const {}), isFalse);
    const beat = {'n': BeatBinding(shape: BeatShape.sine, min: 0, max: 1)};
    expect(needsAudioFeatures(info, beat), isFalse);
    expect(needsAudioClock(info, beat), isTrue);
    const audio = {'n': AudioBinding(feature: AudioFeatureKey.level, min: 0, max: 1)};
    expect(needsAudioFeatures(info, audio), isTrue);
    expect(needsAudioClock(_Probe(usesAudio: true).info, const {}), isTrue);
  });

  test('guards: empty, too long, failing generator', () {
    Matcher kind(GeneratorErrorKind k) => throwsA(isA<GeneratorException>().having((e) => e.kind, 'kind', k));
    expect(() => bakeGenerator(_Probe(), const BakeRequest(setup: setup, frameCount: 0)),
        kind(GeneratorErrorKind.invalidRequest));
    expect(
      () => bakeGenerator(
          _Probe(), BakeRequest.forLength(setup: setup, length: maxBakeLength + const Duration(seconds: 1))),
      kind(GeneratorErrorKind.tooLong),
    );
    expect(BakeRequest.forLength(setup: setup, length: maxBakeLength).length, maxBakeLength);
    expect(() => bakeGenerator(_Probe(fail: true), const BakeRequest(setup: setup, frameCount: 10)),
        kind(GeneratorErrorKind.renderFailed));
    expect(() => bakeGenerator(_Probe(), BakeRequest(setup: setup.copyWith(xCount: 0), frameCount: 1)),
        kind(GeneratorErrorKind.invalidRequest));
  });

  test('FrameAssembler rebuilds the same animation from the raw frames', () {
    const generator = PlasmaGenerator();
    final request = testRequest();
    final assembler = FrameAssembler(request.setup, name: generator.info.name.en);
    renderGeneratorFrames(generator, request, (index, duration, rgb) {
      expect(rgb, hasLength(request.setup.frameBytes));
      assembler.add(duration, rgb);
    });
    expect(assembler.frameCount, request.frameCount);
    expect(assembler.build().toBytes(), bakeBytes(generator, request));
  });

  test('frameIndexAt / frameCountFor', () {
    expect(frameIndexAt(Framerate.fps30, const Duration(milliseconds: 32)), 0);
    expect(frameIndexAt(Framerate.fps30, const Duration(milliseconds: 33)), 1);
    expect(frameCountFor(Framerate.fps30, const Duration(seconds: 1)), 30);
    expect(frameCountFor(Framerate.fps30, Duration.zero), 0);
  });
}
