import 'package:meta/meta.dart';

/// The live state of a connection, delivered as a stream by a session.
///
/// A sealed hierarchy so consumers can exhaustively `switch` over it. State is
/// pushed from a Rust event channel, never polled.
@immutable
sealed class ConnectionState {
  const ConnectionState();
}

/// A connection state that carries no payload, so all instances are equal.
///
/// Value equality by runtime type, so a non-const instance still compares equal
/// to the canonical const one.
@immutable
sealed class _SingletonState extends ConnectionState {
  const _SingletonState();

  @override
  bool operator ==(Object other) => other.runtimeType == runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// The engine is establishing the tunnel (directory fetch, handshake).
final class Connecting extends _SingletonState {
  /// Creates the connecting state.
  const Connecting();

  @override
  String toString() => 'Connecting';
}

/// The tunnel is up and carrying traffic.
final class Connected extends _SingletonState {
  /// Creates the connected state.
  const Connected();

  @override
  String toString() => 'Connected';
}

/// The tunnel dropped and the supervisor is rebuilding it with backoff.
final class Reconnecting extends _SingletonState {
  /// Creates the reconnecting state.
  const Reconnecting();

  @override
  String toString() => 'Reconnecting';
}

/// The current exit signalled a planned maintenance drain and the supervisor is
/// proactively migrating to another exit (ADR 36).
///
/// Distinct from [Reconnecting]: the tunnel did not fail, it is being switched
/// for maintenance, so an app can show a "switching server" hint rather than a
/// connection-lost warning. Followed by [Connected].
final class Draining extends _SingletonState {
  /// Creates the draining state.
  const Draining();

  @override
  String toString() => 'Draining';
}

/// The connection was torn down on purpose.
final class Disconnected extends _SingletonState {
  /// Creates the disconnected state.
  const Disconnected();

  @override
  String toString() => 'Disconnected';
}

/// Why a connection failed for good, when the failure is definitive.
///
/// Present on a [ConnectionFailed] exactly when no redial and no other exit
/// resolves it: the engine classified the refusal as tied to the account or an
/// opaque policy close. A [ConnectionFailed] whose [ConnectionFailed.cause] is
/// `null` is mere retry exhaustion, a transient failure that never resolved. The
/// engine owns this classification; the SDK maps it, it never re-decides.
enum WarrenFatalCause {
  /// No active subscription, or the identity is not in the exit allowlist. The
  /// user must provision or renew; retrying reproduces it.
  notAuthorized,

  /// The account already holds its maximum number of simultaneous devices.
  deviceLimit,

  /// The exit refused with an opaque policy-rejection code and no sealed cause
  /// arrived: definitive, but the specific reason is unknown to the client.
  policyRefused,

  /// The account is banned: revoked until the revocation lapses or is lifted.
  /// Renewing the subscription does not help.
  banned,
}

/// The connection failed and will not be retried automatically.
///
/// The [code] is stable; the [message] is redacted and carries no secret
/// material (no pubkey, address, IP, nonce or seed). A non-null [cause] means
/// the failure is definitive (no redial helps): a consumer surfaces the reason
/// and stops, rather than presenting an endless "reconnecting".
final class ConnectionFailed extends ConnectionState {
  /// Creates the failed state. [cause] is set only when the engine classified
  /// the failure as definitive; it is `null` for plain retry exhaustion.
  const ConnectionFailed({
    required this.code,
    required this.message,
    this.cause,
  });

  /// A stable, machine-readable failure code.
  final String code;

  /// A redacted human-readable message.
  final String message;

  /// The definitive fatal cause when no redial or other exit helps (expired
  /// subscription, device limit, opaque policy refusal), or `null` when the
  /// connection merely exhausted its retries.
  final WarrenFatalCause? cause;

  @override
  bool operator ==(Object other) =>
      other is ConnectionFailed &&
      other.code == code &&
      other.message == message &&
      other.cause == cause;

  @override
  int get hashCode => Object.hash(code, message, cause);

  @override
  String toString() => cause == null
      ? 'ConnectionFailed($code)'
      : 'ConnectionFailed($code, $cause)';
}
