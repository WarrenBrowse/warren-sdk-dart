/// Optional Riverpod 3 integration for the Warren VPN SDK.
///
/// These providers wrap the framework-agnostic `warren_sdk` facade. Adding this
/// package is entirely optional; the SDK works with any state-management
/// approach. It uses modern Riverpod 3 with code generation (no legacy
/// `StateProvider` / `StateNotifierProvider` / `ChangeNotifierProvider`).
///
/// The app must supply a live client by overriding [warrenClientProvider] (the
/// client needs the user's mnemonic and account configuration, which the SDK
/// cannot guess):
///
/// ```dart
/// ProviderScope(
///   overrides: [
///     warrenClientProvider.overrideWith((ref) async {
///       final client = await WarrenClient.create(
///         mnemonic: await secureStore.read('warren_mnemonic'),
///         apiBase: Uri.parse('https://api.warrenbrowse.com'),
///         serverPubkeyPin: kWarrenServerPubkeyPin,
///       );
///       ref.onDispose(client.dispose);
///       return client;
///     }),
///   ],
///   child: const App(),
/// );
/// ```
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:warren_sdk/warren_sdk.dart';

export 'package:warren_sdk/warren_sdk.dart';

part 'warren_sdk_riverpod.g.dart';

/// The live [WarrenClient]. Must be overridden by the app (see library docs);
/// the default throws to make a missing override obvious.
@riverpod
Future<WarrenClient> warrenClient(Ref ref) {
  throw UnimplementedError(
    'Override warrenClientProvider with WarrenClient.create(...). '
    'See the warren_sdk_riverpod library documentation.',
  );
}

/// The current subscription snapshot, refreshed on demand.
@riverpod
Future<SubscriptionInfo> subscription(Ref ref) async {
  final client = await ref.watch(warrenClientProvider.future);
  return client.subscription();
}

/// The verified list of available exits.
@riverpod
Future<List<ExitInfo>> exits(Ref ref) async {
  final client = await ref.watch(warrenClientProvider.future);
  return client.listExits();
}

/// The live connection state for a [WarrenSession]. Pass the active session as
/// the family argument; the provider mirrors its broadcast state stream.
@riverpod
Stream<ConnectionState> connectionState(Ref ref, WarrenSession session) =>
    session.states;
