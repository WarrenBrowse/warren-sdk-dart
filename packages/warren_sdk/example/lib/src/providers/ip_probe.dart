import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'connection.dart';

part 'ip_probe.g.dart';

/// A single "what is my public IP" answer. Carries no app secret: a public
/// egress IP is, by definition, already visible to every server it reaches.
@immutable
class IpReport {
  const IpReport({required this.ip, this.country, this.isIpv6 = false});

  /// Parses Cloudflare's `cdn-cgi/trace` body (`key=value` lines), which gives
  /// the egress `ip` and a two-letter `loc` country with no extra request.
  factory IpReport.fromTrace(String body, {bool isIpv6 = false}) {
    String? ip;
    String? loc;
    for (final line in body.split('\n')) {
      if (line.startsWith('ip=')) ip = line.substring(3).trim();
      if (line.startsWith('loc=')) loc = line.substring(4).trim();
    }
    if (ip == null || ip.isEmpty) {
      throw const FormatException('no ip= in trace');
    }
    return IpReport(
      ip: ip,
      country: (loc != null && loc.isNotEmpty) ? loc : null,
      isIpv6: isIpv6 || ip.contains(':'),
    );
  }

  final String ip;
  final String? country;
  final bool isIpv6;

  bool sameHostAs(IpReport? other) => other != null && other.ip == ip;
}

/// What the network check concluded about the current exposure.
enum LeakVerdict {
  /// No tunnel: the real public IP is what every server sees.
  exposed,

  /// Tunnel active and the observed egress IP differs from the real one.
  protected,

  /// Tunnel active but the egress IP equals the real IP: traffic is NOT tunneled.
  leaking,

  /// Could not reach the lookup service through one of the paths.
  unknown,

  /// A check is in flight or has not run yet.
  pending,
}

/// The outcome of one network check: the IP seen on the real connection versus
/// the IP seen through the Warren tunnel, plus an IPv6 probe so a classic IPv6
/// leak is visible.
@immutable
class NetCheck {
  const NetCheck({
    required this.connected,
    required this.systemVpn,
    this.direct,
    this.directError,
    this.directIpv6,
    this.tunnel,
    this.tunnelError,
    this.tunnelIpv6,
  });

  /// Whether a session is currently open.
  final bool connected;

  /// True for Mode B (system VPN): there is no local proxy, so the "direct"
  /// probe already travels through the tunnel and no side-by-side compare is
  /// possible from inside the app.
  final bool systemVpn;

  /// Public IPv4 on the real connection (proxy bypassed). In system-VPN mode
  /// this is already the tunneled egress.
  final IpReport? direct;
  final String? directError;

  /// Public IPv6 on the real connection, if the host/ISP has one.
  final IpReport? directIpv6;

  /// Public IPv4 as seen through the Warren proxy (proxy mode only).
  final IpReport? tunnel;
  final String? tunnelError;

  /// Public IPv6 through the Warren proxy, if the exit offers IPv6 egress.
  final IpReport? tunnelIpv6;

  /// The IP every server effectively sees right now: the tunnel egress when a
  /// proxy session carries it, otherwise the real connection.
  IpReport? get effective => tunnel ?? direct;

  LeakVerdict get verdict {
    if (!connected) {
      return direct != null ? LeakVerdict.exposed : LeakVerdict.unknown;
    }
    if (systemVpn) {
      // No local baseline to compare against; a non-empty egress is the best
      // signal the app can offer for Mode B.
      return direct != null ? LeakVerdict.protected : LeakVerdict.unknown;
    }
    if (tunnel == null) return LeakVerdict.unknown;
    if (tunnel!.sameHostAs(direct)) return LeakVerdict.leaking;
    return LeakVerdict.protected;
  }
}

/// Runs the network check and re-runs it whenever the session changes, so the
/// displayed IP stays live across connect / disconnect. Invalidate the provider
/// to force a manual re-check.
@Riverpod(keepAlive: true)
Future<NetCheck> netCheck(Ref ref) async {
  final session = ref.watch(connectionControllerProvider).asData?.value;
  final endpoints = session?.endpoints;
  final httpProxy = endpoints?.http;
  final connected = session != null;
  final systemVpn = connected && endpoints == null;

  // The real-connection probes are reliable; the tunnel egress is intermittent,
  // so its probes retry harder. All probes run concurrently.
  final directF = _safeProbe(tries: 2);
  final directV6F = _safeProbe(ipv6: true, tries: 2);
  final tunnelF = httpProxy != null
      ? _safeProbe(proxy: httpProxy, tries: 6)
      : Future<(IpReport?, String?)>.value((null, null));
  final tunnelV6F = httpProxy != null
      ? _safeProbe(proxy: httpProxy, ipv6: true, tries: 4)
      : Future<(IpReport?, String?)>.value((null, null));

  final results = await Future.wait([directF, directV6F, tunnelF, tunnelV6F]);
  final (direct, directError) = results[0];
  final (directV6, _) = results[1];
  final (tunnel, tunnelError) = results[2];
  final (tunnelV6, _) = results[3];

  return NetCheck(
    connected: connected,
    systemVpn: systemVpn,
    direct: direct,
    directError: directError,
    directIpv6: directV6,
    tunnel: tunnel,
    tunnelError: tunnelError,
    tunnelIpv6: tunnelV6,
  );
}

/// Runs one probe with retries (the tunnel egress drops a fair share of
/// connect attempts), returning either a report or a short error string and
/// never throwing, so one failed path does not sink the whole check.
Future<(IpReport?, String?)> _safeProbe({
  String? proxy,
  bool ipv6 = false,
  int tries = 3,
}) async {
  String? lastError;
  for (var attempt = 0; attempt < tries; attempt++) {
    try {
      return (await _probe(proxy: proxy, ipv6: ipv6), null);
    } on TimeoutException {
      lastError = 'timed out';
    } on SocketException {
      lastError = ipv6 ? 'no IPv6 route' : 'no route';
    } on HttpException catch (e) {
      lastError = e.message;
    } catch (e) {
      lastError = e.toString();
    }
  }
  return (null, lastError);
}

Future<IpReport> _probe({String? proxy, bool ipv6 = false}) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 6)
    ..userAgent = 'warren-sdk-example/netcheck'
    // We reach Cloudflare's resolver by IP literal, so the cert (issued for
    // cloudflare-dns.com) will not match the host. This probe only reads our
    // own egress IP back; it sends nothing sensitive, so the mismatch is safe.
    ..badCertificateCallback = (_, __, ___) => true;
  if (proxy != null) {
    // Stock HttpClient issues CONNECT for an https target through an HTTP proxy.
    client.findProxy = (_) => 'PROXY $proxy';
  }
  try {
    // Cloudflare's trace is reachable by IP on 443 (no tunnel DNS needed) and
    // returns both the egress ip and a country, on v4 and v6 literals alike.
    final url = ipv6
        ? Uri.parse('https://[2606:4700:4700::1111]/cdn-cgi/trace')
        : Uri.parse('https://1.1.1.1/cdn-cgi/trace');
    final request = await client.getUrl(url);
    final response = await request.close().timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}');
    }
    final body = await response.transform(utf8.decoder).join();
    return IpReport.fromTrace(body, isIpv6: ipv6);
  } finally {
    client.close(force: true);
  }
}
