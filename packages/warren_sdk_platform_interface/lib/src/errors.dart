import 'package:meta/meta.dart';

/// The sealed error type for every failure surfaced by the SDK.
///
/// Rust engine errors are mapped to one of these at the bridge. Each carries a
/// stable [code] and a [message] that is already redacted: it never contains a
/// pubkey, address, IP, nonce or seed. Consumers can exhaustively `switch` over
/// the subtypes.
@immutable
sealed class WarrenError implements Exception {
  /// Creates a Warren error.
  const WarrenError({required this.code, required this.message});

  /// A stable, machine-readable code, suitable for branching and analytics.
  final String code;

  /// A redacted, human-readable description. Safe to log and display.
  final String message;

  @override
  String toString() => '$runtimeType($code): $message';
}

/// The mnemonic, address or signing input was malformed or invalid.
final class WarrenIdentityError extends WarrenError {
  /// Creates an identity error.
  const WarrenIdentityError({required super.code, required super.message});
}

/// An account API call failed (network, auth, server, or fallback exhaustion).
final class WarrenApiError extends WarrenError {
  /// Creates an API error.
  const WarrenApiError({
    required super.code,
    required super.message,
    this.httpStatus,
  });

  /// The HTTP status code, when the failure was an HTTP response.
  final int? httpStatus;
}

/// Relay-list verification or exit selection failed (bad signature, rollback,
/// expiry, or no exit matched the query).
final class WarrenDiscoveryError extends WarrenError {
  /// Creates a discovery error.
  const WarrenDiscoveryError({required super.code, required super.message});
}

/// The tunnel or datapath failed (handshake, transport, multihop, TUN setup).
final class WarrenTunnelError extends WarrenError {
  /// Creates a tunnel error.
  const WarrenTunnelError({required super.code, required super.message});
}

/// A privileged-mode failure: the daemon or network extension is missing,
/// unreachable, or privilege was denied.
final class WarrenPrivilegeError extends WarrenError {
  /// Creates a privilege error.
  const WarrenPrivilegeError({required super.code, required super.message});
}

/// A requested capability is not implemented on the current platform yet.
final class WarrenUnsupportedError extends WarrenError {
  /// Creates an unsupported-capability error.
  const WarrenUnsupportedError({required super.code, required super.message});
}
