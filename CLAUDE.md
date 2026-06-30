# warren-sdk-dart: Project Rules for Claude Code

The Dart/Flutter client SDK for the Warren VPN. It is a thin, reactive,
framework-agnostic surface over the Rust engine `warren-sdk-rs` (sibling repo at
`../warren-sdk-rs`). Read `ARCHITECTURE.md` for the layering, `DECISIONS.md` for
the rationale, and `ROADMAP.md` for the phase plan.

> Shared Warren rules (single source of truth: WarrenBrowse/warren-workspace).
> They resolve when this repo is checked out inside the workspace (mani sync);
> cloned standalone, the imports just warn harmlessly.
@../shared/rules/00-conventions.md
@../shared/rules/10-tdd.md
@../shared/rules/20-errors-secrets.md
@../shared/rules/30-git-commits.md
@../shared/rules/40-wire-vectors.md

## Prime directive: reuse the engine, do not reimplement the protocol

1. **The Warren protocol is Rust.** Identity, crypto, wire codecs, QUIC, TLS-RPK,
   HPKE multihop, netstack, TUN all live in `warren-sdk-rs` and are reused. Dart
   implements only the ergonomic API, reactive state, secret storage and platform
   integration. Never reimplement a frozen format in Dart.
2. **Wire compatibility is inherited and must be proven** (see the shared
   wire-vectors rule). The Dart surface is validated by replaying the shared
   `vectors/` from `warren-sdk-rs`.
3. **One engine, two FFI surfaces.** Flutter uses `flutter_rust_bridge`
   (`native/warren_sdk_frb`). Non-Flutter languages use the engine's uniffi
   surface. Do not blur them.
4. **Framework-agnostic core.** `warren_sdk` pulls in no state-management
   dependency. Riverpod lives only in the optional `warren_sdk_riverpod`.

## Testing specifics (in addition to the shared TDD rule)

Widget-free unit tests for the facade (fake the platform interface); integration
tests over the real engine for `warren_sdk_ffi`; live tests against a real exit
for tunnel features (a tunnel feature is only "done" once validated against a
real exit). Frozen formats get a vector-replay test.

## Error handling specifics

Public errors are a sealed `WarrenError` hierarchy with a stable code and a
redacted message. Map Rust errors at the bridge; never surface raw
secret-bearing strings (see the shared errors/secrets rule).

## Dart and Flutter conventions

- Target a current stable Dart/Flutter SDK; Dart pub workspaces for the monorepo.
- `analysis_options.yaml` is strict (`flutter_lints` plus the project additions);
  `dart analyze` and `dart format --set-exit-if-changed` must be clean before any
  commit. Analysis only; never run a Flutter build to check.
- Immutable models (`final` fields, `const` constructors, value equality). Sealed
  classes for closed unions (errors, connection state).
- Public API is documented with `///`; every package has a library doc comment.
- Modern Riverpod only (v3, `Notifier`/`AsyncNotifier`, code generation); never
  the legacy `StateProvider` / `StateNotifierProvider` / `ChangeNotifierProvider`.

## Build constraints (environment)

- `flutter pub get`, `dart pub get`, `dart analyze`, `flutter analyze`,
  `dart format`, `dart test` and FRB/`build_runner` codegen are allowed.
- Do **not** run `flutter build` or `flutter run` (they break this environment).

## Commit gates

Before any commit, these must be green:

```bash
dart format --output=none --set-exit-if-changed .
dart analyze
dart test            # in packages that have tests
# plus FRB codegen drift check once P1 lands
```
