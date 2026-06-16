import 'dart:io';

import 'ipc/daemon_client.dart';

/// Connects to the Warren daemon over a Unix domain socket and returns a
/// [DaemonClient] driving it.
///
/// The daemon listens on [socketPath] (for example `/var/run/warren-vpn.sock`
/// in production, or a dev path). Closing the returned client closes the socket.
Future<DaemonClient> connectDaemonSocket(String socketPath) async {
  final socket = await Socket.connect(
    InternetAddress(socketPath, type: InternetAddressType.unix),
    0,
  );
  return DaemonClient(
    incoming: socket,
    send: socket.add,
    onClose: () async {
      await socket.flush();
      await socket.close();
      socket.destroy();
    },
  );
}
