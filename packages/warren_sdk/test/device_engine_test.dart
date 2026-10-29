@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:warren_sdk/warren_sdk.dart';

import 'support/engine.dart';

/// The device registry surface over the real engine, offline: registration
/// is wired at build time and the identity is kept on disk, and the typed
/// refusals the bridge maps come from the engine itself. The calls that reach
/// the account's registry are live-only (`account_live_test.dart` territory).
void main() {
  if (!tryRegisterEngine()) {
    fail(
      'Native engine library not found at ${engineLibraryPath()}. Build it:\n'
      '  (cd native/warren_sdk_frb && cargo build --release)',
    );
  }

  late Directory stateDir;
  late String mnemonic;

  setUpAll(() async => mnemonic = await WarrenIdentity.generateMnemonic());

  setUp(() async {
    stateDir = await Directory.systemTemp.createTemp('warren-device-test-');
  });

  tearDown(() async {
    if (stateDir.existsSync()) await stateDir.delete(recursive: true);
  });

  Future<WarrenClient> client({String? appVersion = '1.2.0', bool? dir}) async {
    final created = await WarrenClient.create(
      mnemonic: mnemonic,
      apiBase: Uri.parse('https://api.example.test'),
      serverPubkeyPin: '00' * 32,
      stateDir: (dir ?? true) ? stateDir.path : null,
      appVersion: appVersion,
    );
    addTearDown(created.dispose);
    return created;
  }

  test('an app version registers the install under a kept identity', () async {
    final first = await client();
    final second = await client();

    final id = first.devices.thisDeviceId;
    expect(id, matches(RegExp(r'^[A-Za-z0-9_-]{22}$')));
    expect(second.devices.thisDeviceId, id, reason: 'one install, one device');
    expect(File('${stateDir.path}/device').existsSync(), isTrue);
  });

  test('a client without an app version registers no device', () async {
    final plain = await client(appVersion: null);

    expect(plain.devices.thisDeviceId, isNull);
    expect(await plain.devices.revoked.first, isFalse);
  });

  test('an app version without a state directory is refused', () async {
    await expectLater(
      client(dir: false),
      throwsA(isA<WarrenApiError>()),
    );
  });

  test('a forgotten device is drawn anew by the next client', () async {
    final revoked = await client();
    final old = revoked.devices.thisDeviceId;

    await revoked.devices.forgetThisDevice();
    final next = await client();

    expect(next.devices.thisDeviceId, isNot(old));
  });

  test('a malformed device id is refused typed by the engine', () async {
    final registered = await client();

    await expectLater(
      registered.devices.revoke('not-a-device'),
      throwsA(isA<WarrenInvalidDeviceIdError>()),
    );
    await expectLater(
      registered.devices.rename('not-a-device', 'quiet otter'),
      throwsA(isA<WarrenInvalidDeviceIdError>()),
    );
  });

  test('a fresh install is neither revoked nor over the cap', () async {
    final registered = await client();

    expect(await registered.devices.revoked.first, isFalse);
    expect(await registered.devices.limitReached(), isFalse);
  });
}
