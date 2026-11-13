import 'dart:math' as math;
import 'dart:typed_data';

import 'package:icicles_animation_dart/icicles_animation_dart.dart';

import '../audio/audio_feature_key.dart';
import '../audio/audio_frame.dart';
import '../bake/bake_request.dart';
import '../effect/effect.dart';
import '../generator/generator.dart';
import '../params/param_spec.dart';
import '../params/param_values.dart';
import '../util/audio_range.dart';
import '../util/color.dart';
import 'audio_reactivity.dart';
import 'reactive_target.dart';

/// The reactive quantities of one frame, from [ReactiveEngine.step].
final class ReactiveFrame {
  /// The shared energy after gate, gain, follower and inversion (`0..1`).
  final double energy;

  /// Brightness factor, `null` while the mode is off.
  final double? brightness;

  /// Speed rate (1 = normal), `null` while the mode is off.
  final double? rate;

  /// Warped generator time: the integral of the rate (generator time while
  /// the speed mode is off).
  final Duration warpedTime;

  /// Hue rotation in turns, `null` while the mode is off.
  final double? hue;

  /// Flash intensity (`0..1`, 0 without a flash).
  final double flash;

  /// Whether the program restarts on this frame.
  final bool restart;

  /// Restarts so far (the seed offset of the current run).
  final int restartCount;

  /// Size level (`0..1` of the parameter's range), `null` while the mode is
  /// off.
  final double? size;

  const ReactiveFrame({
    required this.energy,
    required this.brightness,
    required this.rate,
    required this.warpedTime,
    required this.hue,
    required this.flash,
    required this.restart,
    required this.restartCount,
    required this.size,
  });
}

/// Steps an [AudioReactivity] frame by frame: the energy follower, the
/// trigger edges, the flash decay, the restart count and the time warp. One
/// engine per run; call [step] once per frame in order (deterministic for
/// the same frames).
final class ReactiveEngine {
  final AudioReactivity reactivity;
  final AudioRange _range;
  double _follower = 0;
  double _lastOnset = 0;
  double _lastGained = 0;
  int? _lastBeat;
  double _flash = 0;
  int _restarts = 0;
  int _warpedUs = 0;

  ReactiveEngine(AudioReactivity reactivity)
      : reactivity = reactivity.normalized(),
        _range = reactivity.normalized().audioRange;

  /// The frame's quantities for [audio] after [dt] of generator time (the
  /// first frame's `dt` should be its own duration, not zero).
  ReactiveFrame step(AudioFrame audio, Duration dt) {
    final r = reactivity;
    final raw = _range.energy(audio);
    final gated = r.threshold > 0 ? math.max(0.0, (raw - r.threshold) / (1 - r.threshold)) : raw;
    final gained = (gated * r.sensitivity).clamp(0.0, 1.0);
    _follower = _follow(_follower, gained, _follower < gained ? r.attack : r.release, dt);
    final energy = r.invert ? 1 - _follower : _follower;

    // Trigger edges are evaluated every frame so a mode turned on later sees
    // consistent state.
    final beatFires = audio.bpm > 0 && _lastBeat != null && audio.beatIndex != _lastBeat;
    _lastBeat = audio.bpm > 0 ? audio.beatIndex : null;
    final onsetFires = _lastOnset < AudioReactivity.triggerLevel && audio.onset >= AudioReactivity.triggerLevel;
    _lastOnset = audio.onset;
    final rangeFires = _lastGained < AudioReactivity.triggerLevel && gained >= AudioReactivity.triggerLevel;
    _lastGained = gained;
    bool fires(ReactiveTrigger trigger) => switch (trigger) {
          ReactiveTrigger.beat => beatFires,
          ReactiveTrigger.onset => onsetFires,
          ReactiveTrigger.range => rangeFires,
        };

    final seconds = dt.inMicroseconds / Duration.microsecondsPerSecond;
    final flashMode = r[ReactiveModeKind.flash];
    if (flashMode == null) {
      _flash = 0;
    } else {
      final decay = flashMode.decay.inMicroseconds / Duration.microsecondsPerSecond;
      _flash = decay <= 0 ? 0 : _flash * math.exp(-seconds / decay);
      if (fires(flashMode.trigger)) _flash = math.max(_flash, flashMode.max);
      if (_flash < 1e-3) _flash = 0;
    }

    final restartMode = r[ReactiveModeKind.restart];
    final restart = restartMode != null && fires(restartMode.trigger);
    if (restart) _restarts++;

    // The warped time of this frame is the integral of the rate over the
    // frames before it (frame 0 is at 0, like the plain clock); this frame's
    // advance is added for the next one.
    final speedMode = r[ReactiveModeKind.speed];
    final rate = speedMode?.at(energy);
    final warped = _warpedUs;
    _warpedUs += ((rate ?? 1) * dt.inMicroseconds).round();

    final hueMode = r[ReactiveModeKind.hue];
    final hue = hueMode?.at(hueMode.hueSource == ReactiveHueSource.frequency ? audio.peakFrequency : energy);

    return ReactiveFrame(
      energy: energy,
      brightness: r[ReactiveModeKind.brightness]?.at(energy),
      rate: rate,
      warpedTime: Duration(microseconds: warped),
      hue: hue,
      flash: _flash,
      restart: restart,
      restartCount: _restarts,
      size: r[ReactiveModeKind.size]?.at(energy),
    );
  }

