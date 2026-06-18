import 'dart:io' show Platform;

import 'package:flutter_rust_bridge/flutter_rust_bridge.dart'
    show AnyhowException;
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:meta/meta.dart';
import 'package:warren_sdk_platform_interface/warren_sdk_platform_interface.dart';

import 'engine_mapping.dart';
import 'rust/api/client.dart' as rust_client;
import 'rust/api/error.dart';
import 'rust/api/identity.dart' as rust;
import 'rust/frb_generated.dart';
import 'warren_client_ffi.dart';

/// Authentication material for a signed Warren API request.
///
/// A clean, bridge-free mirror of the engine's request signature: the generated
/// type uses `BigInt` for the 64-bit timestamp, this exposes a plain `int`.
@immutable
class WarrenRequestSignature {
  /// Creates a request signature.
  const WarrenRequestSignature({
    required this.pubkeySs58,
    required this.signatureHex,
    required this.timestamp,
    required this.nonceHex,
  });

  /// The signer's SS58 `wb...` address.
  final String pubkeySs58;

  /// The 64-byte Ed25519 signature, hex-encoded.
  final String signatureHex;

  /// The request timestamp echoed back, in seconds.
  final int timestamp;

  /// The 16-byte nonce echoed back, hex-encoded.
  final String nonceHex;
}

/// In-process engine implementation of [WarrenSdkPlatform] (Mode A).
///
/// Delegates to the Warren Rust engine bound through `flutter_rust_bridge`. The
/// native library is initialized lazily and once; identity (P1) is wired, while
/// the client lifecycle (P2) and proxy datapath (P3) land in later phases.
class WarrenSdkFfi extends WarrenSdkPlatform {
  /// Registers this implementation as the active platform, unless a privileged
  /// Mode B implementation has already taken over. Idempotent.
  static void ensureRegistered() {
    // A Mode B implementation that registered first must win for its platform;
    // only claim the slot while it is still the unset sentinel.
    if (!WarrenSdkPlatform.hasInstance) {
      WarrenSdkPlatform.instance = WarrenSdkFfi();
    }
  }

  static Future<void>? _init;
  static ExternalLibrary? _externalLibraryOverride;

  /// Overrides the native library used to initialize the bridge. Tests on the
  /// host VM point this at the `cargo build` output before any call; production
  /// leaves it null so the bundled cargokit-built library is loaded.
  @visibleForTesting
  static set externalLibraryOverride(ExternalLibrary? library) {
    _externalLibraryOverride = library;
  }

  /// Drops the memoized init so a test can reinitialize. Test-only.
  @visibleForTesting
  static void resetForTest() {
    _init = null;
    _externalLibraryOverride = null;
  }

  static Future<void> _ensureInitialized() => _init ??= WarrenRustBridge.init(
        externalLibrary: _externalLibraryOverride ?? _bundledLibrary(),
      );

  /// Resolves the bundled native engine for a real app build.
  ///
  /// On macOS/iOS the engine is force-loaded as a static library into the FFI
  /// plugin framework, whose name (`warren_sdk_ffi`, the Dart plugin) differs
  /// from the crate/stem (`warren_sdk_frb`). `flutter_rust_bridge`'s default
  /// loader looks for `<stem>.framework/<stem>`, which does not exist here, so
  /// the symbols are resolved from the already-loaded process image instead.
  /// Other platforms load the bundled dynamic library by name via the default
  /// loader, so this returns null and lets that path run. Returns null in tests
  /// too (they set [externalLibraryOverride] to the cargo-built library).
  static ExternalLibrary? _bundledLibrary() {
    if (Platform.isMacOS || Platform.isIOS) {
      return ExternalLibrary.process(iKnowHowToUseIt: true);
    }
    return null;
  }

  /// Runs [body] after ensuring the bridge is initialized, mapping a redacted
  /// engine error to a [WarrenIdentityError] with [code].
  Future<T> _identityCall<T>(String code, Future<T> Function() body) async {
    await _ensureInitialized();
    try {
      return await body();
    } on AnyhowException catch (e) {
      // The engine already redacts these messages (no seed, key or address).
      throw WarrenIdentityError(code: code, message: e.message);
    }
  }

  @override
  Future<String> generateMnemonic() =>
      _identityCall('identity/generate', rust.generateMnemonic);

  @override
  Future<String> addressFromMnemonic(String mnemonic) => _identityCall(
        'identity/from-mnemonic',
        () => rust.addressFromMnemonic(mnemonic: mnemonic),
      );

  @override
  Future<String> ss58Encode(String publicKeyHex) => _identityCall(
        'identity/ss58-encode',
        () => rust.ss58Encode(publicKeyHex: publicKeyHex),
      );

  @override
  Future<String> ss58Decode(String address) => _identityCall(
        'identity/ss58-decode',
        () => rust.ss58Decode(address: address),
      );

  /// Signs a Warren API request deterministically from a 32-byte seed (hex).
  ///
  /// Low-level conformance and utility surface; production signing happens
  /// inside the engine client. Pinned by the shared `request_signature` golden
  /// vectors. Throws a [WarrenIdentityError] if the seed or nonce is malformed.
  Future<WarrenRequestSignature> signRequest({
    required String seedHex,
    required String method,
    required String path,
    required List<int> body,
    required int timestamp,
    required String nonceHex,
  }) =>
      _identityCall('identity/sign-request', () async {
        final sig = await rust.signRequest(
          seedHex: seedHex,
          method: method,
          path: path,
          body: body,
          timestamp: BigInt.from(timestamp),
          nonceHex: nonceHex,
        );
        return WarrenRequestSignature(
          pubkeySs58: sig.pubkeySs58,
          signatureHex: sig.signatureHex,
          timestamp: sig.timestamp.toInt(),
          nonceHex: sig.nonceHex,
        );
      });

  @override
  Future<WarrenClientHandle> createClient(WarrenClientConfig config) async {
    await _ensureInitialized();
    try {
      final client = await rust_client.WarrenClientFrb.create(
        mnemonic: config.mnemonic,
        apiBase: config.apiBase.toString(),
        serverPubkeyPin: config.serverPubkeyPin,
        multihopRootPin: config.multihopRootPin,
        daita: config.daita,
        daitaMachine: config.daitaMachine,
        requestIpv6: config.requestIpv6,
        stateDir: config.stateDir,
      );
      final address = await client.address();
      return FfiClientHandle(client, address);
    } on WarrenFfiError catch (error) {
      throw mapEngineError(error);
    }
  }
}
