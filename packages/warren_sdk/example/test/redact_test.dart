import 'package:flutter_test/flutter_test.dart';
import 'package:warren_sdk_example/src/common/redact.dart';

void main() {
  group('redactAddress', () {
    test('shortens long values to a recognizable stub', () {
      final out = redactAddress('wb1qabcdefghijklmnopqrstuvwxyz0123');
      expect(out, 'wb1qabcd…0123');
      expect(out.contains('…'), isTrue);
    });

    test('leaves short values untouched', () {
      expect(redactAddress('wb1short'), 'wb1short');
    });
  });

  group('countryFlag', () {
    test('maps an ISO code to a regional-indicator flag', () {
      expect(countryFlag('RO'), '🇷🇴');
      expect(countryFlag('us'), '🇺🇸');
    });

    test('falls back for malformed input', () {
      expect(countryFlag('X'), '🏳️');
      expect(countryFlag('1A'), '🏳️');
    });
  });

  group('formatUnixSeconds', () {
    test('returns a dash for zero (no subscription)', () {
      expect(formatUnixSeconds(0), '—');
    });

    test('formats a real timestamp', () {
      // 2021-01-01T00:00:00Z; exact local rendering depends on the zone, but it
      // must be a full date-time, not the dash sentinel.
      expect(formatUnixSeconds(1609459200), isNot('—'));
    });
  });
}
