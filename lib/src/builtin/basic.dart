import 'package:icicles_animation_dart/icicles_animation_dart.dart';

import '../generator/generator.dart';
import '../generator/generator_info.dart';
import '../generator/localized_text.dart';
import '../params/param_spec.dart';
import '../util/audio_range.dart';
import '../util/color.dart';
import '../util/palette.dart';
import '../util/panel_mode.dart';
import 'common.dart';

/// One color everywhere.
final class SolidGenerator implements Generator {
  const SolidGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.solid',
        version: 1,
        name: LocalizedText('Solid color', pl: 'Jeden kolor'),
        description: LocalizedText('Every LED in one color.', pl: 'Wszystkie diody w jednym kolorze.'),
        category: GeneratorCategory.basic,
      );

  @override
  List<ParamSpec> get params => const [
        ColorParam(id: 'color', label: colorLabel, defaultValue: Color(0xFFFFB060)),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => const _SolidInstance();
}

final class _SolidInstance implements GeneratorInstance {
  const _SolidInstance();

  @override
  void render(FrameContext ctx, Icicles out) {
    final color = dim(ctx.params.color('color'), ctx.params.number('brightness'));
    out.setAllPixelsColor(color);
    if (panelModeOf(ctx.params) == PanelMode.off) {
      applyPanelMode(out, PanelMode.off);
    } else {
      out.setAllRadioPanelsColor(color);
    }
  }
}

/// A palette scrolling over the icicles.
final class GradientGenerator implements Generator {
  const GradientGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.gradient',
        version: 1,
        name: LocalizedText('Palette scroll', pl: 'Przewijana paleta'),
        description: LocalizedText(
          'A color gradient sliding across or along the icicles.',
          pl: 'Gradient kolorów przesuwający się wzdłuż rzędu lub sopli.',
        ),
        category: GeneratorCategory.basic,
      );

  @override
  List<ParamSpec> get params => const [
        PaletteParam(id: 'palette', label: paletteLabel, defaultValue: Palette.party),
        NumberParam(
          id: 'speed',
          label: LocalizedText('Speed', pl: 'Prędkość'),
          description: LocalizedText('Palette cycles per second.', pl: 'Obiegi palety na sekundę.'),
          min: -2,
          max: 2,
          defaultValue: 0.2,
          step: 0.01,
          unit: '/s',
        ),
        NumberParam(
          id: 'spread',
          label: LocalizedText('Repeats', pl: 'Powtórzenia'),
          min: 0.25,
          max: 4,
          defaultValue: 1,
          scale: NumberScale.log,
          unit: '×',
        ),
        axisParam,
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => const _GradientInstance();
}

final class _GradientInstance implements GeneratorInstance {
  const _GradientInstance();

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final palette = p.palette('palette');
    final offset = ctx.seconds * p.number('speed');
    final spread = p.number('spread');
    final brightness = p.number('brightness');
    final direction = p.choice('direction');
    for (var x = 0; x < ctx.xCount; x++) {
      for (var y = 0; y < ctx.yCount; y++) {
        final position = switch (direction) {
          'vertical' => ctx.ny(y),
          'diagonal' => (ctx.nx(x) + ctx.ny(y)) / 2,
          _ => ctx.nx(x),
        };
        out.setPixelColor(x, y, dim(palette.sample(position * spread - offset, wrap: true), brightness));
      }
    }
    applyPanelMode(out, panelModeOf(p));
  }
}

