import 'package:icicles_animation_dart/icicles_animation_dart.dart';

import '../effect/effect.dart';
import '../effect/effect_info.dart';
import '../generator/generator.dart';
import '../generator/localized_text.dart';
import '../params/param_spec.dart';
import 'common.dart';

const _wrapParam = BoolParam(
  id: 'wrap',
  label: LocalizedText('Wrap around', pl: 'Zawijanie'),
  description: LocalizedText('What leaves one edge comes back at the other; off leaves black.',
      pl: 'Co wychodzi jedną krawędzią, wraca drugą; wyłączone zostawia czerń.'),
  defaultValue: true,
);

const _panelsOrderParam = BoolParam(
  id: 'panels',
  label: LocalizedText('Radio panels too', pl: 'Także panele radiowe'),
  description: LocalizedText('Reverses the order of the panels as well.', pl: 'Odwraca też kolejność paneli.'),
  defaultValue: true,
);

/// Writes [grid] (column-major) into [out] and reverses the radio panel
/// order when [panels] is set.
void _finish(AnimationView input, Icicles out, List<Color> grid, {required bool panels}) {
  setGrid(out, grid);
  if (!panels) return;
  final count = input.radioPanels.length;
  for (final panel in input.radioPanels) {
    out.radioPanels[count - panel.index].setPixels(panel.colors);
  }
}

/// Flips horizontally, vertically or both.
final class FlipEffect implements Effect {
  const FlipEffect();

  @override
  EffectInfo get info => const EffectInfo(
        id: 'icicles.fx.flip',
        version: 1,
        name: LocalizedText('Flip', pl: 'Odbicie'),
        description: LocalizedText('Flips the layers across or along the icicles.',
            pl: 'Odbija warstwy w poprzek lub wzdłuż sopli.'),
        category: EffectCategory.transform,
      );

  @override
  List<ParamSpec> get params => const [
        ChoiceParam(
          id: 'axis',
          label: LocalizedText('Flip', pl: 'Odbicie'),
          options: [
            ChoiceOption('horizontal', LocalizedText('Left ↔ right', pl: 'Lewo ↔ prawo')),
            ChoiceOption('vertical', LocalizedText('Roof ↔ tips', pl: 'Dach ↔ końcówki')),
            ChoiceOption('both', LocalizedText('Both', pl: 'Oba')),
          ],
          defaultValue: 'horizontal',
        ),
        _panelsOrderParam,
      ];

  @override
  EffectInstance create(GeneratorSetup setup) => const _FlipInstance();
}

final class _FlipInstance implements EffectInstance {
  const _FlipInstance();

  @override
  void apply(FrameContext ctx, AnimationView input, Icicles out) {
    final axis = ctx.params.choice('axis');
    final flipX = axis != 'vertical';
    final flipY = axis != 'horizontal';
    final w = ctx.xCount, h = ctx.yCount;
    final grid = List<Color>.filled(w * h, black);
    for (var x = 0; x < w; x++) {
      for (var y = 0; y < h; y++) {
        grid[x * h + y] = inputPixel(ctx, input, flipX ? w - 1 - x : x, flipY ? h - 1 - y : y);
      }
    }
    _finish(input, out, grid, panels: flipX && ctx.params.flag('panels'));
  }
}

/// Mirrors one half onto the other, or folds the grid into a kaleidoscope.
final class MirrorEffect implements Effect {
  const MirrorEffect();

  @override
  EffectInfo get info => const EffectInfo(
        id: 'icicles.fx.mirror',
        version: 1,
        name: LocalizedText('Mirror', pl: 'Lustro'),
        description: LocalizedText(
          'Mirrors one half of the layers onto the other, or folds them into kaleidoscope segments.',
          pl: 'Odbija jedną połowę warstw na drugą albo składa je w segmenty kalejdoskopu.',
        ),
        category: EffectCategory.transform,
      );

