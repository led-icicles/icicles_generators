import 'package:equatable/equatable.dart';

import '../reactive/reactive_target.dart';
import 'localized_text.dart';

/// Where a generator is listed in the bin.
enum GeneratorCategory {
  /// Static colors and simple fills.
  basic,

  /// Things that move along or across the icicles: chases, wipes, scanners.
  motion,

  /// Organic effects: fire, water, snow, plasma, noise.
  nature,

  /// Many small lights: sparks, twinkles, fireworks.
  particles,

  /// 2D patterns over the grid: rings, shapes, text, masks.
  geometry,

  /// Driven by the music.
  audio,
}

/// Identity and presentation of a [Generator].
final class GeneratorInfo extends Equatable {
  /// Stable id, unique across the app: `icicles.<name>` for the built-in
  /// generators, `<pluginId>/<name>` for plugins.
  final String id;

  /// Version of the generator's output. Bump it when the same parameters
  /// render differently, so stored bakes are refreshed.
  final int version;

  final LocalizedText name;
  final LocalizedText description;
  final GeneratorCategory category;

  /// Whether the generator reads [FrameContext.audio] features (not counting
  /// parameter bindings, which declare their own needs).
  final bool usesAudio;

  /// Length of a new clip of this generator.
  final Duration defaultLength;

  /// The generator's own parameters audio reactivity drives natively, by
  /// [ReactiveTarget] (`{ReactiveTarget.speed: 'speed'}`): the reactive
  /// wrapper writes the music into these instead of post-processing the
  /// frame. Empty means "by convention": number parameters with the ids
  /// `brightness`, `speed`, `size` and `hue` (see `resolveReactiveTargets`).
  final Map<ReactiveTarget, String> reactiveTargets;

  const GeneratorInfo({
    required this.id,
    required this.version,
    required this.name,
    required this.description,
    required this.category,
    this.usesAudio = false,
    this.defaultLength = const Duration(seconds: 10),
    this.reactiveTargets = const {},
  });

  @override
  List<Object?> get props => [
        id,
        version,
        name,
        description,
        category,
        usesAudio,
        defaultLength,
        for (final target in ReactiveTarget.values) reactiveTargets[target],
      ];
}
