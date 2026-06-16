# warren_sdk_mobile

Mobile **system-VPN (Mode B)** support for the Warren SDK on Android and iOS.

Mode A (the default in-process proxy in `warren_sdk_ffi`) works on mobile too and
needs no special entitlement. Mode B captures all device traffic through a real
TUN, which on mobile runs inside an OS network extension that embeds the Warren
engine; the app drives it over platform channels.

This package provides `MobileVpnController`: `configure` / `connect` /
`disconnect` over a method channel, and a `ConnectionState` stream over an event
channel. The native extensions are described in [`MOBILE.md`](MOBILE.md) and
validated on device.

## Status

The controller and event mapping are implemented and unit-tested with mocked
channels. The Android `VpnService` and iOS/macOS `NEPacketTunnelProvider`
extensions land with mobile app integration (roadmap P5).
