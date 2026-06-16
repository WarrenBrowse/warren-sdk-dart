# warren_sdk_desktop

Desktop **system-VPN (Mode B)** support for the Warren SDK on Windows, macOS and
Linux.

Mode A (the default, in-process proxy in `warren_sdk_ffi`) needs no privilege and
works everywhere. Mode B captures all OS traffic through a real TUN device, which
needs privilege, so the datapath runs in a separate **Warren daemon** and the app
drives it over a local IPC socket.

This package provides the app-side IPC layer:

- `FrameCodec` / `FrameReader`: length-prefixed framing over a stream socket.
- `DaemonMessage` and friends: the typed, JSON wire protocol.
- `DaemonClient`: a transport-agnostic client that frames requests and surfaces
  connection-state transitions (and daemon errors as typed stream errors).

The daemon itself (privileged TUN, routing, killswitch, per-OS privilege
bootstrap) is specified in [`IPC.md`](IPC.md) and validated on a real host; it is
out of scope for the SDK's automated tests.

## Status

The IPC protocol, framing and client are implemented and unit-tested against an
in-memory daemon. Wiring `DaemonClient` into a `WarrenSdkPlatform` implementation
and shipping the daemon binary land with desktop app integration (roadmap P4).
