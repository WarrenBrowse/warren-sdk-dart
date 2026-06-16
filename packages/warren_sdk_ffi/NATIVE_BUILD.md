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

Each hook points at `../native/warren_sdk_frb` (the crate) and the crate name
`warren_sdk_frb`. `flutter_rust_bridge.yaml` already targets that crate.

## Why it is not committed yet

The plugin platform folders and the vendored `cargokit/` are only exercised by
`flutter build` / `flutter run`. Those commands are out of scope for the
automated environment that bootstrapped this SDK, so wiring them blind would be
unverifiable. They are added (and validated on a real target) when desktop app
integration lands.

## What works today without cargokit

The wire-compatibility gate does not need cargokit. The conformance test builds
the engine directly:

```bash
(cd native/warren_sdk_frb && cargo build --release)
(cd packages/warren_sdk && flutter test)   # loads the cargo-built library
```

This is exactly what CI does for the golden-vector replay (roadmap P7).
