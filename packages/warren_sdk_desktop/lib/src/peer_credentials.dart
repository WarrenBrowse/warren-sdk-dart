import 'dart:io';
import 'dart:typed_data';

// macOS `getsockopt(SOL_LOCAL, LOCAL_PEERCRED)` fills a `struct xucred`:
// `u_int cr_version; uid_t cr_uid; short cr_ngroups; gid_t cr_groups[16]`.
const int _solLocal = 0;
const int _localPeerCred = 1;
const int _xucredSize = 76;
const int _xucredVersion = 0;

// Linux `getsockopt(SOL_SOCKET, SO_PEERCRED)` fills a `struct ucred`:
// `pid_t pid; uid_t uid; gid_t gid`.
const int _solSocket = 1;
const int _soPeerCred = 17;
const int _ucredSize = 12;

/// The uid of the account serving the other end of [socket], as the kernel
/// recorded it, or null when it cannot be established.
///
/// Null covers a platform with no peer-credential query, a failed query, and a
/// socket that carries no peer credentials. Dart hands back the zero-filled
/// buffer it passed in whatever length the kernel wrote, and a zeroed uid reads
/// as root, so an answer is only trusted when a field no real credential leaves
/// at zero is set: the group count on macOS, the peer pid on Linux.
int? peerUid(Socket socket) {
  final bool macos;
  if (Platform.isMacOS) {
    macos = true;
  } else if (Platform.isLinux) {
    macos = false;
  } else {
    return null;
  }
  final Uint8List value;
  try {
    value = socket.getRawOption(
      macos
          ? RawSocketOption(_solLocal, _localPeerCred, Uint8List(_xucredSize))
          : RawSocketOption(_solSocket, _soPeerCred, Uint8List(_ucredSize)),
    );
  } on Exception {
    return null;
  }
  final fields = ByteData.sublistView(value);
  if (macos) {
    final version = fields.getUint32(0, Endian.host);
    final groupCount = fields.getInt16(8, Endian.host);
    if (version != _xucredVersion || groupCount < 1) return null;
  } else if (fields.getInt32(0, Endian.host) <= 0) {
    return null;
  }
  return fields.getUint32(4, Endian.host);
}
