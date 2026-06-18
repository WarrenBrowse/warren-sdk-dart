import 'package:meta/meta.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'connection_state.dart';
import 'errors.dart';
import 'models.dart';

/// Immutable configuration for creating an engine client.
///
/// The [mnemonic] is consumed once and zeroized in Rust; it is never retained in
/// Dart. Obtain it from the platform secure store, pass it here, and drop your
/// own reference.
@immutable
class WarrenClientConfig {
  /// Creates a client configuration.
  const WarrenClientConfig({
    required this.mnemonic,
    required this.apiBase,
    required this.serverPubkeyPin,
    this.multihopRootPin,
    this.daita = false,
    this.daitaMachine,
    this.requestIpv6 = true,
    this.stateDir,
  });

  /// The 12-word BIP39 mnemonic. Consumed once, zeroized in Rust.
  final String mnemonic;

  /// The account API base, for example `https://api.warrenbrowse.com`.
  final Uri apiBase;

  /// The pinned server public key (hex) used to verify the signed relay list.
  final String serverPubkeyPin;

  /// Optional pinned multihop directory root, for stricter PKI verification.
  final String? multihopRootPin;

  /// Whether to enable DAITA (Defense Against AI Traffic Analysis) padding.
  ///
  /// DAITA is configured when the client is built, so it is set here rather than
  /// per connection.
  final bool daita;

  /// An optional named DAITA machine from the curated pool; the engine picks a
  /// default when null. Ignored unless [daita] is true. The name is a public
  /// protocol label, not identity material.
  final String? daitaMachine;

  /// Whether to request a dual-stack IPv6 allocation from exits that serve it.
  ///
  /// On by default and always safe: an exit that serves no IPv6 simply grants
  /// none and the tunnel stays v4-only. When granted, IPv6 egress is routed
  /// through the tunnel.
  final bool requestIpv6;

  /// Optional directory for on-disk persistence of the anti-rollback floors and
  /// the TOFU server pin. Without it those live in memory only, so rollback
  /// protection does not survive a restart. Pass a private, app-owned path.
  final String? stateDir;
}

/// The federated-plugin contract every platform implementation satisfies.
///
/// The facade package (`warren_sdk`) talks only to [instance]. The default
/// in-process implementation (`warren_sdk_ffi`, Mode A) registers itself;
/// privileged Mode B implementations override it per platform.
abstract class WarrenSdkPlatform extends PlatformInterface {
  /// Constructs a platform implementation. Subclasses must call this and pass
  /// the verification token through `super`.
  WarrenSdkPlatform() : super(token: _token);

  static final Object _token = Object();

  static WarrenSdkPlatform _instance = _UnsetWarrenSdkPlatform();

  /// The active platform implementation.
  static WarrenSdkPlatform get instance => _instance;

  /// Whether a real implementation has registered (versus the unset sentinel).
  static bool get hasInstance => _instance is! _UnsetWarrenSdkPlatform;

  /// Registers the active platform implementation. Implementations call this
  /// from their `registerWith`; the token guards against an unverified subclass.
  static set instance(WarrenSdkPlatform value) {
    PlatformInterface.verify(value, _token);
    _instance = value;
  }

  // --- Stateless identity helpers (no client needed) ---

  /// Generates a fresh 12-word BIP39 mnemonic.
  Future<String> generateMnemonic();

  /// Derives the SS58 `wb...` address from a mnemonic.
  Future<String> addressFromMnemonic(String mnemonic);

  /// Encodes a 32-byte public key (hex) to its SS58 `wb...` address.
  Future<String> ss58Encode(String publicKeyHex);

  /// Decodes an SS58 `wb...` address back to its public key hex.
  Future<String> ss58Decode(String address);

  // --- Client lifecycle ---

  /// Creates an engine client bound to an identity and an account API.
  Future<WarrenClientHandle> createClient(WarrenClientConfig config);
}

/// An engine client handle. Wraps a live Rust client; the facade never exposes
/// it directly. Always [dispose] it when done.
abstract interface class WarrenClientHandle {
  /// The SS58 `wb...` address of the bound identity.
  String get address;

  /// Returns the current subscription snapshot.
  Future<SubscriptionInfo> subscription();

  /// Redeems a voucher secret, crediting the account.
  Future<void> redeemVoucher(String secret);

  /// Asks the account server what it observes for this connection: whether
  /// traffic egresses from a registered Warren exit, and which one.
  Future<TunnelCheck> checkTunnel();

  /// Fetches and verifies the signed relay list and returns the exits.
  Future<List<ExitInfo>> listExits();

  /// Opens a connection to [exit] using [mode] and [options].
  Future<WarrenSessionHandle> connect(
    ExitInfo exit,
    ConnectMode mode,
    ConnectOptions options,
  );

  /// Releases the client and any engine resources it holds.
  Future<void> dispose();
}

/// A live connection handle. Wraps a Rust session; the facade wraps it again as
/// a `WarrenSession`.
abstract interface class WarrenSessionHandle {
  /// The local proxy endpoints, in proxy mode; `null` in system-VPN mode.
  ProxyEndpoints? get endpoints;

  /// The live connection-state stream (broadcast, latest-state on listen).
  Stream<ConnectionState> get states;

  /// Tears the connection down.
  Future<void> disconnect();
}

/// The default implementation, active until a real one registers. Every call
/// throws [WarrenUnsupportedError] with a clear remedy.
final class _UnsetWarrenSdkPlatform extends WarrenSdkPlatform {
  static const WarrenError _error = WarrenUnsupportedError(
    code: 'platform/unregistered',
    message: 'No Warren platform implementation is registered. Depend on '
        'warren_sdk (which bundles the in-process engine) or a Mode B platform '
        'package.',
  );

  @override
  Future<String> generateMnemonic() => throw _error;

  @override
  Future<String> addressFromMnemonic(String mnemonic) => throw _error;

  @override
  Future<String> ss58Encode(String publicKeyHex) => throw _error;

  @override
  Future<String> ss58Decode(String address) => throw _error;

  @override
  Future<WarrenClientHandle> createClient(WarrenClientConfig config) =>
      throw _error;
}
