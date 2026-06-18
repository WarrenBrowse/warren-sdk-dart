// Smoke test: with no wallet, the app shows onboarding and reveals the import
// field. The wallet provider is faked, so no secure storage or native engine is
// touched.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warren_sdk_example/src/app/app.dart';
import 'package:warren_sdk_example/src/providers/wallet.dart';

class _NoWallet extends Wallet {
  @override
  Future<String?> build() async => null;
}

void main() {
  testWidgets('onboarding shows when no wallet exists', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, __) => null,
        overrides: [walletProvider.overrideWith(_NoWallet.new)],
        child: const WarrenExampleApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Warren VPN'), findsOneWidget);
    expect(find.text('Create a new wallet'), findsOneWidget);

    await tester.tap(find.text('I have a recovery phrase'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Import wallet'), findsOneWidget);
  });
}
