import 'package:flutter_test/flutter_test.dart';
import 'package:warren_sdk_platform_interface/warren_sdk_platform_interface.dart';

void main() {
  group('warrenErrorOfKind', () {
    final cases = <String, Type>{
      'identity': WarrenIdentityError,
      'api': WarrenApiError,
      'discovery': WarrenDiscoveryError,
      'tunnel': WarrenTunnelError,
      'privilege': WarrenPrivilegeError,
    };

    cases.forEach((kind, type) {
      test('$kind maps to $type with the given code and message', () {
        final error = warrenErrorOfKind(kind, code: '$kind/x', message: 'm');
        expect(error.runtimeType, type);
        expect(error.code, '$kind/x');
        expect(error.message, 'm');
      });
    });

    test('unsupported maps to WarrenUnsupportedError', () {
      final error = warrenErrorOfKind(
        'unsupported',
        code: 'unsupported/x',
        message: 'm',
      );
      expect(error, isA<WarrenUnsupportedError>());
      expect(error.code, 'unsupported/x');
    });

    test('an unknown kind falls back to WarrenTunnelError', () {
      final error = warrenErrorOfKind('bogus', code: 'c', message: 'm');
      expect(error, isA<WarrenTunnelError>());
    });
  });

  group('ConnectionState equality', () {
    test('payload-free states use value equality by runtime type', () {
      expect(const Connected(), equals(const Connected()));
      // A non-const instance still equals the canonical const one.
      // ignore: prefer_const_constructors
      expect(Connected(), equals(const Connected()));
      expect(const Connected().hashCode, const Connected().hashCode);
      expect(const Connecting(), isNot(equals(const Connected())));
      expect(const Reconnecting(), isNot(equals(const Disconnected())));
      // Draining is distinct from the failure-driven Reconnecting.
      expect(const Draining(), equals(const Draining()));
      expect(const Draining(), isNot(equals(const Reconnecting())));
    });

    test('ConnectionFailed compares code and message', () {
      expect(
        const ConnectionFailed(code: 'tunnel/failed', message: 'm'),
        equals(const ConnectionFailed(code: 'tunnel/failed', message: 'm')),
      );
      expect(
        const ConnectionFailed(code: 'tunnel/failed', message: 'm'),
        isNot(
          equals(const ConnectionFailed(code: 'tunnel/other', message: 'm')),
        ),
      );
    });
  });

  group('the unregistered platform sentinel', () {
    test('reports no instance', () {
      expect(WarrenSdkPlatform.hasInstance, isFalse);
    });

    test('throws WarrenUnsupportedError on use', () {
      expect(
        () => WarrenSdkPlatform.instance.generateMnemonic(),
        throwsA(
          isA<WarrenUnsupportedError>().having(
            (e) => e.code,
            'code',
            'platform/unregistered',
          ),
        ),
      );
    });
  });

  group('models', () {
    test('ExitInfo equality and hashCode are value-based', () {
      const a = ExitInfo(
        id: 'x',
        country: 'RO',
        city: 'Bucharest',
        supportsIpv6: true,
      );
      const b = ExitInfo(
        id: 'x',
        country: 'RO',
        city: 'Bucharest',
        supportsIpv6: true,
      );
      const c = ExitInfo(
        id: 'y',
        country: 'RO',
        city: 'Bucharest',
        supportsIpv6: true,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });

    test('ExitInfo metadata participates in equality', () {
      const base = ExitInfo(
        id: 'x',
        country: 'RO',
        city: 'Bucharest',
        supportsIpv6: true,
        weight: 10,
      );
      const differentCover = ExitInfo(
        id: 'x',
        country: 'RO',
        city: 'Bucharest',
        supportsIpv6: true,
        weight: 10,
        coverDomain: 'cover.example',
      );
      const differentWeight = ExitInfo(
        id: 'x',
        country: 'RO',
        city: 'Bucharest',
        supportsIpv6: true,
        weight: 11,
      );
      expect(base, isNot(equals(differentCover)));
      expect(base, isNot(equals(differentWeight)));
    });

    test('ConnectOptions equality includes the failover exits', () {
      const backup = ExitInfo(
        id: 'e2',
        country: 'RO',
        city: 'Cluj',
        supportsIpv6: false,
      );
      expect(
        const ConnectOptions(failoverExits: [backup]),
        equals(const ConnectOptions(failoverExits: [backup])),
      );
      expect(
        const ConnectOptions(failoverExits: [backup]),
        isNot(equals(const ConnectOptions())),
      );
    });

    test('SubscriptionInfo.isActive reflects a non-zero expiry', () {
      expect(const SubscriptionInfo(expiresAtUnix: 0).isActive, isFalse);
      expect(const SubscriptionInfo(expiresAtUnix: 1).isActive, isTrue);
    });

    test('SubscriptionInfo equality is value-based', () {
      expect(
        const SubscriptionInfo(expiresAtUnix: 5),
        equals(const SubscriptionInfo(expiresAtUnix: 5)),
      );
      expect(
        const SubscriptionInfo(expiresAtUnix: 5),
        isNot(equals(const SubscriptionInfo(expiresAtUnix: 6))),
      );
    });

    test('ConnectOptions equality is value-based', () {
      expect(const ConnectOptions(), equals(const ConnectOptions()));
      expect(
        const ConnectOptions().hashCode,
        const ConnectOptions().hashCode,
      );
      expect(
        const ConnectOptions(httpListen: '127.0.0.1:8080'),
        isNot(equals(const ConnectOptions())),
      );
    });

    test('ExitQuery equality is value-based', () {
      expect(
        const ExitQuery(country: 'RO', requireIpv6: true),
        equals(const ExitQuery(country: 'RO', requireIpv6: true)),
      );
      expect(
        const ExitQuery(country: 'RO'),
        isNot(equals(const ExitQuery(country: 'SE'))),
      );
    });

    test('ProxyEndpoints equality is value-based, credentials included', () {
      const session = ProxyCredentials(username: 'warren', password: 's1');
      expect(
        const ProxyEndpoints(socks5: '127.0.0.1:1', credentials: session),
        equals(
          const ProxyEndpoints(socks5: '127.0.0.1:1', credentials: session),
        ),
      );
      expect(
        const ProxyEndpoints(socks5: '127.0.0.1:1', credentials: session),
        isNot(
          equals(
            const ProxyEndpoints(socks5: '127.0.0.1:2', credentials: session),
          ),
        ),
      );
      expect(
        const ProxyEndpoints(socks5: '127.0.0.1:1', credentials: session),
        isNot(
          equals(
            const ProxyEndpoints(
              socks5: '127.0.0.1:1',
              credentials: ProxyCredentials(username: 'warren', password: 's2'),
            ),
          ),
        ),
      );
    });

    test('ProxyCredentials never render the password', () {
      const credentials = ProxyCredentials(
        username: 'warren',
        password: 'per-session-secret',
      );
      expect(credentials.toString(), isNot(contains('per-session-secret')));
      expect(
        const ProxyEndpoints(socks5: '127.0.0.1:1', credentials: credentials)
            .toString(),
        isNot(contains('per-session-secret')),
      );
    });

    test('TunnelCheck equality is value-based', () {
      expect(
        const TunnelCheck(ip: '203.0.113.7', isExit: true, country: 'RO'),
        equals(
          const TunnelCheck(ip: '203.0.113.7', isExit: true, country: 'RO'),
        ),
      );
      expect(
        const TunnelCheck(ip: '203.0.113.7', isExit: true),
        isNot(equals(const TunnelCheck(ip: '203.0.113.8', isExit: true))),
      );
    });

    test('WarrenClientConfig equality is value-based', () {
      final a = WarrenClientConfig(
        mnemonic: 'm',
        apiBase: Uri.parse('https://api.example.com'),
        serverPubkeyPin: 'pin',
      );
      final b = WarrenClientConfig(
        mnemonic: 'm',
        apiBase: Uri.parse('https://api.example.com'),
        serverPubkeyPin: 'pin',
      );
      final c = WarrenClientConfig(
        mnemonic: 'other',
        apiBase: Uri.parse('https://api.example.com'),
        serverPubkeyPin: 'pin',
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });
  });
}
