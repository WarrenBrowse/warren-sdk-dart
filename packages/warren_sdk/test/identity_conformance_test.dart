@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';
import 'package:warren_sdk/warren_sdk.dart';
import 'package:warren_sdk_ffi/warren_sdk_ffi.dart';

/// Replays the shared `vectors/identity.json` golden vectors through the public
/// Dart surface, backed by the real Rust engine over flutter_rust_bridge. This
/// proves the Dart SDK is byte-for-byte wire-compatible with every sibling SDK;
/// the vectors are the contract and are never edited to make a test pass.
void main() {
  // Resolve paths from the package directory (the test working directory).
  final dylib = _engineLibraryPath();
  if (!File(dylib).existsSync()) {
    // Fail loudly rather than silently skip: the conformance gate must run.
    fail(
      'Native engine library not found at $dylib. Build it first:\n'
      '  (cd native/warren_sdk_frb && cargo build --release)\n'
      'or run `melos run gen` then the build.',
    );
  }

  final vectors = jsonDecode(
    File('../../vectors/identity.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  setUpAll(() {
    WarrenSdkFfi.externalLibraryOverride = ExternalLibrary.open(dylib);
    WarrenSdkFfi.ensureRegistered();
  });

  group('ss58', () {
    final cases = (vectors['ss58'] as Map<String, dynamic>)['vectors'] as List;
    for (final entry in cases) {
      final pair = (entry as List).cast<String>();
      final pubkeyHex = pair[0];
      final address = pair[1];

      test('encode $pubkeyHex', () async {
        expect(await WarrenIdentity.ss58Encode(pubkeyHex), address);
      });

      test('decode $address', () async {
        expect(await WarrenIdentity.ss58Decode(address), pubkeyHex);
      });
    }
  });

  group('bip39 mnemonic to address', () {
    final cases = (vectors['bip39'] as Map<String, dynamic>)['vectors'] as List;
    for (final entry in cases) {
      final v = entry as Map<String, dynamic>;
      test('"${(v['mnemonic'] as String).split(' ').take(2).join(' ')}…"',
          () async {
        expect(
          await WarrenIdentity.addressFromMnemonic(v['mnemonic'] as String),
          v['address'],
        );
      });
    }
  });

  group('request signature', () {
    final cases = (vectors['request_signature']
        as Map<String, dynamic>)['vectors'] as List;
    for (final entry in cases) {
      final v = entry as Map<String, dynamic>;
      test('${v['method']} ${v['path']}', () async {
        final sig = await WarrenSdkFfi().signRequest(
          seedHex: v['seed_hex'] as String,
          method: v['method'] as String,
          path: v['path'] as String,
          body: utf8.encode(v['body_utf8'] as String),
          timestamp: v['timestamp'] as int,
          nonceHex: v['nonce_hex'] as String,
        );
        expect(sig.pubkeySs58, v['pubkey_ss58']);
        expect(sig.signatureHex, v['signature_hex']);
        expect(sig.nonceHex, v['nonce_hex']);
        expect(sig.timestamp, v['timestamp']);
      });
    }
  });

  group('generate round-trips through the engine', () {
    test('fresh mnemonic derives a wb address that decodes and re-encodes',
        () async {
      final mnemonic = await WarrenIdentity.generateMnemonic();
      expect(mnemonic.split(' ').length, 12);

      final address = await WarrenIdentity.addressFromMnemonic(mnemonic);
      expect(address, startsWith('wb'));

      final pubkeyHex = await WarrenIdentity.ss58Decode(address);
      expect(await WarrenIdentity.ss58Encode(pubkeyHex), address);
    });
  });

  group('errors are redacted WarrenIdentityError', () {
    test('addressFromMnemonic rejects a malformed mnemonic', () async {
      await expectLater(
        WarrenIdentity.addressFromMnemonic('not a valid mnemonic'),
        throwsA(isA<WarrenIdentityError>()),
      );
    });

    test('ss58Decode rejects a malformed address', () async {
      await expectLater(
        WarrenIdentity.ss58Decode('not-an-address'),
        throwsA(isA<WarrenIdentityError>()),
      );
    });

    test('ss58Encode rejects a wrong-length key', () async {
      await expectLater(
        WarrenIdentity.ss58Encode('00ff'),
        throwsA(isA<WarrenIdentityError>()),
      );
    });
  });
}

/// The cargo `cdylib` output path for the host platform, relative to the package
/// directory that `flutter test` runs from.
String _engineLibraryPath() {
  const base = '../../native/warren_sdk_frb/target/release/';
  if (Platform.isMacOS) return '${base}libwarren_sdk_frb.dylib';
  if (Platform.isWindows) return '${base}warren_sdk_frb.dll';
  return '${base}libwarren_sdk_frb.so';
}
