import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warren_sdk_mobile/warren_sdk_mobile.dart';
import 'package:warren_sdk_platform_interface/warren_sdk_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('mapMobileEvent', () {
    ConnectionState state(String name) =>
        mapMobileEvent({'type': 'state', 'state': name});

    test('maps each state', () {
      expect(state('connecting'), const Connecting());
      expect(state('connected'), const Connected());
      expect(state('reconnecting'), const Reconnecting());
      expect(state('disconnected'), const Disconnected());
      expect(state('failed'), isA<ConnectionFailed>());
    });

    test('an error event throws the mapped WarrenError', () {
      expect(
        () => mapMobileEvent({
          'type': 'error',
          'kind': 'privilege',
          'message': 'denied',
        }),
        throwsA(isA<WarrenPrivilegeError>()),
      );
    });

    test('an unknown event type throws', () {
      expect(() => mapMobileEvent({'type': 'nope'}), throwsFormatException);
    });

    test('an unknown state name throws', () {
      expect(
        () => mapMobileEvent({'type': 'state', 'state': 'bogus'}),
        throwsFormatException,
      );
    });
  });

  group('MobileVpnController method calls', () {
    final calls = <MethodCall>[];
    const channel = MethodChannel('test/vpn');
    late MobileVpnController controller;

    setUp(() {
      calls.clear();
      TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      controller = MobileVpnController(
        method: channel,
        events: const Stream.empty(),
      );
    });

    tearDown(() {
      TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('connect invokes the connect method with the exit id', () async {
      await controller.connect(exitPubkeyHex: 'ab12');
      expect(calls.single.method, 'connect');
      final args = (calls.single.arguments as Map).cast<String, Object?>();
      expect(args['exitPubkeyHex'], 'ab12');
      expect(args['dnsOverTunnel'], isTrue);
    });

    test('configure omits an absent root pin and disconnect takes none',
        () async {
      await controller.configure(
        mnemonic: 'm',
        apiBase: 'https://a',
        serverPubkeyPin: 'p',
      );
      await controller.disconnect();
      expect(calls.map((c) => c.method), ['configure', 'disconnect']);
      final configureArgs =
          (calls.first.arguments as Map).cast<String, Object?>();
      expect(configureArgs.containsKey('multihopRootPin'), isFalse);
      // Defaults: DAITA omitted (off), IPv6 present and on.
      expect(configureArgs.containsKey('daita'), isFalse);
      expect(configureArgs['requestIpv6'], isTrue);
    });

    test('configure forwards DAITA and IPv6 options when set', () async {
      await controller.configure(
        mnemonic: 'm',
        apiBase: 'https://a',
        serverPubkeyPin: 'p',
        daita: true,
        daitaMachine: 'tamaraw',
        requestIpv6: false,
      );
      final args = (calls.single.arguments as Map).cast<String, Object?>();
      expect(args['daita'], isTrue);
      expect(args['daitaMachine'], 'tamaraw');
      expect(args['requestIpv6'], isFalse);
    });
  });

  test('controller maps injected events into its state stream', () async {
    final events = StreamController<Object?>();
    final controller = MobileVpnController(
      method: const MethodChannel('unused'),
      events: events.stream,
    );
    final collected = controller.states.take(2).toList();
    events
      ..add({'type': 'state', 'state': 'connecting'})
      ..add({'type': 'state', 'state': 'connected'});
    expect(await collected, [const Connecting(), const Connected()]);
    await events.close();
  });
}
