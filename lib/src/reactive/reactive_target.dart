/// A quantity of a generator or effect that audio reactivity can drive
/// through one of the program's own parameters (`GeneratorInfo.reactiveTargets`
/// / `EffectInfo.reactiveTargets` map a target to a parameter id).
///
/// When a program declares a target, the reactive wrapper writes the music
/// into that parameter (a generator's own `speed` moves its particles
/// faster, its `size` grows its shapes); without one, the brightness, speed
/// and hue modes fall back to a generic post-process of the rendered frame
/// (time warp, pixel dimming, hue rotation), and the size mode does nothing.
enum ReactiveTarget {
  /// A number parameter scaled by the brightness factor.
  brightness,

  /// A number parameter multiplied by the speed rate.
  speed,

  /// A number parameter set across its range by the size level.
  size,

  /// A number parameter shifted (wrapping) across its range by the hue
  /// amount in turns.
  hue;

  static ReactiveTarget? fromName(String? name) => values.where((t) => t.name == name).firstOrNull;
}
