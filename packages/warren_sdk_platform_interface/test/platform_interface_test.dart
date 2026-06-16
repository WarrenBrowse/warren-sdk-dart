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

    test('an unknown kind falls back to WarrenTunnelError', () {
      final error = warrenErrorOfKind('bogus', code: 'c', message: 'm');
      expect(error, isA<WarrenTunnelError>());
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
        supportsPortForwarding: false,
      );
      const b = ExitInfo(
        id: 'x',
        country: 'RO',
        city: 'Bucharest',
        supportsIpv6: true,
        supportsPortForwarding: false,
      );
      const c = ExitInfo(
        id: 'y',
        country: 'RO',
        city: 'Bucharest',
        supportsIpv6: true,
        supportsPortForwarding: false,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });

    test('SubscriptionInfo.isActive reflects a non-zero expiry', () {
      expect(const SubscriptionInfo(expiresAtUnix: 0).isActive, isFalse);
      expect(const SubscriptionInfo(expiresAtUnix: 1).isActive, isTrue);
    });
  });
}
