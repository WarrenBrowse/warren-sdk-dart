import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:warren_sdk_ffi/warren_sdk_ffi.dart';

/// The cargo `cdylib` output path for the host platform, relative to the package
/// directory that `flutter test` runs from.
String engineLibraryPath() {
  const base = '../../native/warren_sdk_frb/target/release/';
  if (Platform.isMacOS) return '${base}libwarren_sdk_frb.dylib';
  if (Platform.isWindows) return '${base}warren_sdk_frb.dll';
  return '${base}libwarren_sdk_frb.so';
}

/// Registers the in-process engine backed by the cargo-built library, so tests
/// exercise the real Rust code. Returns `false` if the library is not built yet.
bool tryRegisterEngine() {
  final path = engineLibraryPath();
  if (!File(path).existsSync()) return false;
  WarrenSdkFfi.externalLibraryOverride = ExternalLibrary.open(path);
  WarrenSdkFfi.ensureRegistered();
  return true;
}
