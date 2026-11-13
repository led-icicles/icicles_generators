/// Parametric, audio-reactive generators for icicles animations: the
/// generator contract, the parameter schema and bindings, song-wide audio
/// features, the baker that renders a generator into an animation, helpers
/// and the built-in generators.
///
/// Effects (adjustment layers over the composited layers below) share the
/// parameter schema: the contract, runner and built-in catalog are exported
/// here too.
///
/// Pure Dart: no Flutter and no `dart:io`. The out-of-process plugin
/// protocol is the separate `package:icicles_generators/plugin.dart`.
library;

export 'src/audio/audio_feature_extractor.dart';
export 'src/audio/audio_feature_key.dart';
export 'src/audio/audio_features.dart';
export 'src/audio/audio_frame.dart';
export 'src/bake/bake.dart';
export 'src/bake/bake_request.dart';
export 'src/bake/frame_assembler.dart';
export 'src/bake/frame_codec.dart';
export 'src/builtin/built_in_generators.dart';
export 'src/builtin_effects/built_in_effects.dart';
export 'src/effect/effect.dart';
export 'src/effect/effect_info.dart';
export 'src/effect/effect_registry.dart';
export 'src/effect/effect_runner.dart';
export 'src/generator/generator.dart';
export 'src/generator/generator_exception.dart';
export 'src/generator/generator_info.dart';
export 'src/generator/generator_registry.dart';
export 'src/generator/localized_text.dart';
export 'src/params/param_binding.dart';
export 'src/params/param_binding_json.dart';
export 'src/params/param_resolver.dart';
export 'src/params/param_spec.dart';
export 'src/params/param_values.dart';
export 'src/reactive/audio_reactivity.dart';
export 'src/reactive/reactive_instance.dart';
export 'src/reactive/reactive_target.dart';
export 'src/time/beat_grid.dart';
export 'src/time/frame_grid.dart';
export 'src/time/tempo.dart';
export 'src/util/audio_range.dart';
export 'src/util/color.dart';
export 'src/util/direction.dart';
export 'src/util/font3x5.dart';
export 'src/util/noise.dart';
export 'src/util/palette.dart';
export 'src/util/panel_mode.dart';
