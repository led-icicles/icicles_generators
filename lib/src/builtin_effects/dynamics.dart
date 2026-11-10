import 'dart:math' as math;
import 'dart:typed_data';

import 'package:icicles_animation_dart/icicles_animation_dart.dart';

import '../effect/effect.dart';
import '../effect/effect_info.dart';
import '../generator/generator.dart';
import '../generator/localized_text.dart';
import '../params/param_spec.dart';
import '../util/audio_range.dart';
import '../util/color.dart';
import 'common.dart';

/// All pixels of [view] (icicles, then the panels in index order) as
/// channel floats in `0..1`.
Float32List _floatsOf(GeneratorSetup setup, AnimationView view) {
  final out = Float32List(setup.frameBytes);
  var o = 0;
  void put(Color c) {
    out[o++] = c.red / 255;
    out[o++] = c.green / 255;
    out[o++] = c.blue / 255;
  }

  view.frame.pixels.forEach(put);
  for (var p = 1; p <= setup.radioPanelsCount; p++) {
    view.radioPanels.firstWhere((panel) => panel.index == p).colors.forEach(put);
  }
  return out;
}

/// Writes [floats] (the layout of [_floatsOf]) into [out]; the panels only
/// when [panels] is set.
void _writeFloats(GeneratorSetup setup, Float32List floats, Icicles out, {required bool panels}) {
  var o = 0;
  for (var i = 0; i < setup.pixelsCount; i++, o += 3) {
    out.setPixelColorAtIndex(i, colorFromUnit(floats[o], floats[o + 1], floats[o + 2]));
  }
  if (!panels) return;
  for (var p = 0; p < setup.radioPanelsCount; p++) {
    final target = out.radioPanels[p];
    for (var i = 0; i < setup.radioPanelPixelCount; i++, o += 3) {
      target.setPixel(i, colorFromUnit(floats[o], floats[o + 1], floats[o + 2]));
    }
  }
}

/// Motion blur: the frame fades out slowly.
final class TrailEffect implements Effect {
  const TrailEffect();

  @override
  EffectInfo get info => const EffectInfo(
        id: 'icicles.fx.trail',
        version: 1,
        name: LocalizedText('Trail', pl: 'Smuga'),
        description: LocalizedText(
          'Every pixel fades out slowly after it lights, so moving things leave trails.',
          pl: 'Każdy piksel gaśnie powoli, gdy już zaświecił, więc ruch zostawia smugi.',
        ),
        category: EffectCategory.dynamics,
      );

  @override
  List<ParamSpec> get params => const [
        NumberParam(
          id: 'fade',
          label: LocalizedText('Fade', pl: 'Gaśnięcie'),
          description: LocalizedText('Time constant of the fade-out.', pl: 'Stała czasowa gaśnięcia.'),
          min: 0.05,
          max: 5,
          defaultValue: 0.5,
          scale: NumberScale.log,
          unit: 's',
        ),
        ChoiceParam(
          id: 'mode',
          label: LocalizedText('Mode', pl: 'Tryb'),
          options: [
            ChoiceOption('max', LocalizedText('Brightest wins', pl: 'Jaśniejszy wygrywa')),
            ChoiceOption('add', LocalizedText('Add up', pl: 'Sumowanie')),
          ],
          defaultValue: 'max',
        ),
        effectPanelsParam,
      ];

  @override
  EffectInstance create(GeneratorSetup setup) => _TrailInstance(setup);
}

final class _TrailInstance implements EffectInstance {
  final GeneratorSetup setup;
  Float32List? _buffer;

  _TrailInstance(this.setup);

  @override
  void apply(FrameContext ctx, AnimationView input, Icicles out) {
    final p = ctx.params;
    final k = math.exp(-ctx.deltaSeconds / p.number('fade'));
    final add = p.choice('mode') == 'add';
    final current = _floatsOf(setup, input);
    final buffer = _buffer ??= Float32List(current.length);
    for (var i = 0; i < buffer.length; i++) {
      final faded = buffer[i] * k;
      buffer[i] = (add ? faded + current[i] : math.max(faded, current[i])).clamp(0.0, 1.0);
    }
    _writeFloats(setup, buffer, out, panels: panelsOf(p));
  }
}

/// Delayed, decaying copies.
final class EchoEffect implements Effect {
  const EchoEffect();

  @override
  EffectInfo get info => const EffectInfo(
        id: 'icicles.fx.echo',
        version: 1,
        name: LocalizedText('Echo', pl: 'Echo'),
        description: LocalizedText(
          'Adds delayed, dimmer copies of the past frames.',
          pl: 'Dodaje opóźnione, przyciemnione kopie minionych klatek.',
        ),
        category: EffectCategory.dynamics,
      );

