import 'dart:math' as math;

import 'package:icicles_animation_dart/icicles_animation_dart.dart';

import '../generator/generator.dart';
import '../generator/generator_info.dart';
import '../generator/localized_text.dart';
import '../params/param_spec.dart';
import '../time/drum_hits.dart';
import '../util/color.dart';
import 'common.dart';

/// Where the front of an [ImpactGenerator] hit starts.
enum ImpactShape {
  /// The whole installation at once.
  full,

  /// A ring growing from the middle.
  center,

  /// Rising from the icicle tips (the bottom LEDs) to the roots.
  tips,

  /// Falling from the roots (the top LEDs) to the tips.
  roots,

  /// A ring from the middle that breaks into sparks while it fades.
  burst,

  /// From the two outer icicles to the middle.
  sides;

  static ImpactShape fromId(String id) => values.firstWhere((s) => s.name == id, orElse: () => ImpactShape.full);

  /// When the front reaches the point at ([u], [v]) (`0..1` across the
  /// icicles and down an icicle, `v` = 0 at the roots), as a fraction of the
  /// travel time.
  double reachAt(double u, double v) => switch (this) {
        full => 0,
        center || burst => math.min(1.0, math.sqrt(math.pow(u - 0.5, 2) + math.pow(v - 0.5, 2)) / math.sqrt(0.5)),
        tips => 1 - v,
        roots => v,
        sides => 1 - (u - 0.5).abs() * 2,
      };
}

/// How an [ImpactGenerator] hit fades after its hold.
enum ImpactCurve {
  /// `exp(−t / decay)`: a quick drop with a long tail.
  exp,

  /// A straight fade to black over the decay.
  linear,

  /// Full until the decay ends, then off.
  hold;

  static ImpactCurve fromId(String id) => values.firstWhere((c) => c.name == id, orElse: () => ImpactCurve.exp);

  /// The level `0..1` at [t] seconds after the hold, for [decay] seconds.
  double at(double t, double decay) {
    if (t <= 0) return 1;
    if (decay <= 0) return 0;
    return switch (this) {
      exp => math.exp(-t / decay * 3),
      linear => math.max(0.0, 1 - t / decay),
      hold => t < decay ? 1.0 : 0.0,
    };
  }
}

/// A one-shot accent ("hit"): a flash with a shape, a travel time, a fade
/// curve and a color shift — made for drops. By default it fires once at
/// the clip start; it can also fire on beats, drum hits, cues or a bound
/// trigger. Repeating triggers keep to the photosensitive limit (at most 3
/// hits a second, [minGap]).
final class ImpactGenerator implements Generator {
  /// The shortest time between two repeating hits (≤ 3 a second).
  static const minGap = Duration(milliseconds: 335);

  /// Tempo of the beat trigger without a beat clock.
  static const fallbackBpm = 120.0;

