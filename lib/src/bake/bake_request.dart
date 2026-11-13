import 'package:equatable/equatable.dart';
import 'package:icicles_animation_dart/icicles_animation_dart.dart';

import '../audio/audio_features.dart';
import '../generator/generator.dart';
import '../generator/generator_exception.dart';
import '../generator/generator_info.dart';
import '../params/param_binding.dart';
import '../reactive/audio_reactivity.dart';
import '../time/beat_grid.dart';
import '../time/frame_grid.dart';
import '../time/tempo.dart';

/// The longest bake. Memory of a bake is about frames × (pixels + panel
/// pixels) × 4 bytes while the animation is built, so a 10-minute bake of
/// 24×20 at 30 fps is about 35 MB.
const maxBakeLength = Duration(minutes: 10);

/// What to bake: the layout and seed, the length on the frame grid, the
/// parameter bindings and the audio clock.
final class BakeRequest extends Equatable {
  final GeneratorSetup setup;

  /// Grid frames to render: frame `i` starts at `framerate.frameStart(i)`
  /// and lasts `framerate.frameDuration(i)`.
  final int frameCount;

  /// Bindings by parameter id; salvaged against the generator's schema
  /// (missing ids get the default).
  final Map<String, ParamBinding> bindings;

  /// Song-wide features, `null` without a soundtrack.
  final AudioFeatures? audio;

  /// The constant beat grid on the same clock as [audio], `null` without
  /// one. The fallback beat clock when [beats] is `null`.
  final Tempo? tempo;

  /// The real beats (and downbeats) of the music on the same clock as
  /// [audio], `null` without a beat tracker's result. Wins over [tempo] for
  /// the beat fields and the beat-based bindings.
  final BeatGrid? beats;

  /// Time on the [audio]/[tempo] clock of generator time 0 (the song time
  /// at the clip's source start).
  final Duration audioOrigin;

  /// Name of the baked animation; the generator's English name when `null`.
  final String? name;

  /// The composition's macros by id: named global bindings a
  /// [MacroBinding] reads, each evaluated on the same clock as the
  /// parameters (keyframed, audio-driven…; one level — a macro reading a
  /// macro resolves to nothing).
  final Map<String, ParamBinding> macros;

  /// Universal audio reactivity applied around the program
  /// (`ReactiveGeneratorInstance` / `ReactiveEffectInstance`);
  /// [AudioReactivity.none] by default.
  final AudioReactivity reactivity;

  const BakeRequest({
    required this.setup,
    required this.frameCount,
    this.bindings = const {},
    this.audio,
    this.tempo,
    this.beats,
    this.audioOrigin = Duration.zero,
    this.name,
    this.macros = const {},
    this.reactivity = AudioReactivity.none,
  });

  /// A request covering `[0, length)` on the setup's frame grid.
  factory BakeRequest.forLength({
    required GeneratorSetup setup,
    required Duration length,
    Map<String, ParamBinding> bindings = const {},
    AudioFeatures? audio,
    Tempo? tempo,
    BeatGrid? beats,
    Duration audioOrigin = Duration.zero,
    String? name,
    Map<String, ParamBinding> macros = const {},
    AudioReactivity reactivity = AudioReactivity.none,
  }) =>
      BakeRequest(
        setup: setup,
        frameCount: frameCountFor(setup.framerate, length),
        bindings: bindings,
        audio: audio,
        tempo: tempo,
        beats: beats,
        audioOrigin: audioOrigin,
        name: name,
        macros: macros,
        reactivity: reactivity,
      );

  /// Whether the bindings (or a macro one of them reads) read the analysed
  /// audio.
  bool get bindingsUseAudioFeatures => bindingsUseAudio(bindings, macros);

  /// Whether the bindings (or a macro one of them reads) depend on the
  /// audio clock: the analysed audio or the beat clock (tempo / beats).
  bool get bindingsUseAudioClock => bindingsUseAudio(bindings, macros) || bindingsUseTempo(bindings, macros);

  /// Whether the bindings, their macros or the reactivity read the analysed
  /// audio.
  bool get usesAudioFeatures => bindingsUseAudioFeatures || reactivity.usesAudioFeatures;

  /// Whether the bindings, their macros or the reactivity depend on the
  /// audio clock.
  bool get usesAudioClock => bindingsUseAudioClock || reactivity.usesAudioFeatures || reactivity.usesTempo;

