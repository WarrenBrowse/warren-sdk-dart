// Full-app end-to-end UI test against the real backend: onboarding, the connect
// screen, the location picker, a real proxy connection, account, settings and
// the developer tools, asserting no stray exception along the way.
//
// Env-gated on a subscribed test wallet:
//   WARREN_MNEMONIC="word1 …" \
//     fvm flutter test integration_test/app_e2e_test.dart -d macos
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:warren_sdk_desktop/warren_sdk_desktop.dart';
import 'package:warren_sdk_example/src/app/app.dart';
import 'package:warren_sdk_example/src/providers/client.dart';
import 'package:warren_sdk_example/src/providers/constants.dart';
import 'package:warren_sdk_riverpod/warren_sdk_riverpod.dart';

const _store = FlutterSecureStorage(
  mOptions: MacOsOptions(useDataProtectionKeyChain: false),
);

/// Pumps real frames until [finder] matches or the timeout elapses. Unlike
/// pumpAndSettle it tolerates the perpetual spinners on the connect screen.
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 45),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 200));
  }
  if (finder.evaluate().isEmpty) {
    final visible = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    throw TestFailure(
      '${reason ?? 'timed out'} — on screen: $visible',
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final mnemonic = Platform.environment['WARREN_MNEMONIC'];
  final ready = mnemonic != null && mnemonic.isNotEmpty;

  testWidgets(
    'onboard, connect (proxy), browse every screen',
    (tester) async {
      // Clean slate so onboarding shows.
      await _store.delete(key: AppEnv.mnemonicKey);
      DesktopWarrenSdkPlatform.registerWith(socketPath: AppEnv.daemonSocket);

      await tester.pumpWidget(
        ProviderScope(
          retry: (_, __) => null,
          overrides: [warrenClientProvider.overrideWith(createWarrenClient)],
          child: const WarrenExampleApp(),
        ),
      );

      // --- Onboarding: import the subscribed test wallet ---
      await pumpUntil(tester, find.text('Create a new wallet'));
      await tester.tap(find.text('I have a recovery phrase'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, mnemonic!);
      await tester.tap(find.widgetWithText(FilledButton, 'Import wallet'));

      // --- Main app: connect screen ---
      await pumpUntil(tester, find.text('Account'), reason: 'reach main app');
      await pumpUntil(
        tester,
        find.textContaining('Active'),
        reason: 'subscription active',
      );

      // --- Location picker: exits load, pick the first city ---
      await pumpUntil(tester, find.text('Location'));
      await tester.tap(find.text('Location'));
      await pumpUntil(tester, find.text('Select location'));
      await pumpUntil(
        tester,
        find.byIcon(Icons.radio_button_unchecked),
        reason: 'exits listed',
      );
      await tester.tap(find.byIcon(Icons.radio_button_unchecked).first);
      await pumpUntil(
        tester,
        find.text('Not connected'),
        reason: 'back to home',
      );

      // --- Connect (proxy) and reach Secured ---
      await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
      await pumpUntil(
        tester,
        find.text('Secured'),
        timeout: const Duration(seconds: 80),
        reason: 'proxy connect reaches Secured',
      );
      expect(find.textContaining('SOCKS5'), findsOneWidget);

      // --- Disconnect ---
      await tester.tap(find.widgetWithText(FilledButton, 'Disconnect'));
      await pumpUntil(tester, find.text('Not connected'), reason: 'disconnect');

      // --- Account tab ---
      await tester.tap(find.text('Account'));
      await pumpUntil(tester, find.text('Subscription'));
      expect(find.text('Wallet'), findsOneWidget);

      // --- Settings -> Developer -> Identity helpers -> Generate ---
      await tester.tap(find.text('Settings'));
      await pumpUntil(tester, find.text('Developer tools'));
      await tester.tap(find.text('Developer tools'));
      await pumpUntil(tester, find.text('Identity helpers'));
      await tester.tap(find.text('Identity helpers'));
      await pumpUntil(tester, find.text('Generate mnemonic'));
      await tester.tap(find.widgetWithText(FilledButton, 'Generate'));
      await pumpUntil(tester, find.text('Done'), reason: 'identity generate');

      expect(tester.takeException(), isNull);
    },
    skip: !ready,
  );
}
