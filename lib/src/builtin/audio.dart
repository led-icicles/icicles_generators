import 'dart:math' as math;
import 'dart:typed_data';

import 'package:icicles_animation_dart/icicles_animation_dart.dart';

import '../audio/audio_feature_key.dart';
import '../audio/audio_frame.dart';
import '../generator/generator.dart';
import '../generator/generator_info.dart';
import '../generator/localized_text.dart';
import '../params/param_spec.dart';
import '../params/param_values.dart';
import '../util/audio_range.dart';
import '../util/color.dart';
import '../util/palette.dart';
import '../util/panel_mode.dart';
import 'common.dart';

/// Green → yellow → red, the classic meter colors.
const meterPalette = Palette([
  PaletteStop(0.0, Color(0xFF00C030)),
  PaletteStop(0.6, Color(0xFFC0E000)),
  PaletteStop(0.8, Color(0xFFFF9000)),
  PaletteStop(1.0, Color(0xFFFF1000)),
]);

const _releaseParam = NumberParam(
  id: 'release',
  label: LocalizedText('Fall time', pl: 'Czas opadania'),
  description: LocalizedText('How slowly the bars fall back.', pl: 'Jak wolno opadają słupki.'),
  min: 0,
  max: 1,
  defaultValue: 0.2,
  step: 0.01,
  unit: 's',
);

/// A one-pole follower that rises at once and falls over `release`.
double _fall(double previous, double input, double release, double dt) {
  if (input >= previous || release <= 0) return input;
  return input + (previous - input) * math.exp(-dt / release);
}

/// The value of the `feature` choice: the [audioRangeParams] energy for
/// `range`, else the named [AudioFeatureKey].
double featureValue(ParamValues p, AudioFrame audio, {String id = 'feature', String rangePrefix = 'range'}) {
  final feature = p.choice(id);
  if (feature == 'range') return audioRangeValue(p, audio, prefix: rangePrefix);
  return audio[AudioFeatureKey.values.byName(feature)];
}

/// Every icicle fills from the bottom with the energy of a frequency range,
/// with a peak dot.
final class VuMeterGenerator implements Generator {
  const VuMeterGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.vu_meter',
        version: 1,
        name: LocalizedText('VU meter', pl: 'Wskaźnik wysterowania'),
        description: LocalizedText(
          'Icicles fill up with the energy of a frequency range (or the loudness) of the music.',
          pl: 'Sople wypełniają się energią zakresu częstotliwości (lub głośnością) muzyki.',
        ),
        category: GeneratorCategory.audio,
        usesAudio: true,
        defaultLength: Duration(seconds: 30),
      );

  static final _vuRangeParams = audioRangeParams(defaultPreset: AudioRangePreset.full);

  @override
  List<ParamSpec> get params => [
        const ChoiceParam(
          id: 'feature',
          label: LocalizedText('Follows', pl: 'Reaguje na'),
          options: [
            ChoiceOption('range', LocalizedText('Frequency range', pl: 'Zakres częstotliwości')),
            ChoiceOption('level', LocalizedText('Loudness', pl: 'Głośność')),
            ChoiceOption('bass', LocalizedText('Bass', pl: 'Basy')),
            ChoiceOption('mid', LocalizedText('Mids', pl: 'Średnie')),
            ChoiceOption('treble', LocalizedText('Treble', pl: 'Wysokie')),
            ChoiceOption('onset', LocalizedText('Hits', pl: 'Uderzenia')),
          ],
          defaultValue: 'range',
        ),
        ..._vuRangeParams,
        const ChoiceParam(
          id: 'style',
          label: LocalizedText('Style', pl: 'Styl'),
          options: [
            ChoiceOption('columns', LocalizedText('Every icicle fills up', pl: 'Każdy sopel się wypełnia')),
            ChoiceOption('center', LocalizedText('From the center outwards', pl: 'Od środka na boki')),
          ],
          defaultValue: 'columns',
        ),
        const PaletteParam(id: 'palette', label: paletteLabel, defaultValue: meterPalette),
        gainParam,
        _releaseParam,
        const NumberParam(
          id: 'peakHold',
          label: LocalizedText('Peak hold', pl: 'Podtrzymanie szczytu'),
          min: 0,
          max: 3,
          defaultValue: 1,
          step: 0.05,
          unit: 's',
        ),
        brightnessParam,
        panelModeParamWithOwn,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _VuMeterInstance();
}

