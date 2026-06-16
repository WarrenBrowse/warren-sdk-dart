# warren-sdk-dart

The Dart/Flutter client SDK for the **Warren VPN**. Embed Warren in any Flutter
app, desktop first (Windows, macOS, Linux) and mobile too (Android, iOS), with a
single dependency and an API that fits any app architecture.

> Status: design and scaffolding. See [ROADMAP.md](ROADMAP.md) for what is built
> and what is next.

## What this is

A thin, idiomatic, reactive Dart surface over the audited Warren Rust engine
(`warren-sdk-rs`). The protocol, crypto and tunnel are **not** reimplemented in
Dart: they are reused from Rust, the same way Mullvad, Cloudflare WARP and
Tailscale ship one native engine behind thin per-platform wrappers. Read
[ARCHITECTURE.md](ARCHITECTURE.md) for the full design and
[DECISIONS.md](DECISIONS.md) for the why.

## Two connection modes

- **Proxy (default, non-root, every platform).** The engine runs in-process via
  `flutter_rust_bridge` and exposes a local SOCKS5 / HTTP proxy. Nothing to
  install, no privilege.
- **System VPN (privileged, out-of-process).** A real TUN device captures all OS
  traffic, run by a privileged desktop daemon or a mobile network extension that
  embeds the engine; the app drives it over IPC.

The public API is identical across modes.

## Quick start (target API)

```dart
import 'package:warren_sdk/warren_sdk.dart';

final warren = await WarrenClient.create(
  mnemonic: await secureStore.read('warren_mnemonic'),
  apiBase: Uri.parse('https://api.warrenbrowse.com'),
  serverPubkeyPin: kWarrenServerPubkeyPin,
);

final expiry = await warren.subscriptionExpiry();
final exits = await warren.listExits();
final exit = WarrenClient.selectExit(exits, const ExitQuery(country: 'RO'))!;

final session = await warren.connect(exit, mode: ConnectMode.proxy);
session.states.listen((s) => print('connection: $s'));
// ... use the local SOCKS5 endpoint at session.socks5Endpoint ...
await session.disconnect();
```

Apps add exactly one dependency, `warren_sdk`. Riverpod users may also add the
optional `warren_sdk_riverpod`.

## Packages

| Package | What it is |
|---|---|
| [`warren_sdk`](packages/warren_sdk) | The app-facing facade. Add this. |
| [`warren_sdk_platform_interface`](packages/warren_sdk_platform_interface) | Federated-plugin contract. |
| [`warren_sdk_ffi`](packages/warren_sdk_ffi) | In-process engine via `flutter_rust_bridge` (Mode A). |
| [`warren_sdk_desktop`](packages/warren_sdk_desktop) | Mode B desktop: daemon IPC protocol and client. |
| [`warren_sdk_mobile`](packages/warren_sdk_mobile) | Mode B mobile: network-extension channel controller. |
| [`warren_sdk_riverpod`](packages/warren_sdk_riverpod) | Optional Riverpod 3 integration. |
| `native/warren_sdk_frb` | Rust glue crate exposing the FRB API. |

The Mode B datapath (privileged daemon, mobile network extensions) is the gated
half: see each package's `IPC.md` / `MOBILE.md`.

## Repository layout and dependencies

This repo is **standalone on the Dart side** and reuses the Rust engine without
vendoring it:

- **Engine**: the native glue crate (`native/warren_sdk_frb`) depends on the
  Warren engine through a **pinned git dependency** (`warren-sdk-rs`, tag
  `v0.0.1`), so builds are reproducible on any machine and in CI with no
  assumption about on-disk layout. To adopt a newer engine, move the tag in
  `native/warren_sdk_frb/Cargo.toml` and re-run FRB codegen.
- **Golden vectors**: `vectors/` is a **git submodule** of the shared
  `warren-vectors` repository (the same single source of truth used by
  `warren-sdk-rs` and every sibling SDK, no duplication).

Both `warren-sdk-rs` and `warren-vectors` are private; cloning and CI need read
access to them.

## Clone

```bash
git clone --recurse-submodules git@github.com:WarrenBrowse/warren-sdk-dart.git
# or, in an existing checkout:
git submodule update --init
```

## Development

A Dart pub workspace. With the Dart/Flutter SDK (and a Rust toolchain for the
native build):

```bash
dart pub get                 # resolve the whole workspace
melos run analyze            # analyze every package
melos run test               # test every package
melos run gen                # run code generation (FRB, Riverpod, etc.)
```

### Local co-development against a working copy of the engine

The engine is pinned by git tag so CI and releases are reproducible. To build
against a local checkout of `warren-sdk-rs` instead (for example when changing
both repos together), add a **gitignored** cargo path override; it never affects
CI or other developers:

```bash
mkdir -p native/warren_sdk_frb/.cargo
cat > native/warren_sdk_frb/.cargo/config.toml <<'EOF'
paths = ["../../../warren-sdk-rs/crates/warren-sdk"]
EOF
```

Remove the file to go back to the pinned git dependency. `native/warren_sdk_frb/.cargo/`
is gitignored for exactly this purpose.

### CI

`.github/workflows/ci.yml` runs format, analyze and test on GitHub-hosted
runners; the current facade tests need neither the engine nor the vectors. When
the native vector-replay tests land (roadmap P1), CI gains a Rust job and a
submodule checkout that needs a `VECTORS_TOKEN` secret (a PAT with read access to
`warren-vectors`); set it as an org or repo secret.

See [CLAUDE.md](CLAUDE.md) for the engineering conventions (TDD, English-only, no
em-dash, no-log discipline, wire compatibility) shared with the Rust engine.

## License

AGPL-3.0-or-later, matching `warren-sdk-rs`.
