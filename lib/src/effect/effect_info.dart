import 'package:equatable/equatable.dart';

import '../generator/localized_text.dart';

/// Where an effect is listed in the bin.
enum EffectCategory {
  /// Brightness, hue, saturation, palettes, tints.
  color,

  /// Flips, mirrors, offsets, tiles, zooms of the pixels.
  transform,

  /// Blurs and glows.
  blur,

  /// Effects over time or the music: trails, echoes, gates, flicker.
  dynamics,

  /// Looks: pixelation, shimmer, vignettes, displacement.
  stylize,
}

/// Identity and presentation of an `Effect` (the same fields as
/// `GeneratorInfo`).
final class EffectInfo extends Equatable {
  /// Stable id, unique across the app: `icicles.fx.<name>` for the built-in
  /// effects, `<pluginId>/<name>` for plugins.
  final String id;

  /// Version of the effect's output. Bump it when the same parameters
  /// render differently, so stored renders are refreshed.
  final int version;

  final LocalizedText name;
  final LocalizedText description;
  final EffectCategory category;

  /// Whether the effect reads `FrameContext.audio` (not counting parameter
  /// bindings, which declare their own needs).
  final bool usesAudio;

  /// Length of a new effect clip.
  final Duration defaultLength;

  const EffectInfo({
    required this.id,
    required this.version,
    required this.name,
    required this.description,
    required this.category,
    this.usesAudio = false,
    this.defaultLength = const Duration(seconds: 10),
  });

  @override
  List<Object?> get props => [id, version, name, description, category, usesAudio, defaultLength];
}
