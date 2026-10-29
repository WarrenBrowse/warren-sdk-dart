import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warren_sdk_platform_interface/warren_sdk_platform_interface.dart';
import 'package:warren_sdk_riverpod/warren_sdk_riverpod.dart';

void main() {
  setUp(() {
    WarrenSdkPlatform.instance = _FakePlatform();
  });

  ProviderContainer containerWithClient() => ProviderContainer(
        overrides: [
          warrenClientProvider.overrideWith(
            (ref) => WarrenClient.create(
              mnemonic: 'm',
              apiBase: Uri.parse('https://api.example.com'),
              serverPubkeyPin: 'pin',
            ),
          ),
        ],
      );

  test('warrenClientProvider throws without an override', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await expectLater(
      container.read(warrenClientProvider.future),
      throwsUnimplementedError,
    );
  });

  test('subscriptionProvider reads through the client', () async {
    final container = containerWithClient();
    addTearDown(container.dispose);
    final sub = await container.read(subscriptionProvider.future);
    expect(sub.expiresAtUnix, 100);
  });

  test('exitsProvider returns the verified exits', () async {
    final container = containerWithClient();
    addTearDown(container.dispose);
    final exits = await container.read(exitsProvider.future);
    expect(exits.single.city, 'Bucharest');
  });

  test('devicesProvider reads the account devices through the client',
      () async {
    final container = containerWithClient();
    addTearDown(container.dispose);
    final list = await container.read(devicesProvider.future);
    expect(list.thisDevice?.name, 'quiet otter');
  });

  test('deviceRevokedProvider mirrors the revocation of this device', () async {
    final container = containerWithClient();
    addTearDown(container.dispose);
    final subscription = container.listen(deviceRevokedProvider, (_, __) {});
    addTearDown(subscription.close);
    expect(await container.read(deviceRevokedProvider.future), isTrue);
  });

  test('connectionStateProvider mirrors a session state stream', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final session = WarrenSession(_FakeSessionHandle());
    // Keep the provider alive so it subscribes to the source stream.
    final subscription =
        container.listen(connectionStateProvider(session), (_, __) {});
    addTearDown(subscription.close);
    final first = await container.read(connectionStateProvider(session).future);
    expect(first, const Connecting());
  });
}

class _FakeSessionHandle implements WarrenSessionHandle {
  @override
  ProxyEndpoints? get endpoints => const ProxyEndpoints(
        socks5: '127.0.0.1:1',
        credentials: ProxyCredentials(username: 'warren', password: 'test'),
      );

  @override
  Stream<ConnectionState> get states =>
      Stream.fromIterable([const Connecting(), const Connected()]);

  @override
  Stream<MigrationEvent> get migrationEvents => const Stream.empty();

  @override
  Future<WarrenForwardedPort> forwardPort(
    ForwardProtocol proto,
    int internalPort,
    String localTarget, {
    PortFollowPolicy policy = PortFollowPolicy.followBestEffort,
    int? pinnedExternalPort,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> disconnect() async {}
}

class _FakeClientHandle implements WarrenClientHandle {
  @override
  final String address = 'wbFake';

  @override
  Future<SubscriptionInfo> subscription() async =>
      const SubscriptionInfo(expiresAtUnix: 100);

  @override
  Future<void> redeemVoucher(String secret) async {}

  @override
  Future<void> deleteAccount() async {}

  @override
  Future<TunnelCheck> checkTunnel() async =>
      const TunnelCheck(ip: '203.0.113.7', isExit: true);

  @override
  Future<List<ExitInfo>> listExits() async => const [
        ExitInfo(
          id: 'e',
          country: 'RO',
          city: 'Bucharest',
          supportsIpv6: true,
        ),
      ];

  @override
  Future<WarrenSessionHandle> connect(
    ExitInfo exit,
    ConnectMode mode,
    ConnectOptions options,
  ) async =>
      _FakeSessionHandle();

  @override
  Future<void> dispose() async {}

  @override
  final String? deviceId = 'AAAAAAAAAAAAAAAAAAAAAA';

  @override
  Future<String?> deviceName() async => 'quiet otter';

  @override
  Future<WarrenDeviceList> listDevices() async => WarrenDeviceList(
        devices: [
          WarrenDevice(
            deviceId: 'AAAAAAAAAAAAAAAAAAAAAA',
            name: 'quiet otter',
            platform: WarrenDevicePlatform.macos,
            appVersion: '1.2.0',
            registeredOn: DateTime.utc(2026, 10, 1),
            lastSeenOn: DateTime.utc(2026, 10, 28),
            isThisDevice: true,
          ),
        ],
      );

  @override
  Future<void> renameDevice(String deviceId, String name) async {}

  @override
  Future<void> revokeDevice(String deviceId) async {}

  @override
  Future<void> forgetDevice() async {}

  @override
  Future<bool> deviceLimitReached() async => false;

  @override
  Stream<bool> get deviceRevoked => Stream.value(true);
}

class _FakePlatform extends WarrenSdkPlatform {
  Never _unused() => throw UnimplementedError();

  @override
  Future<String> generateMnemonic() => _unused();

  @override
  Future<String> addressFromMnemonic(String mnemonic) => _unused();

  @override
  Future<String> ss58Encode(String publicKeyHex) => _unused();

  @override
  Future<String> ss58Decode(String address) => _unused();

  @override
  Future<WarrenClientHandle> createClient(WarrenClientConfig config) async =>
      _FakeClientHandle();
}