final class _VuMeterInstance implements GeneratorInstance {
  double _value = 0;
  double _peak = 0;
  double _peakAge = 0;

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final dt = ctx.deltaSeconds;
    final input = (featureValue(p, ctx.audio) * p.number('gain')).clamp(0.0, 1.0);
    _value = _fall(_value, input, p.number('release'), dt);
    if (_value >= _peak) {
      _peak = _value;
      _peakAge = 0;
    } else {
      _peakAge += dt;
      if (_peakAge > p.number('peakHold')) _peak = math.max(_value, _peak - dt * 1.5);
    }
    final palette = p.palette('palette');
    final brightness = p.number('brightness');
    final center = p.choice('style') == 'center';
    out.setAllPixelsColor(black);
    if (center) {
      final half = ctx.xCount / 2;
      final lit = _value * half;
      final peak = (_peak * half).floor();
      for (var x = 0; x < ctx.xCount; x++) {
        final distance = (x + 0.5 - half).abs();
        final Color color;
        if (distance < lit) {
          color = dim(palette.sample(distance / half), brightness);
        } else if (_peak > 0.02 && distance.floor() == peak) {
          color = dim(const Color(0xFFFFFFFF), brightness);
        } else {
          continue;
        }
        out.setColumnColor(x, color);
      }
    } else {
      final height = ctx.yCount;
      final lit = (_value * height).round();
      final peak = (_peak * height).round().clamp(1, height);
      for (var level = 0; level < lit; level++) {
        final color = dim(palette.sample((level + 0.5) / height), brightness);
        for (var x = 0; x < ctx.xCount; x++) {
          out.setPixelColor(x, height - 1 - level, color);
        }
      }
      if (_peak > 0.02) {
        for (var x = 0; x < ctx.xCount; x++) {
          out.setPixelColor(x, height - peak, dim(const Color(0xFFFFFFFF), brightness));
        }
      }
    }
    final mode = panelModeOf(p);
    if (mode != PanelMode.own) return applyPanelMode(out, mode);
    out.setAllRadioPanelsColor(dim(palette.sample(_value), _value * brightness));
  }
}

/// A spectrum analyzer: the icicles show the 16 mel bands.
final class SpectrumGenerator implements Generator {
  const SpectrumGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.spectrum',
        version: 1,
        name: LocalizedText('Spectrum', pl: 'Widmo'),
        description: LocalizedText(
          'A spectrum analyzer: low notes on the left, high on the right; a frequency range zooms into part of it.',
          pl: 'Analizator widma: niskie tony po lewej, wysokie po prawej; zakres częstotliwości przybliża jego część.',
        ),
        category: GeneratorCategory.audio,
        usesAudio: true,
        defaultLength: Duration(seconds: 30),
      );

  static final _rangeParams = audioRangeParams(
    defaultPreset: AudioRangePreset.full,
    description: const LocalizedText('The part of the spectrum spread across the icicles.',
        pl: 'Część widma rozłożona na sople.'),
  );

  @override
  List<ParamSpec> get params => [
        ..._rangeParams,
        const PaletteParam(id: 'palette', label: paletteLabel, defaultValue: meterPalette),
        gainParam,
        _releaseParam,
        const BoolParam(
          id: 'mirror',
          label: LocalizedText('From the center', pl: 'Od środka'),
          description:
              LocalizedText('Bass in the middle, treble at the edges.', pl: 'Basy pośrodku, wysokie po bokach.'),
          defaultValue: false,
        ),
        const BoolParam(id: 'peaks', label: LocalizedText('Peak dots', pl: 'Kropki szczytów'), defaultValue: true),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _SpectrumInstance(setup.xCount);
}

final class _SpectrumInstance implements GeneratorInstance {
  final Float64List values;
  final Float64List peaks;

