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
  });

  /// Stable hex identifier of the exit node.
  final String id;

  /// ISO country code, for example `RO`.
  final String country;

  /// Human-readable city, for example `Bucharest`.
  final String city;

  /// Whether the exit can route IPv6 egress.
  final bool supportsIpv6;

  @override
  bool operator ==(Object other) =>
      other is ExitInfo &&
      other.id == id &&
      other.country == country &&
      other.city == city &&
      other.supportsIpv6 == supportsIpv6;

  @override
  int get hashCode => Object.hash(id, country, city, supportsIpv6);

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
  });

  /// Restrict to this ISO country code.
  final String? country;

  /// Restrict to this city.
  final String? city;

  /// Require IPv6 egress support.
  final bool? requireIpv6;
}

/// Options that tune a connection. Sensible defaults match the engine.
@immutable
class ConnectOptions {
  /// Creates connection options.
  const ConnectOptions({
    this.socks5Listen = '127.0.0.1:0',
    this.httpListen,
    this.dnsServer,
    this.dnsOverTunnel = true,
  });

  /// Proxy-mode only: the local SOCKS5 listen address. `:0` picks a free port.
  final String socks5Listen;

  /// Proxy-mode only: optional local HTTP CONNECT listen address.
  final String? httpListen;

  /// Proxy-mode only: optional IPv4 DNS resolver (port 53 implied) to use for
  /// names that travel the tunnel. Needed only for exits that disable the
  /// default tunnel DNS; leave null to use the engine default.
  final String? dnsServer;

  /// System-VPN only: whether DNS is resolved over the tunnel gateway. Proxy
  /// mode always resolves names remotely at the exit (SOCKS5/HTTP CONNECT), so
  /// this flag has no effect there.
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

/// The account server's view of the caller's connection, from a signed
/// `/v1/check`. Confirms, against the backend, whether traffic egresses from a
/// registered Warren exit (and where), independent of any third-party IP echo.
@immutable
class TunnelCheck {
  /// Creates a tunnel-check snapshot.
  const TunnelCheck({
    required this.ip,
    required this.isExit,
    this.country,
    this.city,
  });

  /// The public IP the account server observed for this call.
  final String ip;

  /// Whether [ip] is a registered Warren exit, i.e. traffic is tunneled.
  final bool isExit;

  /// Exit country (ISO 3166-1 alpha-2), when [isExit].
  final String? country;

  /// Exit city, when known.
  final String? city;
}
