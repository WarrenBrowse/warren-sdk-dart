import 'package:flutter/services.dart';
import 'package:warren_sdk_platform_interface/warren_sdk_platform_interface.dart';

/// The method channel the network extension listens on.
const MethodChannel kVpnMethodChannel = MethodChannel('com.warren.sdk/vpn');

/// The event channel the network extension streams state on.
const EventChannel kVpnEventChannel = EventChannel('com.warren.sdk/vpn/state');

/// Drives the mobile network extension that hosts the Warren engine.
///
/// On mobile the privileged datapath runs inside the OS network extension
/// (Android `VpnService`, iOS/macOS `NEPacketTunnelProvider`), not a separate
/// daemon, so control flows over Flutter platform channels rather than a socket.
/// The wire shape mirrors the desktop daemon protocol so both Mode B backends
/// stay aligned.
class MobileVpnController {
  /// Creates a controller over the given channels.
  ///
  /// [events] is injectable so tests can drive state transitions without the
  /// platform; in production it is the extension's event channel.
  MobileVpnController({MethodChannel? method, Stream<Object?>? events})
      : _method = method ?? kVpnMethodChannel,
        _states = (events ?? kVpnEventChannel.receiveBroadcastStream())
            .map(mapMobileEvent)
            .asBroadcastStream();

  final MethodChannel _method;
  final Stream<ConnectionState> _states;

  /// Connection-state transitions from the extension. A failure arrives as a
  /// stream error carrying the mapped [WarrenError].
  Stream<ConnectionState> get states => _states;

  /// Binds an identity and account API inside the extension.
  Future<void> configure({
    required String mnemonic,
    required String apiBase,
    required String serverPubkeyPin,
    String? multihopRootPin,
    bool daita = false,
    String? daitaMachine,
    bool requestIpv6 = true,
  }) =>
      _method.invokeMethod('configure', {
        'mnemonic': mnemonic,
        'apiBase': apiBase,
        'serverPubkeyPin': serverPubkeyPin,
        if (multihopRootPin != null) 'multihopRootPin': multihopRootPin,
        if (daita) 'daita': daita,
        if (daitaMachine != null) 'daitaMachine': daitaMachine,
        'requestIpv6': requestIpv6,
      });

  /// Brings up a system-VPN session to an exit.
  Future<void> connect({
    required String exitPubkeyHex,
    bool dnsOverTunnel = true,
  }) =>
      _method.invokeMethod('connect', {
        'exitPubkeyHex': exitPubkeyHex,
        'dnsOverTunnel': dnsOverTunnel,
      });

  /// Tears the current session down.
  Future<void> disconnect() => _method.invokeMethod('disconnect');
}

/// Maps a raw platform event map to a [ConnectionState].
///
/// A `state` event becomes the matching state; an `error` event throws the
/// mapped [WarrenError] so it surfaces as a stream error. Throws a
/// [FormatException] on a malformed or unknown event.
ConnectionState mapMobileEvent(Object? raw) {
  final event = (raw! as Map).cast<String, Object?>();
  switch (event['type']) {
    case 'state':
      final name = event['state']! as String;
      return switch (name) {
        'connecting' => const Connecting(),
        'connected' => const Connected(),
        'reconnecting' => const Reconnecting(),
        'disconnected' => const Disconnected(),
        'failed' => const ConnectionFailed(
            code: 'tunnel/failed',
            message: 'the connection failed and will not be retried',
          ),
        _ => throw FormatException('unknown state: $name'),
      };
    case 'error':
      final kind = event['kind']! as String;
      throw warrenErrorOfKind(
        kind,
        code: '$kind/extension',
        message: event['message']! as String,
      );
    case final type:
      throw FormatException('unknown vpn event: $type');
  }
}
