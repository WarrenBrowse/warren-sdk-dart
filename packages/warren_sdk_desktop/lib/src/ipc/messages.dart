import 'package:meta/meta.dart';
import 'package:warren_sdk_platform_interface/warren_sdk_platform_interface.dart';

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

  /// The session is being wound down while the killswitch still holds: an
  /// explicit disconnect started tearing the datapath down (or, under a
  /// supervised daemon, the exit signalled a drain migration). Not final:
  /// [disconnected] follows once the network is restored.
  draining,

  /// Every attempt failed; the supervisor gave up.
  failed,

  /// The session was torn down and the network fully restored.
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
    this.daita = false,
    this.daitaMachine,
    this.requestIpv6 = true,
    this.lockdown = false,
  });

  /// The 12-word BIP39 mnemonic.
  final String mnemonic;

  /// The account API base.
  final String apiBase;

  /// The pinned server public key (hex).
  final String serverPubkeyPin;

  /// Optional pinned multihop directory root (hex).
  final String? multihopRootPin;

  /// Whether the daemon enables DAITA padding on its datapath.
  final bool daita;

  /// Optional named DAITA machine; ignored unless [daita] is true.
  final String? daitaMachine;

  /// Whether the daemon requests a dual-stack IPv6 allocation from the exit.
  final bool requestIpv6;

  /// Lockdown mode: user-intended stops (disconnect, daemon stop) keep the
  /// network blocked instead of restoring it.
  final bool lockdown;

  @override
  Map<String, Object?> toJson() => {
        'type': 'configure',
        'mnemonic': mnemonic,
        'apiBase': apiBase,
        'serverPubkeyPin': serverPubkeyPin,
        if (multihopRootPin != null) 'multihopRootPin': multihopRootPin,
        if (daita) 'daita': daita,
        if (daitaMachine != null) 'daitaMachine': daitaMachine,
        'requestIpv6': requestIpv6,
        if (lockdown) 'lockdown': lockdown,
      };

  static ConfigureRequest _fromJson(Map<String, Object?> json) =>
      ConfigureRequest(
        mnemonic: json['mnemonic']! as String,
        apiBase: json['apiBase']! as String,
        serverPubkeyPin: json['serverPubkeyPin']! as String,
        multihopRootPin: json['multihopRootPin'] as String?,
        daita: json['daita'] as bool? ?? false,
        daitaMachine: json['daitaMachine'] as String?,
        requestIpv6: json['requestIpv6'] as bool? ?? true,
        lockdown: json['lockdown'] as bool? ?? false,
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
///
/// [clockSkew] and [fatalCause] are present only when the engine typed the
/// failure; an older daemon omits them and the event reads as before.
final class ErrorEvent extends DaemonMessage {
  /// Creates an error event.
  const ErrorEvent({
    required this.kind,
    required this.message,
    this.clockSkew,
    this.fatalCause,
  });

  /// The failure category (`identity`, `api`, `discovery`, `tunnel`,
  /// `privilege`).
  final String kind;

  /// A redacted, human-readable description.
  final String message;

  /// Present when the server refused a signed call's timestamp: the device's
  /// clock is off, and the wallet may well be fine.
  final DaemonClockSkew? clockSkew;

  /// The engine's definitive verdict, present when no redial and no other exit
  /// helps.
  final WarrenFatalCause? fatalCause;

  @override
  Map<String, Object?> toJson() => {
        'type': 'error',
        'kind': kind,
        'message': message,
        if (clockSkew case final skew?) 'clockSkew': skew.toJson(),
        if (fatalCause case final cause?) 'fatalCause': cause.name,
      };

  static ErrorEvent _fromJson(Map<String, Object?> json) => ErrorEvent(
        kind: json['kind']! as String,
        message: json['message']! as String,
        clockSkew: switch (json['clockSkew']) {
          final Map<String, Object?> skew => DaemonClockSkew._fromJson(skew),
          _ => null,
        },
        fatalCause: switch (json['fatalCause']) {
          final String name => _fatalCauseNamed(name),
          _ => null,
        },
      );

  // A cause this client does not know yet still reads as definitive: taken
  // for a transient failure, a consumer would redial a fatal forever.
  static WarrenFatalCause _fatalCauseNamed(String name) =>
      WarrenFatalCause.values.asNameMap()[name] ??
      WarrenFatalCause.policyRefused;
}

/// The server's clock refusal as the daemon reports it.
@immutable
final class DaemonClockSkew {
  /// Creates the clock refusal.
  const DaemonClockSkew({this.offsetSecs});

  /// The server's clock minus this device's, in seconds (positive when the
  /// device is behind); `null` when the refusal carried no usable date.
  final int? offsetSecs;

  /// The wire form.
  Map<String, Object?> toJson() => {'offsetSecs': offsetSecs};

  static DaemonClockSkew _fromJson(Map<String, Object?> json) =>
      DaemonClockSkew(offsetSecs: json['offsetSecs'] as int?);
}
