import 'dart:math' as math;

import 'package:icicles_animation_dart/icicles_animation_dart.dart';

import '../effect/effect.dart';
import '../effect/effect_info.dart';
import '../generator/generator.dart';
import '../generator/localized_text.dart';
import '../params/param_spec.dart';
import 'common.dart';

/// The order a [CascadeEffect] delays the icicles in.
enum CascadeDirection {
  leftToRight,
  rightToLeft,
  fromCenter,
  toCenter,

  /// A seeded shuffle of the icicles.
  random;

  static CascadeDirection fromId(String id) =>
      values.firstWhere((d) => d.name == id, orElse: () => CascadeDirection.leftToRight);
}

/// How a [CascadeEffect] spreads its delay over the steps.
enum CascadeCurve {
  linear,

  /// Slow start: the first icicles follow each other closely.
  easeIn,

  /// Fast start: the last icicles follow each other closely.
  easeOut;

  static CascadeCurve fromId(String id) => values.firstWhere((c) => c.name == id, orElse: () => CascadeCurve.linear);

  /// [t] (`0..1`) on the curve.
  double at(double t) => switch (this) {
        CascadeCurve.linear => t,
        CascadeCurve.easeIn => t * t,
        CascadeCurve.easeOut => 1 - (1 - t) * (1 - t),
      };
}

/// How a [CascadeEffect] delays the radio panels.
enum CascadePanels {
  /// The panels are further steps after the last icicle.
  after,

  /// Not delayed.
  none,

  /// Each panel follows the icicle at its proportional position (panel `i`
  /// of `n` at `(i + 0.5) / n` across the icicles).
  withNearest;

  static CascadePanels fromId(String id) => values.firstWhere((p) => p.name == id, orElse: () => CascadePanels.after);
}

/// The same picture delayed icicle by icicle (like a per-model time offset
/// in xLights): a hit of the tracks below travels across the installation
/// as a wave. Only the past exists for an effect, so the first icicle of the
/// [CascadeDirection] shows the input as is and the others lag behind it;
/// before a lagging icicle has history it is black.
final class CascadeEffect implements Effect {
  /// The longest delay of the last step.
  static const maxTotalDelay = Duration(seconds: 4);

  const CascadeEffect();

  @override
  EffectInfo get info => const EffectInfo(
        id: 'icicles.fx.cascade',
        version: 1,
        name: LocalizedText('Cascade delay', pl: 'Opóźnienie sopel po soplu'),
        description: LocalizedText(
          'Delays the tracks below icicle by icicle, so a hit runs across the installation as a wave.',
          pl: 'Opóźnia ścieżki poniżej sopel po soplu, więc uderzenie przechodzi falą przez instalację.',
        ),
        category: EffectCategory.dynamics,
      );

  @override
  List<ParamSpec> get params => const [
        NumberParam(
          id: 'delay',
          label: LocalizedText('Delay per icicle', pl: 'Opóźnienie na sopel'),
          description: LocalizedText('Time between two neighbouring steps (at most 4 s in total).',
              pl: 'Czas między dwoma kolejnymi krokami (łącznie najwyżej 4 s).'),
          min: 0,
          max: 0.5,
          defaultValue: 0.03,
          unit: 's',
        ),
        ChoiceParam(
          id: 'direction',
          label: LocalizedText('Direction', pl: 'Kierunek'),
          options: [
            ChoiceOption('leftToRight', LocalizedText('Left to right', pl: 'Od lewej do prawej')),
            ChoiceOption('rightToLeft', LocalizedText('Right to left', pl: 'Od prawej do lewej')),
            ChoiceOption('fromCenter', LocalizedText('From the center', pl: 'Od środka')),
            ChoiceOption('toCenter', LocalizedText('To the center', pl: 'Do środka')),
            ChoiceOption('random', LocalizedText('Random order', pl: 'Losowa kolejność')),
          ],
          defaultValue: 'leftToRight',
        ),
        ChoiceParam(
          id: 'curve',
          label: LocalizedText('Spread', pl: 'Rozłożenie'),
          options: [
            ChoiceOption('linear', LocalizedText('Even', pl: 'Równo')),
            ChoiceOption('easeIn', LocalizedText('Slow start', pl: 'Wolny start')),
            ChoiceOption('easeOut', LocalizedText('Fast start', pl: 'Szybki start')),
          ],
          defaultValue: 'linear',
        ),
        ChoiceParam(
          id: 'panels',
          label: LocalizedText('Radio panels', pl: 'Panele radiowe'),
          options: [
            ChoiceOption('after', LocalizedText('After the icicles', pl: 'Po soplach')),
            ChoiceOption('none', LocalizedText('Not delayed', pl: 'Bez opóźnienia')),
            ChoiceOption('withNearest', LocalizedText('With the nearest icicle', pl: 'Z najbliższym soplem')),
          ],
          defaultValue: 'after',
        ),
      ];

  @override
  EffectInstance create(GeneratorSetup setup) => _CascadeInstance(setup);
}

