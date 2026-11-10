import 'package:fire_plugin/fire_generator.dart';
import 'package:icicles_generators/plugin.dart';

/// A generator plugin: the host talks to it over stdin/stdout.
Future<void> main() => runGeneratorPlugin(const [ExampleFireGenerator()], pluginId: 'example.fire');
