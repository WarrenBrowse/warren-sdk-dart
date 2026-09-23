@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:warren_sdk_desktop/src/peer_credentials.dart';

void main() {
  test('a socket that carries no peer credentials has no account, never root',
      () async {
    // A TCP socket has no peer credentials. macOS answers the query as a
    // zero-length IP option and leaves the buffer zero-filled, which decodes
    // as uid 0 and would pass for the root daemon; Linux answers with pid 0.
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((peer) => peer.destroy());
    final socket =
        await Socket.connect(InternetAddress.loopbackIPv4, server.port);
    addTearDown(socket.destroy);

    expect(peerUid(socket), isNull);
  });
}
