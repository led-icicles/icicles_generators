# fire_plugin — an example generator plugin

A Fire2012-style flame per icicle (`example.fire/fire`), served to the icicles visualizer as an external
plugin. The generator lives in `lib/fire_generator.dart`; `bin/fire.dart` is the whole plugin:

```dart
Future<void> main() => runGeneratorPlugin(const [ExampleFireGenerator()], pluginId: 'example.fire');
```

## Build

`dart compile exe` builds for the OS it runs on (no cross-compilation), so build on each target:

```sh
dart pub get

# macOS (Apple Silicon or Intel, matching the machine)
dart compile exe bin/fire.dart -o build/fire

# Windows (PowerShell or cmd)
dart compile exe bin\fire.dart -o build\fire.exe
```

## Install

Copy the executable into the visualizer's plugins folder and press "Refresh" in the editor's Generators tab:

- macOS: `~/Library/Application Support/it.klyta.iciclesVisualizer/plugins/` (the file must be executable:
  `chmod +x fire`; if Gatekeeper quarantines a downloaded binary, `xattr -d com.apple.quarantine fire`)
- Windows: `%APPDATA%\it.klyta.iciclesVisualizer\plugins\` (a `.exe` file)

```sh
mkdir -p ~/Library/Application\ Support/it.klyta.iciclesVisualizer/plugins
cp build/fire ~/Library/Application\ Support/it.klyta.iciclesVisualizer/plugins/
```

## Writing your own

Implement `Generator` (see the package README), give every generator an id prefixed with your plugin id
(`my.plugin/name`), bump `GeneratorInfo.version` when the output changes, and keep parameter ids stable —
projects store bindings by id. Use only `ctx.random` / `setup.seed` for randomness so bakes are reproducible.
Log with `print` (it goes to stderr, which the app logs); stdout is the protocol.

Try it without the app: `dart run bin/fire.dart` waits for protocol messages on stdin (the package's
`test/plugin_test.dart` drives it end to end).
