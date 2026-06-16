import 'package:meta/meta.dart';

/// The live state of a connection, delivered as a stream by a session.
///
/// A sealed hierarchy so consumers can exhaustively `switch` over it. State is
/// pushed from a Rust event channel, never polled.
@immutable
sealed class ConnectionState {
  const ConnectionState();
}

/// The engine is establishing the tunnel (directory fetch, handshake).
final class Connecting extends ConnectionState {
  /// Creates the connecting state.
  const Connecting();

  @override
  String toString() => 'Connecting';
}

/// The tunnel is up and carrying traffic.
final class Connected extends ConnectionState {
  /// Creates the connected state.
  const Connected({this.sinceUnix});

  /// When the tunnel came up, as a Unix timestamp in seconds, if known.
  final int? sinceUnix;

  @override
  bool operator ==(Object other) =>
      other is Connected && other.sinceUnix == sinceUnix;

  @override
  int get hashCode => sinceUnix.hashCode;

  @override
  String toString() => 'Connected';
}

/// The tunnel dropped and the supervisor is rebuilding it with backoff.
final class Reconnecting extends ConnectionState {
  /// Creates the reconnecting state.
  const Reconnecting({this.attempt = 1});

  /// The 1-based reconnect attempt number.
  final int attempt;

  @override
  bool operator ==(Object other) =>
      other is Reconnecting && other.attempt == attempt;

  @override
  int get hashCode => attempt.hashCode;

  @override
  String toString() => 'Reconnecting(attempt: $attempt)';
}

/// The connection was torn down on purpose.
final class Disconnected extends ConnectionState {
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
