import 'dart:async';
import 'dart:typed_data';

import 'package:icicles_animation_dart/icicles_animation_dart.dart';
import 'package:icicles_generators/plugin.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// Features whose every column is [value] (onset 0): a constant energy in
/// every range.
AudioFeatures constantFeatures(double value, {double seconds = 4}) {
  final frames = (seconds * 100).round();
  final data = Float32List(frames * AudioFeatureKey.columnCount);
  for (var i = 0; i < frames; i++) {
    for (var c = 0; c < AudioFeatureKey.columnCount; c++) {
      data[i * AudioFeatureKey.columnCount + c] = c == AudioFeatureKey.onset.index ? 0 : value;
    }
  }
  return AudioFeatures(data);
}

const _setup = GeneratorSetup(xCount: 16, yCount: 4, radioPanelsCount: 1, radioPanelPixelCount: 2, seed: 3);

BakeRequest _request({
  required AudioReactivity reactivity,
  AudioFeatures? audio,
  Tempo? tempo,
  double seconds = 2,
  Map<String, ParamBinding> bindings = const {},
}) =>
    BakeRequest.forLength(
      setup: _setup,
      length: Duration(milliseconds: (seconds * 1000).round()),
      bindings: bindings,
      audio: audio,
      tempo: tempo,
      reactivity: reactivity,
    );

/// A white dot at column `floor(4 · seconds) mod xCount`, no parameters.
final class _Dot implements Generator {
  const _Dot();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'test.dot',
        version: 1,
        name: LocalizedText('Dot'),
        description: LocalizedText(''),
        category: GeneratorCategory.motion,
      );

  @override
  List<ParamSpec> get params => const [];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _DotInstance();
}

final class _DotInstance implements GeneratorInstance {
  @override
  void render(FrameContext ctx, Icicles out) {
    out.setAllPixelsColor(const Color(0xFF000000));
    out.setColumnColor((ctx.seconds * 4).floor() % ctx.xCount, const Color(0xFFFFFFFF));
  }
}

int _dotColumn(AnimationView view, GeneratorSetup setup) {
  for (var x = 0; x < setup.xCount; x++) {
    if (view.frame.pixels[x * setup.yCount].red > 0) return x;
  }
  return -1;
}

/// Paints pixel 0 with a random red drawn once per instance (so a restart
/// shows as a new value).
final class _Seeded implements Generator {
  const _Seeded();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'test.seeded',
        version: 1,
        name: LocalizedText('Seeded'),
        description: LocalizedText(''),
        category: GeneratorCategory.particles,
      );

  @override
  List<ParamSpec> get params => const [];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _SeededInstance();
}

final class _SeededInstance implements GeneratorInstance {
  int? _red;

  @override
  void render(FrameContext ctx, Icicles out) {
    _red ??= 1 + ctx.random.nextInt(255);
    out.setPixelColorAtIndex(0, Color.fromRGB(_red!, 0, 0));
  }
}

/// A generator with a native `speed` parameter: pixel 0's red is `25 · speed`.
final class _NativeSpeed implements Generator {
  const _NativeSpeed();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'test.native_speed',
        version: 1,
        name: LocalizedText('Native speed'),
        description: LocalizedText(''),
        category: GeneratorCategory.motion,
      );

  @override
  List<ParamSpec> get params => const [
        NumberParam(id: 'speed', label: LocalizedText('Speed'), min: 0, max: 10, defaultValue: 1),
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _NativeSpeedInstance();
}

final class _NativeSpeedInstance implements GeneratorInstance {
  @override
  void render(FrameContext ctx, Icicles out) {
    out.setPixelColorAtIndex(0, Color.fromRGB((ctx.params.number('speed') * 25).round().clamp(0, 255), 0, 0));
    // The frame clock must not be warped when the speed drives the parameter.
    out.setPixelColorAtIndex(1, Color.fromRGB((ctx.seconds * 100).round().clamp(0, 255), 0, 0));
  }
}

/// An identity effect.
final class _Pass implements Effect {
  const _Pass();

  @override
  EffectInfo get info => const EffectInfo(
        id: 'test.fx.pass',
        version: 1,
        name: LocalizedText('Pass'),
        description: LocalizedText(''),
        category: EffectCategory.color,
      );

  @override
  List<ParamSpec> get params => const [];

  @override
  EffectInstance create(GeneratorSetup setup) => _PassInstance();
}

