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
- [ ] Lints/tooling green: `dart analyze`, `dart format --set-exit-if-changed`.

## P1: Identity slice over the real engine (Mode A, in-process)

The first vertical slice, mirroring how the Rust engine started with identity.

- [ ] `native/warren_sdk_frb`: FRB glue crate wrapping `warren-sdk` identity
      helpers (generate mnemonic, address from mnemonic, SS58 encode/decode,
      sign request).
- [ ] cargokit build wired into `warren_sdk_ffi` for all desktop targets.
- [ ] FRB codegen producing the Dart bindings.
- [ ] `warren_sdk_ffi` implements the identity part of the platform interface.
- [ ] Golden-vector tests: replay `warren-sdk-rs/vectors/identity.json` through
      the Dart facade so the surface is wire-identical to every sibling SDK.

## P2: Account API (Mode A)

- [ ] FRB wrap of `WarrenClient` create + account calls (subscription expiry,
      redeem voucher, list exits).
- [ ] Facade `WarrenClient.create`, `subscriptionExpiry`, `redeemVoucher`,
      `listExits`, `selectExit`.
- [ ] Error mapping: Rust error to sealed Dart `WarrenError`, redacted.
- [ ] Live happy-path tests gated on a subscribed test account + real exit.

## P3: Proxy datapath (Mode A, the default mode)

- [ ] FRB wrap of `connect(proxy)` returning a session handle, plus a
      connection-state `Stream`.
- [ ] Facade `WarrenSession` with `socks5Endpoint`, `httpEndpoint`, `states`,
      `disconnect`.
- [ ] Multihop support surfaced (mandatory on real exits).
- [ ] DNS-over-tunnel exposed.
- [ ] End-to-end validation against a real exit (confirmed egress).

## P4: Desktop System VPN (Mode B, privileged)

- [ ] Rust daemon binary embedding `warren-sdk` + `warren-tun`, IPC server
      (length-prefixed JSON or gRPC) over Unix socket / named pipe.
- [ ] `warren_sdk_linux` / `_windows` / `_macos` desktop IPC clients implementing
      the platform interface.
- [ ] Privilege bootstrap per OS (polkit / launchd helper / Windows service +
      single UAC elevation).
- [ ] Killswitch and split-default routing surfaced and validated on each OS.

## P5: Mobile System VPN (Mode B)

- [ ] `warren_sdk_android`: `VpnService` foreground + JNI to the engine.
- [ ] `warren_sdk_ios` / `warren_sdk_macos`: `NEPacketTunnelProvider` + engine C
      ABI; control via `NETunnelProviderManager`, status over the app group.
- [ ] Per-platform real-device validation against a real exit.

## P6: Port forwarding and advanced features

- [ ] NAT-PMP port forward surfaced (inbound listener / local relay).
- [ ] Reconnect/backoff supervision surfaced as state-stream transitions.
- [ ] DAITA options exposed through `ConnectOptions`.

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
