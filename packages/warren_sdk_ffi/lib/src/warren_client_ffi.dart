import 'package:warren_sdk_platform_interface/warren_sdk_platform_interface.dart';

import 'device_revocation.dart';
import 'engine_mapping.dart';
import 'rust/api/client.dart' as rust;
import 'rust/api/datapath.dart' as rust_session;
import 'rust/api/error.dart';

/// A live engine client handle backed by the in-process Rust client.
///
/// Wraps the opaque `WarrenClientFrb`. The bound address and device id are
/// read once at creation so their synchronous getters need no bridge
/// round-trip. Every fallible call maps the typed engine error to a sealed
/// [WarrenError].
class FfiClientHandle implements WarrenClientHandle {
  /// Wraps an opaque engine client, its already-resolved [address] and, when
  /// it registers this install as a device, its [deviceId]. A registered
  /// client asks the engine whether the device was revoked every
  /// [revocationCheck] while anyone watches.
  FfiClientHandle(
    this._client,
    this.address, {
    this.deviceId,
    Duration revocationCheck = defaultRevocationCheck,
  }) : _revocation = deviceId == null
            ? null
            : DeviceRevocationWatch(
                _client.deviceRevoked,
                every: revocationCheck,
              );

  /// How often a watched client asks the engine about a revocation. The
  /// engine learns one from its credential refresh, every 10 minutes, so a
  /// check a fraction of that adds little to how long a revoked app runs.
  static const Duration defaultRevocationCheck = Duration(seconds: 30);

  final rust.WarrenClientFrb _client;
  final DeviceRevocationWatch? _revocation;
  bool _disposed = false;

  @override
  final String address;

  @override
  final String? deviceId;

  @override
  Future<String?> deviceName() => _mapped(_client.deviceName);

  @override
  Future<WarrenDeviceList> listDevices() =>
      _mapped(() async => deviceListFromDto(await _client.listDevices()));

  @override
  Future<void> renameDevice(String deviceId, String name) =>
      _mapped(() => _client.renameDevice(deviceId: deviceId, name: name));

  @override
  Future<void> revokeDevice(String deviceId) =>
      _mapped(() => _client.revokeDevice(deviceId: deviceId));

  @override
  Future<void> forgetDevice() => _mapped(_client.forgetDevice);

  @override
  Future<bool> deviceLimitReached() => _mapped(_client.deviceLimitReached);

  @override
  Stream<bool> get deviceRevoked =>
      _revocation?.stream ?? Stream<bool>.value(false);

  @override
  Future<SubscriptionInfo> subscription() => _mapped(() async {
        final expiry = await _client.subscriptionExpiry();
        return SubscriptionInfo(expiresAtUnix: expiry.toInt());
      });

  @override
  Future<void> redeemVoucher(String secret) =>
      _mapped(() => _client.redeemVoucher(secret: secret));

  @override
  Future<void> deleteAccount() => _mapped(_client.deleteAccount);

  @override
  Future<TunnelCheck> checkTunnel() =>
      _mapped(() async => tunnelCheckFromDto(await _client.check()));

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
          failoverExitPubkeysHex:
              options.failoverExits.map((e) => e.id).toList(growable: false),
          socks5Listen: options.socks5Listen,
          httpListen: options.httpListen,
          dnsServer: options.dnsServer,
        );
        final socks5 = await session.socks5Endpoint();
        final http = await session.httpEndpoint();
        final credentials = ProxyCredentials(
          username: await session.proxyUsername(),
          password: await session.proxyPassword(),
        );
        return FfiSessionHandle(
          session,
          ProxyEndpoints(socks5: socks5, http: http, credentials: credentials),
          deviceRevoked: deviceRevoked,
        );
      });

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _revocation?.close();
    _client.dispose();
  }

  Future<T> _mapped<T>(Future<T> Function() body) async {
    // A dropped Rust opaque would otherwise surface a raw FRB disposal exception
    // instead of a clean, secret-free signal.
    if (_disposed) {
      throw StateError('FfiClientHandle used after dispose()');
    }
    try {
      return await body();
    } on WarrenFfiError catch (error) {
      throw mapEngineError(error);
    }
  }
}

