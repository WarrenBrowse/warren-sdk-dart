import 'package:flutter_test/flutter_test.dart';
import 'package:warren_sdk_desktop/warren_sdk_desktop.dart';
import 'package:warren_sdk_platform_interface/warren_sdk_platform_interface.dart';

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
        daita: true,
        daitaMachine: 'tamaraw',
        requestIpv6: false,
        lockdown: true,
      );
      final full = roundTrip(fullSource);
      expect(full.mnemonic, 'twelve words');
      expect(full.apiBase, 'https://api.example.com');
      expect(full.serverPubkeyPin, 'deadbeef');
      expect(full.multihopRootPin, 'feed');
      expect(full.daita, isTrue);
      expect(full.daitaMachine, 'tamaraw');
      expect(full.requestIpv6, isFalse);
      expect(full.lockdown, isTrue);

      const minimalSource = ConfigureRequest(
        mnemonic: 'm',
        apiBase: 'https://a',
        serverPubkeyPin: 'p',
      );
      final minimal = roundTrip(minimalSource);
      expect(minimal.multihopRootPin, isNull);
      // Defaults: DAITA off, IPv6 on, no machine.
      expect(minimal.daita, isFalse);
      expect(minimal.daitaMachine, isNull);
      expect(minimal.requestIpv6, isTrue);
      // Lockdown is opt-in: an older client that never sends it stays off.
      expect(minimal.lockdown, isFalse);
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

  group('a daemon error event, as warrend frames it', () {
    ErrorEvent parse(Map<String, Object?> json) =>
        DaemonMessage.fromJson({'type': 'error', ...json}) as ErrorEvent;

    test('carries a clock refusal and its offset', () {
      final e = parse({
        'kind': 'api',
        'message': 'clock',
        'clockSkew': {'offsetSecs': -3600},
      });
      expect(e.clockSkew?.offsetSecs, -3600);
      expect(e.fatalCause, isNull);
    });

    test('keeps a clock refusal whose offset the server did not give', () {
      final e = parse({
        'kind': 'api',
        'message': 'clock',
        'clockSkew': {'offsetSecs': null},
      });
      expect(e.clockSkew, isNotNull);
      expect(e.clockSkew?.offsetSecs, isNull);
    });

    test('carries the engine fatal cause by its name', () {
      final e = parse({
        'kind': 'tunnel',
        'message': 'no entry',
        'fatalCause': 'noReachableEntry',
      });
      expect(e.fatalCause, WarrenFatalCause.noReachableEntry);
      expect(e.clockSkew, isNull);
    });

    test('reads a fatal cause this client does not know as a refusal', () {
      // Still definitive: read as retryable, it would loop a fatal forever.
      final e = parse({
        'kind': 'tunnel',
        'message': 'm',
        'fatalCause': 'somethingNewer',
      });
      expect(e.fatalCause, WarrenFatalCause.policyRefused);
    });

    test('an untyped failure carries neither', () {
      final e = parse({'kind': 'tunnel', 'message': 'down'});
      expect(e.clockSkew, isNull);
      expect(e.fatalCause, isNull);
    });

    test('round-trips its typed fields', () {
      final e = roundTrip(
        const ErrorEvent(
          kind: 'api',
          message: 'm',
          clockSkew: DaemonClockSkew(offsetSecs: 42),
          fatalCause: WarrenFatalCause.deviceLimit,
        ),
      );
      expect(e.clockSkew?.offsetSecs, 42);
      expect(e.fatalCause, WarrenFatalCause.deviceLimit);
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

  test('the daemon draining wire state parses', () {
    // The daemon announces teardown with `draining` before the terminal
    // `disconnected`; a client that cannot parse it would break on every
    // disconnect.
    final message =
        DaemonMessage.fromJson(const {'type': 'state', 'state': 'draining'});
    expect(message, isA<StateEvent>());
    expect((message as StateEvent).state, DaemonConnectionState.draining);
  });
}
