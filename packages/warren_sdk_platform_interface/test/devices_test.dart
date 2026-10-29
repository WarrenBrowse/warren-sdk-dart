import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:warren_sdk_platform_interface/warren_sdk_platform_interface.dart';

WarrenDevice _device({
  String id = 'AAAAAAAAAAAAAAAAAAAAAA',
  String name = 'quiet otter',
  bool thisDevice = false,
}) =>
    WarrenDevice(
      deviceId: id,
      name: name,
      platform: WarrenDevicePlatform.linux,
      appVersion: '1.2.0',
      registeredOn: DateTime.utc(2026, 10, 1),
      lastSeenOn: DateTime.utc(2026, 10, 28),
      isThisDevice: thisDevice,
    );

void main() {
  group('device models', () {
    test('a device never renders its identifier or its name', () {
      final rendered = _device(id: 'c2VjcmV0LWRldmljZS1pZA').toString();

      expect(rendered, isNot(contains('c2VjcmV0')));
      expect(rendered, isNot(contains('otter')));
      expect(rendered, contains('linux'));
    });

    test('device equality is value-based', () {
      expect(_device(), equals(_device()));
      expect(_device().hashCode, _device().hashCode);
      expect(_device(), isNot(equals(_device(name: 'loud heron'))));
    });

    test('a list names the device this client runs on', () {
      final mine = _device(id: 'BBBBBBBBBBBBBBBBBBBBBB', thisDevice: true);
      final list = WarrenDeviceList(devices: [_device(), mine]);

      expect(list.thisDevice, mine);
      expect(WarrenDeviceList(devices: [_device()]).thisDevice, isNull);
    });

    test('list equality compares the devices and the older-client day', () {
      final a = WarrenDeviceList(
        devices: [_device()],
        olderClientSeenOn: DateTime.utc(2026, 10, 27),
      );
      final b = WarrenDeviceList(
        devices: [_device()],
        olderClientSeenOn: DateTime.utc(2026, 10, 27),
      );

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(WarrenDeviceList(devices: [_device()]))));
      expect(
        a,
        isNot(
          equals(
            WarrenDeviceList(
              devices: [_device(name: 'loud heron')],
              olderClientSeenOn: DateTime.utc(2026, 10, 27),
            ),
          ),
        ),
      );
    });
  });

  group('device errors', () {
    test('each device refusal carries its own stable code', () {
      expect(const WarrenDeviceRevokedError().code, 'api/device-revoked');
      expect(
        const WarrenDeviceLimitReachedError().code,
        'api/device-limit-reached',
      );
      expect(const WarrenInvalidDeviceIdError().code, 'api/invalid-device-id');
    });

    test('a device refusal is still caught as an API error', () {
      expect(const WarrenDeviceRevokedError(), isA<WarrenApiError>());
      expect(const WarrenDeviceLimitReachedError(), isA<WarrenApiError>());
      expect(const WarrenInvalidDeviceIdError(), isA<WarrenApiError>());
    });
  });

  test('a revoked device fails the connection under its own code', () {
    final failed = connectionFailed(WarrenFatalCause.deviceRevoked);

    expect(failed.code, 'tunnel/device-revoked');
    expect(failed.cause, WarrenFatalCause.deviceRevoked);
  });

  test('the app version takes part in the client configuration', () {
    WarrenClientConfig config(String? version) => WarrenClientConfig(
          mnemonic: 'm',
          apiBase: Uri.parse('https://api.example.com'),
          serverPubkeyPin: 'pin',
          appVersion: version,
        );

    expect(config('1.2.0'), equals(config('1.2.0')));
    expect(config('1.2.0').hashCode, config('1.2.0').hashCode);
    expect(config('1.2.0'), isNot(equals(config('1.3.0'))));
  });

  group('withDeviceRevocation', () {
    test('passes the session states through while the device holds', () async {
      final revoked = StreamController<bool>();
      final merged = withDeviceRevocation(
        Stream.fromIterable(const [Connecting(), Connected()]),
        revoked.stream,
      );

      expect(await merged.toList(), const [Connecting(), Connected()]);
      await revoked.close();
    });

    test('ends the session on the revocation and drops later states', () async {
      final states = StreamController<ConnectionState>();
      final revoked = StreamController<bool>();
      final seen = <ConnectionState>[];
      final done = Completer<void>();
      withDeviceRevocation(states.stream, revoked.stream)
          .listen(seen.add, onDone: done.complete);

      states.add(const Connected());
      await pumpEventQueue();
      revoked
        ..add(false)
        ..add(true);
      await pumpEventQueue();
      states.add(const Reconnecting());
      await done.future;

      expect(seen, [
        const Connected(),
        connectionFailed(WarrenFatalCause.deviceRevoked),
      ]);
      await states.close();
      await revoked.close();
    });

    test('a failing revocation check leaves the session alone', () async {
      final revoked = StreamController<bool>();
      final merged = withDeviceRevocation(
        Stream.fromIterable(const [Connected()]),
        revoked.stream,
      );
      revoked.addError(StateError('check failed'));

      expect(await merged.toList(), const [Connected()]);
      await revoked.close();
    });
  });
}
