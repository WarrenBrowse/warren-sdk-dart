// Mode B (system VPN) live validation against the privileged warrend daemon and
// a real exit. THIS REROUTES ALL HOST TRAFFIC through the tunnel for the
// duration of the test; the daemon restores routing + pf on disconnect (and on
// its own SIGINT/SIGTERM fail-safe).
//
// Host-affecting, so it is opt-in: it runs only when WARREN_RUN_MODE_B=1 and a
// mnemonic is set, with the daemon already listening:
//
//   sudo native/warrend/target/release/warrend
//   WARREN_MNEMONIC="word1 …" WARREN_RUN_MODE_B=1 \
//     fvm flutter test integration_test/mode_b_test.dart -d macos
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:warren_sdk_desktop/warren_sdk_desktop.dart';
import 'package:warren_sdk_example/src/providers/constants.dart';
import 'package:warren_sdk_riverpod/warren_sdk_riverpod.dart';

Future<String?> _egressIp() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.getUrl(Uri.parse('https://api.ipify.org'));
    final resp = await req.close();
    return (await resp.transform(utf8.decoder).join()).trim();
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final env = Platform.environment;
  final mnemonic = env['WARREN_MNEMONIC'];
  final optedIn = env['WARREN_RUN_MODE_B'] == '1';
  final socket = env['WARREN_DAEMON_SOCKET'] ?? AppEnv.daemonSocket;
  final ready = optedIn &&
      mnemonic != null &&
      mnemonic.isNotEmpty &&
      File(socket).existsSync();

  testWidgets(
    'system-VPN captures all traffic, then restores routing',
    (
      tester,
    ) async {
      DesktopWarrenSdkPlatform.registerWith(socketPath: socket);

      String? baseline;
      String? tunnelIp;
      var connected = false;

      await tester.runAsync(() async {
        final client = await WarrenClient.create(
          mnemonic: mnemonic!,
          apiBase: Uri.parse(AppEnv.apiBase),
          serverPubkeyPin: AppEnv.serverPubkeyPin,
        );
        final exits = await client.listExits();
        baseline = await _egressIp();

        // connect() drives the daemon and internally awaits `Connected` before
        // returning, so a returned session means the tunnel is already up (the
        // daemon's broadcast state stream does not replay the initial Connected).
        final session = await client.connect(
          exits.first,
          mode: ConnectMode.systemVpn,
        );
        connected = true;
        try {
          // No local proxy endpoints in system-VPN mode.
          expect(session.endpoints, isNull);

          // The first probes after a fresh tunnel can drop (TCP/TLS/PMTU warmup),
          // so poll until egress becomes the exit's address.
          for (var i = 0; i < 6; i++) {
            tunnelIp = await _egressIp();
            if (tunnelIp != null && tunnelIp != baseline) break;
            await Future<void>.delayed(const Duration(seconds: 2));
          }
        } finally {
          // Always restore the host network, even on failure.
          await session.disconnect();
          await client.dispose();
        }
      });

      expect(connected, isTrue, reason: 'system-VPN connect did not reach up');
      expect(baseline, isNotNull);
      expect(tunnelIp, isNotNull);
      expect(
        tunnelIp,
        isNot(baseline),
        reason: 'egress did not become the exit',
      );
    },
    skip: !ready,
  );
}
