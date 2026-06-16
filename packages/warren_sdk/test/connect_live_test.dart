@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:warren_sdk/warren_sdk.dart';

import 'support/engine.dart';

/// Live proxy-datapath validation against a real exit.
///
/// Skipped unless `WARREN_MNEMONIC`, `WARREN_API_BASE` and `WARREN_SERVER_PIN`
/// are set. This is the P3 end-to-end gate: it opens a real multihop proxy and
/// waits for the tunnel to come up. The fakes prove the facade wiring; only this
/// confirms a real connection, the same rule the Rust engine follows.
void main() {
  final env = Platform.environment;
  final mnemonic = env['WARREN_MNEMONIC'];
  final apiBase = env['WARREN_API_BASE'];
  final pin = env['WARREN_SERVER_PIN'];
  final ready = mnemonic != null && apiBase != null && pin != null;

  group(
    'proxy datapath against a real exit',
    () {
      setUpAll(() {
        if (!tryRegisterEngine()) {
          fail('Build the engine first: cd native/warren_sdk_frb && '
              'cargo build --release');
        }
      });

      test('connects, exposes a SOCKS5 endpoint and reaches Connected',
          () async {
        final client = await WarrenClient.create(
          mnemonic: mnemonic!,
          apiBase: Uri.parse(apiBase!),
          serverPubkeyPin: pin!,
        );
        addTearDown(client.dispose);

        final exits = await client.listExits();
        final exit = exits.first;

        final session = await client.connect(exit);
        addTearDown(session.disconnect);

        expect(session.endpoints?.socks5, isNotEmpty);

        final connected = await session.states
            .firstWhere((s) => s is Connected || s is ConnectionFailed)
            .timeout(const Duration(seconds: 30));
        expect(connected, isA<Connected>());
      });
    },
    skip: ready
        ? false
        : 'set WARREN_MNEMONIC, WARREN_API_BASE and WARREN_SERVER_PIN to run',
  );
}