  @override
  List<ParamSpec> get params => const [
        NumberParam(
          id: 'delay',
          label: LocalizedText('Delay', pl: 'Opóźnienie'),
          min: 0.05,
          max: 2,
          defaultValue: 0.25,
          scale: NumberScale.log,
          unit: 's',
        ),
        IntParam(id: 'taps', label: LocalizedText('Echoes', pl: 'Echa'), min: 1, max: 8, defaultValue: 3),
        NumberParam(
          id: 'decay',
          label: LocalizedText('Decay', pl: 'Tłumienie'),
          description: LocalizedText('Brightness of each echo relative to the previous one.',
              pl: 'Jasność każdego echa względem poprzedniego.'),
          min: 0.05,
          max: 1,
          defaultValue: 0.5,
          step: 0.01,
        ),
        effectPanelsParam,
      ];

  @override
  EffectInstance create(GeneratorSetup setup) => _EchoInstance(setup);
}

final class _EchoInstance implements EffectInstance {
  /// Longest history kept (the maximum delay × taps at 60 fps).
  static const maxHistory = 2 * 8 * 60;

  final GeneratorSetup setup;
  final _history = <Float32List>[];

  _EchoInstance(this.setup);

  @override
  void apply(FrameContext ctx, AnimationView input, Icicles out) {
    final p = ctx.params;
    final fps = setup.framerate.framesPerSecond;
    final step = math.max(1, (p.number('delay') * fps).round());
    final taps = p.integer('taps');
    final decay = p.number('decay');
    final current = _floatsOf(setup, input);
    _history.add(current);
    final keep = math.min(maxHistory, step * taps + 1);
    if (_history.length > keep) _history.removeRange(0, _history.length - keep);
    final mixed = Float32List.fromList(current);
    var gain = 1.0;
    for (var tap = 1; tap <= taps; tap++) {
      gain *= decay;
      final index = _history.length - 1 - tap * step;
      if (index < 0) break;
      final past = _history[index];
      for (var i = 0; i < mixed.length; i++) {
        mixed[i] = math.min(1.0, mixed[i] + past[i] * gain);
      }
    }
    _writeFloats(setup, mixed, out, panels: panelsOf(p));
  }
}

/// Opens and closes on the beat.
final class StrobeGateEffect implements Effect {
  /// Tempo used when the project has none.
  static const fallbackBpm = 120.0;

  const StrobeGateEffect();

  @override
  EffectInfo get info => const EffectInfo(
        id: 'icicles.fx.strobe_gate',
        version: 1,
        name: LocalizedText('Strobe gate', pl: 'Bramka stroboskopowa'),
        description: LocalizedText(
          'Shows the layers only for a part of every beat (120 BPM without a tempo).',
          pl: 'Pokazuje warstwy tylko przez część każdego uderzenia (120 BPM bez tempa).',
        ),
        category: EffectCategory.dynamics,
        usesAudio: true,
      );

  @override
  List<ParamSpec> get params => const [
        NumberParam(
          id: 'rate',
          label: LocalizedText('Every', pl: 'Co'),
          description: LocalizedText('Beats between openings.', pl: 'Liczba uderzeń między otwarciami.'),
          min: 0.25,
          max: 4,
          defaultValue: 1,
          scale: NumberScale.log,
          unit: 'beats',
        ),
        NumberParam(
          id: 'duty',
          label: LocalizedText('Open for', pl: 'Otwarta przez'),
          description:
              LocalizedText('Part of the period the gate is open.', pl: 'Część okresu, gdy bramka jest otwarta.'),
          min: 0.05,
          max: 0.95,
          defaultValue: 0.5,
          step: 0.01,
        ),
        NumberParam(
          id: 'closedLevel',
          label: LocalizedText('Closed brightness', pl: 'Jasność zamkniętej'),
          min: 0,
          max: 1,
          defaultValue: 0,
          step: 0.01,
        ),
        effectPanelsParam,
      ];

  @override
  EffectInstance create(GeneratorSetup setup) => const _StrobeGateInstance();
}

final class _StrobeGateInstance implements EffectInstance {
  const _StrobeGateInstance();

  @override
  void apply(FrameContext ctx, AnimationView input, Icicles out) {
    final p = ctx.params;
    final audio = ctx.audio;
    final beats = audio.bpm > 0 ? audio.beatIndex + audio.beatPhase : ctx.seconds * StrobeGateEffect.fallbackBpm / 60;
    final position = beats / p.number('rate');
    final phase = position - position.floor();
    if (phase < p.number('duty')) return;
    final level = p.number('closedLevel');
    mapPixels(ctx, input, out, panelsOf(p), (c) => level <= 0 ? black : scaleColor(c, level));
  }
}