  @override
  List<ParamSpec> get params => const [
        ChoiceParam(
          id: 'mode',
          label: LocalizedText('Mirror', pl: 'Lustro'),
          options: [
            ChoiceOption('leftToRight', LocalizedText('Left half → right', pl: 'Lewa połowa → prawa')),
            ChoiceOption('rightToLeft', LocalizedText('Right half → left', pl: 'Prawa połowa → lewa')),
            ChoiceOption('topToBottom', LocalizedText('Roof half → tips', pl: 'Górna połowa → końcówki')),
            ChoiceOption('bottomToTop', LocalizedText('Tips half → roof', pl: 'Dolna połowa → dach')),
            ChoiceOption('quad', LocalizedText('Quad (both)', pl: 'Poczwórne (oba)')),
            ChoiceOption('kaleidoscope', LocalizedText('Kaleidoscope', pl: 'Kalejdoskop')),
          ],
          defaultValue: 'leftToRight',
        ),
        IntParam(
          id: 'segments',
          label: LocalizedText('Segments', pl: 'Segmenty'),
          description: LocalizedText('Kaleidoscope only: mirrored wedges across the icicles.',
              pl: 'Tylko kalejdoskop: liczba odbitych segmentów w poprzek sopli.'),
          min: 2,
          max: 8,
          defaultValue: 4,
        ),
        BoolParam(
          id: 'panels',
          label: LocalizedText('Radio panels too', pl: 'Także panele radiowe'),
          description: LocalizedText('Mirrors the first half of the panels onto the second.',
              pl: 'Odbija pierwszą połowę paneli na drugą.'),
          defaultValue: true,
        ),
      ];

  @override
  EffectInstance create(GeneratorSetup setup) => const _MirrorInstance();
}

final class _MirrorInstance implements EffectInstance {
  const _MirrorInstance();

  @override
  void apply(FrameContext ctx, AnimationView input, Icicles out) {
    final p = ctx.params;
    final mode = p.choice('mode');
    final w = ctx.xCount, h = ctx.yCount;
    final grid = List<Color>.filled(w * h, black);
    for (var x = 0; x < w; x++) {
      for (var y = 0; y < h; y++) {
        var sx = x, sy = y;
        switch (mode) {
          case 'leftToRight':
            if (x >= w - x - 1) sx = w - 1 - x;
          case 'rightToLeft':
            if (x < w - x - 1) sx = w - 1 - x;
          case 'topToBottom':
            if (y >= h - y - 1) sy = h - 1 - y;
          case 'bottomToTop':
            if (y < h - y - 1) sy = h - 1 - y;
          case 'quad':
            if (x >= w - x - 1) sx = w - 1 - x;
            if (y >= h - y - 1) sy = h - 1 - y;
          default:
            final segments = p.integer('segments');
            final width = (w / segments).ceil();
            final segment = x ~/ width;
            final local = x - segment * width;
            sx = (segment.isEven ? local : width - 1 - local).clamp(0, w - 1);
        }
        grid[x * h + y] = inputPixel(ctx, input, sx, sy);
      }
    }
    setGrid(out, grid);
    if (!p.flag('panels') || mode == 'topToBottom' || mode == 'bottomToTop') return;
    final count = input.radioPanels.length;
    for (final panel in input.radioPanels) {
      final i = panel.index - 1;
      final mirrored = count - 1 - i;
      final fromSecond = mode == 'rightToLeft';
      if (fromSecond ? i < mirrored : i >= mirrored) {
        out.radioPanels[i].setPixels(input.radioPanels.firstWhere((o) => o.index == mirrored + 1).colors);
      }
    }
  }
}

/// Shifts the pixels, optionally scrolling.
final class OffsetEffect implements Effect {
  const OffsetEffect();

  @override
  EffectInfo get info => const EffectInfo(
        id: 'icicles.fx.offset',
        version: 1,
        name: LocalizedText('Offset', pl: 'Przesunięcie'),
        description: LocalizedText(
          'Shifts the layers by whole pixels, or scrolls them at a speed; bind the offset to the beat to bounce.',
          pl: 'Przesuwa warstwy o całe piksele albo przewija je z prędkością; podepnij przesunięcie pod beat, by podskakiwały.',
        ),
        category: EffectCategory.transform,
      );

