# Architecture

`warren-sdk-dart` is the Dart/Flutter client SDK for the Warren VPN. Its job is to
make Warren trivial to embed in **any** Flutter application (desktop first:
Windows, macOS, Linux; then Android and iOS) regardless of the host app's
architecture, while being robust, secure, high performance and built to last.

This SDK does **not** reimplement the Warren protocol in Dart. It reuses the
audited Rust engine (`warren-sdk-rs`, itself a clean-room, wire-compatible
reimplementation of the frozen `warren-contract` client<->server contract) and adds an idiomatic,
reactive, framework-agnostic Dart surface on top. See
[DECISIONS.md](DECISIONS.md) for the rationale behind every choice referenced
here.

## The one rule that shapes everything: control plane vs datapath

A VPN SDK has two very different natures, and the whole design follows the line
between them.

- **Control plane** (low frequency, deterministic, identity and account logic):
  mnemonic to identity, request signing, the signed HTTP account API, signed
  relay-list verification, exit selection, subscription and voucher flows,
  connection orchestration and state.
- **Datapath** (line rate, per-packet crypto, OS privilege): QUIC transport, the
  TLS 1.3 raw-public-key handshake, HPKE multihop sealing, per-packet AEAD, the
  userspace netstack, and the privileged TUN device with its firewall
  killswitch. The engine builds on the `warren-quinn` fork with the obfuscated
  QUIC Initial (Initial-fragmentation) on by default, so the Dart proxy presents
  the same handshake fingerprint as warren-app; it is inherited through the
  pinned engine, nothing is re-tuned in Dart.

**Neither is reimplemented in Dart.** Both live in the Rust engine. Dart owns the
ergonomic API, reactive state, secure secret storage, and the platform
integration glue. This is the universal pattern for production VPNs (Mullvad and
Cloudflare WARP in Rust, Tailscale in Go): one native engine, thin per-platform
wrappers. Reimplementing QUIC, TLS 1.3 and a TCP/IP stack in a GC'd language
would be slower, larger, and would multiply the wire-compatibility surface for no
benefit.

## Two connection modes

The datapath runs in one of two modes. The SDK exposes both behind a single
`connect(mode: ...)` call; the federated plugin selects the right implementation
per platform.

### Mode A: Proxy (non-root, in-process, default, every platform)

The entire Rust engine runs **inside the Flutter app process** through
`flutter_rust_bridge`. It terminates application flows in a userspace netstack
and exposes a local SOCKS5 plus HTTP CONNECT proxy. No elevated privileges on any
OS. This is the default and the only mode that needs nothing but the app itself.

```
Flutter app process
+-----------------------------------------------+
|  Dart UI  ->  warren_sdk  ->  warren_sdk_ffi  |
|                                  |  (FRB)      |
|                          Rust engine (in-proc) |
|                          netstack + SOCKS5/HTTP |
+-----------------------------------------------+
                  |  QUIC to exit
```

### Mode B: System VPN (privileged, out-of-process)

Capturing **all** OS traffic needs a real TUN device, routing, DNS and a
killswitch, which require privilege the GUI app must not hold. So the engine runs
in a separate privileged process and the app drives it over IPC. `flutter_rust_bridge`
is in-process only and does **not** cross this boundary; the engine is embedded
natively in the privileged process instead.

- **Desktop (Windows, macOS, Linux):** a privileged daemon/service embeds the
  Rust engine (`warren-sdk` + the `warren-tun` backend). The Flutter app ships a
  thin IPC client (length-prefixed JSON or gRPC over a Unix socket / named pipe).
  This mirrors the Mullvad daemon split exactly.
- **Mobile (iOS, macOS, Android):** a network extension embeds the engine.
  - iOS / macOS: a `NEPacketTunnelProvider` extension loads the Rust engine
    through a small C ABI; the app controls it via `NETunnelProviderManager` and
    exchanges status over the shared app group.
  - Android: a `VpnService` (foreground) hosts the engine via JNI; the app
    controls it through the service binder.

```
Flutter app process            Privileged process (daemon / network extension)
+--------------------+   IPC   +--------------------------------------------+
| Dart UI            |<------->| Rust engine (warren-sdk + warren-tun)      |
| warren_sdk         |         | real TUN + routing + killswitch + DNS      |
| platform IPC client|         +--------------------------------------------+
+--------------------+                          |  QUIC to exit
```

The public Dart API is identical across modes; only the selected platform
implementation differs.

## Package graph

A pub workspace (monorepo) of small, single-responsibility packages following the
**federated plugin** pattern, so each platform's privileged integration is
isolated and independently testable, and consumers depend on exactly one package.

```
                       consumer Flutter app
                               |
        (optional)             v
  warren_sdk_riverpod --> warren_sdk            <- the ONLY package apps add
   (Riverpod 3          (facade: framework-agnostic
    providers)           pure-Dart API, models, streams)
                            |        |
       endorses the default |        v
       Mode A engine ------>|   warren_sdk_platform_interface
                            |   (abstract surface, models, events,
                            v    the federated-plugin contract)
              /------- warren_sdk_ffi -------\
   implements |         (Mode A: FRB          | reused by
   the surface|          in-process)          | the desktop client
              v             ^                 v
   warren_sdk_<mobile>      | reuses    warren_sdk_<desktop>
   (Mode B: NetworkExt /    | the in-   (Mode B: daemon IPC
    VpnService)             | proc      client + endorsed
              \             | control   proxy control plane)
               \            | plane      /
                v           |           v
              warren-sdk-frb      warren daemon / extension
              (Rust, wraps        (Rust binary / lib, wraps
               warren-sdk)         warren-sdk + warren-tun)
                          \         |         /
                           v        v        v
                        warren-sdk-rs (the shared Rust engine)
```