  _SpectrumInstance(int xCount)
      : values = Float64List(xCount),
        peaks = Float64List(xCount);

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final dt = ctx.deltaSeconds;
    final gain = p.number('gain');
    final release = p.number('release');
    final mirror = p.flag('mirror');
    final showPeaks = p.flag('peaks');
    final palette = p.palette('palette');
    final brightness = p.number('brightness');
    final range = audioRangeOf(p);
    final height = ctx.yCount;
    out.setAllPixelsColor(black);
    for (var x = 0; x < ctx.xCount; x++) {
      final position = mirror ? (2 * ctx.nx(x) - 1).abs() : ctx.nx(x);
      final input = (range.spectrumAt(ctx.audio, position) * gain).clamp(0.0, 1.0);
      values[x] = _fall(values[x], input, release, dt);
      peaks[x] = math.max(values[x], peaks[x] - dt * 0.8);
      final lit = (values[x] * height).round();
      for (var level = 0; level < lit; level++) {
        out.setPixelColor(x, height - 1 - level, dim(palette.sample((level + 0.5) / height), brightness));
      }
      if (showPeaks && peaks[x] > 0.02) {
        final peak = (peaks[x] * height).round().clamp(1, height);
        out.setPixelColor(x, height - peak, dim(const Color(0xFFFFFFFF), brightness * 0.8));
      }
    }
    applyPanelMode(out, panelModeOf(p));
  }
}

/// A glow in the middle that swells with a frequency range (the lows by
/// default) and kicks on the beat.
final class BassPulseGenerator implements Generator {
  const BassPulseGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.bass_pulse',
        version: 1,
        name: LocalizedText('Bass pulse', pl: 'Puls basu'),
        description: LocalizedText(
          'A pulse from a frequency range (the bass by default), kicking on every beat.',
          pl: 'Puls z zakresu częstotliwości (domyślnie basu), uderzający na każdy beat.',
        ),
        category: GeneratorCategory.audio,
        usesAudio: true,
        defaultLength: Duration(seconds: 30),
      );

  static final _rangeParams = audioRangeParams();

  @override
  List<ParamSpec> get params => [
        const ColorParam(id: 'color', label: colorLabel, defaultValue: Color(0xFFFF2060)),
        ..._rangeParams,
        gainParam,
        const NumberParam(
          id: 'beat',
          label: LocalizedText('Beat kick', pl: 'Puls na uderzenie'),
          description: LocalizedText(
            'Mix of the beat pulse (needs a tempo) into the range energy.',
            pl: 'Udział pulsu tempa (wymaga tempa) w energii zakresu.',
          ),
          min: 0,
          max: 1,
          defaultValue: 0.4,
          step: 0.01,
        ),
        const NumberParam(
          id: 'size',
          label: LocalizedText('Size', pl: 'Wielkość'),
          min: 0.2,
          max: 1.5,
          defaultValue: 0.8,
          step: 0.01,
        ),
        brightnessParam,
        panelModeParamWithOwn,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _BassPulseInstance();
}

final class _BassPulseInstance implements GeneratorInstance {
  double _bass = 0;

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    _bass = _fall(_bass, audioRangeValue(p, ctx.audio), 0.15, ctx.deltaSeconds);
    final beat = p.number('beat');
    final energy =
        ((_bass * p.number('gain')).clamp(0.0, 1.0) * (1 - beat) + ctx.audio.beatPulse * beat).clamp(0.0, 1.0);
    final radius = p.number('size') * (0.25 + 0.75 * energy);
    final color = p.color('color');
    final brightness = p.number('brightness');
    final aspect = ctx.xCount / math.max(1, ctx.yCount);
    for (var x = 0; x < ctx.xCount; x++) {
      for (var y = 0; y < ctx.yCount; y++) {
        final dx = (ctx.nx(x) - 0.5) * 2;
        final dy = (ctx.ny(y) - 0.5) * 2 / math.max(1.0, aspect / 2);
        final d = math.sqrt(dx * dx + dy * dy);
        out.setPixelColor(x, y, dim(color, falloff(d, radius) * (0.15 + 0.85 * energy) * brightness));
      }
    }
    final mode = panelModeOf(p);
    if (mode != PanelMode.own) return applyPanelMode(out, mode);
    out.setAllRadioPanelsColor(dim(color, energy * brightness));
  }
}

