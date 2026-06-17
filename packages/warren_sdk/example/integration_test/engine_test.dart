// Runtime validation: drives the real cargokit-bundled engine in-process to
// prove it loads and runs end-to-end. No account or network needed.
//
// Run on a desktop/device:
//   fvm flutter test integration_test/engine_test.dart -d macos
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:warren_sdk_desktop/warren_sdk_desktop.dart';
import 'package:warren_sdk_riverpod/warren_sdk_riverpod.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('bundled engine generates a valid 12-word mnemonic', (
    tester,
  ) async {
    // Same registration the app does at startup; the control plane runs in the
    // in-process engine.
    DesktopWarrenSdkPlatform.registerWith();

    String? mnemonic;
    Object? error;
    await tester.runAsync(() async {
      try {
        mnemonic = await WarrenIdentity.generateMnemonic();
      } catch (e) {
        error = e;
      }
    });

    expect(error, isNull, reason: 'engine threw: $error');
    expect(mnemonic, isNotNull);
    expect(mnemonic!.trim().split(RegExp(r'\s+')).length, 12);

    // A second helper proves a full round-trip through the engine.
    String? address;
    await tester.runAsync(() async {
      try {
        address = await WarrenIdentity.addressFromMnemonic(mnemonic!);
      } catch (e) {
        error = e;
      }
    });
    expect(error, isNull, reason: 'addressFromMnemonic threw: $error');
    expect(address, startsWith('wb'));
  });
}
