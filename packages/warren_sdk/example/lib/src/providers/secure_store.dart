import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'secure_store.g.dart';

/// The platform secure store (Keychain / Keystore / libsecret / DPAPI). The
/// mnemonic is the only thing the app persists, and only here.
///
/// On macOS this dev build uses the legacy login keychain
/// (`useDataProtectionKeyChain: false`). The modern data-protection keychain
/// needs a `keychain-access-groups` entitlement, which requires real Apple
/// development signing (the unsandboxed ad-hoc build cannot carry it, failing
/// with `errSecMissingEntitlement` / -34018). The legacy keychain works without
/// signing; it prompts once for access, where you click "Always Allow".
@Riverpod(keepAlive: true)
FlutterSecureStorage secureStore(Ref ref) => const FlutterSecureStorage(
      mOptions: MacOsOptions(useDataProtectionKeyChain: false),
    );
