import 'dart:math' as math;
import 'dart:typed_data';

import 'package:icicles_animation_dart/icicles_animation_dart.dart';

import '../audio/audio_feature_key.dart';
import '../generator/generator.dart';
import '../generator/generator_info.dart';
import '../generator/localized_text.dart';
import '../params/param_spec.dart';
import '../util/audio_range.dart';
import '../util/color.dart';
import '../util/palette.dart';
import '../util/panel_mode.dart';
import 'audio.dart';
import 'common.dart';

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

const _featureParam = ChoiceParam(
  id: 'feature',
  label: LocalizedText('Follows', pl: 'Reaguje na'),
  options: [
    ChoiceOption('range', LocalizedText('Frequency range', pl: 'Zakres częstotliwości')),
    ChoiceOption('level', LocalizedText('Loudness', pl: 'Głośność')),
    ChoiceOption('bass', LocalizedText('Bass', pl: 'Basy')),
    ChoiceOption('mid', LocalizedText('Mids', pl: 'Średnie')),
    ChoiceOption('treble', LocalizedText('Treble', pl: 'Wysokie')),
  ],
  defaultValue: 'range',
);

/// A one-pole follower that rises at once and falls over `release`.
double _fall(double previous, double input, double release, double dt) {
  if (input >= previous || release <= 0) return input;
  return input + (previous - input) * math.exp(-dt / release);
}

/// A spectrum mirrored about the center in both directions.
final class SpectrumMirrorGenerator implements Generator {
  const SpectrumMirrorGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.spectrum_mirror',
        version: 1,
        name: LocalizedText('Mirrored spectrum', pl: 'Widmo lustrzane'),
        description: LocalizedText(
          'Spectrum bands of a frequency range growing from the center outwards, mirrored left-right and up-down.',
          pl: 'Pasma widma z zakresu częstotliwości rosnące od środka na zewnątrz, odbite w poziomie i w pionie.',
        ),
        category: GeneratorCategory.audio,
        usesAudio: true,
        defaultLength: Duration(seconds: 30),
      );

  static final _rangeParams = audioRangeParams(
    defaultPreset: AudioRangePreset.full,
    description:
        const LocalizedText('The part of the spectrum spread over the bands.', pl: 'Część widma rozłożona na pasma.'),
  );

  @override
  List<ParamSpec> get params => [
        const IntParam(id: 'bands', label: LocalizedText('Bands', pl: 'Pasma'), min: 2, max: 16, defaultValue: 8),
        ..._rangeParams,
        const PaletteParam(id: 'palette', label: paletteLabel, defaultValue: meterPalette),
        gainParam,
        _releaseParam,
        const BoolParam(id: 'peaks', label: LocalizedText('Peak dots', pl: 'Kropki szczytów'), defaultValue: true),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _SpectrumMirrorInstance();
}

final class _SpectrumMirrorInstance implements GeneratorInstance {
  final values = Float64List(AudioFeatureKey.bandCount);
  final peaks = Float64List(AudioFeatureKey.bandCount);

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final dt = ctx.deltaSeconds;
    final bands = p.integer('bands');
    final gain = p.number('gain');
    final release = p.number('release');
    final showPeaks = p.flag('peaks');
    final palette = p.palette('palette');
    final brightness = p.number('brightness');
    final range = audioRangeOf(p);
    for (var b = 0; b < bands; b++) {
      final input = (range.spectrumAt(ctx.audio, bands == 1 ? 0 : b / (bands - 1)) * gain).clamp(0.0, 1.0);
      values[b] = _fall(values[b], input, release, dt);
      peaks[b] = math.max(values[b], peaks[b] - dt * 0.8);
    }
    out.setAllPixelsColor(black);
    final halfWidth = ctx.xCount / 2;
    final halfHeight = ctx.yCount / 2;
    for (var x = 0; x < ctx.xCount; x++) {
      final fromCenter = (x + 0.5 - halfWidth).abs() / halfWidth;
      final b = math.min(bands - 1, (fromCenter * bands).floor());
      final lit = values[b] * halfHeight;
      final peak = showPeaks && peaks[b] > 0.02 ? (peaks[b] * halfHeight).ceil().clamp(1, halfHeight.ceil()) : -1;
      for (var y = 0; y < ctx.yCount; y++) {
        final level = (y + 0.5 - halfHeight).abs();
        if (level < lit) {
          out.setPixelColor(x, y, dim(palette.sample(level / halfHeight), brightness));
        } else if (level.floor() == peak - 1 && peak > 0) {
          out.setPixelColor(x, y, dim(const Color(0xFFFFFFFF), brightness * 0.8));
        }
      }
    }
    applyPanelMode(out, panelModeOf(p));
  }
}

