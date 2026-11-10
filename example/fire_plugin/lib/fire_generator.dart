import 'dart:math' as math;
import 'dart:typed_data';

import 'package:icicles_animation_dart/icicles_animation_dart.dart';
import 'package:icicles_generators/icicles_generators.dart';

/// Fire2012 (Mark Kriegsman) on every icicle: heat rises from the bottom,
/// cools on the way up and new sparks ignite at random.
final class ExampleFireGenerator implements Generator {
  const ExampleFireGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'example.fire/fire',
        version: 1,
        name: LocalizedText('Fire', pl: 'Ogień'),
        description: LocalizedText('Flames climbing up the icicles.', pl: 'Płomienie wspinające się po soplach.'),
        category: GeneratorCategory.nature,
      );

  @override
  List<ParamSpec> get params => const [
        NumberParam(
          id: 'cooling',
          label: LocalizedText('Cooling', pl: 'Chłodzenie'),
          description:
              LocalizedText('Higher values give shorter flames.', pl: 'Większe wartości dają krótsze płomienie.'),
          min: 0.1,
          max: 1,
          defaultValue: 0.5,
          step: 0.01,
        ),
        NumberParam(
          id: 'sparking',
          label: LocalizedText('Sparking', pl: 'Iskrzenie'),
          description: LocalizedText('Chance of a new spark per frame.', pl: 'Szansa nowej iskry na klatkę.'),
          min: 0,
          max: 1,
          defaultValue: 0.5,
          step: 0.01,
        ),
        PaletteParam(id: 'palette', label: LocalizedText('Palette', pl: 'Paleta'), defaultValue: Palette.fire),
        NumberParam(
            id: 'brightness', label: LocalizedText('Brightness', pl: 'Jasność'), min: 0, max: 1, defaultValue: 1),
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _FireInstance(setup.xCount, setup.yCount);
}

final class _FireInstance implements GeneratorInstance {
  final int yCount;
  final List<Float64List> heat;

  _FireInstance(int xCount, this.yCount) : heat = List.generate(xCount, (_) => Float64List(yCount));

  @override
  void render(FrameContext ctx, Icicles out) {
    final p = ctx.params;
    final random = ctx.random;
    final cooling = p.number('cooling') * 10 / yCount;
    final sparking = p.number('sparking');
    final palette = p.palette('palette');
    final brightness = p.number('brightness');
    for (var x = 0; x < heat.length; x++) {
      final column = heat[x];
      // Index 0 is the bottom of the icicle here; y = yCount - 1 - i on screen.
      for (var i = 0; i < yCount; i++) {
        column[i] = math.max(0, column[i] - random.nextDouble() * cooling);
      }
      for (var i = yCount - 1; i >= 2; i--) {
        column[i] = (column[i - 1] + column[i - 2] * 2) / 3;
      }
      if (random.nextDouble() < sparking) {
        final i = random.nextInt(math.min(3, yCount));
        column[i] = math.min(1, column[i] + 0.6 + random.nextDouble() * 0.4);
      }
      for (var i = 0; i < yCount; i++) {
        out.setPixelColor(x, yCount - 1 - i, dim(palette.sample(column[i]), brightness));
      }
    }
    applyPanelMode(out, panelModeOf(p));
  }
}
