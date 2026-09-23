@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:warren_sdk_desktop/warren_sdk_desktop.dart';
import 'package:warren_sdk_platform_interface/warren_sdk_platform_interface.dart';

/// Drives the real Unix-socket transport against an in-process fake daemon, so
/// the framing + transport + client wiring is exercised end-to-end without the
/// privileged daemon (no root, no engine).
void main() {
  // The fake daemon runs in this test process, so the kernel reports this
  // account as the one serving the socket.
  final ownUid = int.parse(
    (Process.runSync('id', ['-u']).stdout as String).trim(),
  );

  late Directory tempDir;
  late String socketPath;
  late ServerSocket server;
  late DaemonMessage? lastRequest;
  late List<int> receivedBytes;
  late Completer<void> peerClosed;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('warren_ipc_test');
    socketPath = '${tempDir.path}/d.sock';
    lastRequest = null;
    receivedBytes = [];
    peerClosed = Completer<void>();

    server = await ServerSocket.bind(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
    );
    // Fake daemon: parse one framed request, then reply with a connected state.
    server.listen((socket) {
      final reader = FrameReader();
      socket.listen(
        (chunk) {
          receivedBytes.addAll(chunk);
          for (final payload in reader.addChunk(chunk)) {
            lastRequest = DaemonMessage.fromJson(
              jsonDecode(utf8.decode(payload)) as Map<String, Object?>,
            );
            if (lastRequest is ConnectRequest) {
              const event = StateEvent(DaemonConnectionState.connected);
              socket.add(
                FrameCodec.encode(utf8.encode(jsonEncode(event.toJson()))),
              );
            }
          }
        },
        onDone: () {
          if (!peerClosed.isCompleted) peerClosed.complete();
          socket.destroy();
        },
        onError: (Object _) {
          if (!peerClosed.isCompleted) peerClosed.complete();
        },
      );
    });
  });

  tearDown(() async {
    await server.close();
    await tempDir.delete(recursive: true);
  });

  test('connect over the socket reaches the daemon and streams state back',
      () async {
    final client = await connectDaemonSocket(socketPath, daemonUid: ownUid);
    addTearDown(client.close);

    final connected = client.states.firstWhere((s) => s is Connected);
    client.connect(const ConnectRequest(exitPubkeyHex: 'ab12'));

    expect(await connected, const Connected());
    expect(lastRequest, isA<ConnectRequest>());
    expect((lastRequest! as ConnectRequest).exitPubkeyHex, 'ab12');
  });

  test(
    'a socket served by another account is refused before any byte is sent',
    () async {
      // The default trusts only root, the account the privileged daemon runs
      // as. A process of any other account listening on the path (a squatter
      // on a shared directory) must never receive the configure request, which
      // carries the mnemonic.
      await expectLater(
        connectDaemonSocket(socketPath),
        throwsA(
          isA<WarrenPrivilegeError>().having(
            (e) => e.code,
            'code',
            'privilege/daemon-untrusted',
          ),
        ),
      );

      await peerClosed.future.timeout(const Duration(seconds: 5));
      expect(receivedBytes, isEmpty);
    },
    skip: ownUid == 0 ? 'the fake daemon would be root-owned' : false,
  );
}
