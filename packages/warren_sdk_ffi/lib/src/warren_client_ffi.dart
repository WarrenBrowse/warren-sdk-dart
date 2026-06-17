import 'package:warren_sdk_platform_interface/warren_sdk_platform_interface.dart';

import 'engine_mapping.dart';
import 'rust/api/client.dart' as rust;
import 'rust/api/datapath.dart' as rust_session;
import 'rust/api/error.dart';

/// A live engine client handle backed by the in-process Rust client.
///
/// Wraps the opaque `WarrenClientFrb`. The bound address is read once at
/// creation so the synchronous [address] getter needs no bridge round-trip.
/// Every fallible call maps the typed engine error to a sealed [WarrenError].
class FfiClientHandle implements WarrenClientHandle {
  /// Wraps an opaque engine client and its already-resolved [address].
  FfiClientHandle(this._client, this.address);

  final rust.WarrenClientFrb _client;
  bool _disposed = false;

  @override
  final String address;

  @override
  Future<SubscriptionInfo> subscription() => _mapped(() async {
        final expiry = await _client.subscriptionExpiry();
        return SubscriptionInfo(expiresAtUnix: expiry.toInt());
      });

  @override
  Future<void> redeemVoucher(String secret) =>
      _mapped(() => _client.redeemVoucher(secret: secret));

  @override
  Future<List<ExitInfo>> listExits() => _mapped(() async {
        final dtos = await _client.listExits();
        return dtos.map(exitInfoFromDto).toList(growable: false);
      });

  @override
  Future<WarrenSessionHandle> connect(
    ExitInfo exit,
    ConnectMode mode,
    ConnectOptions options,
  ) =>
      _mapped(() async {
        if (mode == ConnectMode.systemVpn) {
          // The in-process engine serves proxy mode only; system-VPN needs a
          // privileged platform to own the TUN datapath. Registering it (for
          // example DesktopWarrenSdkPlatform.registerWith() on desktop) replaces
          // this handle, so reaching here means none is active.
          throw const WarrenUnsupportedError(
            code: 'mode/system-vpn-unavailable',
            message: 'System-VPN mode needs a privileged platform. On desktop, '
                'call DesktopWarrenSdkPlatform.registerWith() before creating '
                'the client; otherwise use ConnectMode.proxy.',
          );
        }
        final session = await _client.connectProxy(
          exitPubkeyHex: exit.id,
          socks5Listen: options.socks5Listen,
          httpListen: options.httpListen,
        );
        final socks5 = await session.socks5Endpoint();
        final http = await session.httpEndpoint();
        return FfiSessionHandle(
          session,
          ProxyEndpoints(socks5: socks5, http: http),
        );
      });

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _client.dispose();
  }

  Future<T> _mapped<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on WarrenFfiError catch (error) {
      throw mapEngineError(error);
    }
  }
}

/// A live proxy session backed by the in-process engine.
///
/// The connection-state stream is a broadcast view over the engine's transition
/// stream, so the latest state reaches every listener.
class FfiSessionHandle implements WarrenSessionHandle {
  /// Wraps an opaque engine session and its resolved local endpoints.
  FfiSessionHandle(this._session, this._endpoints);

  final rust_session.WarrenSessionFrb _session;
  final ProxyEndpoints _endpoints;

  late final Stream<ConnectionState> _states =
      _session.states().map(mapConnectionState).asBroadcastStream();

  @override
  ProxyEndpoints? get endpoints => _endpoints;

  @override
  Stream<ConnectionState> get states => _states;

  @override
  Future<void> disconnect() => _session.disconnect();
}