  const ImpactGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'icicles.impact',
        version: 1,
        name: LocalizedText('Impact', pl: 'Uderzenie'),
        description: LocalizedText(
          'A one-shot hit: a flash from the center, the tips, the roots or the sides that fades with a chosen curve. '
          'Fires at the clip start, or on beats, drums or cues.',
          pl: 'Jednorazowe uderzenie: błysk od środka, czubków, nasady albo boków, gasnący z wybraną krzywą. '
              'Wybucha na początku klipu albo na beatach, perkusji lub znacznikach.',
        ),
        category: GeneratorCategory.basic,
        usesAudio: true,
        defaultLength: Duration(seconds: 2),
      );

  @override
  List<ParamSpec> get params => const [
        ChoiceParam(
          id: 'trigger',
          label: LocalizedText('Fires on', pl: 'Wybucha na'),
          options: [
            ChoiceOption('start', LocalizedText('Clip start (once)', pl: 'Początek klipu (raz)')),
            ChoiceOption('beat', LocalizedText('Every beat', pl: 'Każdy beat')),
            ChoiceOption('kick', LocalizedText('Kick', pl: 'Stopa')),
            ChoiceOption('snare', LocalizedText('Snare', pl: 'Werbel')),
            ChoiceOption('drums', LocalizedText('Any drum', pl: 'Dowolna perkusja')),
            ChoiceOption('cues', LocalizedText('Cues (manual)', pl: 'Znaczniki (ręcznie)'), usesCues: true),
            ChoiceOption('fire', LocalizedText('Trigger value', pl: 'Wartość wyzwalacza')),
          ],
          defaultValue: 'start',
        ),
        NumberParam(
          id: 'fire',
          label: LocalizedText('Trigger', pl: 'Wyzwalacz'),
          description: LocalizedText('With "Trigger value": fires when it rises above ½ (bind it).',
              pl: 'Przy „Wartość wyzwalacza”: wybucha, gdy przekroczy ½ (podepnij go).'),
          min: 0,
          max: 1,
          defaultValue: 0,
          step: 0.01,
        ),
        ChoiceParam(
          id: 'shape',
          label: LocalizedText('Shape', pl: 'Kształt'),
          options: [
            ChoiceOption('full', LocalizedText('Everything at once', pl: 'Wszystko naraz')),
            ChoiceOption('center', LocalizedText('From the center', pl: 'Od środka')),
            ChoiceOption('tips', LocalizedText('From the tips up', pl: 'Od czubków w górę')),
            ChoiceOption('roots', LocalizedText('From the roots down', pl: 'Od nasady w dół')),
            ChoiceOption('burst', LocalizedText('Burst', pl: 'Wybuch')),
            ChoiceOption('sides', LocalizedText('From the sides', pl: 'Od boków')),
          ],
          defaultValue: 'center',
        ),
        NumberParam(
          id: 'travel',
          label: LocalizedText('Travel', pl: 'Przejście'),
          description: LocalizedText('Time the front takes to cross the installation.',
              pl: 'Czas, w jakim czoło przechodzi przez instalację.'),
          min: 0,
          max: 2,
          defaultValue: 0.25,
          unit: 's',
        ),
        NumberParam(
          id: 'width',
          label: LocalizedText('Front softness', pl: 'Miękkość czoła'),
          min: 0.05,
          max: 1,
          defaultValue: 0.2,
          step: 0.01,
        ),
        NumberParam(
          id: 'hold',
          label: LocalizedText('Hold', pl: 'Przytrzymanie'),
          min: 0,
          max: 2,
          defaultValue: 0,
          unit: 's',
        ),
        ChoiceParam(
          id: 'curve',
          label: LocalizedText('Fade', pl: 'Wygaszanie'),
          options: [
            ChoiceOption('exp', LocalizedText('Exponential', pl: 'Wykładnicze')),
            ChoiceOption('linear', LocalizedText('Linear', pl: 'Liniowe')),
            ChoiceOption('hold', LocalizedText('Cut off', pl: 'Ucięte')),
          ],
          defaultValue: 'exp',
        ),
        NumberParam(
          id: 'decay',
          label: LocalizedText('Fade time', pl: 'Czas wygaszania'),
          min: 0.05,
          max: 4,
          defaultValue: 0.6,
          scale: NumberScale.log,
          unit: 's',
        ),
        ColorParam(id: 'color', label: colorLabel, defaultValue: Color(0xFFFFFFFF)),
        BoolParam(
          id: 'fadeColor',
          label: LocalizedText('Shift color while fading', pl: 'Zmiana koloru przy wygaszaniu'),
          defaultValue: false,
        ),
        ColorParam(
          id: 'endColor',
          label: LocalizedText('End color', pl: 'Kolor końcowy'),
          defaultValue: Color(0xFFFF5500),
        ),
        BoolParam(
          id: 'panels',
          label: LocalizedText('Radio panels too', pl: 'Także panele radiowe'),
          defaultValue: true,
        ),
        brightnessParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _ImpactInstance(setup.seed);
}

final class _Hit {
  final Duration at;
  final double strength;
  final int seed;

  const _Hit(this.at, this.strength, this.seed);
}

final class _ImpactInstance implements GeneratorInstance {
  final int seed;
  final _hits = <_Hit>[];
  Duration? _lastHit;
  int? _lastBeat;
  bool _armed = true;

  _ImpactInstance(this.seed);

  static const _drums = {'kick': DrumClass.kick, 'snare': DrumClass.snare, 'drums': null};

