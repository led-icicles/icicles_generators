/// A per-frame audio value a generator or an [AudioBinding] can read, each
/// in `0..1`.
///
/// The first [columnCount] keys are the columns of [AudioFeatures] (in this
/// order); the beat keys are derived from a `Tempo` at bake time.
enum AudioFeatureKey {
  /// RMS loudness.
  level,

  /// 20–250 Hz.
  bass,

  /// 250–4000 Hz.
  mid,

  /// 4–16 kHz.
  treble,

  /// Spectral flux: how suddenly new energy appears (hits, notes).
  onset,

  /// The loudest frequency on a log scale: 0 = 40 Hz, 1 = 16 kHz (0 in
  /// silence).
  peakFrequency,

  /// Mel band 1 of 16 (40 Hz…), up to [band15] (…16 kHz).
  band0,
  band1,
  band2,
  band3,
  band4,
  band5,
  band6,
  band7,
  band8,
  band9,
  band10,
  band11,
  band12,
  band13,
  band14,
  band15,

  /// 1 on a beat, decaying exponentially until the next one.
  beatPulse,

  /// Position within the current beat, `0..1`.
  beatPhase,

  /// Position within the current 4-beat bar, `0..1`.
  barPhase;

  /// Number of keys stored as [AudioFeatures] columns.
  static const columnCount = 22;

  /// Index of the first mel band column.
  static const firstBand = 6;

  /// Number of mel bands.
  static const bandCount = 16;

  /// Whether the value comes from the analysed audio (not from the tempo).
  bool get isColumn => index < columnCount;

  /// Whether the value comes from the tempo.
  bool get isBeat => index >= columnCount;

  /// The key of mel band [band] (`0..15`).
  static AudioFeatureKey band(int band) {
    RangeError.checkValueInInterval(band, 0, bandCount - 1, 'band');
    return values[firstBand + band];
  }
}