/// The delay of every icicle and panel in steps of the [CascadeDirection]
/// (`0` = no delay): icicle `x` is step `stepsOf.icicles[x]`, panel `p`
/// (0-based) step `stepsOf.panels[p]`, as a fraction of the last step
/// (`0..1`).
({List<double> icicles, List<double> panels}) cascadeOffsets({
  required int xCount,
  required int panelsCount,
  required CascadeDirection direction,
  required CascadeCurve curve,
  required CascadePanels panels,
  required int seed,
}) {
  // Rank of each icicle: 0 for the first to move.
  final ranks = List<double>.filled(xCount, 0);
  final centre = (xCount - 1) / 2;
  var lastRank = 0.0;
  switch (direction) {
    case CascadeDirection.leftToRight:
      for (var x = 0; x < xCount; x++) {
        ranks[x] = x.toDouble();
      }
      lastRank = (xCount - 1).toDouble();
    case CascadeDirection.rightToLeft:
      for (var x = 0; x < xCount; x++) {
        ranks[x] = (xCount - 1 - x).toDouble();
      }
      lastRank = (xCount - 1).toDouble();
    case CascadeDirection.fromCenter:
      for (var x = 0; x < xCount; x++) {
        ranks[x] = (x - centre).abs().floorToDouble();
      }
      lastRank = centre.floorToDouble();
    case CascadeDirection.toCenter:
      for (var x = 0; x < xCount; x++) {
        ranks[x] = centre.floorToDouble() - (x - centre).abs().floorToDouble();
      }
      lastRank = centre.floorToDouble();
    case CascadeDirection.random:
      final order = List<int>.generate(xCount, (x) => x)..shuffle(math.Random(seed));
      for (var i = 0; i < xCount; i++) {
        ranks[order[i]] = i.toDouble();
      }
      lastRank = (xCount - 1).toDouble();
  }
  final steps = lastRank + (panels == CascadePanels.after ? panelsCount : 0);
  double shaped(double rank) => steps <= 0 ? 0 : curve.at(rank / steps);
  final icicles = [for (final r in ranks) shaped(r)];
  final panelOffsets = [
    for (var p = 0; p < panelsCount; p++)
      switch (panels) {
        CascadePanels.after => shaped(lastRank + p + 1),
        CascadePanels.none => 0.0,
        CascadePanels.withNearest =>
          icicles[(((p + 0.5) / panelsCount) * xCount).floor().clamp(0, math.max(0, xCount - 1))],
      },
  ];
  return (icicles: icicles, panels: panelOffsets);
}

final class _CascadeInstance implements EffectInstance {
  final GeneratorSetup setup;

  /// Past inputs, newest last: the icicle pixels and the panels' pixels.
  final _history = <(List<Color>, List<List<Color>>)>[];

  _CascadeInstance(this.setup);

  @override
  void apply(FrameContext ctx, AnimationView input, Icicles out) {
    final p = ctx.params;
    final fps = setup.framerate.framesPerSecond;
    final panelsMode = CascadePanels.fromId(p.choice('panels'));
    final offsets = cascadeOffsets(
      xCount: setup.xCount,
      panelsCount: setup.radioPanelsCount,
      direction: CascadeDirection.fromId(p.choice('direction')),
      curve: CascadeCurve.fromId(p.choice('curve')),
      panels: panelsMode,
      seed: setup.seed,
    );
    final stepCount = math.max(1, setup.xCount - 1 + (panelsMode == CascadePanels.after ? setup.radioPanelsCount : 0));
    final maxSeconds = CascadeEffect.maxTotalDelay.inMicroseconds / Duration.microsecondsPerSecond;
    final total = math.min(maxSeconds, p.number('delay') * stepCount);
    _history.add((
      List<Color>.of(input.frame.pixels),
      [
        for (var i = 1; i <= setup.radioPanelsCount; i++)
          List<Color>.of(input.radioPanels.firstWhere((panel) => panel.index == i).colors),
      ],
    ));
    final keep = (maxSeconds * fps).ceil() + 1;
    if (_history.length > keep) _history.removeRange(0, _history.length - keep);

    (List<Color>, List<List<Color>>)? back(double offset) {
      final frames = (offset * total * fps).round();
      final index = _history.length - 1 - frames;
      return index < 0 ? null : _history[index];
    }

    final yCount = setup.yCount;
    for (var x = 0; x < setup.xCount; x++) {
      final source = back(offsets.icicles[x]);
      for (var y = 0; y < yCount; y++) {
        final i = x * yCount + y;
        out.setPixelColorAtIndex(i, source == null ? black : source.$1[i]);
      }
    }
    for (var panel = 0; panel < setup.radioPanelsCount; panel++) {
      final source = back(offsets.panels[panel]);
      final target = out.radioPanels[panel];
      for (var i = 0; i < setup.radioPanelPixelCount; i++) {
        target.setPixel(i, source == null ? black : source.$2[panel][i]);
      }
    }
  }
}
