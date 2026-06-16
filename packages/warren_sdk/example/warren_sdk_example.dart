// A minimal end-to-end usage example for the Warren SDK.
//
// This is illustrative console code, not a full Flutter app: it shows the call
// flow an app follows. Replace the placeholders (secure-store read, API base and
// the pinned server key) with your real values.
//
// ignore_for_file: avoid_print

import 'package:warren_sdk/warren_sdk.dart';

Future<void> main() async {
  // 1. Obtain the mnemonic from your platform secure store, then create a
  //    client. The mnemonic is consumed once and zeroized in the engine.
  final client = await WarrenClient.create(
    mnemonic: await _readMnemonicFromSecureStore(),
    apiBase: Uri.parse('https://api.warrenbrowse.com'),
    serverPubkeyPin: _kWarrenServerPubkeyPin,
  );

  try {
    // 2. Check the subscription.
    final subscription = await client.subscription();
    print('subscription active: ${subscription.isActive}');

    // 3. List exits and pick one (here: the first Romanian exit).
    final exits = await client.listExits();
    final exit = WarrenClient.selectExit(exits, const ExitQuery(country: 'RO'));
    if (exit == null) {
      print('no matching exit');
      return;
    }

    // 4. Connect in proxy mode (no privilege). The session exposes a local
    //    SOCKS5 endpoint you can point an HTTP client at.
    final session = await client.connect(exit);
    final subscriptionToStates = session.states.listen((state) {
      print('connection state: $state');
    });

    print('SOCKS5 proxy at ${session.endpoints?.socks5}');

    // ... route traffic through the proxy ...

    await subscriptionToStates.cancel();
    await session.disconnect();
  } finally {
    await client.dispose();
  }
}

// Placeholders for the example only.
Future<String> _readMnemonicFromSecureStore() async =>
    'replace with your stored 12-word mnemonic';

const String _kWarrenServerPubkeyPin = 'replace-with-the-pinned-server-key-hex';
