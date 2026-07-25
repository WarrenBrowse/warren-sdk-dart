import 'package:flutter_test/flutter_test.dart';
import 'package:warren_sdk_platform_interface/warren_sdk_platform_interface.dart';

void main() {
  group('release channel anchors', () {
    test('pins the account API base of every channel', () {
      expect(WarrenChannel.prod.apiBase, 'https://api.warrenbrowse.com');
      expect(WarrenChannel.beta.apiBase, 'https://api.beta.warrenbrowse.com');
    });

    test('never lets beta share the prod host', () {
      // Both names resolve to the same box today, so a wrong binding would stay
      // invisible until production splits off.
      expect(WarrenChannel.beta.apiBase, isNot(WarrenChannel.prod.apiBase));
    });

    test('defaults to prod when the selector is unset or blank', () {
      expect(WarrenChannel.fromSelector(''), WarrenChannel.prod);
      expect(WarrenChannel.fromSelector('  '), WarrenChannel.prod);
      expect(WarrenChannel.fromSelector('prod'), WarrenChannel.prod);
    });

    test('selects beta only on an explicit beta selector', () {
      expect(WarrenChannel.fromSelector('beta'), WarrenChannel.beta);
    });

    test('rejects an unknown selector instead of falling back to prod', () {
      expect(
        () => WarrenChannel.fromSelector('staging'),
        throwsArgumentError,
      );
    });

    test('exposes the compiled anchor of the selected channel', () {
      expect(warrenChannel, WarrenChannel.fromSelector(warrenChannelSelector));
      expect(warrenApiBase, warrenChannel.apiBase);
    });
  });
}
