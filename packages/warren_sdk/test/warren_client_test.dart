import 'package:flutter_test/flutter_test.dart';
import 'package:warren_sdk/warren_sdk.dart';
import 'package:warren_sdk_platform_interface/warren_sdk_platform_interface.dart';

void main() {
  group('WarrenClient.selectExit', () {
    final ro = ExitInfo(
      id: 'a' * 32,
      country: 'RO',
      city: 'Bucharest',
      supportsIpv6: true,
    );
    final se = ExitInfo(
      id: 'b' * 32,
      country: 'SE',
      city: 'Stockholm',
      supportsIpv6: false,
    );
    final exits = [ro, se];

    test('returns the first exit matching a country query', () {
      expect(
        WarrenClient.selectExit(exits, const ExitQuery(country: 'SE')),
        equals(se),
      );
    });

    test('filters on the IPv6 capability', () {
      expect(
        WarrenClient.selectExit(exits, const ExitQuery(requireIpv6: true)),
        equals(ro),
      );
    });

    test('combines predicates with AND and returns null when none match', () {
      expect(
        WarrenClient.selectExit(
          exits,
          const ExitQuery(country: 'SE', requireIpv6: true),
        ),
        isNull,
      );
    });

    test('returns null for an empty exit list', () {
      expect(
        WarrenClient.selectExit(const [], const ExitQuery(country: 'RO')),
        isNull,
      );
    });
  });

  group('WarrenClient lifecycle over a fake platform', () {
    late _FakePlatform platform;
    late _FakeClientHandle handle;

    setUp(() {
      handle = _FakeClientHandle();
      platform = _FakePlatform(handle);
      WarrenSdkPlatform.instance = platform;
    });

    Future<WarrenClient> create() => WarrenClient.create(
          mnemonic: 'twelve word mnemonic here',
          apiBase: Uri.parse('https://api.example.com'),
          serverPubkeyPin: 'deadbeef',
          multihopRootPin: 'feed',
        );

    test('create forwards the config and exposes the bound address', () async {
      final client = await create();
      expect(client.address, 'wbFakeAddress');
      expect(platform.lastConfig?.mnemonic, 'twelve word mnemonic here');
      expect(platform.lastConfig?.apiBase.host, 'api.example.com');
      expect(platform.lastConfig?.serverPubkeyPin, 'deadbeef');
      expect(platform.lastConfig?.multihopRootPin, 'feed');
    });

    test('create forwards DAITA configuration when requested', () async {
      await WarrenClient.create(
        mnemonic: 'm',
        apiBase: Uri.parse('https://api.example.com'),
        serverPubkeyPin: 'pin',
        daita: true,
        daitaMachine: 'curated-1',
      );
      expect(platform.lastConfig?.daita, isTrue);
      expect(platform.lastConfig?.daitaMachine, 'curated-1');
    });

    test('create defaults DAITA off', () async {
      await create();
      expect(platform.lastConfig?.daita, isFalse);
      expect(platform.lastConfig?.daitaMachine, isNull);
    });

    test('create requests IPv6 by default and can opt out', () async {
      await create();
      expect(platform.lastConfig?.requestIpv6, isTrue);

      await WarrenClient.create(
        mnemonic: 'm',
        apiBase: Uri.parse('https://api.example.com'),
        serverPubkeyPin: 'pin',
        requestIpv6: false,
      );
      expect(platform.lastConfig?.requestIpv6, isFalse);
    });

    test('subscription surfaces the engine snapshot', () async {
      final client = await create();
      final sub = await client.subscription();
      expect(sub.expiresAtUnix, 1893456000);
      expect(sub.isActive, isTrue);
    });

    test('redeemVoucher forwards the secret', () async {
      final client = await create();
      await client.redeemVoucher('VOUCHER-123');
      expect(handle.redeemedSecret, 'VOUCHER-123');
    });

    test('listExits returns the verified exits', () async {
      final client = await create();
      final exits = await client.listExits();
      expect(exits, hasLength(1));
      expect(exits.single.city, 'Bucharest');
    });

    test('connect wraps the session handle and forwards disconnect', () async {
      final client = await create();
      final exit = (await client.listExits()).single;

      final session = await client.connect(exit);
      expect(handle.connectedExit, exit);
      expect(session.endpoints?.socks5, '127.0.0.1:1080');
      expect(await session.states.first, const Connected(sinceUnix: 7));

      await session.disconnect();
      expect(handle.session.disconnected, isTrue);
    });

    test('dispose releases the handle', () async {
      final client = await create();
      await client.dispose();
      expect(handle.disposed, isTrue);
    });

    test('an engine error propagates as its sealed type', () async {
      handle.subscriptionError = const WarrenApiError(
        code: 'api/engine',
        message: 'server unavailable',
      );
      final client = await create();
      await expectLater(
        client.subscription(),
        throwsA(isA<WarrenApiError>()),
      );
    });
  });
}

class _FakeSessionHandle implements WarrenSessionHandle {
  bool disconnected = false;

  @override
  ProxyEndpoints? get endpoints =>
      const ProxyEndpoints(socks5: '127.0.0.1:1080');

  @override
  Stream<ConnectionState> get states =>
      Stream.value(const Connected(sinceUnix: 7));

  @override
  Future<void> disconnect() async => disconnected = true;
}

class _FakeClientHandle implements WarrenClientHandle {
  WarrenError? subscriptionError;
  String? redeemedSecret;
  bool disposed = false;
  ExitInfo? connectedExit;
  final _FakeSessionHandle session = _FakeSessionHandle();

  @override
  final String address = 'wbFakeAddress';

  @override
  Future<SubscriptionInfo> subscription() async {
    final error = subscriptionError;
    if (error != null) throw error;
    return const SubscriptionInfo(expiresAtUnix: 1893456000);
  }

  @override
  Future<void> redeemVoucher(String secret) async => redeemedSecret = secret;

  @override
  Future<List<ExitInfo>> listExits() async => const [
        ExitInfo(
          id: 'e1',
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
  ) async {
    connectedExit = exit;
    return session;
  }

  @override
  Future<void> dispose() async => disposed = true;
}

class _FakePlatform extends WarrenSdkPlatform {
  _FakePlatform(this._handle);

  final _FakeClientHandle _handle;
  WarrenClientConfig? lastConfig;

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
  Future<WarrenClientHandle> createClient(WarrenClientConfig config) async {
    lastConfig = config;
    return _handle;
  }
}
