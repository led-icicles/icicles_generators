import 'dart:async';
import 'dart:io';

import '../effect/effect.dart';
import '../generator/generator.dart';
import 'plugin_connection.dart';
import 'plugin_server.dart';

/// The whole `main()` of a generator plugin: serves [generators] (and
/// [effects]) over stdin/stdout until the host closes stdin.
///
/// Stdout carries the protocol, so `print` is redirected to stderr (the
/// host logs it); never write to stdout yourself.
///
/// ```dart
/// Future<void> main() => runGeneratorPlugin(const [FireGenerator()], pluginId: 'example.fire');
/// ```
Future<void> runGeneratorPlugin(
  List<Generator> generators, {
  required String pluginId,
  List<Effect> effects = const [],
}) async {
  final connection = PluginConnection(stdin, stdout);
  await runZoned(
    () => serveGeneratorPlugin(generators, pluginId: pluginId, effects: effects, connection: connection),
    zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) => stderr.writeln(line)),
  );
  await stdout.flush();
  await connection.close();
}
