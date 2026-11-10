/// Why a generator could not be baked.
enum GeneratorErrorKind {
  /// The request is malformed (no frames, a layout the library rejects…).
  invalidRequest,

  /// The request is longer than [maxBakeLength].
  tooLong,

  /// The generator threw while rendering.
  renderFailed,

  /// No generator with the requested id.
  unknownGenerator,

  /// A plugin sent something that does not follow the protocol.
  protocolError,

  /// A plugin did not answer in time.
  timeout,

  /// A plugin process failed or exited.
  pluginFailed,
}

/// A failure of baking a generator, in process or in a plugin.
final class GeneratorException implements Exception {
  final GeneratorErrorKind kind;
  final String message;

  /// The original error, if any (not sent over the plugin protocol).
  final Object? cause;

  const GeneratorException(this.kind, this.message, [this.cause]);

  @override
  String toString() => 'GeneratorException(${kind.name}): $message${cause == null ? '' : ' ($cause)'}';
}
