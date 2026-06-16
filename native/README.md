# native/

Rust glue between the Warren engine and the Dart SDK.

## `warren_sdk_frb`

The `flutter_rust_bridge` (FRB) glue crate for Mode A (in-process engine). It is a
thin delegation layer over `warren-sdk` from the sibling repo `../warren-sdk-rs`;
no protocol logic lives here. FRB scans `src/api` and generates the Dart bindings
that `packages/warren_sdk_ffi` consumes.

Codegen (from the repo root):

```bash
cargo install flutter_rust_bridge_codegen --version 2.12.0
flutter_rust_bridge_codegen generate   # uses ../flutter_rust_bridge.yaml
```

The native build is driven by cargokit from the `warren_sdk_ffi` Flutter FFI
plugin, so app builds compile this crate automatically per platform (see
DECISIONS.md, ADR-007).

## Out of scope here (Mode B)

The privileged datapath does not use FRB. On desktop it is a separate Rust daemon
(reusing `warren-sdk` + `warren-tun`) reached over IPC; on mobile it is a native
network extension embedding the engine through a C ABI / JNI. Those components
live with their platform packages, not here.
