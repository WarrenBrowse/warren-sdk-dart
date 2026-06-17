import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:warren_sdk_desktop/warren_sdk_desktop.dart';
import 'package:warren_sdk_platform_interface/warren_sdk_platform_interface.dart';

void main() {
  const exit = ExitInfo(
    id: 'ab12',
    country: 'RO',
    city: 'Bucharest',
    supportsIpv6: true,
    supportsPortForwarding: false,
  );
  final config = WarrenClientConfig(
    mnemonic: 'donor sphere session favorite cry screen lesson gloom hollow '
        'regular wife link',
    apiBase: Uri.parse('https://api.example.test'),
    serverPubkeyPin: 'deadbeef',
  );

  group('createClient delegates to the inner platform and wraps the handle',
      () {
    test('control-plane calls and dispose forward to the inner handle',
        () async {
      final inner = _FakeInnerPlatform();
      final platform = DesktopWarrenSdkPlatform(
        inner: inner,
        daemonConnector: () async => throw StateError('not used'),
      );

      final handle = await platform.createClient(config);
      expect(handle.address, 'wbADDRESS');
      await handle.subscription();
      await handle.listExits();
      await handle.dispose();

      final calls = inner.handle.calls;
      expect(calls, containsAll(['subscription', 'listExits', 'dispose']));
    });

    test('identity helpers forward to the inner platform', () async {
      final inner = _FakeInnerPlatform();
      final platform = DesktopWarrenSdkPlatform(
        inner: inner,
        daemonConnector: () async => throw StateError('not used'),
      );
      expect(await platform.generateMnemonic(), 'one two three');
      expect(await platform.addressFromMnemonic('m'), 'wbADDRESS');
    });
  });

  group('proxy mode stays in-process', () {
    test('a proxy connection delegates to the inner handle', () async {
      final inner = _FakeInnerPlatform();
      final platform = DesktopWarrenSdkPlatform(
        inner: inner,
        daemonConnector: () async => throw StateError('daemon not used'),
      );
      final handle = await platform.createClient(config);

      final session = await handle.connect(
        exit,
        ConnectMode.proxy,
        const ConnectOptions(),
      );

      expect(session.endpoints?.socks5, '127.0.0.1:51234');
      expect(inner.handle.calls, contains('connect:proxy'));
    });
  });

  group('system-VPN mode drives the daemon', () {
    test('configures the daemon, connects, and returns a TUN session',
        () async {
      final daemon = _FakeDaemon(
        reply: const StateEvent(DaemonConnectionState.connected),
      );
      final platform = DesktopWarrenSdkPlatform(
        inner: _FakeInnerPlatform(),
        daemonConnector: () async => daemon.client,
      );
      final handle = await platform.createClient(config);

      final session = await handle.connect(
        exit,
        ConnectMode.systemVpn,
        const ConnectOptions(dnsOverTunnel: false),
      );

      // A system-VPN session captures everything: no local proxy endpoints.
      expect(session.endpoints, isNull);

      final received = daemon.received();
      final configure = received.whereType<ConfigureRequest>().single;
      expect(configure.mnemonic, config.mnemonic);
      expect(configure.serverPubkeyPin, 'deadbeef');
      final connect = received.whereType<ConnectRequest>().single;
      expect(connect.exitPubkeyHex, 'ab12');
      expect(connect.dnsOverTunnel, isFalse);
    });

    test('a daemon failure state throws a tunnel error and closes the daemon',
        () async {
      final daemon = _FakeDaemon(
        reply: const StateEvent(DaemonConnectionState.failed),
      );
      final platform = DesktopWarrenSdkPlatform(
        inner: _FakeInnerPlatform(),
        daemonConnector: () async => daemon.client,
      );
      final handle = await platform.createClient(config);

      await expectLater(
        handle.connect(exit, ConnectMode.systemVpn, const ConnectOptions()),
        throwsA(isA<WarrenTunnelError>()),
      );
      expect(daemon.closed, isTrue);
    });

    test('a daemon error event surfaces as its typed error', () async {
      final daemon = _FakeDaemon(
        reply: const ErrorEvent(kind: 'privilege', message: 'denied'),
      );
      final platform = DesktopWarrenSdkPlatform(
        inner: _FakeInnerPlatform(),
        daemonConnector: () async => daemon.client,
      );
      final handle = await platform.createClient(config);

      await expectLater(
        handle.connect(exit, ConnectMode.systemVpn, const ConnectOptions()),
        throwsA(isA<WarrenPrivilegeError>()),
      );
      expect(daemon.closed, isTrue);
    });

    test('an unreachable daemon throws a privilege error', () async {
      final platform = DesktopWarrenSdkPlatform(
        inner: _FakeInnerPlatform(),
        daemonConnector: () async =>
            throw const SocketExceptionStub('no such file'),
      );
      final handle = await platform.createClient(config);

      await expectLater(
        handle.connect(exit, ConnectMode.systemVpn, const ConnectOptions()),
        throwsA(isA<WarrenPrivilegeError>()),
      );
    });

    test('the connection times out if the daemon never reports a state',
        () async {
      final daemon = _FakeDaemon(reply: null); // never replies
      final platform = DesktopWarrenSdkPlatform(
        inner: _FakeInnerPlatform(),
        daemonConnector: () async => daemon.client,
        connectTimeout: const Duration(milliseconds: 50),
      );
      final handle = await platform.createClient(config);

      await expectLater(
        handle.connect(exit, ConnectMode.systemVpn, const ConnectOptions()),
        throwsA(isA<WarrenTunnelError>()),
      );
      expect(daemon.closed, isTrue);
    });

    test('disconnecting the session tells the daemon and closes it', () async {
      final daemon = _FakeDaemon(
        reply: const StateEvent(DaemonConnectionState.connected),
      );
      final platform = DesktopWarrenSdkPlatform(
        inner: _FakeInnerPlatform(),
        daemonConnector: () async => daemon.client,
      );
      final handle = await platform.createClient(config);
      final session = await handle.connect(
        exit,
        ConnectMode.systemVpn,
        const ConnectOptions(),
      );

      await session.disconnect();

      expect(daemon.received().whereType<DisconnectRequest>(), isNotEmpty);
      expect(daemon.closed, isTrue);
    });
  });

  group('registerWith installs the desktop platform', () {
    test('wraps the provided inner as the active platform instance', () {
      final inner = _FakeInnerPlatform();
      DesktopWarrenSdkPlatform.registerWith(
        inner: inner,
        daemonConnector: () async => throw StateError('not used'),
      );
      expect(WarrenSdkPlatform.instance, isA<DesktopWarrenSdkPlatform>());
    });
  });
}