  static double _follow(double previous, double input, Duration time, Duration dt) {
    if (time <= Duration.zero || dt <= Duration.zero) return time <= Duration.zero ? input : previous;
    final k = 1 - math.exp(-dt.inMicroseconds / time.inMicroseconds);
    return previous + (input - previous) * k;
  }

  /// The random generator of run [restartCount] of a bake seeded with
  /// [seed]: the bake's own seed for the first run, a derived one after
  /// every restart (the same on every platform).
  static math.Random randomFor(int seed, int restartCount) =>
      math.Random(restartCount == 0 ? seed : (seed ^ (restartCount * 0x9E3779B9)) & 0x7FFFFFFF);
}

/// The reactive targets a program with [params] offers: the declared
/// [declared] map filtered to existing number/integer parameters, or — when
/// nothing is declared — the conventional ids `brightness`, `speed`, `size`
/// and `hue` when the program has such number parameters.
Map<ReactiveTarget, String> resolveReactiveTargets(Map<ReactiveTarget, String> declared, List<ParamSpec> params) {
  final numeric = {
    for (final spec in params)
      if (spec is NumberParam || spec is IntParam) spec.id
  };
  if (declared.isNotEmpty) {
    return Map.unmodifiable({
      for (final MapEntry(:key, :value) in declared.entries)
        if (numeric.contains(value)) key: value
    });
  }
  return Map.unmodifiable({
    for (final target in ReactiveTarget.values)
      if (numeric.contains(target.name)) target: target.name
  });
}

/// The parameter values of [ctx] with the native targets of [frame] written
/// in: brightness scales, speed multiplies, size sets across the range, hue
/// shifts (wrapping) across the range — each clamped by its spec.
ParamValues reactiveParams(
    FrameContext ctx, ReactiveFrame frame, Map<ReactiveTarget, String> targets, List<ParamSpec> params) {
  if (targets.isEmpty) return ctx.params;
  final values = Map<String, Object>.of(ctx.params.toMap());
  var changed = false;
  for (final MapEntry(key: target, value: id) in targets.entries) {
    final spec = params.where((s) => s.id == id).firstOrNull;
    final (double min, double max) = switch (spec) {
      NumberParam(:final min, :final max) => (min, max),
      IntParam(:final min, :final max) => (min.toDouble(), max.toDouble()),
      _ => (0.0, 0.0),
    };
    if (spec == null || (spec is! NumberParam && spec is! IntParam)) continue;
    final base = (values[id] as num?)?.toDouble();
    if (base == null) continue;
    final span = max - min;
    final double? raw = switch (target) {
      ReactiveTarget.brightness => frame.brightness == null ? null : base * frame.brightness!,
      ReactiveTarget.speed => frame.rate == null ? null : base * frame.rate!,
      ReactiveTarget.size => frame.size == null ? null : min + span * frame.size!,
      ReactiveTarget.hue => frame.hue == null || span <= 0 ? null : min + ((base - min + frame.hue! * span) % span),
    };
    if (raw == null) continue;
    values[id] = spec.numericValue(raw);
    changed = true;
  }
  return changed ? ParamValues(values) : ctx.params;
}

/// [color] with the generic post-process of [frame] applied: dimmed by the
/// brightness factor (unless [nativeBrightness]), hue-rotated (unless
/// [nativeHue]) and the flash of [flashColor] added.
Color reactiveColor(Color color, ReactiveFrame frame, Color flashColor,
    {required bool nativeBrightness, required bool nativeHue}) {
  var c = color;
  if (!nativeBrightness && frame.brightness != null) c = dim(c, frame.brightness!);
  if (!nativeHue && frame.hue != null && frame.hue != 0) {
    final h = hsvOf(c);
    if (h.saturation > 0) c = hsv(h.hue + frame.hue!, h.saturation, h.value);
  }
  if (frame.flash > 0) c = addColors(c, dim(flashColor, frame.flash));
  return c;
}

