# Architecture Decision Records

Short, dated records of the non-obvious choices. Each states the decision, the
context, the alternatives weighed, and the consequence. Supersede rather than
edit when a decision changes.

## ADR-001: Reuse the Rust engine, do not reimplement the protocol in Dart

**Decision.** The Warren protocol (identity, crypto, wire codecs, QUIC, TLS-RPK,
HPKE multihop, netstack, TUN) is consumed from the `warren-sdk-rs` Rust engine.
Dart implements only the ergonomic surface, reactive state, secret storage and
platform integration.

**Context.** The engine already exists, is audited, and is pinned byte-for-byte
by the shared `vectors/`. The datapath is line-rate, per-packet crypto plus OS
privilege.

**Alternatives.** (a) Full-Dart reimplementation including the tunnel. Rejected:
no production-grade pure-Dart QUIC + TLS-1.3-RPK + userspace TCP/IP stack exists;
per-packet AEAD in a GC'd language caps throughput; on mobile the datapath must
run in a native network-extension process regardless, so a "full Dart" tunnel is
structurally impossible where it matters most. (b) Partial: control plane in pure
Dart, datapath via FFI. Rejected for Dart specifically because the crypto is
already vector-locked in Rust and re-auditing it in a seventh language adds risk
for no gain.

**Consequence.** One shared engine, thin Dart wrapper. Matches Mullvad /
Cloudflare WARP / Tailscale. Wire compatibility is inherited, not re-proven.

## ADR-002: Use flutter_rust_bridge for the in-process binding (Mode A)

**Decision.** The in-process engine binding (`warren_sdk_ffi`, Mode A) uses
`flutter_rust_bridge` (FRB) v2, in a dedicated Rust glue crate
(`native/warren_sdk_frb`) that delegates to the existing `warren-sdk` API.

**Context.** We need an ergonomic Dart binding over an async Rust API with
streaming connection-state events, on Windows, macOS, Linux, Android and iOS.

**Alternatives.**
- **uniffi + uniffi-bindgen-dart.** The Rust engine already ships a uniffi
  surface (`warren-sdk-ffi`) for non-Flutter languages (Python, Kotlin, Swift,
  standalone). But the Dart generator was found unusable in practice (ABI
  marshaling crash), and uniffi's Dart story is immature. Keep uniffi for the
  non-Flutter consumers; do not use it for Flutter.
- **Hand-written `dart:ffi` + ffigen.** Maximum control, but every async method,
  stream, complex type and error path is hand-marshaled and hand-maintained
  across ABI changes. High cost, high risk, slow to evolve.
- **flutter_rust_bridge v2.** A Flutter Favorite, actively maintained (2.12.0,
  2026), generates ergonomic bindings for complex types, `async fn`, and
  `Stream`s, runs Rust off the UI isolate, supports all six platforms, and
  integrates native builds via cargokit. Chosen.

**Consequence.** A thin `warren_sdk_frb` crate wraps `warren-sdk`; FRB codegen
produces the Dart bindings. uniffi (`warren-sdk-ffi`) remains the binding for
non-Flutter languages. Two FFI surfaces, each used where it is strongest.

## ADR-003: The privileged datapath is out-of-process; FRB does not cross it

**Decision.** Mode B (system-wide VPN) runs the engine in a separate privileged
process: a daemon/service on desktop, a network extension on mobile. The Flutter
app drives it over IPC, not over FRB.

**Context.** TUN, routing and a killswitch need privilege the GUI must not hold.
FRB is in-process only. On iOS/Android the OS forces the datapath into a
dedicated extension process anyway.

**Alternatives.** Run the privileged engine in the app process. Rejected: unsafe
(GUI holding root), impossible on mobile, and fragile on desktop.

**Consequence.** Desktop ships a Rust daemon (reusing `warren-sdk` + `warren-tun`)
plus a Dart IPC client; mobile ships a native extension embedding the engine via
a C ABI / JNI. The federated platform interface hides this from the facade.

## ADR-004: The facade is framework-agnostic; Riverpod is optional and separate

**Decision.** `warren_sdk` depends on no state-management library and exposes only
`Future`s, broadcast `Stream`s, immutable models and sealed errors. A separate
optional `warren_sdk_riverpod` package provides Riverpod 3 integration.

**Context.** The SDK must drop into any Flutter app regardless of its
architecture (Riverpod, BLoC, Provider, GetX, signals, vanilla).

**Alternatives.** Bake Riverpod into the core. Rejected: forces a dependency and
an architecture on every consumer.

**Consequence.** The core is universally embeddable. Riverpod users add one extra
package; everyone else ignores it.

## ADR-005: Riverpod 3 with the modern Notifier API (in the optional package)

**Decision.** Where Riverpod is used (the optional package and examples), target
Riverpod 3.x with code generation and the `Notifier`/`AsyncNotifier` API. Avoid
the legacy `StateProvider` / `StateNotifierProvider` / `ChangeNotifierProvider`.

**Context.** Riverpod 3.0 is stable (Sept 2025); the legacy providers are moved
to a legacy import path and discouraged.

**Consequence.** Modern, generation-based providers; note that a 4.0 is expected,
so the integration is kept thin and easy to migrate.

## ADR-006: Monorepo as a pub workspace, federated plugin layout

**Decision.** One repository, a Dart pub workspace (native workspaces, Dart 3.6+),
packages split by responsibility following the federated-plugin pattern. Melos is
used only as a task runner for codegen/analyze/test/format across packages.

**Context.** Each platform's privileged integration is large and independent;
consumers should add exactly one package.

**Consequence.** Clear boundaries, per-package tests, and a single dependency
(`warren_sdk`) for apps.

## ADR-007: Native build via cargokit (compile-from-source), prebuilt as an opt-in

**Decision.** `warren_sdk_ffi` builds the Rust engine from source via cargokit,
which hooks cargo into Gradle, CocoaPods and CMake and provisions cross targets.
Prebuilt binaries are an optional later optimization for CI/release size.

**Context.** cargokit is the established path for shipping Rust in a Flutter
plugin across all platforms without committing binaries.

**Consequence.** Contributors need a Rust toolchain; release builds may switch to
pinned prebuilt artifacts when that tradeoff is worth it.
