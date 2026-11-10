import '../effect/effect.dart';
import '../effect/effect_registry.dart';
import 'blur.dart';
import 'color.dart';
import 'dynamics.dart';
import 'stylize.dart';
import 'transform.dart';

export 'blur.dart';
export 'color.dart';
export 'common.dart' show effectPanelsParam, mixParam;
export 'dynamics.dart';
export 'stylize.dart';
export 'transform.dart';

/// The effects that ship with the package, as `const` instances, so an
/// isolate can look one up by id (see [builtInEffectRegistry]).
const List<Effect> builtInEffects = [
  // Color.
  BrightnessEffect(),
  HueShiftEffect(),
  SaturationEffect(),
  InvertEffect(),
  PosterizeEffect(),
  ThresholdEffect(),
  PaletteRemapEffect(),
  TintEffect(),
  // Transform.
  FlipEffect(),
  MirrorEffect(),
  OffsetEffect(),
  Rotate180Effect(),
  TileEffect(),
  ZoomEffect(),
  // Blur.
  BlurVerticalEffect(),
  BlurBoxEffect(),
  GlowEffect(),
  // Dynamics.
  TrailEffect(),
  EchoEffect(),
  StrobeGateEffect(),
  FlickerEffect(),
  GateAudioEffect(),
  // Stylize.
  PixelateEffect(),
  ShimmerEffect(),
  FadeEdgesEffect(),
  NoiseDisplaceEffect(),
];

/// A registry of [builtInEffects].
EffectRegistry builtInEffectRegistry() => EffectRegistry(builtInEffects);
