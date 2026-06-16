import 'package:meta/meta.dart';

/// Which datapath the engine uses for a connection.
///
/// See `ARCHITECTURE.md` for the full description of the two modes.
enum ConnectMode {
  /// Non-root, in-process. The engine exposes a local SOCKS5 / HTTP proxy.
  /// The default and the only mode that needs no privilege or extra process.
  proxy,

  /// Privileged, out-of-process. A real TUN device captures all OS traffic,
  /// run by a desktop daemon or a mobile network extension.
  systemVpn,
}

/// How a multihop circuit should be built, when supported by the exit.
enum MultihopMode {
  /// Let the engine decide (mandatory multihop on real exits).
  auto,

  /// Force a direct single-hop path (only where the exit allows it).
  singleHop,
}

/// Immutable description of an exit the engine can connect to, as returned by
/// the verified signed relay list. Identity fields are public by construction;
/// no secret material is carried here.
@immutable
class ExitInfo {
  /// Creates an exit description.
  const ExitInfo({
    required this.id,
    required this.country,
    required this.city,
    required this.supportsIpv6,
    required this.supportsPortForwarding,
    this.load,
  });

  /// Stable hex identifier of the exit node.
  final String id;

  /// ISO country code, for example `RO`.
  final String country;

  /// Human-readable city, for example `Bucharest`.
  final String city;

  /// Whether the exit can route IPv6 egress.
  final bool supportsIpv6;

  /// Whether the exit offers inbound port forwarding (NAT-PMP).
  final bool supportsPortForwarding;

  /// Optional load hint in `[0.0, 1.0]`, when advertised.
  final double? load;

  @override
  bool operator ==(Object other) =>
      other is ExitInfo &&
      other.id == id &&
      other.country == country &&
      other.city == city &&
      other.supportsIpv6 == supportsIpv6 &&
      other.supportsPortForwarding == supportsPortForwarding &&
      other.load == load;

  @override
  int get hashCode => Object.hash(
        id,
        country,
        city,
        supportsIpv6,
        supportsPortForwarding,
        load,
      );

  @override
  String toString() => 'ExitInfo($city, $country)';
}

/// A selection query over the available exits. All fields are optional and
/// combine with AND semantics.
@immutable
class ExitQuery {
  /// Creates an exit query.
  const ExitQuery({
    this.country,
    this.city,
    this.requireIpv6,
    this.requirePortForwarding,
  });

  /// Restrict to this ISO country code.
  final String? country;

  /// Restrict to this city.
  final String? city;

  /// Require IPv6 egress support.
  final bool? requireIpv6;

  /// Require inbound port forwarding support.
  final bool? requirePortForwarding;
}

/// Options that tune a connection. Sensible defaults match the engine.
@immutable
class ConnectOptions {
  /// Creates connection options.
  const ConnectOptions({
    this.multihop = MultihopMode.auto,
    this.socks5Listen = '127.0.0.1:0',
    this.httpListen,
    this.dnsOverTunnel = true,
  });

  /// Multihop behavior for this connection.
  final MultihopMode multihop;

  /// Proxy-mode only: the local SOCKS5 listen address. `:0` picks a free port.
  final String socks5Listen;

  /// Proxy-mode only: optional local HTTP CONNECT listen address.
  final String? httpListen;

  /// Whether DNS is resolved over the tunnel gateway.
  final bool dnsOverTunnel;
}

/// The local endpoints exposed by a proxy-mode session.
@immutable
class ProxyEndpoints {
  /// Creates the endpoint set.
  const ProxyEndpoints({required this.socks5, this.http});

  /// The bound local SOCKS5 endpoint, for example `127.0.0.1:51234`.
  final String socks5;

  /// The bound local HTTP CONNECT endpoint, if enabled.
  final String? http;
}

/// Account subscription state.
@immutable
class SubscriptionInfo {
  /// Creates a subscription snapshot.
  const SubscriptionInfo({required this.expiresAtUnix});

  /// Expiry as a Unix timestamp in seconds; `0` means no active subscription.
  final int expiresAtUnix;

  /// Whether the subscription is currently active.
  bool get isActive => expiresAtUnix > 0;
}