/// A moving rainbow (ported from `rainbow_horizontal`).
final class RainbowGenerator implements Generator {
  const RainbowGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.rainbow',
        version: 1,
        name: LocalizedText('Rainbow', pl: 'Tęcza'),
        description: LocalizedText('Hues running across the icicles.', pl: 'Barwy tęczy płynące po soplach.'),
        category: GeneratorCategory.basic,
      );

  @override
  List<ParamSpec> get params => const [
        ChoiceParam(
          id: 'direction',
          label: LocalizedText('Direction', pl: 'Kierunek'),
          options: [
            ChoiceOption('horizontal', LocalizedText('Across the icicles', pl: 'Wzdłuż rzędu sopli')),
            ChoiceOption('vertical', LocalizedText('Along the icicles', pl: 'Wzdłuż sopla')),
          ],
          defaultValue: 'horizontal',
        ),
        NumberParam(
          id: 'speed',
          label: LocalizedText('Speed', pl: 'Prędkość'),
          description: LocalizedText('Rainbow cycles per second.', pl: 'Obiegi tęczy na sekundę.'),
          min: -2,
          max: 2,
          defaultValue: 0.25,
          step: 0.01,
          unit: '/s',
        ),
        NumberParam(
          id: 'spread',
          label: LocalizedText('Repeats', pl: 'Powtórzenia'),
          min: 0.25,
          max: 4,
          defaultValue: 1,
          scale: NumberScale.log,
          unit: '×',
        ),
        NumberParam(
          id: 'saturation',
          label: LocalizedText('Saturation', pl: 'Nasycenie'),
          min: 0,
          max: 1,
          defaultValue: 1,
          step: 0.01,
        ),
        brightnessParam,
        panelModeParamWithOwn,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => const _RainbowInstance();
}

final class _RainbowInstance implements GeneratorInstance {
  const _RainbowInstance();

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final offset = ctx.seconds * p.number('speed');
    final spread = p.number('spread');
    final saturation = p.number('saturation');
    final brightness = p.number('brightness');
    final vertical = p.choice('direction') == 'vertical';
    for (var x = 0; x < ctx.xCount; x++) {
      for (var y = 0; y < ctx.yCount; y++) {
        final position = vertical ? ctx.ny(y) : ctx.nx(x);
        out.setPixelColor(x, y, hsv(position * spread - offset, saturation, brightness));
      }
    }
    final mode = panelModeOf(p);
    if (mode != PanelMode.own) return applyPanelMode(out, mode);
    final panels = out.radioPanels;
    for (var panel = 0; panel < panels.length; panel++) {
      final count = panels[panel].length;
      for (var i = 0; i < count; i++) {
        final position = (panel + i / count) / panels.length;
        out.setRadioPanelPixelColor(panel, i, hsv(position * spread - offset, saturation, brightness));
      }
    }
  }
}

/// Beat-synced flashes.
final class StrobeGenerator implements Generator {
  /// Tempo used when the project has none.
  static const fallbackBpm = 120.0;

