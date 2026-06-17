# Native build (cargokit)

`warren_sdk_ffi` is a Flutter **FFI plugin**: the Warren Rust engine
(`native/warren_sdk_frb`) is compiled from source and bundled into the host app
by [cargokit](https://github.com/irondash/cargokit), the same toolkit used by
`flutter_rust_bridge`'s own templates.

## How it is meant to be wired

cargokit hooks into each platform's native build system and runs
`cargo build` for `native/warren_sdk_frb`, then links the resulting library:

| Platform | Hook | Output |
|---|---|---|
| Linux | `linux/CMakeLists.txt` includes `cargokit/cmake/cargokit.cmake` | `libwarren_sdk_frb.so` |
| Windows | `windows/CMakeLists.txt` includes the same | `warren_sdk_frb.dll` |
| macOS | `macos/warren_sdk_ffi.podspec` runs `cargokit/build_pod.sh` | static lib |
| iOS | `ios/warren_sdk_ffi.podspec` runs `cargokit/build_pod.sh` | static lib |
| Android | `android/build.gradle` applies `cargokit/gradle/plugin.gradle` | `.so` per ABI |

Each hook points at the crate relative to its platform folder
(`../../../native/warren_sdk_frb`, since the crate lives at the repo root, not
inside the plugin) and the crate/lib name `warren_sdk_frb`.
`flutter_rust_bridge.yaml` already targets that crate.

## Status: wired

The platform folders (`macos/`, `ios/`, `linux/`, `windows/`, `android/`) and
the vendored `cargokit/` are committed. The macОS path is validated by building
the example app (`packages/warren_sdk/example`) with `flutter build macos`: the
podspec script phase compiles `warren_sdk_frb` into `libwarren_sdk_frb.a` and
force-loads it into the plugin framework, and the in-process engine then loads
through `flutter_rust_bridge`'s default loader (no `ExternalLibrary` override).
The other desktop/mobile targets reuse the same cargokit wiring and are validated
on their own hosts.

## What works today without cargokit

The wire-compatibility gate does not need cargokit. The conformance test builds
the engine directly:

```bash
(cd native/warren_sdk_frb && cargo build --release)
(cd packages/warren_sdk && flutter test)   # loads the cargo-built library
```

This is exactly what CI does for the golden-vector replay (roadmap P7).
