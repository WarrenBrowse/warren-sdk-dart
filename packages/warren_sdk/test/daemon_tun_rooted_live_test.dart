@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:warren_sdk/warren_sdk.dart';
import 'package:warren_sdk_desktop/warren_sdk_desktop.dart';

import 'support/engine.dart';

/// Full rooted Mode B validation: brings up a real system-VPN TUN tunnel through
/// the `warrend` daemon to a real exit.
///
/// The daemon needs root to open the TUN device, so this is opt-in via
/// `WARREN_ROOTED=1` (plus the usual `WARREN_*` account env). It runs the daemon
/// with `sudo -n`, which requires the dev sudoers drop-in
/// (`native/warrend/scripts/dev-sudoers.sh`, test-only) to be installed first.
/// It uses the in-process engine to discover a real exit, then drives the daemon
/// to connect to it and waits for `Connected`.
void main() {
  final env = Platform.environment;
  final mnemonic = env['WARREN_MNEMONIC'];
  final apiBase = env['WARREN_API_BASE'];
  final pin = env['WARREN_SERVER_PIN'];
  const daemonBin = '../../native/warrend/target/release/warrend';
  final ready = env['WARREN_ROOTED'] == '1' &&
      mnemonic != null &&
      apiBase != null &&
      pin != null &&
      File(daemonBin).existsSync();

  group(
    'rooted system-VPN TUN to a real exit',
    () {
      test('brings the tunnel up and reaches Connected', () async {
        expect(
          tryRegisterEngine(),
          isTrue,
          reason: 'build native/warren_sdk_frb',
        );

        // Discover a real exit's Ed25519 id with the in-process engine.
        final client = await WarrenClient.create(
          mnemonic: mnemonic!,
          apiBase: Uri.parse(apiBase!),
          serverPubkeyPin: pin!,
        );
        addTearDown(client.dispose);
        final exits = await client.listExits();
        expect(exits, isNotEmpty);
        final exitId = exits.first.id;

        // Launch the privileged daemon (root via the dev sudoers) on a temp
        // socket, then drive it.
        final dir = await Directory.systemTemp.createTemp('warrend_root');
        final socketPath = '${dir.path}/d.sock';
        // Canonical path (no `..`), so it matches the pinned sudoers entry.
        final daemonPath = File(daemonBin).resolveSymbolicLinksSync();
        final daemon =
            await Process.start('sudo', ['-n', daemonPath, socketPath]);
        addTearDown(() async {
          daemon.kill();
          await daemon.exitCode;
        });
        await daemon.stderr
            .transform(const SystemEncoding().decoder)
            .firstWhere((line) => line.contains('listening'))
            .timeout(const Duration(seconds: 10));

        final daemonClient = await connectDaemonSocket(socketPath);
        addTearDown(daemonClient.close);

        final connected = daemonClient.states
            .firstWhere((s) => s is Connected || s is ConnectionFailed)
            .timeout(const Duration(seconds: 60));

        final config = ConfigureRequest(
          mnemonic: mnemonic,
          apiBase: apiBase,
          serverPubkeyPin: pin,
        );
        daemonClient
          ..configure(config)
          ..connect(ConnectRequest(exitPubkeyHex: exitId));

        expect(await connected, isA<Connected>());
      });
    },
    skip: ready
        ? false
        : 'set WARREN_ROOTED=1 + WARREN_* and install the dev sudoers to run',
  );
}
