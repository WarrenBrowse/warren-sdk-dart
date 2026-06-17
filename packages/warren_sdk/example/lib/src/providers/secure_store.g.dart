// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'secure_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The platform secure store (Keychain / Keystore / libsecret / DPAPI). The
/// mnemonic is the only thing the app persists, and only here.

@ProviderFor(secureStore)
const secureStoreProvider = SecureStoreProvider._();

/// The platform secure store (Keychain / Keystore / libsecret / DPAPI). The
/// mnemonic is the only thing the app persists, and only here.

final class SecureStoreProvider extends $FunctionalProvider<
    FlutterSecureStorage,
    FlutterSecureStorage,
    FlutterSecureStorage> with $Provider<FlutterSecureStorage> {
  /// The platform secure store (Keychain / Keystore / libsecret / DPAPI). The
  /// mnemonic is the only thing the app persists, and only here.
  const SecureStoreProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'secureStoreProvider',
          isAutoDispose: true,
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

String _$secureStoreHash() => r'3839f80f4a408779979632df3b22e0bc24eb077b';
