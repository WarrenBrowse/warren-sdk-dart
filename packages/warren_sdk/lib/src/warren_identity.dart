import 'package:warren_sdk_platform_interface/warren_sdk_platform_interface.dart';

/// Stateless identity helpers. These need no account or network and are pinned
/// by the shared golden vectors, so they behave identically to every sibling
/// SDK.
///
/// All work happens in the Rust engine; these are thin, typed entry points.
abstract final class WarrenIdentity {
  /// Generates a fresh 12-word BIP39 mnemonic.
  ///
  /// The returned mnemonic is secret. Store it through the platform secure store
  /// and drop your reference as soon as it is persisted.
  static Future<String> generateMnemonic() =>
      WarrenSdkPlatform.instance.generateMnemonic();

  /// Derives the SS58 `wb...` address from [mnemonic].
  ///
  /// Throws a [WarrenIdentityError] if the mnemonic is malformed.
  static Future<String> addressFromMnemonic(String mnemonic) =>
      WarrenSdkPlatform.instance.addressFromMnemonic(mnemonic);

  /// Encodes a 32-byte public key (hex) to its SS58 `wb...` address.
  ///
  /// Throws a [WarrenIdentityError] if the key is not valid hex of the right
  /// length.
  static Future<String> ss58Encode(String publicKeyHex) =>
      WarrenSdkPlatform.instance.ss58Encode(publicKeyHex);

  /// Decodes an SS58 `wb...` address back to its public key hex.
  ///
  /// Throws a [WarrenIdentityError] if the address checksum or prefix is wrong.
  static Future<String> ss58Decode(String address) =>
      WarrenSdkPlatform.instance.ss58Decode(address);
}
