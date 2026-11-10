import 'generator.dart';

/// Generators by id.
final class GeneratorRegistry {
  final Map<String, Generator> _byId;

  /// Registers [generators]; the first one wins when two share an id.
  GeneratorRegistry(Iterable<Generator> generators) : _byId = {} {
    for (final generator in generators) {
      _byId.putIfAbsent(generator.info.id, () => generator);
    }
  }

  /// All generators in registration order.
  Iterable<Generator> get generators => _byId.values;

  /// The generator with [id], or `null`.
  Generator? find(String id) => _byId[id];

  bool contains(String id) => _byId.containsKey(id);
}
