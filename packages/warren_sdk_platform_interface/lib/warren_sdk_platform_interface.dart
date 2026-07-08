/// The federated-plugin contract for the Warren VPN Dart SDK.
///
/// This package defines the abstract `WarrenSdkPlatform` surface, the shared
/// immutable models, the `ConnectionState` event hierarchy and the sealed
/// `WarrenError` type. Platform implementations (the in-process FFI engine and
/// the privileged Mode B packages) depend on this contract; the app-facing
/// `warren_sdk` facade talks only to `WarrenSdkPlatform.instance`.
library;

export 'src/connection_state.dart';
export 'src/errors.dart';
export 'src/latest_broadcast.dart';
export 'src/models.dart';
export 'src/port_follow.dart';
export 'src/warren_sdk_platform.dart';
