// Live end-to-end validation of the control plane and the proxy datapath
// against the real Warren backend, exactly as the example app drives them.
//
// Env-gated: skipped unless WARREN_MNEMONIC and WARREN_SERVER_PIN are set
// (WARREN_API_BASE defaults to the test network). Run it with:
//
//   WARREN_MNEMONIC="word1 …" WARREN_SERVER_PIN=<hex> \
//     fvm flutter test integration_test/live_test.dart -d macos
//
// No secret is logged: only the public address is asserted, redaction aside.
import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:warren_sdk_desktop/warren_sdk_desktop.dart';
import 'package:warren_sdk_example/src/providers/constants.dart';
import 'package:warren_sdk_riverpod/warren_sdk_riverpod.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final env = Platform.environment;
  final mnemonic = env['WARREN_MNEMONIC'];
  // The pin is a public network key; default to the same one the app uses, so
  // a live run only needs a mnemonic.
  final pin = env['WARREN_SERVER_PIN'] ?? AppEnv.serverPubkeyPin;
  final apiBase = env['WARREN_API_BASE'] ?? AppEnv.apiBase;
  final hasCreds = mnemonic != null && mnemonic.isNotEmpty && pin.isNotEmpty;

  testWidgets(
    'account, exits and a proxy connection reach the backend',
    (
      tester,
    ) async {
      DesktopWarrenSdkPlatform.registerWith();

      late final WarrenClient client;
      late final List<ExitInfo> exits;
      ConnectionState? finalState;

      await tester.runAsync(() async {
        client = await WarrenClient.create(
          mnemonic: mnemonic!,
          apiBase: Uri.parse(apiBase),
          serverPubkeyPin: pin,
        );

        // Control plane: a signed account call and the verified relay list.
        await client.subscription();
        exits = await client.listExits();

        // Datapath: a real multihop proxy session that reaches Connected.
        final session = await client.connect(exits.first);
        finalState = await session.states
            .firstWhere((s) => s is Connected || s is ConnectionFailed)
            .timeout(const Duration(seconds: 60));
        await session.disconnect();
        await client.dispose();
      });

      expect(client.address, startsWith('wb'));
      expect(exits, isNotEmpty);
      expect(finalState, isA<Connected>());
      // skip reason: set WARREN_MNEMONIC + WARREN_SERVER_PIN to run this live.
    },
    skip: !hasCreds,
  );
}
