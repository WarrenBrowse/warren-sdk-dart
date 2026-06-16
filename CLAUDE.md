# warren-sdk-dart: Project Rules for Claude Code

The Dart/Flutter client SDK for the Warren VPN. It is a thin, reactive,
framework-agnostic surface over the Rust engine `warren-sdk-rs` (sibling repo at
`../warren-sdk-rs`). Read `ARCHITECTURE.md` for the layering, `DECISIONS.md` for
the rationale, and `ROADMAP.md` for the phase plan.

## Prime directive: reuse the engine, do not reimplement the protocol

1. **The Warren protocol is Rust.** Identity, crypto, wire codecs, QUIC, TLS-RPK,
   HPKE multihop, netstack, TUN all live in `warren-sdk-rs` and are reused. Dart
   implements only the ergonomic API, reactive state, secret storage and platform
   integration. Never reimplement a frozen format in Dart.
2. **Wire compatibility is inherited and must be proven.** The Dart surface is
   validated by replaying the shared `vectors/` from `warren-sdk-rs`. Never edit
   a vector to make a test pass; fix the code.
3. **One engine, two FFI surfaces.** Flutter uses `flutter_rust_bridge`
   (`native/warren_sdk_frb`). Non-Flutter languages use the engine's uniffi
   surface. Do not blur them.
4. **Framework-agnostic core.** `warren_sdk` pulls in no state-management
   dependency. Riverpod lives only in the optional `warren_sdk_riverpod`.

## TDD is mandatory

Red, green, refactor. Every public API has a direct test. Every documented error
path is triggered by at least one test. Frozen formats get a vector-replay test.
No hollow tests. Widget-free unit tests for the facade (fake the platform
interface); integration tests over the real engine for `warren_sdk_ffi`; live
tests against a real exit for tunnel features (a tunnel feature is only "done"
once validated against a real exit).

## Error handling

- Public errors are a sealed `WarrenError` hierarchy with a stable code and a
  redacted message. Map Rust errors at the bridge; never surface raw
  secret-bearing strings.
- No stringly-typed errors in the public API.

## Secrets and no-log discipline

- The mnemonic is read from the platform secure store, passed once into the
  engine, and zeroized in Rust. Dart keeps only the public address.
- Never log a pubkey, address, IP, nonce or seed in clear, on either side of the
  bridge. Redact to a short prefix if a value is genuinely needed for debugging.

## Dart and Flutter conventions

- Target a current stable Dart/Flutter SDK; Dart pub workspaces for the monorepo.
- `analysis_options.yaml` is strict (`flutter_lints` plus the project additions);
  `dart analyze` and `dart format --set-exit-if-changed` must be clean before any
  commit. Prefer `flutter analyze` is not run in a way that builds; analysis only.
- Immutable models (`final` fields, `const` constructors, value equality). Sealed
  classes for closed unions (errors, connection state).
- Public API is documented with `///`; every package has a library doc comment.
- Modern Riverpod only (v3, `Notifier`/`AsyncNotifier`, code generation); never
  the legacy `StateProvider` / `StateNotifierProvider` / `ChangeNotifierProvider`.

## Language policy: English only in code

All code, comments, doc comments, identifiers and commit messages are in
**English**, to stay aligned with the sibling SDKs. Assistant chat to the user
may be in French.

## Typography: never use the em-dash

The em-dash (U+2014) and en-dash (U+2013) are banned everywhere you author text.
Use a comma, colon, period, a hyphen for ranges, or restructure. Fix stray dashes
in files you touch.

## Comment content: why, not what

A comment explains the non-obvious why: an invariant, a subtle reason, or a
warning that stops a future agent from reintroducing a known bug. No step
narration, no restating the next line. When in doubt, leave it out.

## Build constraints (environment)

- `flutter pub get`, `dart pub get`, `dart analyze`, `flutter analyze`,
  `dart format`, `dart test` and FRB/`build_runner` codegen are allowed.
- Do **not** run `flutter build` or `flutter run` (they break this environment).
- Never use destructive git commands (`stash`, `checkout .`, `restore .`,
  `reset --hard`, `clean`). Use `git log`/`show`/`diff` or ask.
- Commit only when the user asks; subject line only, no body, no Co-Authored-By.

## Commit gates

Before any commit, these must be green:

```bash
dart format --output=none --set-exit-if-changed .
dart analyze
dart test            # in packages that have tests
# plus FRB codegen drift check once P1 lands
```
