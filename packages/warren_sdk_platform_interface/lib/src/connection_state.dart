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

/// The connection was torn down on purpose.
final class Disconnected extends _SingletonState {
  /// Creates the disconnected state.
  const Disconnected();

  @override
  String toString() => 'Disconnected';
}

/// The connection failed and will not be retried automatically.
///
/// The [code] is stable; the [message] is redacted and carries no secret
/// material (no pubkey, address, IP, nonce or seed).
final class ConnectionFailed extends ConnectionState {
  /// Creates the failed state.
  const ConnectionFailed({required this.code, required this.message});

  /// A stable, machine-readable failure code.
  final String code;

  /// A redacted human-readable message.
  final String message;

  @override
  bool operator ==(Object other) =>
      other is ConnectionFailed &&
      other.code == code &&
      other.message == message;

  @override
  int get hashCode => Object.hash(code, message);

  @override
  String toString() => 'ConnectionFailed($code)';
}