/// Every hit in the music drops a few colored drops down the icicles.
final class OnsetDropsGenerator implements Generator {
  const OnsetDropsGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.onset_drops',
        version: 1,
        name: LocalizedText('Onset drops', pl: 'Krople na uderzenia'),
        description: LocalizedText(
          'Each hit in the music sends drops falling down the icicles; a frequency range sets how many and how bright.',
          pl: 'Każde uderzenie w muzyce zrzuca krople po soplach; zakres częstotliwości ustala ich liczbę i jasność.',
        ),
        category: GeneratorCategory.audio,
        usesAudio: true,
        defaultLength: Duration(seconds: 30),
      );

  static final _rangeParams = audioRangeParams(
    defaultPreset: AudioRangePreset.full,
    description: const LocalizedText('Its energy at the hit sets the number and brightness of the drops.',
        pl: 'Jego energia w chwili uderzenia ustala liczbę i jasność kropli.'),
  );

  @override
  List<ParamSpec> get params => [
        const NumberParam(
          id: 'threshold',
          label: LocalizedText('Threshold', pl: 'Próg'),
          description: LocalizedText('How strong a hit must be.', pl: 'Jak mocne musi być uderzenie.'),
          min: 0.05,
          max: 0.95,
          defaultValue: 0.4,
          step: 0.01,
        ),
        ..._rangeParams,
        const NumberParam(
          id: 'speed',
          label: LocalizedText('Fall speed', pl: 'Prędkość spadania'),
          description: LocalizedText('Icicle lengths per second.', pl: 'Długości sopla na sekundę.'),
          min: 0.25,
          max: 5,
          defaultValue: 1.5,
          scale: NumberScale.log,
          unit: '/s',
        ),
        const NumberParam(
          id: 'tail',
          label: LocalizedText('Tail', pl: 'Ogon'),
          min: 0,
          max: 1,
          defaultValue: 0.3,
          step: 0.01,
        ),
        const PaletteParam(id: 'palette', label: paletteLabel, defaultValue: Palette.party),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _OnsetDropsInstance();
}

final class _Drop {
  final int x;
  double y;
  final double speed;
  final Color color;

  /// Brightness of the drop, from the range energy at its hit.
  final double level;

  _Drop(this.x, this.y, this.speed, this.color, this.level);
}

final class _OnsetDropsInstance implements GeneratorInstance {
  static const _refractory = 0.08;

  final drops = <_Drop>[];
  double _previous = 0;
  double _sinceSpawn = double.infinity;

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final random = ctx.random;
    final dt = ctx.deltaSeconds;
    final onset = ctx.audio.onset;
    final threshold = p.number('threshold');
    final palette = p.palette('palette');
    final height = ctx.yCount.toDouble();
    _sinceSpawn += dt;
    if (onset >= threshold && _previous < threshold && _sinceSpawn >= _refractory) {
      _sinceSpawn = 0;
      final energy = audioRangeValue(p, ctx.audio);
      final count = 1 + (energy * 3).floor();
      for (var i = 0; i < count; i++) {
        drops.add(_Drop(
          random.nextInt(ctx.xCount),
          0,
          (0.8 + random.nextDouble() * 0.4) * height * p.number('speed'),
          palette.sample(random.nextDouble()),
          0.4 + 0.6 * energy,
        ));
      }
    }
    _previous = onset;
    final tail = p.number('tail') * height * 0.5;
    final brightness = p.number('brightness');
    out.setAllPixelsColor(black);
    for (var i = drops.length - 1; i >= 0; i--) {
      final drop = drops[i];
      drop.y += drop.speed * dt;
      if (drop.y - tail >= height) {
        drops.removeAt(i);
        continue;
      }
      final head = drop.y.floor();
      for (var y = math.max(0, (drop.y - tail - 1).floor()); y <= head && y < ctx.yCount; y++) {
        final behind = drop.y - y;
        final intensity = behind <= 1 ? 1.0 : (tail <= 0 ? 0.0 : (1 - (behind - 1) / tail).clamp(0.0, 1.0));
        if (intensity <= 0) continue;
        final existing = out.getPixelColor(drop.x, y);
        out.setPixelColor(drop.x, y, addColors(existing, dim(drop.color, intensity * drop.level * brightness)));
      }
    }
    applyPanelMode(out, panelModeOf(p));
  }
}
