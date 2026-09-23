@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:warren_sdk/warren_sdk.dart';
import 'package:warren_sdk_desktop/warren_sdk_desktop.dart';

import 'support/daemon.dart';
import 'support/egress.dart';
import 'support/engine.dart';

/// Full rooted Mode B validation: brings up a real system-VPN TUN tunnel through
/// the `warrend` daemon to a real exit.
///
/// The daemon needs root to open the TUN device, so this is opt-in via
/// `WARREN_ROOTED=1` (plus the usual `WARREN_*` account env). Unless the test
/// already runs as root, it runs the daemon with `sudo -n`, which requires the
/// dev sudoers drop-in (`native/warrend/scripts/dev-sudoers.sh`, test-only):
/// rerun that script after each daemon build, since sudo runs the root-owned
/// copy it installs.
/// It uses the in-process engine to discover a real exit, then drives the daemon
/// to connect to it and waits for `Connected`.
///
/// It rewrites the global OS default route and pf, so it must NOT run in parallel
/// with another system-VPN test: run rooted live tests with `--concurrency=1`.
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
        // ignore: avoid_print
        print(
          '[rooted-test] exit ${exitId.substring(0, 8)} of ${exits.length}',
        );

        // Egress IP before the tunnel, via the physical link. 1.1.1.1 by literal
        // IP so no DNS is needed (the killswitch will block system DNS).
        final physicalEgress = await egressIp();
        expect(physicalEgress, isNotEmpty, reason: 'no baseline egress IP');

        final daemon = await launchRootedDaemon(daemonBin);
        addTearDown(() async {
          daemon.process.kill();
          await daemon.process.exitCode;
        });

        final daemonClient = await connectDaemonSocket(daemon.socketPath);
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

        // Egress proof: with all traffic captured by the TUN, the public egress
        // IP must become the exit's, not the host's. This is the end-to-end
        // datapath assertion: device open, routing, killswitch, the multihop
        // tunnel AND raw-IP packets actually flowing through the exit. A non-empty
        // egress that differs from the physical one is only possible if packets
        // traverse the utun device, get sealed, reach the exit and come back.
        //
        // A freshly established tunnel can drop the very first probe (TCP/TLS
        // warmup, PMTU settling), so poll a few times before judging. This is a
        // real wait on a live network, not a sleep masking a logic bug.
        final tunnelEgress = await egressIpWithRetry();
        // ignore: avoid_print
        print('[rooted-test] tunnel egress: '
            '${tunnelEgress.isEmpty ? "(none)" : tunnelEgress}, '
            'changed: ${tunnelEgress.isNotEmpty && tunnelEgress != physicalEgress}');
        expect(
          tunnelEgress,
          isNotEmpty,
          reason:
              'no egress through the tunnel (datapath not carrying packets)',
        );
        expect(
          tunnelEgress,
          isNot(physicalEgress),
          reason: 'egress must leave at the exit, not the host',
        );
      });
    },
    skip: ready
        ? false
        : 'set WARREN_ROOTED=1 + WARREN_* and install the dev sudoers to run',
  );
}
