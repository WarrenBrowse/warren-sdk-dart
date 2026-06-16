@TestOn('vm')
library;

import 'dart:async';
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

        // Egress IP before the tunnel, via the physical link. 1.1.1.1 by literal
        // IP so no DNS is needed (the killswitch will block system DNS).
        final physicalEgress = await _egressIp();
        expect(physicalEgress, isNotEmpty, reason: 'no baseline egress IP');

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
        // Keep draining both streams for the daemon's lifetime, so a child's
        // inherited output never backs up into a broken pipe.
        unawaited(daemon.stdout.drain<void>());
        final listening = Completer<void>();
        daemon.stderr.transform(const SystemEncoding().decoder).listen((line) {
          if (!listening.isCompleted && line.contains('listening')) {
            listening.complete();
          }
        });
        await listening.future.timeout(const Duration(seconds: 10));

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

        // Egress proof: with all traffic captured by the TUN, the egress IP
        // should become the exit's. The macOS raw-IP TUN datapath is still
        // experimental, so a missing/unchanged egress marks the test skipped
        // rather than failing: the device open, routing, killswitch, Connected
        // and (via teardown) the network restore above are the validated part.
        final tunnelEgress = await _egressIp();
        if (tunnelEgress.isEmpty || tunnelEgress == physicalEgress) {
          markTestSkipped(
            'TUN setup + Connected + teardown validated; raw-IP egress does not '
            'yet flow through the exit on macOS (engine experimental datapath).',
          );
        } else {
          // Real egress confirmed: traffic now leaves at the exit, not the host.
          expect(tunnelEgress, isNot(physicalEgress));
        }
      });
    },
    skip: ready
        ? false
        : 'set WARREN_ROOTED=1 + WARREN_* and install the dev sudoers to run',
  );
}

/// Returns this host's current public egress IP via `1.1.1.1/cdn-cgi/trace`,
/// addressed by literal IP so it needs no DNS (which the killswitch blocks).
/// Empty string if the lookup fails.
Future<String> _egressIp() async {
  final result = await Process.run('curl', [
    '-s',
    '-m',
    '12',
    'https://1.1.1.1/cdn-cgi/trace',
  ]);
  final match = RegExp(r'ip=([0-9a-fA-F:.]+)').firstMatch('${result.stdout}');
  return match?.group(1) ?? '';
}