/// A live proxy session backed by the in-process engine.
///
/// The connection-state stream is a replaying broadcast view over the engine's
/// transition stream, so every listener, including one that attaches after the
/// tunnel is already up, observes the current state. A revocation of this
/// install's device ends it on [WarrenFatalCause.deviceRevoked].
class FfiSessionHandle implements WarrenSessionHandle {
  /// Wraps an opaque engine session and its resolved local endpoints.
  /// [deviceRevoked] is the owning client's revocation flag.
  FfiSessionHandle(
    rust_session.WarrenSessionFrb session,
    this._endpoints, {
    Stream<bool> deviceRevoked = const Stream<bool>.empty(),
  })  : _session = session,
        _states = LatestBroadcast(
          withDeviceRevocation(_mapStates(session), deviceRevoked),
        ),
        _migrationEvents = LatestBroadcast(
          session.migrationEvents().map(mapMigrationEvent),
        );

  /// Maps the engine state stream, enriching the terminal `Failed` with the
  /// engine's fatal cause. The supervisor latches the cause before publishing
  /// `Failed`, so reading it here is race-free; a present cause tells a consumer
  /// no redial helps (expired subscription, device limit) and to stop.
  static Stream<ConnectionState> _mapStates(
    rust_session.WarrenSessionFrb session,
  ) =>
      session.states().asyncMap((dto) async {
        if (dto == rust_session.ConnectionStateDto.failed) {
          return connectionFailed(mapFatalCause(await session.fatalCause()));
        }
        return mapConnectionState(dto);
      });

  final rust_session.WarrenSessionFrb _session;
  final ProxyEndpoints _endpoints;
  final LatestBroadcast<ConnectionState> _states;
  final LatestBroadcast<MigrationEvent> _migrationEvents;

  @override
  ProxyEndpoints? get endpoints => _endpoints;

  @override
  Stream<ConnectionState> get states => _states.stream;

  @override
  Stream<MigrationEvent> get migrationEvents => _migrationEvents.stream;

  @override
  Future<WarrenForwardedPort> forwardPort(
    ForwardProtocol proto,
    int internalPort,
    String localTarget, {
    PortFollowPolicy policy = PortFollowPolicy.followBestEffort,
    int? pinnedExternalPort,
  }) async {
    try {
      final port = await _session.forwardPortWithPolicy(
        proto: proto == ForwardProtocol.udp
            ? rust_session.MapProtoDto.udp
            : rust_session.MapProtoDto.tcp,
        internalPort: internalPort,
        localTarget: localTarget,
        policy: portFollowPolicyToDto(policy),
        pinnedExternalPort: pinnedExternalPort,
      );
      return FfiForwardedPort(port, await port.internalPort());
    } on WarrenFfiError catch (error) {
      throw mapEngineError(error);
    }
  }

  @override
  Future<void> disconnect() async {
    await _states.close();
    await _migrationEvents.close();
    try {
      await _session.disconnect();
    } on WarrenFfiError catch (error) {
      throw mapEngineError(error);
    }
  }
}

/// A self-healing forwarded port backed by the in-process engine.
class FfiForwardedPort implements WarrenForwardedPort {
  /// Wraps an opaque engine forwarded port and its resolved internal port.
  FfiForwardedPort(
    rust_session.WarrenForwardedPortFrb port,
    this.internalPort,
  )   : _port = port,
        _externalPorts = LatestBroadcast(port.externalPorts()),
        _outcomes = LatestBroadcast(
          port.outcomes().map(mapPortFollowOutcome),
        );

  final rust_session.WarrenForwardedPortFrb _port;
  final LatestBroadcast<int?> _externalPorts;
  final LatestBroadcast<PortFollowOutcome> _outcomes;

  @override
  final int internalPort;

  @override
  Future<int?> externalPort() => _port.externalPort();

  @override
  Stream<int?> get externalPorts => _externalPorts.stream;

  @override
  Stream<PortFollowOutcome> get outcomes => _outcomes.stream;

  @override
  Future<void> dispose() async {
    await _externalPorts.close();
    await _outcomes.close();
    try {
      await _port.shutdown();
    } on WarrenFfiError catch (error) {
      throw mapEngineError(error);
    }
  }
}
