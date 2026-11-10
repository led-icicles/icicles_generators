import 'package:icicles_animation_dart/icicles_animation_dart.dart';

import '../util/palette.dart';

/// Parameter values resolved at one frame, read by id.
///
/// Reading an id the generator does not declare, or with the wrong type, is
/// a programming error and throws an [ArgumentError].
final class ParamValues {
  final Map<String, Object> _values;

  /// Values by parameter id (not copied).
  const ParamValues(this._values);

  T _get<T>(String id) {
    final value = _values[id];
    if (value is T) return value;
    throw ArgumentError.value(id, 'id', value == null ? 'Unknown parameter.' : 'Not a $T (${value.runtimeType}).');
  }

  /// A number parameter.
  double number(String id) => _get<num>(id).toDouble();

  /// An integer parameter.
  int integer(String id) => _get<num>(id).round();

  /// A bool parameter.
  bool flag(String id) => _get<bool>(id);

  /// The option id of a choice parameter.
  String choice(String id) => _get<String>(id);

  /// A text parameter.
  String text(String id) => _get<String>(id);

  /// A color parameter.
  Color color(String id) => _get<Color>(id);

  /// A palette parameter.
  Palette palette(String id) => _get<Palette>(id);

  /// All values by id.
  Map<String, Object> toMap() => Map.unmodifiable(_values);
}