final class _PassInstance implements EffectInstance {
  @override
  void apply(FrameContext ctx, AnimationView input, Icicles out) {}
}

/// The view of grid frame [index] (the bake is optimized, so views are
/// looked up by time).
AnimationView _frameAt(Animation animation, int index) =>
    animation.toIndex().viewAt(_setup.framerate.frameStart(index));

void main() {
  const white = ConstantBinding(Color(0xFFFFFFFF));
  const solid = SolidGenerator();
  const brightnessOnly = AudioReactivity(
    enabled: true,
    attack: Duration.zero,
    release: Duration.zero,
    modes: {ReactiveModeKind.brightness: ReactiveMode(min: 0, max: 1)},
  );

  group('AudioReactivity', () {
    test('none is inactive, defaults are brightness on the lows', () {
      expect(AudioReactivity.none.isActive, isFalse);
      expect(AudioReactivity.none.usesAudioFeatures, isFalse);
      expect(AudioReactivity.defaults.isActive, isTrue);
      expect(AudioReactivity.defaults.range, AudioRangePreset.lows);
      expect(AudioReactivity.defaults[ReactiveModeKind.brightness], const ReactiveMode(min: 0.2, max: 1));
      expect(const AudioReactivity(enabled: true).isActive, isFalse, reason: 'no modes');
    });

    test('usesTempo only for beat-triggered modes', () {
      final flash = AudioReactivity.defaults.withMode(ReactiveModeKind.flash, const ReactiveMode(min: 0, max: 1));
      expect(flash.usesTempo, isTrue);
      final onset = AudioReactivity.defaults
          .withMode(ReactiveModeKind.flash, const ReactiveMode(min: 0, max: 1, trigger: ReactiveTrigger.onset));
      expect(onset.usesTempo, isFalse);
      expect(onset.usesAudioFeatures, isTrue);
    });

    test('normalized clamps every field', () {
      final r = const AudioReactivity(
        enabled: true,
        sensitivity: 99,
        attack: Duration(minutes: 5),
        threshold: 2,
        lowHz: -5,
        highHz: 1e9,
        modes: {
          ReactiveModeKind.speed: ReactiveMode(min: -1, max: 100, decay: Duration(hours: 1)),
          ReactiveModeKind.hue: ReactiveMode(min: double.nan, max: 7),
        },
      ).normalized();
      expect(r.sensitivity, AudioReactivity.maxSensitivity);
      expect(r.attack, AudioReactivity.maxSmoothing);
      expect(r.threshold, 0.99);
      expect(r.lowHz, audioRangeMinHz);
      expect(r.highHz, audioRangeMaxHz);
      expect(r[ReactiveModeKind.speed], const ReactiveMode(min: 0, max: 8, decay: ReactiveMode.maxDecay));
      expect(r[ReactiveModeKind.hue], const ReactiveMode(min: 0, max: 1));
    });

    test('withDepth / depthOf are inverse and keep the other fields', () {
      for (final kind in ReactiveModeKind.values.where((k) => k.hasDepth)) {
        for (final depth in [0.0, 0.3, 1.0]) {
          final mode = kind.withDepth(depth, base: const ReactiveMode(min: 0, max: 1, trigger: ReactiveTrigger.onset));
          expect(kind.depthOf(mode), closeTo(depth, 1e-9), reason: kind.name);
          expect(mode.trigger, ReactiveTrigger.onset);
        }
      }
      expect(ReactiveModeKind.brightness.withDepth(0.8).min, closeTo(0.2, 1e-9));
      expect(ReactiveModeKind.brightness.withDepth(0.8).max, 1);
      expect(ReactiveModeKind.speed.withDepth(1), const ReactiveMode(min: 1, max: 4));
    });

    test('JSON round-trip and lenient decoding', () {
      const r = AudioReactivity(
        enabled: true,
        range: AudioRangePreset.custom,
        lowHz: 100,
        highHz: 3000,
        sensitivity: 1.5,
        attack: Duration(milliseconds: 20),
        release: Duration(milliseconds: 400),
        threshold: 0.1,
        invert: true,
        modes: {
          ReactiveModeKind.brightness: ReactiveMode(min: 0.3, max: 1),
          ReactiveModeKind.speed: ReactiveMode(min: 0.5, max: 2.5),
          ReactiveModeKind.hue: ReactiveMode(min: 0, max: 0.25, hueSource: ReactiveHueSource.frequency),
          ReactiveModeKind.flash: ReactiveMode(
            min: 0,
            max: 0.8,
            trigger: ReactiveTrigger.onset,
            decay: Duration(milliseconds: 120),
            flashColor: Color(0xFFFF8800),
          ),
          ReactiveModeKind.restart: ReactiveMode(min: 0, max: 1, trigger: ReactiveTrigger.range),
          ReactiveModeKind.size: ReactiveMode(min: 0.1, max: 0.9),
        },
      );
      final json = AudioReactivityJson.toJson(r);
      expect(json['range'], 'custom');
      expect(json['attackMs'], 20);
      expect((json['modes'] as Map)['flash'], {
        'min': 0,
        'max': 0.8,
        'trigger': 'onset',
        'decayMs': 120,
        'color': '#ff8800',
      });
      expect((json['modes'] as Map)['hue'], {'min': 0, 'max': 0.25, 'source': 'frequency'});
      expect((json['modes'] as Map)['brightness'], {'min': 0.3, 'max': 1});
      expect(AudioReactivityJson.fromJson(json), r);
      expect(AudioReactivityJson.fromJson(AudioReactivityJson.toJson(AudioReactivity.none)), AudioReactivity.none);

      expect(AudioReactivityJson.fromJson('nope'), isNull);
      expect(AudioReactivityJson.fromJson(null), isNull);
      final sparse = AudioReactivityJson.fromJson(<String, Object?>{
        'enabled': true,
        'modes': <String, Object?>{
          'brightness': <String, Object?>{},
          'unknownMode': <String, Object?>{'min': 0},
          'speed': 'bad',
        },
        'range': 'nonsense',
        'sensitivity': 'x',
      });
      expect(sparse, isNotNull);
      expect(sparse!.enabled, isTrue);
      expect(sparse.range, AudioRangePreset.lows);
      expect(sparse.sensitivity, 1);
      expect(sparse.modes.keys, [ReactiveModeKind.brightness]);
      expect(sparse[ReactiveModeKind.brightness], ReactiveModeKind.brightness.defaultMode);
    });

    test('resolveReactiveTargets: declared wins, else the conventional ids', () {
      const params = [
        NumberParam(id: 'speed', label: LocalizedText('s'), min: 0, max: 1, defaultValue: 0.5),
        NumberParam(id: 'radius', label: LocalizedText('r'), min: 0, max: 1, defaultValue: 0.5),
        ChoiceParam(
            id: 'size', label: LocalizedText('c'), options: [ChoiceOption('a', LocalizedText('a'))], defaultValue: 'a'),
      ];
      expect(resolveReactiveTargets(const {}, params), {ReactiveTarget.speed: 'speed'});
      expect(
        resolveReactiveTargets(const {ReactiveTarget.size: 'radius', ReactiveTarget.hue: 'missing'}, params),
        {ReactiveTarget.size: 'radius'},
      );
      expect(const SolidGenerator().info.reactiveTargets, isEmpty);
      expect(
          resolveReactiveTargets(const {}, const SolidGenerator().params), {ReactiveTarget.brightness: 'brightness'});
    });
  });

  group('bake with reactivity', () {
    test('brightness follows the energy (native brightness parameter of the solid generator)', () {
      Color last(double energy) {
        final animation = bakeGenerator(
          solid,
          _request(reactivity: brightnessOnly, audio: constantFeatures(energy), bindings: const {'color': white}),
        );
        return _frameAt(animation, 59).frame.pixels.first;
      }

      expect(last(1.0).red, 255);
      expect(last(0.0).red, 0);
      expect(last(0.5).red, closeTo(128, 2));
      final panels = bakeGenerator(
        solid,
        _request(reactivity: brightnessOnly, audio: constantFeatures(0.5), bindings: const {'color': white}),
      );
      expect(_frameAt(panels, 30).radioPanels.first.colors.first.red, closeTo(128, 2), reason: 'panels follow too');
    });

    test('brightness post-process dims a generator without a brightness parameter', () {
      final animation =
          bakeGenerator(const _Dot(), _request(reactivity: brightnessOnly, audio: constantFeatures(0.25)));
      final view = _frameAt(animation, 30);
      final lit = view.frame.pixels.where((c) => c.red > 0).toList();
      expect(lit, hasLength(_setup.yCount));
      expect(lit.first.red, closeTo(64, 1));
    });

    test('without audio the energy is zero: brightness at min, deterministic', () {
      final r = brightnessOnly.copyWith(modes: {ReactiveModeKind.brightness: const ReactiveMode(min: 0.5, max: 1)});
      final a = bakeGenerator(solid, _request(reactivity: r, bindings: const {'color': white}));
      final b = bakeGenerator(solid, _request(reactivity: r, bindings: const {'color': white}));
      expect(_frameAt(a, 10).frame.pixels.first.red, closeTo(128, 1));
      expect(a.toBytes(), b.toBytes());
    });

    test('threshold, sensitivity, invert and the follower shape the energy', () {
      Color at(AudioReactivity r, double energy, int frame) => _frameAt(
            bakeGenerator(
                solid, _request(reactivity: r, audio: constantFeatures(energy), bindings: const {'color': white})),
            frame,
          ).frame.pixels.first;

      expect(at(brightnessOnly.copyWith(threshold: 0.5), 0.4, 30).red, 0, reason: 'below the gate');
      expect(at(brightnessOnly.copyWith(threshold: 0.5), 0.75, 30).red, closeTo(128, 2), reason: 're-stretched');
      expect(at(brightnessOnly.copyWith(sensitivity: 2), 0.5, 30).red, 255, reason: 'gain clamps at 1');
      expect(at(brightnessOnly.copyWith(invert: true), 1.0, 30).red, 0);
      final slow = brightnessOnly.copyWith(attack: const Duration(seconds: 1));
      final early = at(slow, 1.0, 3).red, late = at(slow, 1.0, 59).red;
      expect(early, lessThan(100));
      expect(late, greaterThan(early));
    });

    test('speed warps the frame clock: the dot travels further with louder audio', () {
      const speed = AudioReactivity(
        enabled: true,
        attack: Duration.zero,
        release: Duration.zero,
        modes: {ReactiveModeKind.speed: ReactiveMode(min: 1, max: 3)},
      );
      int columnAt(AudioFeatures? audio) {
        final animation = bakeGenerator(const _Dot(), _request(reactivity: speed, audio: audio, seconds: 1));
        return _dotColumn(_frameAt(animation, 29), _setup);
      }

      expect(columnAt(null), 3, reason: 'rate 1 at silence: 4 columns/s');
      expect(columnAt(constantFeatures(1.0)), closeTo(11, 1), reason: 'rate 3');
      expect(columnAt(constantFeatures(0.5)), closeTo(7, 1), reason: 'rate 2');
    });

    test('speed drives a native speed parameter instead of warping time', () {
      const speed = AudioReactivity(
        enabled: true,
        attack: Duration.zero,
        release: Duration.zero,
        modes: {ReactiveModeKind.speed: ReactiveMode(min: 1, max: 3)},
      );
      final animation =
          bakeGenerator(const _NativeSpeed(), _request(reactivity: speed, audio: constantFeatures(1.0), seconds: 1));
      final view = _frameAt(animation, 29);
      expect(view.frame.pixels[0].red, 75, reason: 'speed 1 × 3');
      expect(view.frame.pixels[1].red, closeTo(97, 1), reason: 'frame 29 at 30 fps is 0.967 s, not warped');
    });

    test('hue rotates the output; the frequency source follows the peak', () {
      const third = AudioReactivity(
        enabled: true,
        attack: Duration.zero,
        release: Duration.zero,
        modes: {ReactiveModeKind.hue: ReactiveMode(min: 1 / 3, max: 1 / 3)},
      );
      final rotated = bakeGenerator(
        solid,
        _request(
            reactivity: third,
            audio: constantFeatures(1),
            bindings: const {'color': ConstantBinding(Color(0xFFFF0000))}),
      );
      final c = _frameAt(rotated, 10).frame.pixels.first;
      expect([c.red, c.green, c.blue], [0, 255, 0]);

      const byPeak = AudioReactivity(
        enabled: true,
        modes: {ReactiveModeKind.hue: ReactiveMode(min: 0, max: 0.5, hueSource: ReactiveHueSource.frequency)},
      );
      // All columns 1 → peakFrequency 1 → half a turn: red becomes cyan.
      final cyan = bakeGenerator(
        solid,
        _request(
            reactivity: byPeak,
            audio: constantFeatures(1),
            bindings: const {'color': ConstantBinding(Color(0xFFFF0000))}),
      );
      final d = _frameAt(cyan, 10).frame.pixels.first;
      expect([d.red, d.green, d.blue], [0, 255, 255]);
    });

    test('flash fires on beats and decays', () {
      const flash = AudioReactivity(
        enabled: true,
        modes: {
          ReactiveModeKind.flash:
              ReactiveMode(min: 0, max: 1, trigger: ReactiveTrigger.beat, decay: Duration(milliseconds: 100)),
        },
      );
      final animation = bakeGenerator(
        solid,
        _request(
            reactivity: flash, tempo: Tempo(bpm: 120), bindings: const {'color': ConstantBinding(Color(0xFF000000))}),
      );
      int red(int frame) => _frameAt(animation, frame).frame.pixels.first.red;
      expect(red(0), 0, reason: 'the first frame has no previous beat to compare with');
      expect(red(14), 0, reason: 'before the beat at 0.5 s');
      expect(red(15), 255, reason: 'the beat at 0.5 s');
      expect(red(18), inInclusiveRange(80, 120), reason: 'decayed by exp(-0.1 s / 0.1 s)');
      expect(red(29), lessThan(5));
      expect(red(30), 255, reason: 'the beat at 1 s');
    });

    test('flash on onsets with a color; no flash without a trigger source', () {
      final onsets = syntheticFeatures(seconds: 3);
      const flash = AudioReactivity(
        enabled: true,
        modes: {
          ReactiveModeKind.flash: ReactiveMode(
            min: 0,
            max: 1,
            trigger: ReactiveTrigger.onset,
            decay: Duration(milliseconds: 50),
            flashColor: Color(0xFF0000FF),
          ),
        },
      );
      final animation = bakeGenerator(
        solid,
        _request(reactivity: flash, audio: onsets, bindings: const {'color': ConstantBinding(Color(0xFF000000))}),
      );
      // Onsets of 1.0 land every second (rows 0, 100, 200); 0.5 ones every 250 ms.
      final hit = _frameAt(animation, 30).frame.pixels.first;
      expect(hit.blue, 255);
      expect(hit.red, 0);
      expect(_frameAt(animation, 20).frame.pixels.first.blue, lessThan(20), reason: 'the 0.5 hit at 0.5 s decayed');

      const beatless = AudioReactivity(enabled: true, modes: {ReactiveModeKind.flash: ReactiveMode(min: 0, max: 1)});
      final quiet = bakeGenerator(
        solid,
        _request(reactivity: beatless, audio: onsets, bindings: const {'color': ConstantBinding(Color(0xFF000000))}),
      );
      expect(_frameAt(quiet, 30).frame.pixels.first.red, 0, reason: 'a beat trigger without a beat clock never fires');
    });

    test('restart re-creates the instance with a derived seed on every beat, deterministically', () {
      const restart = AudioReactivity(
        enabled: true,
        modes: {ReactiveModeKind.restart: ReactiveMode(min: 0, max: 1)},
      );
      final a = bakeGenerator(const _Seeded(), _request(reactivity: restart, tempo: Tempo(bpm: 120)));
      final b = bakeGenerator(const _Seeded(), _request(reactivity: restart, tempo: Tempo(bpm: 120)));
      expect(a.toBytes(), b.toBytes());
      int red(int frame) => _frameAt(a, frame).frame.pixels.first.red;
      expect(red(0), red(14), reason: 'one run until the beat at 0.5 s');
      expect(red(15), isNot(red(14)), reason: 'a new seed on the beat');
      expect(red(15), red(29));
      expect(red(30), isNot(red(29)));
      final plain = bakeGenerator(const _Seeded(), _request(reactivity: AudioReactivity.none, tempo: Tempo(bpm: 120)));
      expect(_frameAt(plain, 29).frame.pixels.first.red, _frameAt(plain, 0).frame.pixels.first.red);
    });

    test('size sets a native size parameter across its range, nothing without one', () {
      const size = AudioReactivity(
        enabled: true,
        attack: Duration.zero,
        release: Duration.zero,
        modes: {ReactiveModeKind.size: ReactiveMode(min: 0, max: 1)},
      );
      final r = ReactiveEngine(size).step(
        constantFeatures(0.5).sampleAt(const Duration(milliseconds: 100)),
        const Duration(milliseconds: 33),
      );
      expect(r.size, closeTo(0.5, 1e-6));
      const specs = [NumberParam(id: 'size', label: LocalizedText('s'), min: 2, max: 10, defaultValue: 3)];
      final ctx = FrameContext(
        setup: _setup,
        frameIndex: 0,
        time: Duration.zero,
        delta: Duration.zero,
        params: const ParamValues({'size': 3.0}),
        audio: AudioFrame.silent,
        random: ReactiveEngine.randomFor(1, 0),
      );
      expect(reactiveParams(ctx, r, const {ReactiveTarget.size: 'size'}, specs).number('size'), closeTo(6, 1e-6));
      expect(identical(reactiveParams(ctx, r, const {}, specs), ctx.params), isTrue);
    });

    test('needsAudioFeatures / needsAudioClock and the request getters account for the reactivity', () {
      expect(needsAudioFeatures(solid.info, const {}), isFalse);
      expect(needsAudioFeatures(solid.info, const {}, reactivity: AudioReactivity.defaults), isTrue);
      expect(needsAudioClock(solid.info, const {}, reactivity: AudioReactivity.defaults), isTrue);
      expect(effectNeedsAudioFeatures(const _Pass().info, const {}, reactivity: AudioReactivity.defaults), isTrue);
      expect(effectNeedsAudioClock(const _Pass().info, const {}, reactivity: const AudioReactivity(enabled: true)),
          isFalse);
      final request = _request(reactivity: AudioReactivity.defaults);
      expect(request.usesAudioFeatures, isTrue);
      expect(request.bindingsUseAudioFeatures, isFalse);
      expect(request.withoutReactivity().reactivity, AudioReactivity.none);
      expect(request.withoutReactivity().usesAudioFeatures, isFalse);
      expect(request, isNot(request.withoutReactivity()), reason: 'part of equality');
    });

    test('the effect runner wraps the effect the same way', () {
      final request = _request(reactivity: brightnessOnly, audio: constantFeatures(0.5), seconds: 1);
      final runner = EffectRunner(const _Pass(), request);
      final input = FrameCodec.decodeView(
        _setup,
        Uint8List.fromList(List.filled(_setup.frameBytes, 200)),
        duration: const Duration(milliseconds: 33),
      );
      final out = runner.applyAt(10, input);
      expect(out.frame.pixels.first.red, closeTo(100, 1));
      expect(out.radioPanels.first.colors.first.red, closeTo(100, 1));
      final plain = EffectRunner(const _Pass(), request.withoutReactivity()).applyAt(10, input);
      expect(plain.frame.pixels.first.red, 200);
    });
  });

  group('plugin protocol', () {
    test('a plugin of this version applies the reactivity itself, byte-identically', () async {
      final pipe = _Pipe(const [_Dot(), _Seeded()], effects: const [_Pass()]);
      final manifest = await pipe.client.handshake();
      expect(manifest.supportsReactivity, isTrue);
      const speed = AudioReactivity(
        enabled: true,
        modes: {
          ReactiveModeKind.speed: ReactiveMode(min: 1, max: 3),
          ReactiveModeKind.hue: ReactiveMode(min: 0, max: 0.5),
          ReactiveModeKind.restart: ReactiveMode(min: 0, max: 1),
        },
      );
      final request = _request(reactivity: speed, audio: constantFeatures(0.7), tempo: Tempo(bpm: 120));
      final baked = await pipe.client.bake('test.seeded', request);
      expect(baked.toBytes(), bakeBytes(const _Seeded(), request));
      final bakes = pipe.sent.where((m) => m.type == PluginProtocol.bake).toList();
      expect(bakes.single.header['reactivity'], AudioReactivityJson.toJson(speed));

      final inputs = List.generate(
        request.frameCount,
        (i) => FrameCodec.decodeView(_setup, Uint8List.fromList(List.filled(_setup.frameBytes, 120)),
            duration: _setup.framerate.frameDuration(i)),
      );
      final applied = await pipe.client.applyEffect('test.fx.pass', request, inputs);
      final runner = EffectRunner(const _Pass(), request);
      for (var i = 0; i < inputs.length; i++) {
        expect(applied[i].frame.pixels, runner.applyAt(i, inputs[i]).frame.pixels, reason: 'frame $i');
      }
      final applies = pipe.sent.where((m) => m.type == PluginProtocol.apply).toList();
      expect(applies.single.header['reactivity'], AudioReactivityJson.toJson(speed));
      await pipe.client.close();
    });

    test('an inactive reactivity is not sent', () async {
      final pipe = _Pipe(const [_Dot()]);
      await pipe.client.handshake();
      await pipe.client.bake('test.dot', _request(reactivity: AudioReactivity.none, seconds: 0.5));
      expect(pipe.sent.where((m) => m.type == PluginProtocol.bake).single.header.containsKey('reactivity'), isFalse);
      await pipe.client.close();
    });

    test('a plugin built before reactivity gets the request without it; the host post-processes', () async {
      final old = _OldPlugin(const _Dot());
      final client = GeneratorPluginClient(PluginConnection(old.toHost.stream, old.fromHost.sink));
      final manifest = await client.handshake();
      expect(manifest.supportsReactivity, isFalse);
      expect(manifest.capabilities, isEmpty);
      final flash = brightnessOnly.withMode(
        ReactiveModeKind.flash,
        const ReactiveMode(min: 0, max: 1, decay: Duration(milliseconds: 100)),
      );
      final request = _request(reactivity: flash, audio: constantFeatures(0.5), tempo: Tempo(bpm: 120), seconds: 1);
      final baked = await client.bake('test.dot', request);
      expect(old.received.single.containsKey('reactivity'), isFalse);
      expect(old.received.single['audioHash'], isNull, reason: 'the old plugin does not read the audio');
      expect(baked.toBytes(), bakeBytes(const _Dot(), request), reason: 'generic modes match the in-process bake');
      await client.close();
    });
  });
}

