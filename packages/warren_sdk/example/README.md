# Warren SDK example app

A Flutter app that exercises **every** feature of the Warren VPN Dart SDK, wired
through the optional Riverpod 3 integration (`warren_sdk_riverpod`). It is the
hands-on counterpart to the package docs: each tab maps to one slice of the
public API.

| Tab | SDK surface |
|---|---|
| **Overview** | The active environment and a guide to what each tab tests. |
| **Identity** | `WarrenIdentity.generateMnemonic`, `addressFromMnemonic`, `ss58Encode`, `ss58Decode`. Stateless, no account or network. |
| **Client** | The mnemonic in the platform secure store, then `WarrenClient.create` with every option (`apiBase`, `serverPubkeyPin`, `multihopRootPin`, `daita` / `daitaMachine`, `requestIpv6`), and `dispose`. |
| **Account** | `subscription()` snapshot and `redeemVoucher()`. |
| **Exits** | `listExits()` and `selectExit()` driven by an `ExitQuery` filter. |
| **Connection** | `connect()` in proxy or system-VPN mode, full `ConnectOptions`, the live `states` stream (`Connecting` / `Connected` / `Reconnecting` / `Disconnected` / `ConnectionFailed`), proxy `endpoints`, and `disconnect()`. |
| **Activity** | A redacted log of every SDK call and every mapped `WarrenError`. |

## Architecture

- **State**: Riverpod 3 with code generation. The app overrides the package's
  `warrenClientProvider` to build a live client from the in-app config plus the
  mnemonic in secure storage, so `subscriptionProvider` and `exitsProvider`
  resolve with no extra glue. The active session feeds
  `connectionStateProvider(session)`.
- **Secrets**: the 12-word mnemonic lives only in `flutter_secure_storage`
  (Keychain / Keystore / libsecret / DPAPI). It is read once, handed to the
  engine (which zeroizes it) and never retained or logged. The UI redacts every
  address to a short prefix.
- **Native engine**: `warren_sdk_ffi` is a Flutter FFI plugin; the Rust engine
  (`native/warren_sdk_frb`) is compiled from source and bundled by **cargokit**
  during `flutter build` / `flutter run`. No prebuilt binary, no manual library
  loading.

## Run it

The repo pins Flutter with FVM; use `fvm flutter`.

```bash
# from packages/warren_sdk/example
fvm flutter pub get
fvm dart run build_runner build      # Riverpod codegen (once, or after edits)
fvm flutter run -d macos
```

The first build compiles the Rust engine, so it takes a while; later builds are
incremental.

### Validate

```bash
fvm flutter test                                          # unit + widget tests
fvm flutter test integration_test/engine_test.dart -d macos   # real bundled engine
```

The integration test launches the app with the cargokit-bundled engine and
exercises it in-process (generate a mnemonic, derive an address), proving Mode A
loads end-to-end with no manual library handling.

### Configuration (optional `--dart-define`s)

Sensible defaults target the Warren test network; everything is also editable in
the **Client** tab at runtime.

| Define | Default | Meaning |
|---|---|---|
| `WARREN_API_BASE` | `https://api.warrenbrowse.com` | Account API base. |
| `WARREN_SERVER_PIN` | _(the Warren network pin)_ | Pinned server public key (hex). A public key, not a secret. |
| `WARREN_DAEMON_SOCKET` | `/tmp/warren-sdk-daemon.sock` | Mode B daemon socket. |

So against the test network you only need to supply a mnemonic (Client tab, or
the `WARREN_MNEMONIC` env button).

On desktop you can prefill the mnemonic from a `WARREN_MNEMONIC` environment
variable (a "Load from env" button appears in the Client tab); it is written
straight to the secure store, never kept in app state.

```bash
WARREN_MNEMONIC="word1 word2 …" fvm flutter run -d macos \
  --dart-define=WARREN_SERVER_PIN=<hex>
```

### Mode B (system VPN) on desktop

Proxy mode (the default) needs nothing but the app. System-VPN mode needs the
privileged `warrend` daemon running and listening on `WARREN_DAEMON_SOCKET`:

```bash
# from the repo root, see native/warrend
sudo target/release/warrend /tmp/warren-sdk-daemon.sock
```

Without it, selecting **System VPN** and connecting surfaces a
`WarrenPrivilegeError`, which the app shows as-is. Disconnect any other active
VPN first.

> The macOS dev build intentionally **disables the App Sandbox** so the app can
> open raw network sockets and reach the daemon's `/tmp` socket. Re-enable the
> sandbox (with `network.client` and keychain sharing) for a shipped app.