Two edges are pragmatic and worth calling out explicitly. `warren_sdk` has a
direct dependency on `warren_sdk_ffi`: the FFI implementation is the **endorsed
default** (Mode A works on every platform with no privileged process), so the
facade wires it in rather than leaving the consumer to register a platform.
`warren_sdk_desktop` also depends on `warren_sdk_ffi`: the daemon only owns the
privileged datapath, and it reuses the in-process engine for the control plane
(identity, account, proxy mode). Both mean the native engine is a transitive
dependency of any consumer, which is the intended cost of a batteries-included
default.

| Package | Responsibility | Pure Dart? |
|---|---|---|
| `warren_sdk` | App-facing facade: `WarrenClient`, models, connection-state `Stream`s, errors. Framework-agnostic (no state-management dependency). Endorses `warren_sdk_ffi` as the default Mode A engine. | Dart (pulls the FFI plugin transitively) |
| `warren_sdk_platform_interface` | The federated-plugin contract: abstract methods, shared models and events. Library code imports no Flutter; the package depends on the Flutter SDK only for its plugin base class and test harness. | Dart (Flutter SDK dep, Flutter-free code) |
| `warren_sdk_ffi` | Mode A in-process engine via `flutter_rust_bridge` + cargokit build. Default implementation. | Dart + Rust glue |
| `warren_sdk_riverpod` | Optional Riverpod 3 providers wrapping the facade. Never required. | yes |
| `warren_sdk_android` | Mode B: `VpnService` + JNI to the engine. | Dart + Kotlin |
| `warren_sdk_ios` / `warren_sdk_macos` | Mode B: `NEPacketTunnelProvider` + engine C ABI. | Dart + Swift |
| `warren_sdk_windows` / `_linux` | Mode B: privileged daemon IPC client. | Dart |
| `native/warren_sdk_frb` | Rust crate exposing the FRB API by delegating to `warren-sdk`. | Rust |

## What is Dart, what is Rust

| Concern | Lives in |
|---|---|
| Identity, SS58, signing, crypto, wire codecs | Rust (`warren-sdk-rs`), reused, never reimplemented |
| QUIC, TLS-RPK, HPKE multihop, netstack, TUN, killswitch | Rust (`warren-sdk-rs`) |
| Ergonomic API, models, reactive streams, error mapping | Dart (`warren_sdk`) |
| Secret storage (mnemonic) | Dart secure storage to obtain it; held and zeroized in Rust |
| Platform privileged integration (daemon, extension) | Native (Swift / Kotlin / Rust daemon) behind the platform interface |
| Optional state-management integration | Dart (`warren_sdk_riverpod`) |

## Framework-agnostic by construction

The facade exposes only plain Dart: `Future`s, broadcast `Stream`s, immutable
models and sealed error types. It pulls in **no** state-management dependency, so
it drops into any app whether it uses Riverpod, BLoC, Provider, GetX, signals or
plain `setState`. Riverpod 3 integration is a **separate optional package**;
choosing it is the consumer's call, never the SDK's.

## Secrets and no-log discipline

- The 12-word mnemonic is read through the platform secure store
  (`flutter_secure_storage`: Keychain, Keystore, libsecret, DPAPI) and passed
  into the engine, which derives the signing key and **zeroizes it in Rust**,
  keeping only the derived public address. A Dart `String` cannot be zeroized, so
  the SDK never logs the mnemonic and does not retain it beyond what a mode needs:
  the in-process (Mode A) path holds no reference after the client is built; the
  desktop Mode B path holds it only until the client handle is disposed, to
  reconfigure the privileged daemon per session.
- No identity material (pubkey, address, IP, nonce, seed) is ever logged in
  clear, on either side of the bridge. This mirrors the Rust engine's no-log
  rule.
- Errors crossing the bridge are mapped to a sealed Dart error type that carries
  a stable code and a redacted message, never raw secret-bearing strings.

## Performance

- The datapath is entirely in Rust; Dart pays cost only on control-plane calls.
- `flutter_rust_bridge` runs Rust off the Flutter UI isolate and uses its SSE
  codec, so calls never block the UI; bulk bytes cross as `Uint8List` <-> `Vec<u8>`
  without needless copies.
- Connection state reaches Dart as a `Stream` fed by a Rust event channel, not by
  polling.

## Testing strategy

- `warren_sdk` and the platform interface: pure Dart unit and widget-free tests,
  fakes for the platform interface (no native engine needed for facade logic).
- `warren_sdk_ffi`: integration tests over the real compiled engine, replaying
  the shared `vectors/` from `warren-sdk-rs` so the Dart surface stays
  wire-identical to every sibling SDK.
- Mode B platform packages: per-platform integration tests on real devices and a
  real exit, since a tunnel feature is only "done" once validated against a real
  exit (same rule as the Rust engine).
- Optional Riverpod package: provider tests with overridden dependencies.

## See also

- [DECISIONS.md](DECISIONS.md): the architecture decision records.
- [ROADMAP.md](ROADMAP.md): the phase plan.
- `warren-sdk-rs/ARCHITECTURE.md`: the Rust engine and its own consumption
  decision record.