/// A host client wired to an in-memory plugin of this version; [sent]
/// records what the host sent.
final class _Pipe {
  final hostToPlugin = StreamController<List<int>>();
  final pluginToHost = StreamController<List<int>>();
  final sent = <PluginMessage>[];
  late final GeneratorPluginClient client;

  _Pipe(List<Generator> generators, {List<Effect> effects = const []}) {
    final split = hostToPlugin.stream.asBroadcastStream();
    split.transform(const PluginMessageDecoder()).listen(sent.add, onError: (Object _) {});
    final pluginInput = StreamController<List<int>>();
    split.listen(pluginInput.add, onDone: pluginInput.close);
    serveGeneratorPlugin(
      generators,
      pluginId: 'test.plugin',
      effects: effects,
      connection: PluginConnection(pluginInput.stream, pluginToHost.sink),
    ).then((_) => pluginToHost.close());
    client = GeneratorPluginClient(PluginConnection(pluginToHost.stream, hostToPlugin.sink));
  }
}

/// A plugin built before reactivity existed: a manifest without
/// `capabilities`, bakes that ignore the `reactivity` header.
final class _OldPlugin {
  final fromHost = StreamController<List<int>>();
  final toHost = StreamController<List<int>>();
  final received = <Map<String, Object?>>[];

