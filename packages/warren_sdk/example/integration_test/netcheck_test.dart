// Live validation of the in-app network check: a proxy session binds a local
// HTTP CONNECT endpoint, and the public IP seen through that endpoint differs
// from the real one. This is the exact mechanism the Network check screen uses.
//
// The tunnel egress is intermittent, so the probe retries, exactly like the
// app's `_safeProbe`. The IP echo is Cloudflare's `cdn-cgi/trace`, reached by IP
// literal on 443 so it needs no tunnel DNS.
//
// Env-gated like live_test.dart. Run it with:
//
//   WARREN_MNEMONIC="word1 …" WARREN_SERVER_PIN=<hex> \
//     fvm flutter test integration_test/netcheck_test.dart -d macos
//
// No secret is logged; only public egress IPs are compared.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:warren_sdk_desktop/warren_sdk_desktop.dart';
import 'package:warren_sdk_example/src/providers/constants.dart';
import 'package:warren_sdk_riverpod/warren_sdk_riverpod.dart';

Future<String?> _fetchIpOnce({String? proxy}) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 6)
    ..badCertificateCallback = (_, __, ___) => true;
  if (proxy != null) client.findProxy = (_) => 'PROXY $proxy';
  try {
    final request =
        await client.getUrl(Uri.parse('https://1.1.1.1/cdn-cgi/trace'));
    final response = await request.close().timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;
    final body = await response.cast<List<int>>().expand((b) => b).toList();
    for (final line in String.fromCharCodes(body).split('\n')) {
      if (line.startsWith('ip=')) return line.substring(3).trim();
    }
    return null;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

Future<String?> fetchIp({String? proxy, int tries = 6}) async {
  for (var i = 0; i < tries; i++) {
    final ip = await _fetchIpOnce(proxy: proxy);
    if (ip != null) return ip;
  }
  return null;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final env = Platform.environment;
  final mnemonic = env['WARREN_MNEMONIC'];
  final pin = env['WARREN_SERVER_PIN'] ?? AppEnv.serverPubkeyPin;
  final apiBase = env['WARREN_API_BASE'] ?? AppEnv.apiBase;
  final hasCreds = mnemonic != null && mnemonic.isNotEmpty && pin.isNotEmpty;

  testWidgets(
    'proxy exposes HTTP CONNECT and changes the public IP',
    (tester) async {
      DesktopWarrenSdkPlatform.registerWith();

      String? directIp;
      String? tunnelIp;
      String? httpEndpoint;
      ConnectionState? finalState;

      await tester.runAsync(() async {
        final client = await WarrenClient.create(
          mnemonic: mnemonic!,
          apiBase: Uri.parse(apiBase),
          serverPubkeyPin: pin,
        );
        final exits = await client.listExits();

        directIp = await fetchIp(tries: 2);

        final session = await client.connect(
          exits.first,
          options: const ConnectOptions(httpListen: '127.0.0.1:0'),
        );
        finalState = await session.states
            .firstWhere((s) => s is Connected || s is ConnectionFailed)
            .timeout(const Duration(seconds: 60));
        httpEndpoint = session.endpoints?.http;
        if (httpEndpoint != null) {
          tunnelIp = await fetchIp(proxy: httpEndpoint);
        }

        await session.disconnect();
        await client.dispose();
      });

      expect(finalState, isA<Connected>());
      expect(directIp, isNotNull, reason: 'real IP lookup should succeed');
      expect(
        httpEndpoint,
        isNotNull,
        reason: 'proxy session should bind an HTTP CONNECT endpoint',
      );
      expect(tunnelIp, isNotNull, reason: 'tunnel IP lookup should succeed');
      expect(
        tunnelIp,
        isNot(equals(directIp)),
        reason: 'egress IP through the tunnel must differ from the real one',
      );
      // skip reason: set WARREN_MNEMONIC + WARREN_SERVER_PIN to run this live.
    },
    skip: !hasCreds,
  );
}
