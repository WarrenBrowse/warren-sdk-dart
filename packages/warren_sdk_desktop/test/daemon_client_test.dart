import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:warren_sdk_desktop/warren_sdk_desktop.dart';
import 'package:warren_sdk_platform_interface/warren_sdk_platform_interface.dart';

void main() {
  late StreamController<List<int>> incoming;
  late List<List<int>> sent;
  late DaemonClient client;

  setUp(() {
    incoming = StreamController<List<int>>();
    sent = [];
    client = DaemonClient(incoming: incoming.stream, send: sent.add);
  });

  tearDown(() async {
    await client.close();
    if (!incoming.isClosed) await incoming.close();
  });

  /// Decodes the messages the client has framed and sent to the daemon.
  List<DaemonMessage> sentMessages() {
    final reader = FrameReader();
    final messages = <DaemonMessage>[];
    for (final frame in sent) {
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

  /// Frames a daemon-to-app message onto the incoming channel.
  void daemonSends(DaemonMessage message) {
    incoming.add(FrameCodec.encode(utf8.encode(jsonEncode(message.toJson()))));
  }

  test('connect frames a ConnectRequest to the daemon', () {
    client.connect(const ConnectRequest(exitPubkeyHex: 'ab12'));
    final messages = sentMessages();
    expect(messages, hasLength(1));
    expect(messages.single, isA<ConnectRequest>());
    expect((messages.single as ConnectRequest).exitPubkeyHex, 'ab12');
  });

  test('configure and disconnect frame their requests', () {
    const config = ConfigureRequest(
      mnemonic: 'm',
      apiBase: 'https://a',
      serverPubkeyPin: 'p',
    );
    client
      ..configure(config)
      ..disconnect();
    final messages = sentMessages();
    expect(messages[0], isA<ConfigureRequest>());
    expect(messages[1], isA<DisconnectRequest>());
  });

  test('a state event becomes a mapped ConnectionState', () async {
    final states = client.states.take(2).toList();
    daemonSends(const StateEvent(DaemonConnectionState.connecting));
    daemonSends(const StateEvent(DaemonConnectionState.connected));
    expect(await states, [const Connecting(), const Connected()]);
  });

  test('a failed state maps to ConnectionFailed', () async {
    final next = client.states.first;
    daemonSends(const StateEvent(DaemonConnectionState.failed));
    expect(await next, isA<ConnectionFailed>());
  });

  test('reconnecting and disconnected states map to their subtypes', () async {
    final states = client.states.take(2).toList();
    daemonSends(const StateEvent(DaemonConnectionState.reconnecting));
    daemonSends(const StateEvent(DaemonConnectionState.disconnected));
    expect(await states, [const Reconnecting(), const Disconnected()]);
  });

  test('replays the latest state to a listener that attaches late', () async {
    daemonSends(const StateEvent(DaemonConnectionState.connected));
    await pumpEventQueue();

    expect(await client.states.first, const Connected());
  });

  test('a malformed frame surfaces as a typed stream error', () async {
    final caught = client.states.first.then<Object?>(
      (_) => null,
      onError: (Object e) => e,
    );
    incoming.add(FrameCodec.encode(utf8.encode('this is not json')));
    expect(
      await caught,
      isA<WarrenTunnelError>().having(
        (e) => e.code,
        'code',
        'ipc/malformed-frame',
      ),
    );
  });

  test('an error event arrives as a typed stream error', () async {
    final caught = client.states.first.then<Object?>(
      (_) => null,
      onError: (Object e) => e,
    );
    daemonSends(const ErrorEvent(kind: 'privilege', message: 'denied'));
    expect(await caught, isA<WarrenPrivilegeError>());
  });
}
