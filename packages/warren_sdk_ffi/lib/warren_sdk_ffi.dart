/// In-process Warren engine for Flutter (Mode A).
///
/// This package implements `WarrenSdkPlatform` by running the Warren Rust engine
/// inside the app process through `flutter_rust_bridge`. It is the default
/// engine and needs no privilege. Consumers normally do not import this package
/// directly; the `warren_sdk` facade registers it via
/// `WarrenSdkFfi.ensureRegistered`.
library;

export 'src/warren_sdk_ffi.dart';
