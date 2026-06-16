# Roadmap

Phased plan for `warren-sdk-dart`. Each phase is independently testable. Tunnel
features are only "done" once validated against a real exit (same rule as the
Rust engine). Desktop is the priority, so Mode A and the desktop daemon come
before mobile extensions.

## P0: Foundations (this scaffold)

- [x] Repository, pub workspace, federated-plugin layout.
- [x] Architecture, decision records, conventions (`CLAUDE.md`), roadmap.
- [x] Package skeletons: facade, platform interface, ffi, riverpod.
- [x] Public facade API surface (models, `WarrenClient`, sessions, errors) as
      framework-agnostic Dart, with the platform interface it talks to.
- [x] Lints/tooling green: `dart analyze`, `dart format --set-exit-if-changed`.

## P1: Identity slice over the real engine (Mode A, in-process)

The first vertical slice, mirroring how the Rust engine started with identity.

- [x] `native/warren_sdk_frb`: FRB glue crate wrapping `warren-sdk` identity
      helpers (generate mnemonic, address from mnemonic, SS58 encode/decode,
      sign request).
- [x] FRB codegen producing the Dart bindings (checked in under `lib/src/rust`).
- [x] `warren_sdk_ffi` implements the identity part of the platform interface,
      with lazy one-shot native init and redacted error mapping.
- [x] Golden-vector tests: replay `vectors/identity.json` through the Dart
      facade against the real engine so the surface is wire-identical to every
      sibling SDK.
- [ ] cargokit app-bundling build for `warren_sdk_ffi` (Android/iOS/desktop).
      Deferred: it only takes effect at `flutter build`/`flutter run` time, which
      is out of scope for this automated environment. The host-side conformance
      test builds the engine with `cargo build` directly. See
      `packages/warren_sdk_ffi/NATIVE_BUILD.md`.

## P2: Account API (Mode A)

- [x] FRB wrap of `WarrenClient` create + account calls (subscription expiry,
      redeem voucher, list exits) behind an opaque `WarrenClientFrb`.
- [x] Facade `WarrenClient.create`, `subscription`, `redeemVoucher`,
      `listExits`, `selectExit`, backed by an `FfiClientHandle`.
- [x] Error mapping: typed engine error (`WarrenFfiError`) to sealed Dart
      `WarrenError`, redacted, unit-tested per category.
- [~] Live happy-path tests gated on a subscribed test account + real exit:
      `test/account_live_test.dart`, skipped unless `WARREN_MNEMONIC`,
      `WARREN_API_BASE` and `WARREN_SERVER_PIN` are set. Not yet run here.

## P3: Proxy datapath (Mode A, the default mode)

- [x] FRB wrap of `connect(proxy)` returning an opaque session handle, plus a
      connection-state `Stream` (broadcast, current-state-first).
- [x] Facade `WarrenSession` with `endpoints` (SOCKS5/HTTP), `states`,
      `disconnect`.
- [x] Multihop support surfaced: proxy mode always uses the supervised multihop
      datapath, which real exits require.
- [x] DNS-over-tunnel: the engine resolves at the exit gateway by default
      (`ProxyConfig.dns_server = None`).
- [~] End-to-end validation against a real exit (confirmed egress):
      `test/connect_live_test.dart`, env-gated. Not yet run here.

## P4: Desktop System VPN (Mode B, privileged)

- [x] IPC protocol and app-side client (`warren_sdk_desktop`): length-prefixed
      framing, typed framed-JSON messages, and a transport-agnostic
      `DaemonClient`, unit-tested against an in-memory daemon. See `IPC.md`.
- [ ] Rust daemon binary embedding `warren-sdk` + `warren-tun`, serving the IPC
      protocol over a Unix socket / named pipe.
- [ ] Wire `DaemonClient` into a `WarrenSdkPlatform` implementation (system-VPN
      connect path) for `_linux` / `_windows` / `_macos`.
- [ ] Privilege bootstrap per OS (polkit / launchd helper / Windows service +
      single UAC elevation).
- [ ] Killswitch and split-default routing surfaced and validated on each OS
      (needs root; gated, validated on a target host).

## P5: Mobile System VPN (Mode B)

- [x] App-side control (`warren_sdk_mobile`): `MobileVpnController` over method
      and event channels, with state/error mapping, unit-tested with mocked
      channels. See `MOBILE.md`.
- [ ] Android `VpnService` foreground + JNI to the engine.
- [ ] iOS / macOS `NEPacketTunnelProvider` + engine C ABI; control via
      `NETunnelProviderManager`, status over the app group.
- [ ] Per-platform real-device validation against a real exit (needs devices and
      `flutter build`; gated, validated on device).

## P6: Port forwarding and advanced features

- [x] Reconnect/backoff supervision surfaced as state-stream transitions: the
      proxy datapath is supervised, so `Reconnecting` is emitted between epochs
      (mapped and tested).
- [x] DAITA exposed via `WarrenClient.create` (`daita`, `daitaMachine`). The
      engine configures DAITA at client-build time, so it lives on the client
      config, not `ConnectOptions`; forwarding is unit-tested.
- [ ] NAT-PMP port forward surfaced (inbound listener / local relay). Deferred:
      the engine exposes `forward_port` only on the non-supervised `ProxyHandle`,
      while the SDK uses the self-healing `SupervisedProxyHandle` (auto-reconnect)
      which does not. Surfacing it needs an engine addition or a non-supervised
      connect mode, and is live-gated (needs a real exit and an external peer).

## P7: Optional integrations and polish

- [ ] `warren_sdk_riverpod`: Riverpod 3 `AsyncNotifier` providers for client,
      subscription, exits and live connection state.
- [ ] Example apps: a desktop example and a mobile example.
- [ ] CI: analyze, test, golden-vector replay, FRB-codegen drift check, format.
- [ ] API docs published; `dartdoc` clean.

## Cross-cutting (every phase)

- TDD: test first, minimal pass, refactor green.
- No-log discipline and zeroization respected across the bridge.
- Shared `vectors/` are the contract; never edit a vector to pass a test.