/// Writes every pixel and radio panel LED of [source] into [out] through
/// [reactiveColor] ([source] may be [out] itself when nothing persists in it
/// between frames — an effect's output; a generator's own buffer must stay
/// untouched, so its wrapper renders into a private one).
void applyReactivePost(Icicles source, Icicles out, ReactiveFrame frame, Color flashColor,
    {required bool nativeBrightness, required bool nativeHue}) {
  final plain = (nativeBrightness || frame.brightness == null) && (nativeHue || frame.hue == null) && frame.flash <= 0;
  if (plain && identical(source, out)) return;
  for (var i = 0; i < out.pixelsCount; i++) {
    final c = source.getPixelColorAtIndex(i);
    out.setPixelColorAtIndex(
      i,
      plain ? c : reactiveColor(c, frame, flashColor, nativeBrightness: nativeBrightness, nativeHue: nativeHue),
    );
  }
  for (var p = 0; p < out.radioPanelsCount; p++) {
    final panel = source.radioPanels[p];
    for (var i = 0; i < panel.length; i++) {
      final c = panel.getPixelColorAtIndex(i);
      out.setRadioPanelPixelColor(
        p,
        i,
        plain ? c : reactiveColor(c, frame, flashColor, nativeBrightness: nativeBrightness, nativeHue: nativeHue),
      );
    }
  }
}

/// A fresh, black frame buffer of the layout of [setup].
Icicles _bufferFor(GeneratorSetup setup, String id) => Icicles(Animation(
      id,
      xCount: setup.xCount,
      yCount: setup.yCount,
      framerate: setup.framerate,
      radioPanelsCount: setup.radioPanelsCount,
      radioPanelPixelCount: setup.radioPanelPixelCount,
    ));

/// Applies [reactiveColor] to the RGB bytes of one frame in [rgb] from
/// [offset] (`frameBytes` of them).
void applyReactivePostBytes(Uint8List rgb, int offset, int frameBytes, ReactiveFrame frame, Color flashColor,
    {bool nativeBrightness = false, bool nativeHue = false}) {
  if ((nativeBrightness || frame.brightness == null) && (nativeHue || frame.hue == null) && frame.flash <= 0) return;
  for (var o = offset; o < offset + frameBytes; o += 3) {
    final c = reactiveColor(Color.fromRGB(rgb[o], rgb[o + 1], rgb[o + 2]), frame, flashColor,
        nativeBrightness: nativeBrightness, nativeHue: nativeHue);
    rgb[o] = c.red;
    rgb[o + 1] = c.green;
    rgb[o + 2] = c.blue;
  }
}

/// The frame context [ctx] as the wrapped program sees it: warped time
/// (unless the speed drives a native parameter), the reactive parameters and
/// the run's random generator.
FrameContext _innerContext(FrameContext ctx, ReactiveFrame frame, ParamValues params, math.Random random,
    {required bool nativeSpeed}) {
  final warp = !nativeSpeed && frame.rate != null;
  return FrameContext(
    setup: ctx.setup,
    frameIndex: ctx.frameIndex,
    time: warp ? frame.warpedTime : ctx.time,
    delta: warp ? Duration(microseconds: (ctx.delta.inMicroseconds * frame.rate!).round()) : ctx.delta,
    params: params,
    audio: ctx.audio,
    random: random,
  );
}

Duration _dtOf(FrameContext ctx) =>
    ctx.delta > Duration.zero ? ctx.delta : ctx.setup.framerate.frameDuration(ctx.frameIndex);

/// A [GeneratorInstance] applying an [AudioReactivity] around the instances
/// of [generator]: per frame the [ReactiveEngine] turns the frame's audio
/// into the quantities, native targets are written into the parameters
/// ([resolveReactiveTargets]), the speed warps the frame clock otherwise,
/// a restart re-creates the instance with a derived seed, and the generic
/// brightness / hue / flash post-process runs over the rendered frame. The
/// bake uses it when `BakeRequest.reactivity` is active.
final class ReactiveGeneratorInstance implements GeneratorInstance {
  final Generator generator;
  final GeneratorSetup setup;
  final ReactiveEngine engine;
  final Map<ReactiveTarget, String> targets;

  /// The generator's own frame buffer: it keeps the generator's previous
  /// frame (not the post-processed one), as the contract promises.
  final Icicles _buffer;
  GeneratorInstance _instance;
  math.Random _random;

  ReactiveGeneratorInstance(this.generator, this.setup, AudioReactivity reactivity)
      : engine = ReactiveEngine(reactivity),
        targets = resolveReactiveTargets(generator.info.reactiveTargets, generator.params),
        _buffer = _bufferFor(setup, generator.info.id),
        _instance = generator.create(setup),
        _random = ReactiveEngine.randomFor(setup.seed, 0);

  /// Restarts so far.
  int get restartCount => _restarts;
  int _restarts = 0;