  _OldPlugin(Generator generator) {
    final out = PluginConnection(const Stream<List<int>>.empty(), toHost.sink);
    fromHost.stream.transform(const PluginMessageDecoder()).listen((message) {
      switch (message.type) {
        case PluginProtocol.hello:
          out.send(PluginMessage({
            'type': PluginProtocol.manifest,
            'protocol': pluginProtocolVersion,
            'pluginId': 'old',
            'generators': [ManifestJson.entryToJson(GeneratorManifestEntry.of(generator))],
          }));
        case PluginProtocol.bake:
          received.add(message.header);
          final header = message.header;
          final request = BakeRequest(
            setup: PluginProtocol.setupFromJson(header['setup']),
            frameCount: header['frameCount'] as int,
            tempo: PluginProtocol.tempoFromJson(header['tempo']),
            audioOrigin: Duration(microseconds: header['audioOriginUs'] as int),
          );
          final frames = BytesBuilder();
          renderGeneratorFrames(generator, request, (index, duration, rgb) {
            final head = ByteData(2)..setUint16(0, duration.inMilliseconds, Endian.little);
            frames.add(head.buffer.asUint8List());
            frames.add(rgb);
          });
          out.send(PluginMessage(
            {'type': PluginProtocol.frames, 'requestId': header['requestId'], 'first': 0, 'count': request.frameCount},
            frames.takeBytes(),
          ));
          out.send(PluginMessage(
              {'type': PluginProtocol.done, 'requestId': header['requestId'], 'frameCount': request.frameCount}));
      }
    }, onDone: toHost.close);
  }
}
