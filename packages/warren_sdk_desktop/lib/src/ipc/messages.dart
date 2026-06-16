import 'package:meta/meta.dart';

/// The connection state the daemon reports for a system-VPN session.
///
/// Mirrors the in-process engine states plus [disconnected], which the daemon
/// emits when a session is torn down.
enum DaemonConnectionState {
  /// The initial connect attempt is in flight.
  connecting,

  /// The tunnel is up and carrying traffic.
  connected,

  /// A retry is in flight after backoff.
  reconnecting,

  /// Every attempt failed; the supervisor gave up.
  failed,

  /// The session was torn down.
  disconnected,
}

/// A message on the daemon IPC channel, in either direction.
///
/// Requests flow app to daemon; events flow daemon to app. The wire form is a
/// JSON object with a `type` discriminator, framed by `FrameCodec`.
@immutable
sealed class DaemonMessage {
  const DaemonMessage();

  /// The wire representation, including the `type` discriminator.
  Map<String, Object?> toJson();

  /// Parses a message from its decoded JSON object.
  ///
  /// Throws a [FormatException] on an unknown or malformed message.
  static DaemonMessage fromJson(Map<String, Object?> json) {
    final type = json['type'];
    return switch (type) {
      'configure' => ConfigureRequest._fromJson(json),
      'connect' => ConnectRequest._fromJson(json),
      'disconnect' => const DisconnectRequest(),
      'state' => StateEvent._fromJson(json),
      'error' => ErrorEvent._fromJson(json),
      _ => throw FormatException('unknown daemon message type: $type'),
    };
  }
}

/// Binds an identity and account API in the daemon (app to daemon).
///
/// The mnemonic crosses a local, root-owned socket; the daemon zeroizes the
/// derived key and never logs it. It is never echoed in [toString].
final class ConfigureRequest extends DaemonMessage {
  /// Creates a configure request.
  const ConfigureRequest({
    required this.mnemonic,
    required this.apiBase,
    required this.serverPubkeyPin,
    this.multihopRootPin,
  });

  /// The 12-word BIP39 mnemonic.
  final String mnemonic;

  /// The account API base.
  final String apiBase;

  /// The pinned server public key (hex).
  final String serverPubkeyPin;

  /// Optional pinned multihop directory root (hex).
  final String? multihopRootPin;

  @override
  Map<String, Object?> toJson() => {
        'type': 'configure',
        'mnemonic': mnemonic,
        'apiBase': apiBase,
        'serverPubkeyPin': serverPubkeyPin,
        if (multihopRootPin != null) 'multihopRootPin': multihopRootPin,
      };

  static ConfigureRequest _fromJson(Map<String, Object?> json) =>
      ConfigureRequest(
        mnemonic: json['mnemonic']! as String,
        apiBase: json['apiBase']! as String,
        serverPubkeyPin: json['serverPubkeyPin']! as String,
        multihopRootPin: json['multihopRootPin'] as String?,
      );

  // Never render the mnemonic.
  @override
  String toString() => 'ConfigureRequest(apiBase: $apiBase)';
}

/// Opens a system-VPN session to an exit (app to daemon).
final class ConnectRequest extends DaemonMessage {
  /// Creates a connect request.
  const ConnectRequest({
    required this.exitPubkeyHex,
    this.dnsOverTunnel = true,
  });

  /// The exit's Ed25519 identity (hex), as listed by `listExits`.
  final String exitPubkeyHex;

  /// Whether DNS is resolved over the tunnel gateway.
  final bool dnsOverTunnel;

  @override
  Map<String, Object?> toJson() => {
        'type': 'connect',
        'exitPubkeyHex': exitPubkeyHex,
        'dnsOverTunnel': dnsOverTunnel,
      };

  static ConnectRequest _fromJson(Map<String, Object?> json) => ConnectRequest(
        exitPubkeyHex: json['exitPubkeyHex']! as String,
        dnsOverTunnel: json['dnsOverTunnel'] as bool? ?? true,
      );
}

/// Tears the current session down (app to daemon).
final class DisconnectRequest extends DaemonMessage {
  /// Creates a disconnect request.
  const DisconnectRequest();

  @override
  Map<String, Object?> toJson() => const {'type': 'disconnect'};
}

/// A connection-state transition (daemon to app).
final class StateEvent extends DaemonMessage {
  /// Creates a state event.
  const StateEvent(this.state);

  /// The new state.
  final DaemonConnectionState state;

  @override
  Map<String, Object?> toJson() => {'type': 'state', 'state': state.name};

  static StateEvent _fromJson(Map<String, Object?> json) {
    final name = json['state']! as String;
    final state = DaemonConnectionState.values.firstWhere(
      (s) => s.name == name,
      orElse: () => throw FormatException('unknown state: $name'),
    );
    return StateEvent(state);
  }
}

/// A redacted failure (daemon to app).
final class ErrorEvent extends DaemonMessage {
  /// Creates an error event.
  const ErrorEvent({required this.kind, required this.message});

  /// The failure category (`identity`, `api`, `discovery`, `tunnel`,
  /// `privilege`).
  final String kind;

  /// A redacted, human-readable description.
  final String message;

  @override
  Map<String, Object?> toJson() =>
      {'type': 'error', 'kind': kind, 'message': message};

  static ErrorEvent _fromJson(Map<String, Object?> json) => ErrorEvent(
        kind: json['kind']! as String,
        message: json['message']! as String,
      );
}
