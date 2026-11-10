import 'dart:math' as math;

import '../audio/audio_frame.dart';
import '../generator/localized_text.dart';
import '../params/param_spec.dart';
import '../params/param_values.dart';

/// A part of the spectrum an audio-driven generator follows, like LedFx's
/// per-effect "frequency range": a preset band or a [custom] Hz pair.
enum AudioRangePreset {
  full('full', 20, 16000, LocalizedText('Full spectrum', pl: 'Całe widmo')),
  lows('lows', 20, 250, LocalizedText('Lows (20–250 Hz)', pl: 'Basy (20–250 Hz)')),
  lowMids('lowMids', 250, 500, LocalizedText('Low mids (250–500 Hz)', pl: 'Niskie średnie (250–500 Hz)')),
  mids('mids', 500, 2000, LocalizedText('Mids (500 Hz–2 kHz)', pl: 'Średnie (500 Hz–2 kHz)')),
  highMids('highMids', 2000, 4000, LocalizedText('High mids (2–4 kHz)', pl: 'Wysokie średnie (2–4 kHz)')),
  highs('highs', 4000, 16000, LocalizedText('Highs (4–16 kHz)', pl: 'Wysokie (4–16 kHz)')),
  custom('custom', 20, 16000, LocalizedText('Custom (Hz)', pl: 'Własny (Hz)'));

  /// The option id stored in projects.
  final String id;

  /// Lower bound in Hz (the whole spectrum for [custom]; the custom pair
  /// comes from the `…LowHz`/`…HighHz` parameters).
  final double lowHz;

  /// Upper bound in Hz.
  final double highHz;
  final LocalizedText label;

  const AudioRangePreset(this.id, this.lowHz, this.highHz, this.label);

  /// The choice option of this preset.
  ChoiceOption get option => ChoiceOption(id, label);

  /// The preset of option [id], [fallback] for an unknown one.
  static AudioRangePreset fromId(String id, [AudioRangePreset fallback = AudioRangePreset.full]) =>
      values.firstWhere((p) => p.id == id, orElse: () => fallback);
}

/// Lowest frequency of a range parameter.
const audioRangeMinHz = 20.0;

/// Highest frequency of a range parameter.
const audioRangeMaxHz = 16000.0;

/// A resolved frequency range in Hz (`lowHz ≤ highHz`).
final class AudioRange {
  final double lowHz;
  final double highHz;

  /// The range `[lowHz, highHz]` (swapped when reversed, clamped to
  /// [audioRangeMinHz]..[audioRangeMaxHz]).
  AudioRange(double lowHz, double highHz)
      : lowHz = math.min(lowHz, highHz).clamp(audioRangeMinHz, audioRangeMaxHz),
        highHz = math.max(lowHz, highHz).clamp(audioRangeMinHz, audioRangeMaxHz);

  /// The bounds of [preset] (the whole spectrum for [AudioRangePreset.custom]).
  AudioRange.ofPreset(AudioRangePreset preset) : this(preset.lowHz, preset.highHz);

  static double _mel(double hz) => 2595 * math.log(1 + hz / 700) / math.ln10;
  static double _hz(double mel) => 700 * (math.pow(10, mel / 2595) - 1);

  /// The frequency at [position] (`0` = [lowHz], `1` = [highHz]) on the mel
  /// scale — the spectrum generators map this across the icicles.
  double frequencyAt(double position) {
    final t = position.isFinite ? position.clamp(0.0, 1.0) : 0.0;
    final low = _mel(lowHz);
    return _hz(low + (_mel(highHz) - low) * t);
  }

  /// The spectrum of [audio] at [position] of this range (see
  /// [frequencyAt], [AudioFrame.bandAtHz]).
  double spectrumAt(AudioFrame audio, double position) => audio.bandAtHz(frequencyAt(position));

  /// The energy of [audio] in this range ([AudioFrame.energyBetween]).
  double energy(AudioFrame audio) => audio.energyBetween(lowHz, highHz);

  @override
  String toString() => 'AudioRange($lowHz–$highHz Hz)';
}

const _rangeLabel = LocalizedText('Frequency range', pl: 'Zakres częstotliwości');
const _customOnly = LocalizedText('Custom range only.', pl: 'Tylko dla zakresu własnego.');

