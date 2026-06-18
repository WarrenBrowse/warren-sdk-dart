import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:warren_sdk_riverpod/warren_sdk_riverpod.dart';

part 'session_settings.g.dart';

/// User-facing connection preferences applied to each `connect` call: the
/// datapath mode and the tunables that map to `ConnectOptions`.
@immutable
class SessionSettings {
  const SessionSettings({
    this.mode = ConnectMode.proxy,
    this.dnsOverTunnel = true,
  });

  final ConnectMode mode;

  /// System-VPN only (proxy always resolves remotely at the exit).
  final bool dnsOverTunnel;

  ConnectOptions toOptions() => ConnectOptions(
        dnsOverTunnel: dnsOverTunnel,
        // Bind a local HTTP CONNECT proxy alongside SOCKS5 so the in-app network
        // check can route a probe through the tunnel with the stock HttpClient.
        httpListen: '127.0.0.1:0',
      );

  SessionSettings copyWith({
    ConnectMode? mode,
    bool? dnsOverTunnel,
  }) =>
      SessionSettings(
        mode: mode ?? this.mode,
        dnsOverTunnel: dnsOverTunnel ?? this.dnsOverTunnel,
      );
}

@Riverpod(keepAlive: true)
class SessionSettingsController extends _$SessionSettingsController {
  @override
  SessionSettings build() => const SessionSettings();

  void setMode(ConnectMode mode) => state = state.copyWith(mode: mode);

  void setDnsOverTunnel(bool value) =>
      state = state.copyWith(dnsOverTunnel: value);
}
