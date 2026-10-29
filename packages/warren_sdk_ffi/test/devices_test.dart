import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:warren_sdk_ffi/src/device_revocation.dart';
import 'package:warren_sdk_ffi/src/engine_mapping.dart';
import 'package:warren_sdk_ffi/src/rust/api/client.dart' as rust;
import 'package:warren_sdk_ffi/src/rust/api/datapath.dart' as rust_session;
import 'package:warren_sdk_ffi/src/rust/api/device.dart';
import 'package:warren_sdk_ffi/src/rust/api/error.dart';
import 'package:warren_sdk_ffi/src/warren_client_ffi.dart';
import 'package:warren_sdk_platform_interface/warren_sdk_platform_interface.dart';

/// Device registry tests for the in-process bridge. They need no native
/// engine: the generated DTOs are plain data classes, and the opaque engine
/// client and session are faked at their generated interfaces.
void main() {
  group('mapEngineError types each device refusal', () {
    WarrenError mapped(DeviceRefusalDto refusal) => mapEngineError(
          WarrenFfiError(
            kind: WarrenErrorKind.api,
            message: 'refused',
            device: refusal,
          ),
        );

    test('a revocation', () {
      expect(mapped(DeviceRefusalDto.revoked), isA<WarrenDeviceRevokedError>());
    });

    test('the device cap', () {
      expect(
        mapped(DeviceRefusalDto.limitReached),
        isA<WarrenDeviceLimitReachedError>(),
      );
    });

    test('a malformed identifier', () {
      expect(
        mapped(DeviceRefusalDto.invalidId),
        isA<WarrenInvalidDeviceIdError>(),
      );
    });
  });

  group('device list mapping', () {
    test('carries every field, days as UTC midnight', () {
      final list = deviceListFromDto(
        const DeviceListDto(
          devices: [
            DeviceDto(
              deviceId: 'AAAAAAAAAAAAAAAAAAAAAA',
              name: 'quiet otter',
              platform: DevicePlatformDto.ios,
              appVersion: '1.2.0',
              registeredOn: '2026-10-01',
              lastSeenOn: '2026-10-28',
              thisDevice: true,
            ),
          ],
          olderClientSeenOn: '2026-10-27',
        ),
      );

      expect(
        list,
        WarrenDeviceList(
          devices: [
            WarrenDevice(
              deviceId: 'AAAAAAAAAAAAAAAAAAAAAA',
              name: 'quiet otter',
              platform: WarrenDevicePlatform.ios,
              appVersion: '1.2.0',
              registeredOn: DateTime.utc(2026, 10, 1),
              lastSeenOn: DateTime.utc(2026, 10, 28),
              isThisDevice: true,
            ),
          ],
          olderClientSeenOn: DateTime.utc(2026, 10, 27),
        ),
      );
    });

    test('keeps the older-client day absent when the registry has none', () {
      final list = deviceListFromDto(const DeviceListDto(devices: []));

      expect(list.olderClientSeenOn, isNull);
      expect(list.devices, isEmpty);
    });

    test('maps each platform to its own name', () {
      for (final platform in DevicePlatformDto.values) {
        expect(devicePlatformFromDto(platform).name, platform.name);
      }
    });

    test('refuses a day that is not YYYY-MM-DD', () {
      for (final day in ['2026-10-28T10:00:00Z', '28/10/2026', '']) {
        expect(
          () => registryDay(day),
          throwsA(
            isA<WarrenApiError>()
                .having((e) => e.code, 'code', 'api/malformed-device-list'),
          ),
          reason: day,
        );
      }
    });
  });

  group('DeviceRevocationWatch', () {
    test('emits the first answer, then only the change to revoked', () async {
      final answers = [false, false, true];
      var asked = 0;
      final watch = DeviceRevocationWatch(
        () async => answers[asked++ % answers.length],
        every: const Duration(milliseconds: 5),
      );

      final seen = await watch.stream.take(2).toList();

      expect(seen, [false, true]);
      await watch.close();
    });

    test('stops asking once revoked, and replays it to a late listener',
        () async {
      var asked = 0;
      final watch = DeviceRevocationWatch(
        () async {
          asked++;
          return true;
        },
        every: const Duration(milliseconds: 5),
      );
      final sub = watch.stream.listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await sub.cancel();

      expect(asked, 1, reason: 'a revocation is never lifted');
      expect(await watch.stream.first, isTrue);
      await watch.close();
    });

    test('asks nothing while nobody listens', () async {
      var asked = 0;
      final watch = DeviceRevocationWatch(
        () async {
          asked++;
          return false;
        },
        every: const Duration(milliseconds: 5),
      );
      final sub = watch.stream.listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await sub.cancel();
      final afterCancel = asked;
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(afterCancel, greaterThan(0));
      expect(asked, afterCancel);
      await watch.close();
    });

    test('a failing check emits nothing and is asked again', () async {
      var asked = 0;
      final watch = DeviceRevocationWatch(
        () async {
          asked++;
          if (asked == 1) throw StateError('bridge fault');
          return true;
        },
        every: const Duration(milliseconds: 5),
      );

      expect(await watch.stream.first, isTrue);
      expect(asked, greaterThan(1));
      await watch.close();
    });
  });

  group('FfiClientHandle device calls', () {
    late _FakeClient engine;

    setUp(() => engine = _FakeClient());

    FfiClientHandle handle({String? deviceId = 'AAAAAAAAAAAAAAAAAAAAAA'}) =>
        FfiClientHandle(
          engine,
          'wbFake',
          deviceId: deviceId,
          revocationCheck: const Duration(milliseconds: 5),
        );

    test('lists the devices mapped to the public model', () async {
      final list = await handle().listDevices();

      expect(list.thisDevice?.name, 'quiet otter');
      expect(list.thisDevice?.lastSeenOn, DateTime.utc(2026, 10, 28));
    });

    test('forwards a rename and a revocation by identifier', () async {
      final client = handle();

      await client.renameDevice('BBBBBBBBBBBBBBBBBBBBBB', 'loud heron');
      await client.revokeDevice('BBBBBBBBBBBBBBBBBBBBBB');

      expect(engine.renamed, ('BBBBBBBBBBBBBBBBBBBBBB', 'loud heron'));
      expect(engine.revoked, 'BBBBBBBBBBBBBBBBBBBBBB');
    });

    test('surfaces a malformed identifier as its typed error', () async {
      engine.refusal = DeviceRefusalDto.invalidId;

      await expectLater(
        handle().revokeDevice('nope'),
        throwsA(isA<WarrenInvalidDeviceIdError>()),
      );
    });

    test('forgets the device and reads the cap through the engine', () async {
      engine.limitReached = true;
      final client = handle();

      await client.forgetDevice();

      expect(engine.forgotten, isTrue);
      expect(await client.deviceLimitReached(), isTrue);
    });

    test('reports the engine revocation on its stream', () async {
      engine.revokedAnswer = true;

      expect(await handle().deviceRevoked.first, isTrue);
    });

    test('a client without a device is never revoked and asks nothing',
        () async {
      engine.revokedAnswer = true;

      expect(await handle(deviceId: null).deviceRevoked.first, isFalse);
      expect(engine.revocationChecks, 0);
    });

    test('a revocation ends a live proxy session on its fatal cause', () async {
      final client = handle();
      final session = await client.connect(
        const ExitInfo(
          id: 'e1',
          country: 'RO',
          city: 'Cluj',
          supportsIpv6: true,
        ),
        ConnectMode.proxy,
        const ConnectOptions(),
      );
      expect(
        await session.states.firstWhere((s) => s is Connected),
        const Connected(),
      );

      engine.revokedAnswer = true;

      expect(
        await session.states.firstWhere((s) => s is ConnectionFailed),
        connectionFailed(WarrenFatalCause.deviceRevoked),
      );
      await session.disconnect();
    });
  });
}

