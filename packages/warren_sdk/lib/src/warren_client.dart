import 'package:warren_sdk_ffi/warren_sdk_ffi.dart';
import 'package:warren_sdk_platform_interface/warren_sdk_platform_interface.dart';

import 'warren_session.dart';

/// The entry point of the Warren VPN SDK.
///
/// Create one with [WarrenClient.create], then query the account, list exits and
/// open connections. The client owns engine resources; call [dispose] when done.
///
/// The SDK works out of the box in proxy mode (no privilege) on every platform.
/// System-VPN mode is selected per connection and is served by the platform's
/// privileged implementation where available.
///
/// {@template warren_framework_agnostic}
/// This API is framework-agnostic: it exposes only `Future`s, broadcast
/// `Stream`s, immutable models and sealed errors, so it fits any app
/// architecture. For Riverpod integration, add the optional
/// `warren_sdk_riverpod` package.
/// {@endtemplate}
class WarrenClient {
  WarrenClient._(this._handle);

  final WarrenClientHandle _handle;

  /// The SS58 `wb...` address of the bound identity.
  String get address => _handle.address;

  /// Creates a client bound to an identity and an account API.
  ///
  /// The [mnemonic] is consumed once and zeroized in the Rust engine; it is
  /// never retained in Dart. Read it from the platform secure store, pass it
  /// here, and drop your own reference.
  ///
  /// Throws a [WarrenIdentityError] if the mnemonic is invalid, or a
  /// [WarrenApiError] if the API base is unreachable during setup.
  static Future<WarrenClient> create({
    required String mnemonic,
    required Uri apiBase,
    required String serverPubkeyPin,
    String? multihopRootPin,
    bool daita = false,
    String? daitaMachine,
    bool requestIpv6 = true,
  }) async {
    // Ensure the default in-process engine is registered. A privileged Mode B
    // implementation may have already overridden the instance; if so, this is a
    // no-op and that implementation is kept.
    WarrenSdkFfi.ensureRegistered();
    final handle = await WarrenSdkPlatform.instance.createClient(
      WarrenClientConfig(
        mnemonic: mnemonic,
        apiBase: apiBase,
        serverPubkeyPin: serverPubkeyPin,
        multihopRootPin: multihopRootPin,
        daita: daita,
        daitaMachine: daitaMachine,
        requestIpv6: requestIpv6,
      ),
    );
    return WarrenClient._(handle);
  }

  /// Returns the current subscription snapshot.
  ///
  /// Throws a [WarrenApiError] on a network or server failure.
  Future<SubscriptionInfo> subscription() => _handle.subscription();

  /// Redeems a voucher [secret], crediting the account.
  ///
  /// Throws a [WarrenApiError] if the voucher is invalid or already used.
  Future<void> redeemVoucher(String secret) => _handle.redeemVoucher(secret);

  /// Fetches and verifies the signed relay list and returns the available
  /// exits.
  ///
  /// Throws a [WarrenDiscoveryError] if verification fails (bad signature,
  /// rollback or expiry).
  Future<List<ExitInfo>> listExits() => _handle.listExits();

  /// Selects the first exit from [exits] matching [query].
  ///
  /// This is a convenience filter (country, city, capability flags). The engine
  /// still performs weighted, wire-correct selection internally when building
  /// the circuit at [connect]. Returns `null` if nothing matches.
  static ExitInfo? selectExit(List<ExitInfo> exits, ExitQuery query) {
    for (final exit in exits) {
      if (query.country != null && exit.country != query.country) continue;
      if (query.city != null && exit.city != query.city) continue;
      if (query.requireIpv6 == true && !exit.supportsIpv6) continue;
      if (query.requirePortForwarding == true && !exit.supportsPortForwarding) {
        continue;
      }
      return exit;
    }
    return null;
  }

  /// Opens a connection to [exit].
  ///
  /// In [ConnectMode.proxy] (default) the engine runs in-process and the
  /// returned session exposes local proxy endpoints. In
  /// [ConnectMode.systemVpn] the privileged datapath captures all OS traffic.
  ///
  /// Throws a [WarrenTunnelError] on handshake or transport failure, or a
  /// [WarrenPrivilegeError] if system-VPN mode is requested but the privileged
  /// component is unavailable.
  Future<WarrenSession> connect(
    ExitInfo exit, {
    ConnectMode mode = ConnectMode.proxy,
    ConnectOptions options = const ConnectOptions(),
  }) async {
    final session = await _handle.connect(exit, mode, options);
    return WarrenSession(session);
  }

  /// Releases the client and any engine resources it holds. After this, the
  /// client must not be used again.
  Future<void> dispose() => _handle.dispose();
}