/// The standard frequency-range parameters: a [ChoiceParam] `<prefix>` over
/// the [AudioRangePreset]s (default [defaultPreset]) and the two
/// [NumberParam]s `<prefix>LowHz` / `<prefix>HighHz` (20–16000 Hz, log
/// scale) read only with the `custom` preset. Resolve them with
/// [audioRangeOf] / [audioRangeValue].
List<ParamSpec> audioRangeParams({
  String prefix = 'range',
  AudioRangePreset defaultPreset = AudioRangePreset.lows,
  LocalizedText label = _rangeLabel,
  LocalizedText? description,
}) =>
    List.unmodifiable([
      ChoiceParam(
        id: prefix,
        label: label,
        description: description,
        options: List.unmodifiable([for (final preset in AudioRangePreset.values) preset.option]),
        defaultValue: defaultPreset.id,
      ),
      NumberParam(
        id: '${prefix}LowHz',
        label: const LocalizedText('Range from', pl: 'Zakres od'),
        description: _customOnly,
        min: audioRangeMinHz,
        max: audioRangeMaxHz,
        defaultValue: defaultPreset == AudioRangePreset.custom ? audioRangeMinHz : defaultPreset.lowHz,
        scale: NumberScale.log,
        unit: 'Hz',
      ),
      NumberParam(
        id: '${prefix}HighHz',
        label: const LocalizedText('Range to', pl: 'Zakres do'),
        description: _customOnly,
        min: audioRangeMinHz,
        max: audioRangeMaxHz,
        defaultValue: defaultPreset == AudioRangePreset.custom ? audioRangeMaxHz : defaultPreset.highHz,
        scale: NumberScale.log,
        unit: 'Hz',
      ),
    ]);

/// The range the [audioRangeParams] with [prefix] select in [p]: the
/// preset's bounds, or the custom pair (swapped when reversed).
AudioRange audioRangeOf(ParamValues p, {String prefix = 'range'}) {
  final preset = AudioRangePreset.fromId(p.choice(prefix));
  if (preset != AudioRangePreset.custom) return AudioRange.ofPreset(preset);
  return AudioRange(p.number('${prefix}LowHz'), p.number('${prefix}HighHz'));
}

/// The energy (`0..1`) of [audio] in the range the [audioRangeParams] with
/// [prefix] select in [p].
double audioRangeValue(ParamValues p, AudioFrame audio, {String prefix = 'range'}) =>
    audioRangeOf(p, prefix: prefix).energy(audio);

/// What an audio-driven generator follows, the value of [audioSourceParam].
enum AudioSource {
  level('level', LocalizedText('Loudness', pl: 'Głośność')),
  range('range', LocalizedText('Frequency range', pl: 'Zakres częstotliwości')),
  onset('onset', LocalizedText('Hits (onset)', pl: 'Uderzenia (onset)')),
  beat('beat', LocalizedText('Beat pulse (needs a tempo)', pl: 'Puls tempa (wymaga tempa)'));

  /// The option id stored in projects.
  final String id;
  final LocalizedText label;

  const AudioSource(this.id, this.label);

  /// The choice option of this source.
  ChoiceOption get option => ChoiceOption(id, label);

  /// The source of option [id], [fallback] for an unknown one.
  static AudioSource fromId(String id, [AudioSource fallback = AudioSource.range]) =>
      values.firstWhere((s) => s.id == id, orElse: () => fallback);
}

/// The standard "follows" parameter (`source` by default): loudness, the
/// frequency range of the [audioRangeParams], onsets or the beat pulse.
/// Read it with [audioSourceValue].
ChoiceParam audioSourceParam({
  String id = 'source',
  LocalizedText label = const LocalizedText('Follows', pl: 'Reaguje na'),
  LocalizedText? description,
  AudioSource defaultValue = AudioSource.range,
}) =>
    ChoiceParam(
      id: id,
      label: label,
      description: description,
      options: List.unmodifiable([for (final source in AudioSource.values) source.option]),
      defaultValue: defaultValue.id,
    );

/// The value (`0..1`) of the [AudioSource] chosen by the choice parameter
/// [id] in [p]; [AudioSource.range] reads the [audioRangeParams] with
/// [rangePrefix].
double audioSourceValue(ParamValues p, AudioFrame audio, {String id = 'source', String rangePrefix = 'range'}) =>
    switch (AudioSource.fromId(p.choice(id))) {
      AudioSource.level => audio.level,
      AudioSource.range => audioRangeValue(p, audio, prefix: rangePrefix),
      AudioSource.onset => audio.onset,
      AudioSource.beat => audio.beatPulse,
    };
