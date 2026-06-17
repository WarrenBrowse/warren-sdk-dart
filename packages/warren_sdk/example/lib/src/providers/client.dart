import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:warren_sdk_riverpod/warren_sdk_riverpod.dart';

import 'client_config.dart';
import 'constants.dart';
import 'secure_store.dart';

/// Builds the live `WarrenClient` from the current `ClientConfig` and the
/// mnemonic in secure storage. Wired in as the override for the package's
/// `warrenClientProvider`, so `subscriptionProvider` and `exitsProvider` resolve
/// against the user's account with no extra glue.
///
/// The mnemonic is read here, handed once to `WarrenClient.create` (which
/// zeroizes it in the Rust engine) and never retained by the app.
Future<WarrenClient> createWarrenClient(Ref ref) async {
  final config = ref.watch(clientConfigControllerProvider);
  if (config == null) {
    throw const WarrenApiError(
      code: 'app/no-config',
      message: 'No client configured. Open the Client tab and create one.',
    );
  }

  final mnemonic = await ref.watch(secureStoreProvider).read(
        key: AppEnv.mnemonicKey,
      );
  if (mnemonic == null || mnemonic.isEmpty) {
    throw const WarrenIdentityError(
      code: 'app/no-mnemonic',
      message: 'No mnemonic in secure storage. Set one in the Client tab.',
    );
  }

  final client = await WarrenClient.create(
    mnemonic: mnemonic,
    apiBase: config.apiBase,
    serverPubkeyPin: config.serverPubkeyPin,
    multihopRootPin: config.multihopRootPin,
    daita: config.daita,
    daitaMachine: config.daitaMachine,
    requestIpv6: config.requestIpv6,
  );
  ref.onDispose(() => unawaited(client.dispose()));
  return client;
}
