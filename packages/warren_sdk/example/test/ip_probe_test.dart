import 'package:flutter_test/flutter_test.dart';
import 'package:warren_sdk_example/src/providers/ip_probe.dart';

void main() {
  group('IpReport.fromTrace', () {
    test('parses ip and loc from a Cloudflare trace body', () {
      const body = 'fl=123abc\n'
          'h=1.1.1.1\n'
          'ip=50.7.46.90\n'
          'ts=1700000000\n'
          'loc=NL\n'
          'tls=TLSv1.3\n';
      final report = IpReport.fromTrace(body);
      expect(report.ip, '50.7.46.90');
      expect(report.country, 'NL');
      expect(report.isIpv6, isFalse);
    });

    test('flags an IPv6 address even without the ipv6 hint', () {
      const body = 'ip=2606:4700:4700::1111\nloc=US\n';
      final report = IpReport.fromTrace(body);
      expect(report.ip, '2606:4700:4700::1111');
      expect(report.isIpv6, isTrue);
    });

    test('leaves country null when loc is absent', () {
      final report = IpReport.fromTrace('ip=9.9.9.9\n');
      expect(report.country, isNull);
    });

    test('throws when the body carries no ip', () {
      expect(
        () => IpReport.fromTrace('loc=FR\nts=1\n'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('NetCheck.verdict', () {
    IpReport ip(String value) => IpReport(ip: value);

    test('exposed when not connected but the real IP is known', () {
      final check = NetCheck(
        connected: false,
        systemVpn: false,
        direct: ip('192.0.2.7'),
      );
      expect(check.verdict, LeakVerdict.exposed);
      expect(check.effective?.ip, '192.0.2.7');
    });

    test('protected when the tunnel egress differs from the real IP', () {
      final check = NetCheck(
        connected: true,
        systemVpn: false,
        direct: ip('192.0.2.7'),
        tunnel: ip('50.7.46.90'),
      );
      expect(check.verdict, LeakVerdict.protected);
      // The effective identity is the tunnel egress, not the real IP.
      expect(check.effective?.ip, '50.7.46.90');
    });

    test('leaking when the tunnel egress equals the real IP', () {
      final check = NetCheck(
        connected: true,
        systemVpn: false,
        direct: ip('192.0.2.7'),
        tunnel: ip('192.0.2.7'),
      );
      expect(check.verdict, LeakVerdict.leaking);
    });

    test('unknown when connected but the tunnel probe produced nothing', () {
      final check = NetCheck(
        connected: true,
        systemVpn: false,
        direct: ip('192.0.2.7'),
      );
      expect(check.verdict, LeakVerdict.unknown);
    });

    test('system VPN is protected on any observed egress', () {
      final check = NetCheck(
        connected: true,
        systemVpn: true,
        direct: ip('50.7.46.90'),
      );
      expect(check.verdict, LeakVerdict.protected);
    });
  });
}
