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
  ProxyEndpoints? get endpoints => const ProxyEndpoints(socks5: '127.0.0.1:1');

  @override
  Stream<ConnectionState> get states =>
      Stream.fromIterable([const Connecting(), const Connected()]);

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