  @override
  List<ParamSpec> get params => const [
        NumberParam(
          id: 'dx',
          label: LocalizedText('Across', pl: 'W poprzek'),
          description: LocalizedText('Icicles to the right.', pl: 'Sople w prawo.'),
          min: -100,
          max: 100,
          defaultValue: 0,
          step: 1,
          unit: 'px',
        ),
        NumberParam(
          id: 'dy',
          label: LocalizedText('Along', pl: 'Wzdłuż'),
          description: LocalizedText('LEDs towards the tips.', pl: 'Diody w stronę końcówek.'),
          min: -100,
          max: 100,
          defaultValue: 0,
          step: 1,
          unit: 'px',
        ),
        NumberParam(
          id: 'speedX',
          label: LocalizedText('Scroll across', pl: 'Przewijanie w poprzek'),
          min: -50,
          max: 50,
          defaultValue: 0,
          step: 0.5,
          unit: 'px/s',
        ),
        NumberParam(
          id: 'speedY',
          label: LocalizedText('Scroll along', pl: 'Przewijanie wzdłuż'),
          min: -50,
          max: 50,
          defaultValue: 0,
          step: 0.5,
          unit: 'px/s',
        ),
        _wrapParam,
      ];

  @override
  EffectInstance create(GeneratorSetup setup) => const _OffsetInstance();
}

final class _OffsetInstance implements EffectInstance {
  const _OffsetInstance();

  @override
  void apply(FrameContext ctx, AnimationView input, Icicles out) {
    final p = ctx.params;
    final dx = (p.number('dx') + p.number('speedX') * ctx.seconds).round();
    final dy = (p.number('dy') + p.number('speedY') * ctx.seconds).round();
    if (dx == 0 && dy == 0) return;
    final wrap = p.flag('wrap');
    final w = ctx.xCount, h = ctx.yCount;
    final grid = List<Color>.filled(w * h, black);
    for (var x = 0; x < w; x++) {
      for (var y = 0; y < h; y++) {
        grid[x * h + y] = sampleGrid(ctx, input, x - dx, y - dy, wrap: wrap);
      }
    }
    setGrid(out, grid);
  }
}

/// Turns the grid upside down.
final class Rotate180Effect implements Effect {
  const Rotate180Effect();

  @override
  EffectInfo get info => const EffectInfo(
        id: 'icicles.fx.rotate180',
        version: 1,
        name: LocalizedText('Rotate 180°', pl: 'Obrót o 180°'),
        description: LocalizedText('Turns the layers upside down (a flip both ways).',
            pl: 'Obraca warstwy do góry nogami (odbicie w obu osiach).'),
        category: EffectCategory.transform,
      );

  @override
  List<ParamSpec> get params => const [
        _panelsOrderParam,
        BoolParam(
          id: 'panelPixels',
          label: LocalizedText('Reverse the panel pixels', pl: 'Odwróć piksele paneli'),
          defaultValue: true,
        ),
      ];

  @override
  EffectInstance create(GeneratorSetup setup) => const _Rotate180Instance();
}

final class _Rotate180Instance implements EffectInstance {
  const _Rotate180Instance();

  @override
  void apply(FrameContext ctx, AnimationView input, Icicles out) {
    final pixels = input.frame.pixels;
    final n = pixels.length;
    setGrid(out, List<Color>.generate(n, (i) => pixels[n - 1 - i], growable: false));
    final p = ctx.params;
    final order = p.flag('panels');
    final reversePixels = p.flag('panelPixels');
    final count = input.radioPanels.length;
    for (final panel in input.radioPanels) {
      final target = out.radioPanels[order ? count - panel.index : panel.index - 1];
      final len = panel.colors.length;
      for (var i = 0; i < len; i++) {
        target.setPixel(i, panel.colors[reversePixels ? len - 1 - i : i]);
      }
    }
  }
}

/// Repeats a shrunken copy of the layers.
final class TileEffect implements Effect {
  const TileEffect();

  @override
  EffectInfo get info => const EffectInfo(
        id: 'icicles.fx.tile',
        version: 1,
        name: LocalizedText('Tile', pl: 'Kafelki'),
        description: LocalizedText(
          'Shrinks the layers and repeats them across and along the icicles.',
          pl: 'Zmniejsza warstwy i powtarza je w poprzek i wzdłuż sopli.',
        ),
        category: EffectCategory.transform,
      );

