/// The out-of-process generator plugin protocol (uses `dart:io`).
///
/// A plugin is a Dart program compiled with `dart compile exe` whose `main`
/// calls [runGeneratorPlugin]; the host starts it, talks over its
/// stdin/stdout with [GeneratorPluginClient] and gets animations
/// byte-identical to an in-process [bakeGenerator]. Import this library
/// only in plugins and in the host's data layer.
library;

export 'icicles_generators.dart';
export 'src/plugin/manifest_json.dart';
export 'src/plugin/plugin_client.dart';
export 'src/plugin/plugin_connection.dart';
export 'src/plugin/plugin_io.dart';
export 'src/plugin/plugin_protocol.dart';
export 'src/plugin/plugin_server.dart';
