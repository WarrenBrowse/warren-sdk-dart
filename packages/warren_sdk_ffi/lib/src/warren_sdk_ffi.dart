import 'package:warren_sdk_platform_interface/warren_sdk_platform_interface.dart';

/// In-process engine implementation of [WarrenSdkPlatform] (Mode A).
///
/// Delegates to the Warren Rust engine bound through `flutter_rust_bridge`. The
/// generated bindings and the wiring of each method land in roadmap phase P1
/// (identity), P2 (account) and P3 (proxy datapath); until then the methods
/// throw a clear [WarrenUnsupportedError] so the surface is honest and
/// analyzable.
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

  static Never _pending(String surface) => throw WarrenUnsupportedError(
        code: 'ffi/not-generated',
        message:
            'The flutter_rust_bridge bindings for "$surface" are not generated '
            'yet. Run code generation and build the engine (roadmap P1-P3).',
      );

  @override
  Future<String> generateMnemonic() async => _pending('generateMnemonic');

  @override
  Future<String> addressFromMnemonic(String mnemonic) async =>
      _pending('addressFromMnemonic');

  @override
  Future<String> ss58Encode(String publicKeyHex) async =>
      _pending('ss58Encode');

  @override
  Future<String> ss58Decode(String address) async => _pending('ss58Decode');

  @override
  Future<WarrenClientHandle> createClient(WarrenClientConfig config) async =>
      _pending('createClient');
}
