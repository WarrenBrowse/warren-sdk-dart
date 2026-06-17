import 'package:flutter/foundation.dart';

/// The account/engine configuration the app uses to build a `WarrenClient`.
///
/// Deliberately holds no secret: the mnemonic lives only in the platform secure
/// store and is read once at client-creation time. This object carries the
/// public, non-secret knobs of `WarrenClient.create`.
@immutable
class ClientConfig {
  const ClientConfig({
    required this.apiBase,
    required this.serverPubkeyPin,
    this.multihopRootPin,
    this.daita = false,
    this.daitaMachine,
    this.requestIpv6 = true,
  });

  /// The account API base, e.g. `https://api.warrenbrowse.com`.
  final Uri apiBase;

  /// The pinned server public key (hex) the API connection is verified against.
  final String serverPubkeyPin;

  /// Optional pinned multihop root key (hex).
  final String? multihopRootPin;

  /// Whether to enable DAITA traffic shaping on the client.
  final bool daita;

  /// Optional named DAITA machine.
  final String? daitaMachine;

  /// Whether to request a dual-stack (IPv6) allocation from the exit.
  final bool requestIpv6;

  ClientConfig copyWith({
    Uri? apiBase,
    String? serverPubkeyPin,
    String? multihopRootPin,
    bool? daita,
    String? daitaMachine,
    bool? requestIpv6,
  }) {
    return ClientConfig(
      apiBase: apiBase ?? this.apiBase,
      serverPubkeyPin: serverPubkeyPin ?? this.serverPubkeyPin,
      multihopRootPin: multihopRootPin ?? this.multihopRootPin,
      daita: daita ?? this.daita,
      daitaMachine: daitaMachine ?? this.daitaMachine,
      requestIpv6: requestIpv6 ?? this.requestIpv6,
    );
  }
}
