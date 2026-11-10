import '../generator/generator.dart';
import '../generator/generator_registry.dart';
import 'audio.dart';
import 'audio_extra.dart';
import 'basic.dart';
import 'flicker.dart';
import 'geometry.dart';
import 'motion.dart';
import 'nature.dart';
import 'particles.dart';
import 'physics.dart';

export 'audio.dart';
export 'audio_extra.dart';
export 'basic.dart';
export 'common.dart' show brightnessParam, falloff, gainParam, scaleParam, speedParam;
export 'flicker.dart';
export 'geometry.dart';
export 'motion.dart';
export 'nature.dart';
export 'particles.dart';
export 'physics.dart';

/// The generators that ship with the package, as `const` instances, so an
/// isolate can look one up by id (see [builtInGeneratorRegistry]).
const List<Generator> builtInGenerators = [
  SolidGenerator(),
  GradientGenerator(),
  RainbowGenerator(),
  StrobeGenerator(),
  PlasmaGenerator(),
  NoiseGenerator(),
  AuroraGenerator(),
  WavesGenerator(),
  SnowGenerator(),
  WaterDropsGenerator(),
  SparksGenerator(),
  FirefliesGenerator(),
  VuMeterGenerator(),
  SpectrumGenerator(),
  BassPulseGenerator(),
  OnsetDropsGenerator(),
  // Phase G1b.
  WipeGenerator(),
  ChaseGenerator(),
  ScannerGenerator(),
  BreatheGenerator(),
  MeteorGenerator(),
  BounceGenerator(),
  MarqueeGenerator(),
  BarsGenerator(),
  SnakeGenerator(),
  SlideGenerator(),
  TwinkleGenerator(),
  GlitterGenerator(),
  CandleGenerator(),
  LightningGenerator(),
  FireGenerator(),
  IcicleDripGenerator(),
  IcicleGrowGenerator(),
  RainGenerator(),
  FireworksGenerator(),
  HeartbeatGenerator(),
  RippleGenerator(),
  ShockwaveGenerator(),
  RadialGenerator(),
  ShapesGenerator(),
  CurtainGenerator(),
  KaleidoscopeGenerator(),
  LissajousGenerator(),
  LifeGenerator(),
  TextGenerator(),
  HeatmapGenerator(),
  VignetteGenerator(),
  SpectrumMirrorGenerator(),
  WaveformScrollGenerator(),
  BeatBarsGenerator(),
  FreqColorGenerator(),
  RipplePeakGenerator(),
];

/// A registry of [builtInGenerators].
GeneratorRegistry builtInGeneratorRegistry() => GeneratorRegistry(builtInGenerators);
