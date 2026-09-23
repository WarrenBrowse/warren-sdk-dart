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
    this.coverDomain,
    this.weight = 0,
    this.isActive = true,
  });

  /// Stable hex identifier of the exit node.
  final String id;

  /// ISO country code, for example `RO`.
  final String country;

  /// Human-readable city, for example `Bucharest`.
  final String city;

  /// Whether the exit can route IPv6 egress.
  final bool supportsIpv6;

  /// The exit's X.509 cover domain, when it advertises one. Cover-domain exits
  /// need dialing support the engine does not provide yet, so an app can filter
  /// them out (a non-null value means the exit is not currently reachable).
  final String? coverDomain;

  /// Relative selection weight advertised for load balancing (0 when unknown).
  final int weight;

  /// Whether the relay list marks this exit active.
  final bool isActive;

  @override
  bool operator ==(Object other) =>
      other is ExitInfo &&
      other.id == id &&
      other.country == country &&
      other.city == city &&
      other.supportsIpv6 == supportsIpv6 &&
      other.coverDomain == coverDomain &&
      other.weight == weight &&
      other.isActive == isActive;

  @override
  int get hashCode => Object.hash(
        id,
        country,
        city,
        supportsIpv6,
        coverDomain,
        weight,
        isActive,
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
  });

  /// Restrict to this ISO country code.
  final String? country;

  /// Restrict to this city.
  final String? city;

  /// Require IPv6 egress support.
  final bool? requireIpv6;

  @override
  bool operator ==(Object other) =>
      other is ExitQuery &&
      other.country == country &&
      other.city == city &&
      other.requireIpv6 == requireIpv6;

  @override
  int get hashCode => Object.hash(country, city, requireIpv6);
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
    this.failoverExits = const <ExitInfo>[],
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

  /// Proxy-mode only: additional exits, in priority order, the datapath fails
  /// over to when the primary exit cannot (re)establish. Empty means no failover
  /// (a single broken exit then leaves the session reconnecting). The primary
  /// exit passed to `connect` is always tried first.
  final List<ExitInfo> failoverExits;

  @override
  bool operator ==(Object other) =>
      other is ConnectOptions &&
      other.socks5Listen == socks5Listen &&
      other.httpListen == httpListen &&
      other.dnsServer == dnsServer &&
      other.dnsOverTunnel == dnsOverTunnel &&
      _listEquals(other.failoverExits, failoverExits);

  @override
  int get hashCode => Object.hash(
        socks5Listen,
        httpListen,
        dnsServer,
        dnsOverTunnel,
        Object.hashAll(failoverExits),
      );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Transport protocol for an inbound forwarded port.
enum ForwardProtocol {
  /// TCP.
  tcp,

  /// UDP.
  udp,
}

/// The credentials every client of a session's local proxy endpoints presents:
/// RFC 1929 on SOCKS5, `Proxy-Authorization: Basic` on HTTP. The listeners
/// refuse any client without them, since any local process can reach a
/// loopback port.
@immutable
class ProxyCredentials {
  /// Creates the credential pair.
  const ProxyCredentials({required this.username, required this.password});

  /// The username clients present.
  final String username;

  /// The password clients present. A per-session secret: keep it out of logs,
  /// argv and anything another local account can read.
  final String password;

  @override
  bool operator ==(Object other) =>
      other is ProxyCredentials &&
      other.username == username &&
      other.password == password;

  @override
  int get hashCode => Object.hash(username, password);

  @override
  String toString() => 'ProxyCredentials($username, <redacted>)';
}

/// The local endpoints exposed by a proxy-mode session.
@immutable
class ProxyEndpoints {
  /// Creates the endpoint set.
  const ProxyEndpoints({
    required this.socks5,
    this.http,
    required this.credentials,
  });

  /// The bound local SOCKS5 endpoint, for example `127.0.0.1:51234`.
  final String socks5;

  /// The bound local HTTP CONNECT endpoint, if enabled.
  final String? http;

  /// What every client of [socks5] and [http] presents.
  final ProxyCredentials credentials;

  @override
  bool operator ==(Object other) =>
      other is ProxyEndpoints &&
      other.socks5 == socks5 &&
      other.http == http &&
      other.credentials == credentials;

  @override
  int get hashCode => Object.hash(socks5, http, credentials);

  @override
  String toString() => 'ProxyEndpoints($socks5, $http, $credentials)';
}

/// Account subscription state.
@immutable
class SubscriptionInfo {
  /// Creates a subscription snapshot.
  const SubscriptionInfo({required this.expiresAtUnix});

  /// Expiry as a Unix timestamp in seconds; `0` means no active subscription.
  final int expiresAtUnix;

  /// Whether the subscription is currently active.
  ///
  /// The engine reports `0` when there is no active subscription and a non-zero
  /// expiry otherwise, so this trusts that backend contract rather than
  /// re-deciding activeness against the local clock (which could disagree with
  /// a server-side grace period).
  bool get isActive => expiresAtUnix > 0;

  @override
  bool operator ==(Object other) =>
      other is SubscriptionInfo && other.expiresAtUnix == expiresAtUnix;

  @override
  int get hashCode => expiresAtUnix.hashCode;
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

  @override
  bool operator ==(Object other) =>
      other is TunnelCheck &&
      other.ip == ip &&
      other.isExit == isExit &&
      other.country == country &&
      other.city == city;

  @override
  int get hashCode => Object.hash(ip, isExit, country, city);
}