/// A throwable that mimics a socket-connect failure, without importing dart:io.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub(this.message);
  final String message;
  @override
  String toString() => 'SocketExceptionStub: $message';
}

/// A fake control-plane platform: identity helpers return canned values and
/// `createClient` hands back a recording handle.
class _FakeInnerPlatform extends WarrenSdkPlatform {
  final _FakeInnerHandle handle = _FakeInnerHandle();

  @override
  Future<String> generateMnemonic() async => 'one two three';
  @override
  Future<String> addressFromMnemonic(String mnemonic) async => 'wbADDRESS';
  @override
  Future<String> ss58Encode(String publicKeyHex) async => 'wbENCODED';
  @override
  Future<String> ss58Decode(String address) async => 'deadbeef';
  @override
  Future<WarrenClientHandle> createClient(WarrenClientConfig config) async =>
      handle;
}

/// A recording control-plane handle. Proxy connects return a fake session;
/// system-VPN must never reach here (the desktop handle intercepts it).
class _FakeInnerHandle implements WarrenClientHandle {
  final List<String> calls = [];

  @override
  String get address => 'wbADDRESS';
  @override
  Future<SubscriptionInfo> subscription() async {
    calls.add('subscription');
    return const SubscriptionInfo(expiresAtUnix: 1);
  }

  @override
  Future<void> redeemVoucher(String secret) async => calls.add('redeem');
  @override
  Future<List<ExitInfo>> listExits() async {
    calls.add('listExits');
    return const [];
  }

  @override
  Future<WarrenSessionHandle> connect(
    ExitInfo exit,
    ConnectMode mode,
    ConnectOptions options,
  ) async {
    calls.add('connect:${mode.name}');
    return _FakeProxySession();
  }

  @override
  Future<void> dispose() async => calls.add('dispose');
}

class _FakeProxySession implements WarrenSessionHandle {
  @override
  ProxyEndpoints? get endpoints =>
      const ProxyEndpoints(socks5: '127.0.0.1:51234');
  @override
  Stream<ConnectionState> get states => const Stream.empty();
  @override
  Future<void> disconnect() async {}
}

/// A reactive fake daemon over an in-memory channel: when it receives a connect
/// request it emits [reply] (a state or error event), or nothing if null.
class _FakeDaemon {
  _FakeDaemon({required this.reply}) {
    client = DaemonClient(
      incoming: _incoming.stream,
      send: _onSend,
      onClose: () async => closed = true,
    );
  }

  final DaemonMessage? reply;
  final StreamController<List<int>> _incoming = StreamController<List<int>>();
  final List<List<int>> _sent = [];
  late final DaemonClient client;
  bool closed = false;
  bool _replied = false;

  void _onSend(List<int> frame) {
    _sent.add(frame);
    final reply = this.reply;
    final isConnect = received().any((m) => m is ConnectRequest);
    if (isConnect && !_replied && reply != null && !_incoming.isClosed) {
      _replied = true;
      _incoming.add(
        FrameCodec.encode(utf8.encode(jsonEncode(reply.toJson()))),
      );
    }
  }

  List<DaemonMessage> received() {
    final reader = FrameReader();
    final messages = <DaemonMessage>[];
    for (final frame in _sent) {
      for (final payload in reader.addChunk(frame)) {
        messages.add(
          DaemonMessage.fromJson(
            jsonDecode(utf8.decode(payload)) as Map<String, Object?>,
          ),
        );
      }
    }
    return messages;
  }
}
