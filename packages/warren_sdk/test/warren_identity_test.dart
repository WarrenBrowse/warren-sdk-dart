import 'package:flutter_test/flutter_test.dart';
import 'package:warren_sdk/warren_sdk.dart';
import 'package:warren_sdk_platform_interface/warren_sdk_platform_interface.dart';

/// A fake platform that records calls and returns canned values, so the facade
/// delegation can be tested without the native engine.
class _FakePlatform extends WarrenSdkPlatform {
  String? lastMnemonicForAddress;
  String? lastEncodeHex;
  String? lastDecodeAddress;

  @override
  Future<String> generateMnemonic() async => 'word ' * 11 + 'word';

  @override
  Future<String> addressFromMnemonic(String mnemonic) async {
    lastMnemonicForAddress = mnemonic;
    return 'wbFakeAddress';
  }

  @override
  Future<String> ss58Encode(String publicKeyHex) async {
    lastEncodeHex = publicKeyHex;
    return 'wbEncoded';
  }

  @override
  Future<String> ss58Decode(String address) async {
    lastDecodeAddress = address;
    return 'ab' * 32;
  }

  @override
  Future<WarrenClientHandle> createClient(WarrenClientConfig config) async {
    throw UnimplementedError();
  }
}

void main() {
  late _FakePlatform fake;

  setUp(() {
    fake = _FakePlatform();
    WarrenSdkPlatform.instance = fake;
  });

  test('generateMnemonic delegates to the platform', () async {
    expect((await WarrenIdentity.generateMnemonic()).split(' ').length, 12);
  });

  test(
    'addressFromMnemonic forwards the mnemonic and returns the address',
    () async {
      final address = await WarrenIdentity.addressFromMnemonic('my phrase');
      expect(address, 'wbFakeAddress');
      expect(fake.lastMnemonicForAddress, 'my phrase');
    },
  );

  test('ss58Encode and ss58Decode forward their arguments', () async {
    expect(await WarrenIdentity.ss58Encode('00' * 32), 'wbEncoded');
    expect(fake.lastEncodeHex, '00' * 32);

    expect(await WarrenIdentity.ss58Decode('wbSomething'), 'ab' * 32);
    expect(fake.lastDecodeAddress, 'wbSomething');
  });

  test('hasInstance reflects a registered platform', () {
    expect(WarrenSdkPlatform.hasInstance, isTrue);
  });
}
