import 'package:icicles_animation_dart/icicles_animation_dart.dart';

import '../generator/localized_text.dart';
import '../params/param_spec.dart';
import '../params/param_values.dart';

/// What a generator shows on the radio panels.
enum PanelMode {
  /// Panels black.
  off,

  /// Each panel shows the average color of its share of the icicles
  /// (panel `p` of `n` averages the columns `[p·x/n, (p+1)·x/n)`).
  mirror,

  /// The generator draws the panels itself.
  own;

  static PanelMode fromId(String id) => values.firstWhere((m) => m.name == id, orElse: () => PanelMode.mirror);
}

const _off = ChoiceOption('off', LocalizedText('Off', pl: 'Wyłączone'));
const _mirror = ChoiceOption('mirror', LocalizedText('Mirror the icicles', pl: 'Jak sople'));
const _own = ChoiceOption('own', LocalizedText('Own effect', pl: 'Własny efekt'));
const _label = LocalizedText('Radio panels', pl: 'Panele radiowe');

/// The standard radio panel parameter (`panels`): off or mirror.
const panelModeParam = ChoiceParam(id: 'panels', label: _label, options: [_off, _mirror], defaultValue: 'mirror');

/// The standard radio panel parameter (`panels`) of a generator that also
/// draws the panels itself (default).
const panelModeParamWithOwn = ChoiceParam(
  id: 'panels',
  label: _label,
  options: [_off, _mirror, _own],
  defaultValue: 'own',
);

/// The [PanelMode] of the `panels` parameter in [params].
PanelMode panelModeOf(ParamValues params, [String id = 'panels']) => PanelMode.fromId(params.choice(id));

/// Applies [mode] to the radio panels of [out] after the icicles are drawn:
/// [PanelMode.off] blacks them out, [PanelMode.mirror] averages the
/// icicles, [PanelMode.own] leaves them to the generator.
void applyPanelMode(Icicles out, PanelMode mode) {
  final panels = out.radioPanelsCount;
  if (panels == 0) return;
  switch (mode) {
    case PanelMode.off:
      out.setAllRadioPanelsColor(const Color(0xFF000000));
    case PanelMode.mirror:
      final xCount = out.size.width;
      final yCount = out.size.height;
      for (var p = 0; p < panels; p++) {
        var from = p * xCount ~/ panels;
        var to = (p + 1) * xCount ~/ panels;
        if (to <= from) {
          from = from.clamp(0, xCount - 1);
          to = from + 1;
        }
        var r = 0, g = 0, b = 0, n = 0;
        for (var x = from; x < to; x++) {
          for (var y = 0; y < yCount; y++) {
            final c = out.getPixelColor(x, y);
            r += c.red;
            g += c.green;
            b += c.blue;
            n++;
          }
        }
        out.setRadioPanelColor(p, n == 0 ? const Color(0xFF000000) : Color.fromRGB(r ~/ n, g ~/ n, b ~/ n));
      }
    case PanelMode.own:
      break;
  }
}