/// The loudness history scrolling down the icicles (WLED Waverly).
final class WaveformScrollGenerator implements Generator {
  const WaveformScrollGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.waveform_scroll',
        version: 1,
        name: LocalizedText('Waveform scroll', pl: 'Przewijana fala'),
        description: LocalizedText(
          'The history of a frequency range (or the loudness) scrolling down the icicles as a waveform or glowing rows.',
          pl: 'Historia zakresu częstotliwości (lub głośności) przewijana w dół sopli jako fala lub świecące rzędy.',
        ),
        category: GeneratorCategory.audio,
        usesAudio: true,
        defaultLength: Duration(seconds: 30),
      );

  static final _rangeParams = audioRangeParams(defaultPreset: AudioRangePreset.full);

  @override
  List<ParamSpec> get params => [
        _featureParam,
        ..._rangeParams,
        gainParam,
        const NumberParam(
          id: 'speed',
          label: LocalizedText('Scroll speed', pl: 'Prędkość przewijania'),
          min: 2,
          max: 60,
          defaultValue: 20,
          scale: NumberScale.log,
          unit: 'px/s',
        ),
        const ChoiceParam(
          id: 'style',
          label: LocalizedText('Style', pl: 'Styl'),
          options: [
            ChoiceOption('wave', LocalizedText('Waveform (width)', pl: 'Fala (szerokość)')),
            ChoiceOption('rows', LocalizedText('Glowing rows', pl: 'Świecące rzędy')),
          ],
          defaultValue: 'wave',
        ),
        const PaletteParam(id: 'palette', label: paletteLabel, defaultValue: Palette.ocean),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _WaveformScrollInstance(setup.yCount);
}

final class _WaveformScrollInstance implements GeneratorInstance {
  /// Newest row first.
  final Float64List history;
  double _pending = 1;
  double _current = 0;

  _WaveformScrollInstance(int yCount) : history = Float64List(yCount + 1);

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final dt = ctx.deltaSeconds;
    _current = math.max(_current, (featureValue(p, ctx.audio) * p.number('gain')).clamp(0.0, 1.0));
    _pending += dt * p.number('speed');
    while (_pending >= 1) {
      _pending -= 1;
      for (var i = history.length - 1; i > 0; i--) {
        history[i] = history[i - 1];
      }
      history[0] = _current;
      _current = 0;
    }
    final wave = p.choice('style') == 'wave';
    final palette = p.palette('palette');
    final brightness = p.number('brightness');
    final halfWidth = ctx.xCount / 2;
    for (var y = 0; y < ctx.yCount; y++) {
      final v = history[y];
      final color = palette.sample(0.2 + 0.8 * v);
      for (var x = 0; x < ctx.xCount; x++) {
        final double intensity;
        if (wave) {
          final fromCenter = (x + 0.5 - halfWidth).abs() / halfWidth;
          intensity = fromCenter <= v ? 1 : 0;
        } else {
          intensity = v;
        }
        out.setPixelColor(x, y, dim(color, intensity * brightness));
      }
    }
    applyPanelMode(out, panelModeOf(p));
  }
}

/// One bar per beat of the bar, lit on its beat.
final class BeatBarsGenerator implements Generator {
  /// Tempo used when the project has none.
  static const fallbackBpm = 120.0;

