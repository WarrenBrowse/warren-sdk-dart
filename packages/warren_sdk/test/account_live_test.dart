@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:warren_sdk/warren_sdk.dart';

import 'support/engine.dart';

/// Live account-API validation against a real Warren API and exit.
///
/// Skipped unless `WARREN_MNEMONIC`, `WARREN_API_BASE` and `WARREN_SERVER_PIN`
/// are set, so CI and offline runs stay green. This is the P2 "live happy-path"
/// gate: the in-repo fakes prove the orchestration, but the real account path is
/// only confirmed here, the same rule the Rust engine follows.
void main() {
  final env = Platform.environment;
  final mnemonic = env['WARREN_MNEMONIC'];
  final apiBase = env['WARREN_API_BASE'];
  final pin = env['WARREN_SERVER_PIN'];
  final ready = mnemonic != null && apiBase != null && pin != null;

  group(
    'account API against a real backend',
    () {
      setUpAll(() {
        if (!tryRegisterEngine()) {
          fail('Build the engine first: cd native/warren_sdk_frb && '
              'cargo build --release');
        }
      });

      test('create, then read subscription and exits', () async {
        final client = await WarrenClient.create(
          mnemonic: mnemonic!,
          apiBase: Uri.parse(apiBase!),
          serverPubkeyPin: pin!,
        );
        addTearDown(client.dispose);

        expect(client.address, startsWith('wb'));

        final sub = await client.subscription();
        expect(sub.expiresAtUnix, greaterThanOrEqualTo(0));

        final exits = await client.listExits();
        expect(exits, isNotEmpty);
        expect(exits.first.country, isNotEmpty);
      });
    },
    skip: ready
        ? false
        : 'set WARREN_MNEMONIC, WARREN_API_BASE and WARREN_SERVER_PIN to run',
  );
}
