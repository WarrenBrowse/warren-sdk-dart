import 'package:flutter_driver/driver_extension.dart';
import 'package:warren_sdk_example/main.dart' as app;

/// Driver-instrumented entrypoint. It enables the Flutter Driver extension and
/// then runs the normal app, so the Dart MCP `flutter_driver_command` (tap,
/// enter_text, scroll, screenshot, ...) can drive the live UI by widget finder.
///
/// This is a development/testing entrypoint only; production runs use
/// `lib/main.dart`. Launch it with:
///
///   fvm flutter run -t test_driver/app.dart -d macos --debug
void main() {
  enableFlutterDriverExtension();
  app.main();
}