  const BeatBarsGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.beat_bars',
        version: 1,
        name: LocalizedText('Beat bars', pl: 'Słupki taktu'),
        description: LocalizedText(
          'One bar per beat of the bar, flashing on its beat (120 BPM without a tempo).',
          pl: 'Jeden słupek na każde uderzenie taktu, błyskający w swoim momencie (120 BPM bez tempa).',
        ),
        category: GeneratorCategory.audio,
        usesAudio: true,
        defaultLength: Duration(seconds: 30),
      );

  @override
  List<ParamSpec> get params => const [
        IntParam(
            id: 'beats',
            label: LocalizedText('Beats per bar', pl: 'Uderzeń w takcie'),
            min: 2,
            max: 8,
            defaultValue: 4),
        NumberParam(
          id: 'decay',
          label: LocalizedText('Decay', pl: 'Wygaszanie'),
          min: 0.05,
          max: 1,
          defaultValue: 0.3,
          scale: NumberScale.log,
          unit: 's',
        ),
        NumberParam(
          id: 'accent',
          label: LocalizedText('Downbeat accent', pl: 'Akcent na raz'),
          description:
              LocalizedText('How much the first beat stands out.', pl: 'Jak mocno wyróżnia się pierwsze uderzenie.'),
          min: 0,
          max: 1,
          defaultValue: 0.5,
          step: 0.01,
        ),
        ChoiceParam(
          id: 'layout',
          label: LocalizedText('Layout', pl: 'Układ'),
          options: [
            ChoiceOption('columns', LocalizedText('Side by side', pl: 'Obok siebie')),
            ChoiceOption('rows', LocalizedText('Stacked down the icicles', pl: 'Jeden pod drugim')),
          ],
          defaultValue: 'columns',
        ),
        PaletteParam(id: 'palette', label: paletteLabel, defaultValue: Palette.party),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => const _BeatBarsInstance();
}

final class _BeatBarsInstance implements GeneratorInstance {
  const _BeatBarsInstance();

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final audio = ctx.audio;
    final bpm = audio.bpm > 0 ? audio.bpm : BeatBarsGenerator.fallbackBpm;
    final position = audio.bpm > 0 ? audio.beatIndex + audio.beatPhase : ctx.seconds * bpm / 60;
    final beats = p.integer('beats');
    final beat = position.floor();
    final sinceBeat = (position - beat) * 60 / bpm;
    final current = ((beat % beats) + beats) % beats;
    final pulse = math.exp(-sinceBeat / p.number('decay'));
    final accent = p.number('accent');
    final columns = p.choice('layout') == 'columns';
    final palette = p.palette('palette');
    final brightness = p.number('brightness');
    for (var x = 0; x < ctx.xCount; x++) {
      for (var y = 0; y < ctx.yCount; y++) {
        final slot = columns ? (x * beats) ~/ ctx.xCount : (y * beats) ~/ ctx.yCount;
        final color = palette.sample((slot + 0.5) / beats);
        var v = slot == current ? pulse : 0.0;
        if (slot == 0) v = v * (1 + accent);
        v = math.max(v, 0.08 * (1 - accent * 0.5));
        out.setPixelColor(x, y, dim(color, v.clamp(0.0, 1.0) * brightness));
      }
    }
    applyPanelMode(out, panelModeOf(p));
  }
}

/// Hue from the loudest frequency, brightness from the loudness.
final class FreqColorGenerator implements Generator {
  const FreqColorGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.freq_color',
        version: 1,
        name: LocalizedText('Pitch color', pl: 'Kolor wysokości dźwięku'),
        description: LocalizedText(
          'The whole grid colored by the loudest frequency, as bright as the energy of a frequency range.',
          pl: 'Cała siatka w kolorze najgłośniejszej częstotliwości, tak jasna, jak energia zakresu częstotliwości.',
        ),
        category: GeneratorCategory.audio,
        usesAudio: true,
        defaultLength: Duration(seconds: 30),
      );

  static final _rangeParams = audioRangeParams(
    defaultPreset: AudioRangePreset.full,
    description: const LocalizedText('Its energy sets the brightness.', pl: 'Jego energia ustala jasność.'),
  );

  @override
  List<ParamSpec> get params => [
        ..._rangeParams,
        const NumberParam(
          id: 'smoothing',
          label: LocalizedText('Smoothing', pl: 'Wygładzanie'),
          min: 0,
          max: 1,
          defaultValue: 0.15,
          step: 0.01,
          unit: 's',
        ),
        const NumberParam(
          id: 'hueRange',
          label: LocalizedText('Hue range', pl: 'Zakres barw'),
          description: LocalizedText('Turns of the color wheel from the lowest to the highest pitch.',
              pl: 'Obroty koła barw od najniższego do najwyższego dźwięku.'),
          min: 0.1,
          max: 1,
          defaultValue: 0.7,
          step: 0.01,
        ),
        const NumberParam(
            id: 'hueOffset',
            label: LocalizedText('Hue offset', pl: 'Przesunięcie barwy'),
            min: 0,
            max: 1,
            defaultValue: 0,
            step: 0.01),
        gainParam,
        const NumberParam(
            id: 'saturation',
            label: LocalizedText('Saturation', pl: 'Nasycenie'),
            min: 0,
            max: 1,
            defaultValue: 1,
            step: 0.01),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _FreqColorInstance();
}

