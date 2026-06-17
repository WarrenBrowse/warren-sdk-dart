import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'secure_store.g.dart';

/// The platform secure store (Keychain / Keystore / libsecret / DPAPI). The
/// mnemonic is the only thing the app persists, and only here.
@riverpod
FlutterSecureStorage secureStore(Ref ref) => const FlutterSecureStorage();
