import 'effect.dart';

/// Effects by id.
final class EffectRegistry {
  final Map<String, Effect> _byId;

  /// Registers [effects]; the first one wins when two share an id.
  EffectRegistry(Iterable<Effect> effects) : _byId = {} {
    for (final effect in effects) {
      _byId.putIfAbsent(effect.info.id, () => effect);
    }
  }

  /// All effects in registration order.
  Iterable<Effect> get effects => _byId.values;

  /// The effect with [id], or `null`.
  Effect? find(String id) => _byId[id];

  bool contains(String id) => _byId.containsKey(id);
}