  /// The strength (`0..1`, 0 = none) of a hit the trigger fires this frame.
  double _fires(FrameContext ctx, String trigger) {
    final audio = ctx.audio;
    // Without detected drums the drum triggers follow the beat clock.
    if (_drums.containsKey(trigger) && !audio.hasDrums) trigger = 'beat';
    switch (trigger) {
      case 'start':
        return ctx.frameIndex == 0 ? 1 : 0;
      case 'beat':
        final beat = audio.bpm > 0 ? audio.beatIndex : (ctx.seconds * ImpactGenerator.fallbackBpm / 60 + 1e-9).floor();
        final fired = ctx.frameIndex == 0 ? (audio.bpm > 0 ? audio.beatPhase < 0.05 : true) : beat != _lastBeat;
        _lastBeat = beat;
        return fired ? 1 : 0;
      case 'cues':
        return audio.cueHit;
      case 'fire':
        final value = ctx.params.number('fire');
        if (value < 0.5) {
          _armed = true;
          return 0;
        }
        if (!_armed) return 0;
        _armed = false;
        return 1;
      default:
        final cls = _drums[trigger];
        return cls == null ? audio.anyDrumHit : audio.drumHit(cls);
    }
  }

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final trigger = p.choice('trigger');
    final strength = _fires(ctx, trigger);
    final last = _lastHit;
    if (strength > 0 && (trigger == 'start' || last == null || ctx.time - last >= ImpactGenerator.minGap)) {
      _lastHit = ctx.time;
      _hits.add(_Hit(ctx.time, strength.clamp(0.0, 1.0), seed * 7919 + _hits.length));
    }

    final shape = ImpactShape.fromId(p.choice('shape'));
    final curve = ImpactCurve.fromId(p.choice('curve'));
    final travel = p.number('travel');
    final width = p.number('width');
    final hold = p.number('hold');
    final decay = p.number('decay');
    final color = p.color('color');
    final endColor = p.flag('fadeColor') ? p.color('endColor') : null;
    final brightness = p.number('brightness');
    final lifetime = travel + hold + decay * (curve == ImpactCurve.exp ? 3 : 1);
    _hits.removeWhere((h) => _seconds(ctx.time - h.at) > lifetime + width);

    Color at(double u, double v, int pixel) {
      var level = 0.0;
      var progress = 0.0;
      for (final hit in _hits) {
        final age = _seconds(ctx.time - hit.at);
        final reach = shape.reachAt(u, v);
        // How far the front has passed this point, in the softness' units.
        final front = travel <= 0 ? double.infinity : (age / travel - reach) / width;
        if (front < 0) continue;
        final edge = math.min(1.0, front);
        final since = travel <= 0 ? age : age - reach * travel;
        var l = edge * curve.at(since - hold, decay) * hit.strength;
        if (shape == ImpactShape.burst) l = math.pow(l, 0.5 + 1.5 * _noise(hit.seed, pixel)).toDouble();
        if (l > level) {
          level = l;
          progress = decay <= 0 ? 1 : ((since - hold) / decay).clamp(0.0, 1.0);
        }
      }
      if (level <= 0) return black;
      final c = endColor == null ? color : mixColors(color, endColor, progress);
      return dim(c, level * brightness);
    }

    final xCount = ctx.xCount, yCount = ctx.yCount;
    for (var x = 0; x < xCount; x++) {
      final u = xCount == 1 ? 0.5 : x / (xCount - 1);
      for (var y = 0; y < yCount; y++) {
        final v = yCount == 1 ? 0.5 : y / (yCount - 1);
        final i = x * yCount + y;
        out.setPixelColorAtIndex(i, at(u, v, i));
      }
    }
    final panels = out.radioPanels;
    final showPanels = p.flag('panels');
    for (var n = 0; n < panels.length; n++) {
      final c = showPanels ? at((n + 0.5) / panels.length, 0.5, xCount * yCount + n) : black;
      for (var i = 0; i < ctx.setup.radioPanelPixelCount; i++) {
        panels[n].setPixel(i, c);
      }
    }
  }

  static double _seconds(Duration d) => d.inMicroseconds / Duration.microsecondsPerSecond;

  /// A deterministic `0..1` per hit and pixel.
  static double _noise(int seed, int pixel) {
    var h = (seed * 0x9E3779B1 + pixel * 0x85EBCA77) & 0x7fffffff;
    h = ((h ^ (h >> 15)) * 0x2C1B3C6D) & 0x7fffffff;
    h = (h ^ (h >> 12)) & 0x7fffffff;
    return h / 0x7fffffff;
  }
}