/// Random brightness per frame.
final class FlickerEffect implements Effect {
  const FlickerEffect();

  @override
  EffectInfo get info => const EffectInfo(
        id: 'icicles.fx.flicker',
        version: 1,
        name: LocalizedText('Flicker', pl: 'Migotanie'),
        description: LocalizedText(
          'The whole picture flickers at a random brightness, like a faulty lamp.',
          pl: 'Cały obraz migocze losową jasnością, jak wadliwa lampa.',
        ),
        category: EffectCategory.dynamics,
      );

  @override
  List<ParamSpec> get params => const [
        NumberParam(
          id: 'amount',
          label: LocalizedText('Amount', pl: 'Stopień'),
          description: LocalizedText('How dark the dips get.', pl: 'Jak ciemne są spadki.'),
          min: 0,
          max: 1,
          defaultValue: 0.5,
          step: 0.01,
        ),
        NumberParam(
          id: 'rate',
          label: LocalizedText('Rate', pl: 'Częstość'),
          description: LocalizedText('Brightness changes per second.', pl: 'Zmiany jasności na sekundę.'),
          min: 1,
          max: 60,
          defaultValue: 15,
          scale: NumberScale.log,
          unit: '/s',
        ),
        effectPanelsParam,
      ];

  @override
  EffectInstance create(GeneratorSetup setup) => _FlickerInstance();
}

final class _FlickerInstance implements EffectInstance {
  double _level = 1;
  double _nextChange = 0;

  @override
  void apply(FrameContext ctx, AnimationView input, Icicles out) {
    final p = ctx.params;
    final amount = p.number('amount');
    if (ctx.seconds >= _nextChange) {
      _level = 1 - amount * ctx.random.nextDouble();
      _nextChange = ctx.seconds + 1 / p.number('rate');
    }
    if (_level >= 1) return;
    final level = _level;
    mapPixels(ctx, input, out, panelsOf(p), (c) => scaleColor(c, level));
  }
}

/// Brightness follows a frequency range.
final class GateAudioEffect implements Effect {
  const GateAudioEffect();

  @override
  EffectInfo get info => const EffectInfo(
        id: 'icicles.fx.gate_audio',
        version: 1,
        name: LocalizedText('Audio gate', pl: 'Bramka audio'),
        description: LocalizedText(
          'The brightness of the layers follows the energy of a frequency range.',
          pl: 'Jasność warstw podąża za energią zakresu częstotliwości.',
        ),
        category: EffectCategory.dynamics,
        usesAudio: true,
      );

  static final _rangeParams = audioRangeParams();

  @override
  List<ParamSpec> get params => [
        ..._rangeParams,
        const NumberParam(
          id: 'floor',
          label: LocalizedText('Floor', pl: 'Minimum'),
          description: LocalizedText('Brightness in silence.', pl: 'Jasność w ciszy.'),
          min: 0,
          max: 1,
          defaultValue: 0,
          step: 0.01,
        ),
        const NumberParam(
          id: 'gain',
          label: LocalizedText('Sensitivity', pl: 'Czułość'),
          min: 0.25,
          max: 4,
          defaultValue: 1,
          scale: NumberScale.log,
          unit: '×',
        ),
        const NumberParam(
          id: 'smoothing',
          label: LocalizedText('Smoothing', pl: 'Wygładzanie'),
          description: LocalizedText('Release time of the follower.', pl: 'Czas opadania.'),
          min: 0,
          max: 1,
          defaultValue: 0.1,
          step: 0.01,
          unit: 's',
        ),
        effectPanelsParam,
      ];

  @override
  EffectInstance create(GeneratorSetup setup) => _GateAudioInstance();
}

final class _GateAudioInstance implements EffectInstance {
  double _follower = 0;

  @override
  void apply(FrameContext ctx, AnimationView input, Icicles out) {
    final p = ctx.params;
    final energy = (audioRangeValue(p, ctx.audio) * p.number('gain')).clamp(0.0, 1.0);
    final smoothing = p.number('smoothing');
    if (energy >= _follower || smoothing <= 0) {
      _follower = energy;
    } else {
      _follower += (energy - _follower) * (1 - math.exp(-ctx.deltaSeconds / smoothing));
    }
    final floor = p.number('floor');
    final level = floor + (1 - floor) * _follower;
    if (level >= 1) return;
    mapPixels(ctx, input, out, panelsOf(p), (c) => scaleColor(c, level));
  }
}
