# Warren mobile network extension

On mobile, the OS runs the VPN datapath inside a sandboxed **network extension**,
not a daemon. The extension embeds the Warren engine and is controlled by the app
over Flutter platform channels; `MobileVpnController` is the app side.

## Channels

- Method channel `com.warren.sdk/vpn`: `configure`, `connect`, `disconnect`
  (same fields as the desktop daemon protocol).
- Event channel `com.warren.sdk/vpn/state`: emits `{type: state, state: ...}` and
  `{type: error, kind, message}` maps, mapped to `ConnectionState` and
  `WarrenError`.

## Native side (the gated half)

### Android (`VpnService`)

- A foreground `VpnService` establishes the TUN fd and reads/writes packets.
- The engine is reached over JNI (the `cdylib` from `warren_sdk_frb` or a
  dedicated JNI crate); `connect` builds the multihop tunnel and pumps the fd.
- Routing and DNS are configured through `VpnService.Builder`.

### iOS / macOS (`NEPacketTunnelProvider`)

- A packet-tunnel provider extension links the engine's static lib via a C ABI.
- The app controls it through `NETunnelProviderManager`; status crosses back over
  the app group and the event channel.

These require real devices, signing and `flutter build`, so they are validated on
device, not in the SDK's automated tests. The app-side controller and the event
mapping in this package are unit-tested with mocked channels.
