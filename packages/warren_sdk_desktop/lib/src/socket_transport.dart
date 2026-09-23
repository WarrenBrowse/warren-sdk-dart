import 'dart:io';

import 'package:meta/meta.dart';
import 'package:warren_sdk_platform_interface/warren_sdk_platform_interface.dart';

import 'ipc/daemon_client.dart';
import 'peer_credentials.dart';

/// Connects to the Warren daemon over a Unix domain socket and returns a
/// [DaemonClient] driving it.
///
/// The daemon listens on [socketPath] (`defaultDaemonSocketPath` in production,
/// or a dev path). Closing the returned client closes the socket.
///
/// The kernel reports which account serves the socket, and the connection is
/// kept only when that account is root, the account the privileged daemon runs
/// as. A `configure` request carries the mnemonic, so a listener another local
/// account planted at [socketPath] must never get a client to receive it.
///
/// Throws a [WarrenPrivilegeError] with code `privilege/daemon-untrusted` when
/// the socket is served by another account, or when the platform cannot say
/// which account serves it.
Future<DaemonClient> connectDaemonSocket(String socketPath) =>
    _connect(socketPath, 0);

/// [connectDaemonSocket] for a daemon run unprivileged under [daemonUid], the
/// caller's own account: the tests that drive the real daemon without root.
@visibleForTesting
Future<DaemonClient> connectUnprivilegedDaemonSocket(
  String socketPath, {
  required int daemonUid,
}) =>
    _connect(socketPath, daemonUid);

Future<DaemonClient> _connect(String socketPath, int daemonUid) async {
  final socket = await Socket.connect(
    InternetAddress(socketPath, type: InternetAddressType.unix),
    0,
  );
  if (peerUid(socket) != daemonUid) {
    socket.destroy();
    throw const WarrenPrivilegeError(
      code: 'privilege/daemon-untrusted',
      message: 'the system-VPN socket is not served by the Warren daemon '
          'account',
    );
  }
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