class _FakeClient implements rust.WarrenClientFrb {
  (String, String)? renamed;
  String? revoked;
  bool forgotten = false;
  bool limitReached = false;
  bool revokedAnswer = false;
  int revocationChecks = 0;
  DeviceRefusalDto? refusal;

  Never _refuse() => throw WarrenFfiError(
        kind: WarrenErrorKind.api,
        message: 'refused',
        device: refusal,
      );

  @override
  Future<DeviceListDto> listDevices() async => const DeviceListDto(
        devices: [
          DeviceDto(
            deviceId: 'AAAAAAAAAAAAAAAAAAAAAA',
            name: 'quiet otter',
            platform: DevicePlatformDto.linux,
            appVersion: '1.2.0',
            registeredOn: '2026-10-01',
            lastSeenOn: '2026-10-28',
            thisDevice: true,
          ),
        ],
      );

  @override
  Future<void> renameDevice({
    required String deviceId,
    required String name,
  }) async {
    if (refusal != null) _refuse();
    renamed = (deviceId, name);
  }

  @override
  Future<void> revokeDevice({required String deviceId}) async {
    if (refusal != null) _refuse();
    revoked = deviceId;
  }

  @override
  Future<void> forgetDevice() async => forgotten = true;

  @override
  Future<bool> deviceLimitReached() async => limitReached;

  @override
  Future<bool> deviceRevoked() async {
    revocationChecks++;
    return revokedAnswer;
  }

  @override
  Future<rust_session.WarrenSessionFrb> connectProxy({
    required String exitPubkeyHex,
    required List<String> failoverExitPubkeysHex,
    required String socks5Listen,
    String? httpListen,
    String? dnsServer,
  }) async =>
      _FakeSession();

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakeSession implements rust_session.WarrenSessionFrb {
  // Like the engine's, the stream stays open for the session's life.
  @override
  Stream<rust_session.ConnectionStateDto> states() => Stream.multi(
        (c) => c.add(rust_session.ConnectionStateDto.connected),
      );

  @override
  Stream<rust_session.MigrationEventDto> migrationEvents() =>
      const Stream.empty();

  @override
  Future<String> socks5Endpoint() async => '127.0.0.1:1080';

  @override
  Future<String?> httpEndpoint() async => null;

  @override
  Future<String> proxyUsername() async => 'warren';

  @override
  Future<String> proxyPassword() async => 'test';

  @override
  Future<void> disconnect() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
