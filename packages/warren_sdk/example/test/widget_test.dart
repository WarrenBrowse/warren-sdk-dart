// Smoke test: the app renders and navigates without a native engine. No SDK
// call is made until a button is pressed, so the in-process engine library is
// never loaded here.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warren_sdk_example/src/app/app.dart';
import 'package:warren_sdk_example/src/providers/client.dart';
import 'package:warren_sdk_riverpod/warren_sdk_riverpod.dart';

void main() {
  testWidgets('renders the overview and navigates to Identity', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [warrenClientProvider.overrideWith(createWarrenClient)],
        child: const WarrenExampleApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Overview is the landing screen; no client is configured yet, so the
    // overridden warrenClientProvider resolves to an error and the pill reads
    // "No client".
    expect(find.text('What to test'), findsOneWidget);
    expect(find.text('No client'), findsOneWidget);

    // The navigation rail switches the active screen.
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Identity'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Generate mnemonic'), findsOneWidget);
  });
}
