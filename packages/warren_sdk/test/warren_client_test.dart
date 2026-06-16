import 'package:flutter_test/flutter_test.dart';
import 'package:warren_sdk/warren_sdk.dart';

void main() {
  group('WarrenClient.selectExit', () {
    final ro = ExitInfo(
      id: 'a' * 32,
      country: 'RO',
      city: 'Bucharest',
      supportsIpv6: true,
      supportsPortForwarding: false,
    );
    final se = ExitInfo(
      id: 'b' * 32,
      country: 'SE',
      city: 'Stockholm',
      supportsIpv6: false,
      supportsPortForwarding: true,
    );
    final exits = [ro, se];

    test('returns the first exit matching a country query', () {
      expect(
        WarrenClient.selectExit(exits, const ExitQuery(country: 'SE')),
        equals(se),
      );
    });

    test('filters on the IPv6 capability', () {
      expect(
        WarrenClient.selectExit(exits, const ExitQuery(requireIpv6: true)),
        equals(ro),
      );
    });

    test('filters on the port-forwarding capability', () {
      expect(
        WarrenClient.selectExit(
          exits,
          const ExitQuery(requirePortForwarding: true),
        ),
        equals(se),
      );
    });

    test('combines predicates with AND and returns null when none match', () {
      expect(
        WarrenClient.selectExit(
          exits,
          const ExitQuery(country: 'RO', requirePortForwarding: true),
        ),
        isNull,
      );
    });

    test('returns null for an empty exit list', () {
      expect(
        WarrenClient.selectExit(const [], const ExitQuery(country: 'RO')),
        isNull,
      );
    });
  });
}
