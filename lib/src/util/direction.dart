import '../generator/localized_text.dart';
import '../params/param_spec.dart';
import '../params/param_values.dart';

/// A direction over the grid, the value of a [directionParam].
///
/// [down] is towards the tips of the icicles (increasing `y`), [right] is
/// increasing `x`; [inward] and [outward] are relative to the center.
enum Direction {
  up('up', LocalizedText('Up', pl: 'W górę')),
  down('down', LocalizedText('Down', pl: 'W dół')),
  left('left', LocalizedText('Left', pl: 'W lewo')),
  right('right', LocalizedText('Right', pl: 'W prawo')),
  inward('in', LocalizedText('Inwards', pl: 'Do środka')),
  outward('out', LocalizedText('Outwards', pl: 'Na zewnątrz'));

  /// The option id stored in projects.
  final String id;
  final LocalizedText label;

  const Direction(this.id, this.label);

  /// The choice option of this direction.
  ChoiceOption get option => ChoiceOption(id, label);

  /// Whether the direction runs along the icicles ([up]/[down]).
  bool get isVertical => this == up || this == down;

  /// Whether the direction runs across the icicles ([left]/[right]).
  bool get isHorizontal => this == left || this == right;

  /// Whether the direction is relative to the center ([inward]/[outward]).
  bool get isRadial => this == inward || this == outward;

  /// The opposite direction.
  Direction get reversed => switch (this) {
        up => down,
        down => up,
        left => right,
        right => left,
        inward => outward,
        outward => inward,
      };

  /// The direction of option [id], [fallback] for an unknown one.
  static Direction fromId(String id, [Direction fallback = Direction.down]) =>
      values.firstWhere((d) => d.id == id, orElse: () => fallback);
}

/// The four straight directions.
const straightDirections = [Direction.up, Direction.down, Direction.left, Direction.right];

const _label = LocalizedText('Direction', pl: 'Kierunek');

/// The standard direction parameter (`direction` by default): a
/// [ChoiceParam] over [options] (all of [Direction.values] by default) with
/// the option ids `up`, `down`, `left`, `right`, `in`, `out`. Read it with
/// [directionOf].
ChoiceParam directionParam({
  String id = 'direction',
  LocalizedText label = _label,
  LocalizedText? description,
  List<Direction> options = Direction.values,
  Direction defaultValue = Direction.down,
}) {
  if (!options.contains(defaultValue)) {
    throw ArgumentError.value(defaultValue, 'defaultValue', 'Not among the options.');
  }
  return ChoiceParam(
    id: id,
    label: label,
    description: description,
    options: List.unmodifiable([for (final direction in options) direction.option]),
    defaultValue: defaultValue.id,
  );
}

/// The [Direction] of the choice parameter [id] in [params].
Direction directionOf(ParamValues params, [String id = 'direction']) => Direction.fromId(params.choice(id));
