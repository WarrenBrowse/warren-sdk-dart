// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'wallet.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The wallet gate: the SS58 `wb...` address derived from the mnemonic in the
/// secure store, or null when no wallet exists yet (drives onboarding). Holds
/// no secret; the mnemonic is read transiently to derive the address.

@ProviderFor(Wallet)
const walletProvider = WalletProvider._();

/// The wallet gate: the SS58 `wb...` address derived from the mnemonic in the
/// secure store, or null when no wallet exists yet (drives onboarding). Holds
/// no secret; the mnemonic is read transiently to derive the address.
final class WalletProvider extends $AsyncNotifierProvider<Wallet, String?> {
  /// The wallet gate: the SS58 `wb...` address derived from the mnemonic in the
  /// secure store, or null when no wallet exists yet (drives onboarding). Holds
  /// no secret; the mnemonic is read transiently to derive the address.
  const WalletProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'walletProvider',
          isAutoDispose: false,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$walletHash();

  @$internal
  @override
  Wallet create() => Wallet();
}

String _$walletHash() => r'60396caf311527b25fb510b8cc4e80c3765b07fb';

/// The wallet gate: the SS58 `wb...` address derived from the mnemonic in the
/// secure store, or null when no wallet exists yet (drives onboarding). Holds
/// no secret; the mnemonic is read transiently to derive the address.

abstract class _$Wallet extends $AsyncNotifier<String?> {
  FutureOr<String?> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<AsyncValue<String?>, String?>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<AsyncValue<String?>, String?>,
        AsyncValue<String?>,
        Object?,
        Object?>;
    element.handleValue(ref, created);
  }
}