  /// This request without its reactivity (what a plugin that cannot apply
  /// it is asked for; the host post-processes the frames).
  BakeRequest withoutReactivity() => BakeRequest(
        setup: setup,
        frameCount: frameCount,
        bindings: bindings,
        audio: audio,
        tempo: tempo,
        beats: beats,
        audioOrigin: audioOrigin,
        name: name,
        macros: macros,
      );

  /// Grid time of all frames.
  Duration get length => setup.framerate.frameStart(frameCount);

  /// Throws a [GeneratorException] when the request cannot be baked.
  void validate() {
    if (frameCount <= 0) {
      throw GeneratorException(GeneratorErrorKind.invalidRequest, 'Nothing to bake: $frameCount frames.');
    }
    if (length > maxBakeLength) {
      throw GeneratorException(
        GeneratorErrorKind.tooLong,
        'The bake is ${length.inSeconds} s long; at most ${maxBakeLength.inSeconds} s.',
      );
    }
    final s = setup;
    if (s.xCount < 1 || s.xCount > 255 || s.yCount < 1 || s.yCount > 255) {
      throw GeneratorException(GeneratorErrorKind.invalidRequest, 'Invalid size ${s.xCount}×${s.yCount}.');
    }
    if (s.radioPanelsCount < 0 ||
        s.radioPanelsCount > 255 ||
        s.radioPanelPixelCount < 1 ||
        s.radioPanelPixelCount > 255) {
      throw GeneratorException(
        GeneratorErrorKind.invalidRequest,
        'Invalid radio panels ${s.radioPanelsCount}×${s.radioPanelPixelCount}.',
      );
    }
    if (s.framerate == Framerate.unlimited) {
      throw const GeneratorException(GeneratorErrorKind.invalidRequest, 'Generators need a fixed framerate.');
    }
  }

  @override
  List<Object?> get props =>
      [setup, frameCount, bindings, audio?.contentHash, tempo, beats, audioOrigin, name, macros, reactivity];
}

/// Whether a generator with [info] baked with [bindings] (and [reactivity])
/// reads the analysed audio (then a bake needs `BakeRequest.audio`).
/// [macros] are the request's macros: a [MacroBinding] reads the audio when
/// its macro does; an active [reactivity] always does.
bool needsAudioFeatures(GeneratorInfo info, Map<String, ParamBinding> bindings,
        {Map<String, ParamBinding> macros = const {}, AudioReactivity reactivity = AudioReactivity.none}) =>
    info.usesAudio || bindingsUseAudio(bindings, macros) || reactivity.usesAudioFeatures;

/// Whether the output depends on the audio clock (audio features or the
/// tempo), so the clip's position relative to the song matters
/// (`audioOrigin`).
bool needsAudioClock(GeneratorInfo info, Map<String, ParamBinding> bindings,
        {Map<String, ParamBinding> macros = const {}, AudioReactivity reactivity = AudioReactivity.none}) =>
    info.usesAudio ||
    bindingsUseAudio(bindings, macros) ||
    bindingsUseTempo(bindings, macros) ||
    reactivity.usesAudioFeatures ||
    reactivity.usesTempo;

/// Whether any of [bindings] reads the analysed audio, following the
/// [MacroBinding]s into [macros].
bool bindingsUseAudio(Map<String, ParamBinding> bindings, Map<String, ParamBinding> macros) =>
    bindings.values.any((b) => b.usesAudioFeatures || _macrosOf(b).any((id) => macros[id]?.usesAudioFeatures ?? false));

/// Whether any of [bindings] reads the tempo, following the
/// [MacroBinding]s into [macros].
bool bindingsUseTempo(Map<String, ParamBinding> bindings, Map<String, ParamBinding> macros) =>
    bindings.values.any((b) => b.usesTempo || _macrosOf(b).any((id) => macros[id]?.usesTempo ?? false));

/// The ids of the macros [binding] reads (through a stack's base, sources
/// and depth bindings).
Iterable<String> _macrosOf(ParamBinding binding) sync* {
  switch (binding) {
    case MacroBinding(:final macroId):
      yield macroId;
    case StackedBinding(:final base, :final modulators):
      yield* _macrosOf(base);
      for (final m in modulators) {
        yield* _macrosOf(m.source);
        if (m.depthBinding case final depth?) yield* _macrosOf(depth);
      }
    default:
      break;
  }
}
