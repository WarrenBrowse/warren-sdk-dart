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

  /// Maintenance-migration events. Broadcast; the latest event is delivered on
  /// listen (nothing before the first drain advisory).
  ///
  /// Richer than the bare [Draining] state: each [MigrationEvent] carries the
  /// drain deadline, the operator reason and the outcome, including
  /// [MigrationOutcome.cancelledPortConflict] when a migration was called off
  /// so a pinned forwarded port could be kept.
  Stream<MigrationEvent> get migrationEvents => _handle.migrationEvents;

  /// Forwards an inbound tunnel-side [internalPort] to a local [localTarget]
  /// (`ip:port`) via NAT-PMP, re-mapped automatically across reconnects. The
  /// returned [WarrenForwardedPort] keeps it alive until disposed.
  ///
  /// [policy] controls how the external port follows the client across
  /// reconnects and maintenance migrations (doc 59): best-effort follow (the
  /// default), pin-or-stay via [PortFollowPolicy.keepPortOrStay] with an
  /// optional [pinnedExternalPort] (`null` pins the first granted port), or no
  /// follow at all. Observe per-rebuild results on
  /// [WarrenForwardedPort.outcomes].
  ///
  /// Proxy mode only, and only against an exit that runs a NAT-PMP gateway;
  /// throws [WarrenUnsupportedError] in system-VPN mode and [WarrenTunnelError]
  /// if the local target is malformed or the session has ended.
  Future<WarrenForwardedPort> forwardPort(
    ForwardProtocol proto,
    int internalPort,
    String localTarget, {
    PortFollowPolicy policy = PortFollowPolicy.followBestEffort,
    int? pinnedExternalPort,
  }) =>
      _handle.forwardPort(
        proto,
        internalPort,
        localTarget,
        policy: policy,
        pinnedExternalPort: pinnedExternalPort,
      );

  /// Tears the connection down and releases its datapath resources.
  Future<void> disconnect() => _handle.disconnect();
}