  @override
  List<ParamSpec> get params => const [
        IntParam(
            id: 'repeatX', label: LocalizedText('Across', pl: 'W poprzek'), min: 1, max: 8, defaultValue: 2, unit: '×'),
        IntParam(
            id: 'repeatY', label: LocalizedText('Along', pl: 'Wzdłuż'), min: 1, max: 8, defaultValue: 2, unit: '×'),
        BoolParam(
          id: 'mirrorTiles',
          label: LocalizedText('Mirror every other tile', pl: 'Odbijaj co drugi kafelek'),
          defaultValue: false,
        ),
      ];

  @override
  EffectInstance create(GeneratorSetup setup) => const _TileInstance();
}

final class _TileInstance implements EffectInstance {
  const _TileInstance();

  @override
  void apply(FrameContext ctx, AnimationView input, Icicles out) {
    final p = ctx.params;
    final rx = p.integer('repeatX');
    final ry = p.integer('repeatY');
    final mirror = p.flag('mirrorTiles');
    if (rx == 1 && ry == 1) return;
    final w = ctx.xCount, h = ctx.yCount;
    final grid = List<Color>.filled(w * h, black);
    for (var x = 0; x < w; x++) {
      for (var y = 0; y < h; y++) {
        final tx = x * rx ~/ w, ty = y * ry ~/ h;
        var sx = (x * rx) % w, sy = (y * ry) % h;
        if (mirror) {
          if (tx.isOdd) sx = w - 1 - sx;
          if (ty.isOdd) sy = h - 1 - sy;
        }
        grid[x * h + y] = inputPixel(ctx, input, sx, sy);
      }
    }
    setGrid(out, grid);
  }
}

/// Scales about a center.
final class ZoomEffect implements Effect {
  const ZoomEffect();

  @override
  EffectInfo get info => const EffectInfo(
        id: 'icicles.fx.zoom',
        version: 1,
        name: LocalizedText('Zoom', pl: 'Zbliżenie'),
        description: LocalizedText(
          'Scales the layers about a center (nearest pixel); bind the scale to the beat to pump.',
          pl: 'Skaluje warstwy względem środka (najbliższy piksel); podepnij skalę pod beat, by pulsowały.',
        ),
        category: EffectCategory.transform,
      );

  @override
  List<ParamSpec> get params => const [
        NumberParam(
          id: 'scale',
          label: LocalizedText('Scale', pl: 'Skala'),
          min: 0.25,
          max: 4,
          defaultValue: 1.5,
          scale: NumberScale.log,
          unit: '×',
        ),
        NumberParam(
            id: 'centerX',
            label: LocalizedText('Center across', pl: 'Środek w poprzek'),
            min: 0,
            max: 1,
            defaultValue: 0.5,
            step: 0.01),
        NumberParam(
            id: 'centerY',
            label: LocalizedText('Center along', pl: 'Środek wzdłuż'),
            min: 0,
            max: 1,
            defaultValue: 0.5,
            step: 0.01),
        BoolParam(
          id: 'wrap',
          label: LocalizedText('Wrap around', pl: 'Zawijanie'),
          description: LocalizedText('Zooming out repeats the layers instead of leaving black.',
              pl: 'Oddalenie powtarza warstwy zamiast zostawiać czerń.'),
          defaultValue: false,
        ),
      ];

  @override
  EffectInstance create(GeneratorSetup setup) => const _ZoomInstance();
}

final class _ZoomInstance implements EffectInstance {
  const _ZoomInstance();

  @override
  void apply(FrameContext ctx, AnimationView input, Icicles out) {
    final p = ctx.params;
    final scale = p.number('scale');
    if (scale == 1) return;
    final wrap = p.flag('wrap');
    final w = ctx.xCount, h = ctx.yCount;
    final cx = p.number('centerX') * (w - 1), cy = p.number('centerY') * (h - 1);
    final grid = List<Color>.filled(w * h, black);
    for (var x = 0; x < w; x++) {
      for (var y = 0; y < h; y++) {
        final sx = (cx + (x - cx) / scale).round();
        final sy = (cy + (y - cy) / scale).round();
        grid[x * h + y] = sampleGrid(ctx, input, sx, sy, wrap: wrap);
      }
    }
    setGrid(out, grid);
  }
}