  const StrobeGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.strobe',
        version: 1,
        name: LocalizedText('Strobe', pl: 'Stroboskop'),
        description: LocalizedText(
          'Flashes on the beat grid or on every hit of a frequency range, the bass or an onset.',
          pl: 'Błyski w rytm siatki beatu albo na każde uderzenie zakresu częstotliwości, basu lub onset.',
        ),
        category: GeneratorCategory.basic,
        usesAudio: true,
      );

  static final _rangeParams = audioRangeParams(
    description: const LocalizedText('"Frequency range hit" trigger only.', pl: 'Tylko wyzwalacz „Uderzenie zakresu”.'),
  );

  @override
  List<ParamSpec> get params => [
        const ColorParam(id: 'color', label: colorLabel, defaultValue: Color(0xFFFFFFFF)),
        const ChoiceParam(
          id: 'trigger',
          label: LocalizedText('Trigger', pl: 'Wyzwalacz'),
          description: LocalizedText(
            'What fires a flash: the beat grid, or a rising audio feature crossing the threshold.',
            pl: 'Co odpala błysk: siatka beatu albo cecha audio rosnąca ponad próg.',
          ),
          options: [
            ChoiceOption('beat', LocalizedText('Beat grid', pl: 'Siatka beatu')),
            ChoiceOption('range', LocalizedText('Frequency range hit', pl: 'Uderzenie zakresu częstotliwości')),
            ChoiceOption('bass', LocalizedText('Bass hit', pl: 'Uderzenie basu')),
            ChoiceOption('onset', LocalizedText('Onset (any hit)', pl: 'Onset (każde uderzenie)')),
            ChoiceOption('mid', LocalizedText('Mid hit', pl: 'Uderzenie środka')),
            ChoiceOption('treble', LocalizedText('Treble hit', pl: 'Uderzenie góry')),
            ChoiceOption('level', LocalizedText('Level', pl: 'Głośność')),
          ],
          defaultValue: 'beat',
        ),
        ..._rangeParams,
        const NumberParam(
          id: 'threshold',
          label: LocalizedText('Threshold', pl: 'Próg'),
          description: LocalizedText(
            'Audio triggers only: the feature must rise above this to fire (and drop below half of it to re-arm).',
            pl: 'Tylko wyzwalacze audio: cecha musi wzrosnąć ponad próg (i opaść poniżej jego połowy, by uzbroić ponownie).',
          ),
          min: 0.05,
          max: 0.95,
          defaultValue: 0.5,
          step: 0.01,
        ),
        const NumberParam(
          id: 'flashMs',
          label: LocalizedText('Flash (ms)', pl: 'Błysk (ms)'),
          description: LocalizedText(
            'Audio triggers only: how long a triggered flash stays on.',
            pl: 'Tylko wyzwalacze audio: jak długo świeci wyzwolony błysk.',
          ),
          min: 20,
          max: 500,
          defaultValue: 80,
          step: 5,
          unit: 'ms',
        ),
        const NumberParam(
          id: 'rate',
          label: LocalizedText('Every', pl: 'Co'),
          description: LocalizedText('Beats between flashes.', pl: 'Liczba uderzeń między błyskami.'),
          min: 0.25,
          max: 4,
          defaultValue: 1,
          scale: NumberScale.log,
          unit: 'beats',
        ),
        const NumberParam(
          id: 'duty',
          label: LocalizedText('Flash length', pl: 'Długość błysku'),
          description: LocalizedText('Part of the period the flash is on.', pl: 'Część okresu, gdy błysk świeci.'),
          min: 0.05,
          max: 0.9,
          defaultValue: 0.2,
          step: 0.01,
        ),
        brightnessParam,
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _StrobeInstance();
}

final class _StrobeInstance implements GeneratorInstance {
  /// Audio triggers: the flash currently on ends at this time (exclusive).
  Duration _flashUntil = Duration.zero;

  /// Audio triggers: a hit was already fired and the feature has not yet
  /// dropped below half the threshold (hysteresis, so one hit = one flash).
  bool _armed = true;

  /// Minimum time between two triggered flashes, like a drum's re-trigger gap.
  static const refractory = Duration(milliseconds: 60);
  Duration _lastHit = const Duration(days: -1);

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final audio = ctx.audio;
    final trigger = p.choice('trigger');
    final bool on;
    if (trigger == 'beat') {
      final beats = audio.bpm > 0 ? audio.beatIndex + audio.beatPhase : ctx.seconds * StrobeGenerator.fallbackBpm / 60;
      final position = beats / p.number('rate');
      final phase = position - position.floor();
      on = phase < p.number('duty');
    } else {
      final value = switch (trigger) {
        'range' => audioRangeValue(p, audio),
        'bass' => audio.bass,
        'mid' => audio.mid,
        'treble' => audio.treble,
        'level' => audio.level,
        _ => audio.onset,
      };
      final threshold = p.number('threshold');
      if (!_armed && value < threshold / 2) _armed = true;
      if (_armed && value >= threshold && ctx.time - _lastHit >= refractory) {
        _armed = false;
        _lastHit = ctx.time;
        _flashUntil = ctx.time + Duration(milliseconds: p.number('flashMs').round());
      }
      on = ctx.time < _flashUntil;
    }
    final color = on ? dim(p.color('color'), p.number('brightness')) : black;
    out.setAllPixelsColor(color);
    if (panelModeOf(p) == PanelMode.off) {
      applyPanelMode(out, PanelMode.off);
    } else {
      out.setAllRadioPanelsColor(color);
    }
  }
}
