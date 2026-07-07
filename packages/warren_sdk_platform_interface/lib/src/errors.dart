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
  const WarrenApiError({required super.code, required super.message});
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

/// Builds the [WarrenError] subtype for a category [kind], with a caller-chosen
/// [code] and redacted [message].
///
/// Every engine boundary (in-process bridge, desktop daemon, mobile extension)
/// reports the same categories; this picks the subtype so each boundary does not
/// reimplement the mapping. An unknown kind falls back to [WarrenTunnelError].
WarrenError warrenErrorOfKind(
  String kind, {
  required String code,
  required String message,
}) =>
    switch (kind) {
      'identity' => WarrenIdentityError(code: code, message: message),
      'api' => WarrenApiError(code: code, message: message),
      'discovery' => WarrenDiscoveryError(code: code, message: message),
      'tunnel' => WarrenTunnelError(code: code, message: message),
      'privilege' => WarrenPrivilegeError(code: code, message: message),
      'unsupported' => WarrenUnsupportedError(code: code, message: message),
      _ => WarrenTunnelError(code: code, message: message),
    };