  @override
  void render(FrameContext ctx, Icicles out) {
    final frame = engine.step(ctx.audio, _dtOf(ctx));
    if (frame.restart) {
      _instance = generator.create(setup);
      _random = ReactiveEngine.randomFor(setup.seed, frame.restartCount);
      _restarts = frame.restartCount;
    }
    final params = reactiveParams(ctx, frame, targets, generator.params);
    _instance.render(
        _innerContext(ctx, frame, params, _random, nativeSpeed: targets.containsKey(ReactiveTarget.speed)), _buffer);
    applyReactivePost(
      _buffer,
      out,
      frame,
      engine.reactivity[ReactiveModeKind.flash]?.flashColor ?? const Color(0xFFFFFFFF),
      nativeBrightness: targets.containsKey(ReactiveTarget.brightness),
      nativeHue: targets.containsKey(ReactiveTarget.hue),
    );
  }
}

/// [ReactiveGeneratorInstance] for an [Effect]: the same wrapper around
/// `EffectInstance.apply` (the post-process runs over the effect's output,
/// a restart re-creates the effect instance — trails and echoes start over).
final class ReactiveEffectInstance implements EffectInstance {
  final Effect effect;
  final GeneratorSetup setup;
  final ReactiveEngine engine;
  final Map<ReactiveTarget, String> targets;
  EffectInstance _instance;
  math.Random _random;

  ReactiveEffectInstance(this.effect, this.setup, AudioReactivity reactivity)
      : engine = ReactiveEngine(reactivity),
        targets = resolveReactiveTargets(effect.info.reactiveTargets, effect.params),
        _instance = effect.create(setup),
        _random = ReactiveEngine.randomFor(setup.seed, 0);

  @override
  void apply(FrameContext ctx, AnimationView input, Icicles out) {
    final frame = engine.step(ctx.audio, _dtOf(ctx));
    if (frame.restart) {
      _instance = effect.create(setup);
      _random = ReactiveEngine.randomFor(setup.seed, frame.restartCount);
    }
    final params = reactiveParams(ctx, frame, targets, effect.params);
    _instance.apply(
        _innerContext(ctx, frame, params, _random, nativeSpeed: targets.containsKey(ReactiveTarget.speed)), input, out);
    applyReactivePost(
      out,
      out,
      frame,
      engine.reactivity[ReactiveModeKind.flash]?.flashColor ?? const Color(0xFFFFFFFF),
      nativeBrightness: targets.containsKey(ReactiveTarget.brightness),
      nativeHue: targets.containsKey(ReactiveTarget.hue),
    );
  }
}

/// The host-side fallback for plugins built before reactivity existed: the
/// generic brightness / hue / flash post-process of `request.reactivity`
/// over the frames a plugin returns, fed by the request's own audio clock.
/// The speed, restart and size modes need the program and are skipped.
final class ReactivePostProcessor {
  final BakeRequest request;
  ReactiveEngine _engine;
  int _next = 0;

  static final _silent = Float32List(AudioFeatureKey.columnCount);

  ReactivePostProcessor(this.request) : _engine = ReactiveEngine(request.reactivity);

  /// The engine of the current run.
  ReactiveEngine get engine => _engine;

  /// Whether the processor changes anything for [request].
  static bool applies(BakeRequest request) {
    final r = request.reactivity;
    return r.isActive &&
        (r[ReactiveModeKind.brightness] != null ||
            r[ReactiveModeKind.hue] != null ||
            r[ReactiveModeKind.flash] != null);
  }

  /// The audio frame of grid frame [index] of [request] (the resolver's
  /// sampling: song time `audioOrigin + frameStart`, beat fields from the
  /// beats, else the tempo).
  static AudioFrame audioFrameAt(BakeRequest request, int index) {
    final songTime = request.audioOrigin + request.setup.framerate.frameStart(index);
    final audio = request.audio;
    if (audio != null) return audio.sampleAt(songTime, tempo: request.tempo, beats: request.beats);
    if (request.tempo == null && request.beats == null) return AudioFrame.silent;
    return AudioFrame.fromColumns(_silent, tempo: request.tempo, beats: request.beats, time: songTime);
  }

  /// Post-processes frame [index] (frames in order from 0; an earlier index
  /// restarts the engine) in [rgb] from [offset].
  void process(int index, Uint8List rgb, int offset) {
    if (index < _next) {
      _next = 0;
      _engine = ReactiveEngine(request.reactivity);
    }
    final framerate = request.setup.framerate;
    ReactiveFrame? frame;
    while (_next <= index) {
      final i = _next++;
      final dt = i == 0 ? framerate.frameDuration(0) : framerate.frameStart(i) - framerate.frameStart(i - 1);
      frame = engine.step(audioFrameAt(request, i), dt);
    }
    if (frame == null) return;
    applyReactivePostBytes(
      rgb,
      offset,
      request.setup.frameBytes,
      frame,
      engine.reactivity[ReactiveModeKind.flash]?.flashColor ?? const Color(0xFFFFFFFF),
    );
  }
}
