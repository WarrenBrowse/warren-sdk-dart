@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:warren_sdk_desktop/warren_sdk_desktop.dart';
import 'package:warren_sdk_platform_interface/warren_sdk_platform_interface.dart';

/// Spawns the real `warrend` daemon (non-root) and drives it over the Unix
/// socket with a real test account. This proves the daemon's engine integration
/// end-to-end up to the privileged TUN step: configuring builds the real engine
/// client, and connecting fetches and verifies the real multihop directory (a
/// bogus exit id then yields a discovery error). The actual rooted TUN bring-up
/// is validated separately (see native/warrend, dev-sudoers).
///
/// Skipped unless `WARREN_MNEMONIC`, `WARREN_API_BASE`, `WARREN_SERVER_PIN` are
/// set and the daemon binary is built.
void main() {
  final env = Platform.environment;
  final mnemonic = env['WARREN_MNEMONIC'];
  final apiBase = env['WARREN_API_BASE'];
  final pin = env['WARREN_SERVER_PIN'];
  const daemonBin = '../../native/warrend/target/release/warrend';
  // The daemon runs unprivileged here, under this test's own account.
  final ownUid = int.parse(
    (Process.runSync('id', ['-u']).stdout as String).trim(),
  );
  final ready = mnemonic != null &&
      apiBase != null &&
      pin != null &&
      File(daemonBin).existsSync();

  group(
    'warrend daemon integration (non-root)',
    () {
      late Process daemon;
      late String socketPath;
      late DaemonClient client;

      setUp(() async {
        final dir = await Directory.systemTemp.createTemp('warrend_it');
        socketPath = '${dir.path}/d.sock';
        daemon = await Process.start(daemonBin, [socketPath]);
        // Wait for the daemon to announce it is listening.
        await daemon.stderr
            .transform(const SystemEncoding().decoder)
            .firstWhere((line) => line.contains('listening'))
            .timeout(const Duration(seconds: 10));
        client = await connectDaemonSocket(socketPath, daemonUid: ownUid);
      });

      tearDown(() async {
        await client.close();
        daemon.kill();
        await daemon.exitCode;
      });

      test('configures the real engine and fetches the real multihop directory',
          () async {
        // The first state-stream item is a typed error: it proves the request
        // crossed the socket, the engine built, and the real directory was
        // fetched and searched (the bogus exit is absent from it).
        final firstEvent = client.states.first;

        final config = ConfigureRequest(
          mnemonic: mnemonic!,
          apiBase: apiBase!,
          serverPubkeyPin: pin!,
        );
        client
          ..configure(config)
          ..connect(ConnectRequest(exitPubkeyHex: '00' * 32));

        await expectLater(
          firstEvent,
          throwsA(isA<WarrenDiscoveryError>()),
        );
      });
    },
    skip: ready
        ? false
        : 'set WARREN_MNEMONIC, WARREN_API_BASE, WARREN_SERVER_PIN and build '
            'native/warrend to run',
  );
}
