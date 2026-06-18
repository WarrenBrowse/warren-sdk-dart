// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'secure_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The platform secure store (Keychain / Keystore / libsecret / DPAPI). The
/// mnemonic is the only thing the app persists, and only here.
///
/// On macOS this dev build uses the legacy login keychain
/// (`useDataProtectionKeyChain: false`). The modern data-protection keychain
/// needs a `keychain-access-groups` entitlement, which requires real Apple
/// development signing (the unsandboxed ad-hoc build cannot carry it, failing
/// with `errSecMissingEntitlement` / -34018). The legacy keychain works without
/// signing; it prompts once for access, where you click "Always Allow".

@ProviderFor(secureStore)
const secureStoreProvider = SecureStoreProvider._();

/// The platform secure store (Keychain / Keystore / libsecret / DPAPI). The
/// mnemonic is the only thing the app persists, and only here.
///
/// On macOS this dev build uses the legacy login keychain
/// (`useDataProtectionKeyChain: false`). The modern data-protection keychain
/// needs a `keychain-access-groups` entitlement, which requires real Apple
/// development signing (the unsandboxed ad-hoc build cannot carry it, failing
/// with `errSecMissingEntitlement` / -34018). The legacy keychain works without
/// signing; it prompts once for access, where you click "Always Allow".

final class SecureStoreProvider extends $FunctionalProvider<
    FlutterSecureStorage,
    FlutterSecureStorage,
    FlutterSecureStorage> with $Provider<FlutterSecureStorage> {
  /// The platform secure store (Keychain / Keystore / libsecret / DPAPI). The
  /// mnemonic is the only thing the app persists, and only here.
  ///
  /// On macOS this dev build uses the legacy login keychain
  /// (`useDataProtectionKeyChain: false`). The modern data-protection keychain
  /// needs a `keychain-access-groups` entitlement, which requires real Apple
  /// development signing (the unsandboxed ad-hoc build cannot carry it, failing
  /// with `errSecMissingEntitlement` / -34018). The legacy keychain works without
  /// signing; it prompts once for access, where you click "Always Allow".
  const SecureStoreProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'secureStoreProvider',
          isAutoDispose: false,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$secureStoreHash();

  @$internal
  @override
  $ProviderElement<FlutterSecureStorage> $createElement(
          $ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  FlutterSecureStorage create(Ref ref) {
    return secureStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FlutterSecureStorage value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FlutterSecureStorage>(value),
    );
  }
}

String _$secureStoreHash() => r'e76939447aca46c90564c5847336ff246ee8a86e';
