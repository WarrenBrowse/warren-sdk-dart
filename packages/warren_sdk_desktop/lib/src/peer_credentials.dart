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

/// `(uid_t)-1`: never an account. Linux reports it for a socket with no peer
/// credentials.
const int _noUid = 0xFFFFFFFF;

/// The uid of the account serving the other end of [socket], as the kernel
/// recorded it, or null when it cannot be established.
///
/// Null covers a platform with no peer-credential query, a failed query, and a
/// socket that carries no peer credentials. Dart hands back the buffer it
/// passed in whatever length the kernel actually wrote, so the buffer starts
/// filled with `0xFF`: a field the kernel left alone then reads as `(uid_t)-1`
/// or a wrong struct version, never as uid 0, which would pass for root.
int? peerUid(Socket socket) {
  final bool macos;
  if (Platform.isMacOS) {
    macos = true;
  } else if (Platform.isLinux) {
    macos = false;
  } else {
    return null;
  }
  final size = macos ? _xucredSize : _ucredSize;
  final buffer = Uint8List(size)..fillRange(0, size, 0xFF);
  final Uint8List value;
  try {
    value = socket.getRawOption(
      macos
          ? RawSocketOption(_solLocal, _localPeerCred, buffer)
          : RawSocketOption(_solSocket, _soPeerCred, buffer),
    );
  } on Exception {
    return null;
  }
  final fields = ByteData.sublistView(value);
  if (macos && fields.getUint32(0, Endian.host) != _xucredVersion) return null;
  final uid = fields.getUint32(4, Endian.host);
  return uid == _noUid ? null : uid;
}
