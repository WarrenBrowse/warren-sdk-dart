@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:warren_sdk/warren_sdk.dart';
import 'package:warren_sdk_desktop/warren_sdk_desktop.dart';

import 'support/daemon.dart';
import 'support/egress.dart';
import 'support/engine.dart';

/// End-to-end Mode B through the public facade: registers the desktop platform,
/// then drives a real system-VPN tunnel entirely via `WarrenClient.connect(
/// mode: systemVpn)`. Unlike `daemon_tun_rooted_live_test`, which talks to the
/// daemon directly, this proves the facade wiring (`DesktopWarrenSdkPlatform` ->
/// daemon IPC) carries real egress.
///
/// Opt-in via `WARREN_ROOTED=1` (plus the usual `WARREN_*`); runs the daemon with
/// `sudo -n`, which needs the dev sudoers drop-in installed first.
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
    'system-VPN through the facade reaches a real exit',
    () {
      test('connect(systemVpn) carries egress through the exit', () async {
        expect(
          tryRegisterEngine(),
          isTrue,
          reason: 'build native/warren_sdk_frb',
        );

        final physicalEgress = await egressIp();
        expect(physicalEgress, isNotEmpty, reason: 'no baseline egress IP');

        final daemon = await launchRootedDaemon(daemonBin);
        addTearDown(() async {
          daemon.process.kill();
          await daemon.process.exitCode;
        });

        // Register the desktop Mode B platform over the in-process engine, with
        // the connector pointed at the just-launched daemon's socket.
        DesktopWarrenSdkPlatform.registerWith(
          daemonConnector: () => connectDaemonSocket(daemon.socketPath),
        );

        final client = await WarrenClient.create(
          mnemonic: mnemonic!,
          apiBase: Uri.parse(apiBase!),
          serverPubkeyPin: pin!,
        );
        addTearDown(client.dispose);

        final exits = await client.listExits();
        expect(exits, isNotEmpty);
        final exit = exits.first;

        final session = await client.connect(exit, mode: ConnectMode.systemVpn);
        addTearDown(session.disconnect);

        // A system-VPN session exposes no local proxy endpoints.
        expect(session.endpoints, isNull);

        final tunnelEgress = await egressIpWithRetry();
        expect(
          tunnelEgress,
          isNotEmpty,
          reason: 'no egress through the facade system-VPN session',
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
