import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:warren_sdk_riverpod/warren_sdk_riverpod.dart';

import 'activity_log.dart';
import 'constants.dart';
import 'secure_store.dart';

part 'wallet.g.dart';

/// The wallet gate: the SS58 `wb...` address derived from the mnemonic in the
/// secure store, or null when no wallet exists yet (drives onboarding). Holds
/// no secret; the mnemonic is read transiently to derive the address.
@Riverpod(keepAlive: true)
class Wallet extends _$Wallet {
  @override
  Future<String?> build() async {
    // Dev override: a runtime WARREN_MNEMONIC skips onboarding and the keychain.
    final env = AppEnv.envMnemonic;
    if (env != null) return WarrenIdentity.addressFromMnemonic(env);

    final mnemonic = await ref.watch(secureStoreProvider).read(
          key: AppEnv.mnemonicKey,
        );
    if (mnemonic == null || mnemonic.isEmpty) return null;
    return WarrenIdentity.addressFromMnemonic(mnemonic);
  }

  /// Generates a fresh wallet and stores it.
  Future<void> generate() async {
    final mnemonic = await WarrenIdentity.generateMnemonic();
    await _store(mnemonic, 'generated');
  }

  /// Imports an existing recovery phrase after validating it.
  Future<void> import(String mnemonic) async {
    final phrase = mnemonic.trim();
    // Deriving validates the phrase; an invalid one throws WarrenIdentityError.
    await WarrenIdentity.addressFromMnemonic(phrase);
    await _store(phrase, 'imported');
  }

  /// Wipes the wallet from the secure store and tears down the live client.
  Future<void> reset() async {
    await ref.read(secureStoreProvider).delete(key: AppEnv.mnemonicKey);
    ref.read(activityLogProvider.notifier).info('wallet', 'wallet reset');
    ref.invalidate(warrenClientProvider);
    ref.invalidateSelf();
  }

  Future<void> _store(String mnemonic, String how) async {
    await ref
        .read(secureStoreProvider)
        .write(key: AppEnv.mnemonicKey, value: mnemonic);
    ref.read(activityLogProvider.notifier).success('wallet', 'wallet $how');
    ref.invalidate(warrenClientProvider);
    ref.invalidateSelf();
  }
}
