import 'package:meta/meta.dart';

import 'port_follow.dart' show BanReason;

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
base class WarrenApiError extends WarrenError {
  /// Creates an API error.
  const WarrenApiError({required super.code, required super.message});
}

/// The server refused the call because the account is banned.
///
/// Every call that credits time answers a banned wallet this way before
/// consuming anything: a refused voucher redemption leaves the voucher
/// unredeemed, so keep it and redeem it once the ban ends. It is a
/// [WarrenApiError], so an existing `on WarrenApiError` handler still catches it.
final class WarrenAccountBannedError extends WarrenApiError {
  /// Creates the ban refusal.
  const WarrenAccountBannedError({
    required super.message,
    required this.reason,
    this.lapsesAtUnixSecs,
  }) : super(code: 'api/banned');

  /// Why the account is banned.
  final BanReason reason;

  /// When the ban lapses on its own, Unix seconds; `null` for a ban that does
  /// not lapse, and when the refusing endpoint does not say.
  final int? lapsesAtUnixSecs;
}

/// The server refused a signed call's timestamp: this device's clock is off,
/// and the wallet may well be fine.
///
/// The engine already corrects its stamps from the server's `Date`; this is
/// raised when that correction could not bring them inside the server's
/// window. What the user can do is set the device's date and time. It is a
/// [WarrenApiError], so an existing `on WarrenApiError` handler still catches
/// it.
final class WarrenClockSkewError extends WarrenApiError {
  /// Creates the clock refusal.
  const WarrenClockSkewError({this.offsetSecs})
      : super(
          code: 'api/clock-skew',
          message: "this device's clock is off, so the server refused the "
              'request; set the date and time automatically, then retry',
        );

  /// The server's clock minus this device's, in seconds (positive when the
  /// device is behind); `null` when the refusal carried no usable date.
  final int? offsetSecs;
}

/// This install's device was revoked from another device of the account
/// (warren-core doc 115).
///
/// The app disconnects, forgets the device identity, and shows "This device
/// was disconnected from another device of your account. Sign in with your
/// recovery phrase to use it again." It is a [WarrenApiError], so an existing
/// `on WarrenApiError` handler still catches it.
final class WarrenDeviceRevokedError extends WarrenApiError {
  /// Creates the revocation refusal.
  const WarrenDeviceRevokedError()
      : super(
          code: 'api/device-revoked',
          message: 'this device was disconnected from another device of the '
              'account; sign in again with the recovery phrase',
        );
}

/// The account already holds as many devices as it may, so this install is
/// not registered and is issued nothing until another device is revoked.
///
/// The app opens the account's device list. It is a [WarrenApiError], so an
/// existing `on WarrenApiError` handler still catches it.
final class WarrenDeviceLimitReachedError extends WarrenApiError {
  /// Creates the device cap refusal.
  const WarrenDeviceLimitReachedError()
      : super(
          code: 'api/device-limit-reached',
          message: 'the account already has as many devices as it may; '
              'disconnect one of them to use this one',
        );
}

/// A device identifier passed to a device call is not one the registry
/// issues (16 bytes of base64url without padding). It is a [WarrenApiError],
/// so an existing `on WarrenApiError` handler still catches it.
final class WarrenInvalidDeviceIdError extends WarrenApiError {
  /// Creates the malformed identifier refusal.
  const WarrenInvalidDeviceIdError()
      : super(code: 'api/invalid-device-id', message: 'invalid device id');
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
