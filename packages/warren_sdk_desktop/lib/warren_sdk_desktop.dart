/// Desktop system-VPN (Mode B) support for the Warren SDK.
///
/// The privileged datapath (TUN device, routing, killswitch) runs out of process
/// in a Warren daemon; this package speaks the daemon's framed-JSON IPC protocol.
/// See `IPC.md` for the protocol and the daemon's responsibilities.
library;

export 'src/ipc/daemon_client.dart';
export 'src/ipc/framing.dart';
export 'src/ipc/messages.dart';
export 'src/socket_transport.dart';