final class _FreqColorInstance implements GeneratorInstance {
  double _hue = 0;
  double _level = 0;

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final dt = ctx.deltaSeconds;
    final smoothing = p.number('smoothing');
    final k = smoothing <= 0 ? 1.0 : 1 - math.exp(-dt / smoothing);
    _hue += (ctx.audio.peakFrequency - _hue) * k;
    _level += ((audioRangeValue(p, ctx.audio) * p.number('gain')).clamp(0.0, 1.0) - _level) * k;
    final color = hsv(
        p.number('hueOffset') + _hue * p.number('hueRange'), p.number('saturation'), _level * p.number('brightness'));
    out.setAllPixelsColor(color);
    if (panelModeOf(p) == PanelMode.off) {
      applyPanelMode(out, PanelMode.off);
    } else {
      out.setAllRadioPanelsColor(color);
    }
  }
}

/// A ring per hit, colored by the pitch (WLED Ripple Peak).
final class RipplePeakGenerator implements Generator {
  const RipplePeakGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.ripple_peak',
        version: 1,
        name: LocalizedText('Ripple on hits', pl: 'Kręgi na uderzenia'),
        description: LocalizedText(
          'Every hit in the music sends out a ring, colored by the pitch of the moment and sized by a frequency range.',
          pl: 'Każde uderzenie w muzyce wysyła pierścień w kolorze wysokości dźwięku w tej chwili, wielki jak energia zakresu częstotliwości.',
        ),
        category: GeneratorCategory.audio,
        usesAudio: true,
        defaultLength: Duration(seconds: 30),
      );

  static final _rangeParams = audioRangeParams(
    defaultPreset: AudioRangePreset.full,
    description: const LocalizedText('Its energy at the hit sets the size of the ring.',
        pl: 'Jego energia w chwili uderzenia ustala wielkość pierścienia.'),
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
          label: LocalizedText('Speed', pl: 'Prędkość'),
          description: LocalizedText('Grid widths per second.', pl: 'Szerokości siatki na sekundę.'),
          min: 0.2,
          max: 5,
          defaultValue: 1,
          scale: NumberScale.log,
          unit: '/s',
        ),
        const NumberParam(
          id: 'thickness',
          label: LocalizedText('Ring thickness', pl: 'Grubość pierścienia'),
          min: 0.5,
          max: 5,
          defaultValue: 1.5,
          step: 0.1,
          unit: 'px',
        ),
        const NumberParam(
          id: 'life',
          label: LocalizedText('Ring life', pl: 'Czas pierścienia'),
          min: 0.3,
          max: 5,
          defaultValue: 1.2,
          scale: NumberScale.log,
          unit: 's',
        ),
        const PaletteParam(id: 'palette', label: paletteLabel, defaultValue: Palette.rainbow),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _RipplePeakInstance();
}

final class _RipplePeakInstance implements GeneratorInstance {
  static const _refractory = 0.08;

  final rings = <Ring>[];
  double _previous = 0;
  double _sinceHit = double.infinity;

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final random = ctx.random;
    final dt = ctx.deltaSeconds;
    final onset = ctx.audio.onset;
    final threshold = p.number('threshold');
    _sinceHit += dt;
    if (onset >= threshold && _previous < threshold && _sinceHit >= _refractory) {
      _sinceHit = 0;
      final energy = audioRangeValue(p, ctx.audio);
      rings.add(Ring(
        x: random.nextDouble() * (ctx.xCount - 1),
        y: random.nextDouble() * (ctx.yCount - 1),
        speed: p.number('speed') * ctx.xCount * (0.5 + 0.5 * energy),
        life: p.number('life') * (0.6 + 0.4 * onset),
        color: p.palette('palette').sample(ctx.audio.peakFrequency),
      ));
    }
    _previous = onset;
    drawRings(ctx, out, rings, dt, p.number('thickness'), p.number('brightness'));
    applyPanelMode(out, panelModeOf(p));
  }
}
