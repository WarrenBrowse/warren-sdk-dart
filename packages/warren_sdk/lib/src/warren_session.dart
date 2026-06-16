import 'package:warren_sdk_platform_interface/warren_sdk_platform_interface.dart';

/// A live Warren connection.
///
/// Obtained from `WarrenClient.connect`. Exposes the local proxy endpoints (in
/// proxy mode), a reactive [states] stream, and a [disconnect] method. The
/// underlying engine session is never exposed.
class WarrenSession {
  /// Wraps a platform session handle. Internal to the facade.
  WarrenSession(this._handle);

  final WarrenSessionHandle _handle;

  /// The local proxy endpoints in proxy mode, or `null` in system-VPN mode
  /// (where traffic is captured by the OS through the privileged datapath).
  ProxyEndpoints? get endpoints => _handle.endpoints;

  /// The live connection state. Broadcast; the latest state is delivered on
  /// listen, and updates are pushed from the engine, never polled.
  Stream<ConnectionState> get states => _handle.states;

  /// Tears the connection down and releases its datapath resources.
  Future<void> disconnect() => _handle.disconnect();
}
