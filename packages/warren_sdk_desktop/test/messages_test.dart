import 'package:flutter_test/flutter_test.dart';
import 'package:warren_sdk_desktop/warren_sdk_desktop.dart';

void main() {
  T roundTrip<T extends DaemonMessage>(T message) {
    final decoded = DaemonMessage.fromJson(message.toJson());
    return decoded as T;
  }

  group('message round-trips', () {
    test('ConfigureRequest with and without the optional root pin', () {
      const fullSource = ConfigureRequest(
        mnemonic: 'twelve words',
        apiBase: 'https://api.example.com',
        serverPubkeyPin: 'deadbeef',
        multihopRootPin: 'feed',
      );
      final full = roundTrip(fullSource);
      expect(full.mnemonic, 'twelve words');
      expect(full.apiBase, 'https://api.example.com');
      expect(full.serverPubkeyPin, 'deadbeef');
      expect(full.multihopRootPin, 'feed');

      const minimalSource = ConfigureRequest(
        mnemonic: 'm',
        apiBase: 'https://a',
        serverPubkeyPin: 'p',
      );
      expect(roundTrip(minimalSource).multihopRootPin, isNull);
    });

    test('ConnectRequest', () {
      const source =
          ConnectRequest(exitPubkeyHex: 'ab12', dnsOverTunnel: false);
      final r = roundTrip(source);
      expect(r.exitPubkeyHex, 'ab12');
      expect(r.dnsOverTunnel, isFalse);
    });

    test('DisconnectRequest', () {
      expect(roundTrip(const DisconnectRequest()), isA<DisconnectRequest>());
    });

    test('StateEvent for every state', () {
      for (final state in DaemonConnectionState.values) {
        expect(roundTrip(StateEvent(state)).state, state);
      }
    });

    test('ErrorEvent', () {
      final e = roundTrip(const ErrorEvent(kind: 'tunnel', message: 'down'));
      expect(e.kind, 'tunnel');
      expect(e.message, 'down');
    });
  });

  test('ConfigureRequest.toString never leaks the mnemonic', () {
    const request = ConfigureRequest(
      mnemonic: 'super secret seed phrase',
      apiBase: 'https://api.example.com',
      serverPubkeyPin: 'deadbeef',
    );
    expect(request.toString(), isNot(contains('secret')));
  });

  test('an unknown message type throws', () {
    expect(
      () => DaemonMessage.fromJson({'type': 'nope'}),
      throwsFormatException,
    );
  });

  test('an unknown state name throws', () {
    expect(
      () => DaemonMessage.fromJson({'type': 'state', 'state': 'bogus'}),
      throwsFormatException,
    );
  });
}
