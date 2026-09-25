import 'package:flutter_test/flutter_test.dart';
import 'package:warren_sdk_ffi/src/engine_mapping.dart';
import 'package:warren_sdk_ffi/src/rust/api/client.dart';
import 'package:warren_sdk_ffi/src/rust/api/datapath.dart';
import 'package:warren_sdk_ffi/src/rust/api/error.dart';
import 'package:warren_sdk_platform_interface/warren_sdk_platform_interface.dart';

/// Unit tests for the bridge-to-public mapping. These need no native engine:
/// the engine error and exit DTO are plain generated data classes.
void main() {
  group('mapEngineError keeps the message and picks the right subtype', () {
    final cases = <WarrenErrorKind, ({Type type, String code})>{
      WarrenErrorKind.identity: (
        type: WarrenIdentityError,
        code: 'identity/engine'
      ),
      WarrenErrorKind.api: (type: WarrenApiError, code: 'api/engine'),
      WarrenErrorKind.discovery: (
        type: WarrenDiscoveryError,
        code: 'discovery/engine'
      ),
      WarrenErrorKind.tunnel: (type: WarrenTunnelError, code: 'tunnel/engine'),
      WarrenErrorKind.privilege: (
        type: WarrenPrivilegeError,
        code: 'privilege/engine'
      ),
    };

    cases.forEach((kind, expected) {
      test('$kind', () {
        final mapped = mapEngineError(
          WarrenFfiError(kind: kind, message: 'redacted detail'),
        );
        expect(mapped.runtimeType, expected.type);
        expect(mapped.code, expected.code);
        expect(mapped.message, 'redacted detail');
      });
    });
  });

  group('exitInfoFromDto', () {
    test('maps the public exit fields', () {
      final dto = ExitInfoDto(
        id: 'exit-1',
        country: 'RO',
        city: 'Bucharest',
        supportsIpv6: true,
        coverDomain: 'cover.example.com',
        weight: BigInt.from(42),
        isActive: true,
      );
      final info = exitInfoFromDto(dto);
      expect(info.id, 'exit-1');
      expect(info.country, 'RO');
      expect(info.city, 'Bucharest');
      expect(info.supportsIpv6, isTrue);
      expect(info.coverDomain, 'cover.example.com');
      expect(info.weight, 42);
      expect(info.isActive, isTrue);
    });
  });

  group('tunnelCheckFromDto', () {
    test('maps an exit hit with location', () {
      const dto = TunnelCheckDto(
        ip: '203.0.113.7',
        isExit: true,
        country: 'NL',
        city: 'Amsterdam',
      );
      final check = tunnelCheckFromDto(dto);
      expect(check.ip, '203.0.113.7');
      expect(check.isExit, isTrue);
      expect(check.country, 'NL');
      expect(check.city, 'Amsterdam');
    });

    test('maps a non-exit with no location', () {
      const dto = TunnelCheckDto(ip: '192.0.2.7', isExit: false);
      final check = tunnelCheckFromDto(dto);
      expect(check.isExit, isFalse);
      expect(check.country, isNull);
      expect(check.city, isNull);
    });
  });

  group('mapMigrationEvent', () {
    test('maps each outcome and keeps the advisory fields', () {
      final dto = MigrationEventDto(
        deadlineUnixSecs: BigInt.from(1767225600),
        reasonCode: 3,
        outcome: MigrationOutcomeDto.completed,
      );
      expect(
        mapMigrationEvent(dto),
        const MigrationEvent(
          deadlineUnixSecs: 1767225600,
          reasonCode: 3,
          outcome: MigrationOutcome.completed,
        ),
      );
      expect(
        mapMigrationEvent(
          MigrationEventDto(
            deadlineUnixSecs: BigInt.from(1767225600),
            reasonCode: 0,
            outcome: MigrationOutcomeDto.migrating,
          ),
        ).outcome,
        MigrationOutcome.migrating,
      );
      expect(
        mapMigrationEvent(
          MigrationEventDto(
            deadlineUnixSecs: BigInt.from(1767225600),
            reasonCode: 0,
            outcome: MigrationOutcomeDto.cancelledPortConflict,
          ),
        ).outcome,
        MigrationOutcome.cancelledPortConflict,
      );
    });

    test('the u64::MAX sentinel becomes a null soft-drain deadline', () {
      final dto = MigrationEventDto(
        // u64::MAX on the wire means "soft drain, no hard-close deadline".
        deadlineUnixSecs: (BigInt.one << 64) - BigInt.one,
        reasonCode: 0,
        outcome: MigrationOutcomeDto.migrating,
      );
      expect(mapMigrationEvent(dto).deadlineUnixSecs, isNull);
    });
  });

  group('mapPortFollowOutcome', () {
    test('maps each kind to its sealed subtype', () {
      expect(
        mapPortFollowOutcome(
          const PortFollowOutcomeDto(
            kind: PortFollowOutcomeKindDto.kept,
            port: 51820,
          ),
        ),
        const PortKept(port: 51820),
      );
      expect(
        mapPortFollowOutcome(
          const PortFollowOutcomeDto(
            kind: PortFollowOutcomeKindDto.changed,
            previousPort: 51820,
            port: 40000,
          ),
        ),
        const PortChanged(previousPort: 51820, port: 40000),
      );
      expect(
        mapPortFollowOutcome(
          const PortFollowOutcomeDto(
            kind: PortFollowOutcomeKindDto.conflictStayed,
            port: 51820,
          ),
        ),
        const PortConflictStayed(pinnedPort: 51820),
      );
      expect(
        mapPortFollowOutcome(
          const PortFollowOutcomeDto(kind: PortFollowOutcomeKindDto.failed),
        ),
        const PortFollowFailed(),
      );
    });

    test('an entitlement refusal keeps whether one was presented', () {
      for (final presented in [true, false]) {
        expect(
          mapPortFollowOutcome(
            PortFollowOutcomeDto(
              kind: PortFollowOutcomeKindDto.notAuthorized,
              entitlementPresented: presented,
            ),
          ),
          PortForwardNotAuthorized(entitlementPresented: presented),
        );
      }
    });

    test('a ban keeps its reason and its lapse', () {
      expect(
        mapPortFollowOutcome(
          PortFollowOutcomeDto(
            kind: PortFollowOutcomeKindDto.banned,
            banReason: BanReasonDto.portForwardingAbuse,
            banLapsesAtUnixSecs: BigInt.from(1790000000),
          ),
        ),
        const PortForwardBanned(
          reason: BanReason.portForwardingAbuse,
          lapsesAtUnixSecs: 1790000000,
        ),
      );
      expect(
        mapPortFollowOutcome(
          const PortFollowOutcomeDto(
            kind: PortFollowOutcomeKindDto.banned,
            banReason: BanReasonDto.other,
          ),
        ),
        const PortForwardBanned(reason: BanReason.other),
      );
    });

    test('a first grant maps to PortChanged with no previous port', () {
      expect(
        mapPortFollowOutcome(
          const PortFollowOutcomeDto(
            kind: PortFollowOutcomeKindDto.changed,
            port: 40000,
          ),
        ),
        const PortChanged(port: 40000),
      );
    });

    test('a port-bearing kind missing its port degrades to failed', () {
      // A malformed event must never throw in the mapping layer: the safe
      // reading of an outcome without its port is "not established, retrying".
      for (final kind in [
        PortFollowOutcomeKindDto.kept,
        PortFollowOutcomeKindDto.changed,
        PortFollowOutcomeKindDto.conflictStayed,
      ]) {
        expect(
          mapPortFollowOutcome(PortFollowOutcomeDto(kind: kind)),
          const PortFollowFailed(),
          reason: '$kind without a port must degrade to PortFollowFailed',
        );
      }
    });
  });

  group('portFollowPolicyToDto', () {
    test('maps each public policy to its bridge value', () {
      expect(
        portFollowPolicyToDto(PortFollowPolicy.followBestEffort),
        PortFollowPolicyDto.followBestEffort,
      );
      expect(
        portFollowPolicyToDto(PortFollowPolicy.keepPortOrStay),
        PortFollowPolicyDto.keepPortOrStay,
      );
      expect(
        portFollowPolicyToDto(PortFollowPolicy.disabled),
        PortFollowPolicyDto.disabled,
      );
    });
  });

  group('mapConnectionState', () {
    test('maps each engine state to its sealed subtype', () {
      expect(
        mapConnectionState(ConnectionStateDto.connecting),
        const Connecting(),
      );
      expect(
        mapConnectionState(ConnectionStateDto.connected),
        const Connected(),
      );
      expect(
        mapConnectionState(ConnectionStateDto.reconnecting),
        const Reconnecting(),
      );
      // A maintenance drain must map to the distinct Draining state, not to the
      // terminal ConnectionFailed it used to collapse into.
      expect(
        mapConnectionState(ConnectionStateDto.draining),
        const Draining(),
      );
      expect(
        mapConnectionState(ConnectionStateDto.failed),
        isA<ConnectionFailed>().having((s) => s.code, 'code', 'tunnel/failed'),
      );
    });

    test('a bare failed state carries no fatal cause', () {
      expect(
        mapConnectionState(ConnectionStateDto.failed),
        isA<ConnectionFailed>().having((s) => s.cause, 'cause', isNull),
      );
    });
  });

  group('mapFatalCause', () {
    test('maps each engine fatal cause to its own distinct public kind', () {
      // The taxonomy must NOT collapse: a consumer has to tell "renew the
      // subscription" from "too many devices" from an opaque refusal to react.
      expect(
        mapFatalCause(WarrenFatalCauseDto.notAuthorized),
        WarrenFatalCause.notAuthorized,
      );
      expect(
        mapFatalCause(WarrenFatalCauseDto.deviceLimit),
        WarrenFatalCause.deviceLimit,
      );
      expect(
        mapFatalCause(WarrenFatalCauseDto.policyRefused),
        WarrenFatalCause.policyRefused,
      );
      // Every engine kind reaches its own public kind: no two collapse.
      final mapped = WarrenFatalCauseDto.values.map(mapFatalCause).toList();
      expect(mapped.toSet().length, WarrenFatalCauseDto.values.length);
    });

    test('a null bridge cause is transient exhaustion, not a fatal cause', () {
      expect(mapFatalCause(null), isNull);
    });
  });

  group('connectionFailed', () {
    test('a null cause is plain retry exhaustion', () {
      expect(
        connectionFailed(null),
        const ConnectionFailed(
          code: 'tunnel/failed',
          message: 'the connection failed and will not be retried',
        ),
      );
    });

    test('each fatal cause yields a distinct code and carries the cause', () {
      final byCause = {
        for (final cause in WarrenFatalCause.values)
          cause: connectionFailed(cause) as ConnectionFailed,
      };
      // The public state carries the machine-readable cause so a consumer can
      // stop on it.
      for (final entry in byCause.entries) {
        expect(entry.value.cause, entry.key);
      }
      // Distinct code per cause: a consumer branching on `code` alone still
      // distinguishes an expired subscription from a device-limit rejection.
      final codes = byCause.values.map((f) => f.code).toSet();
      expect(codes.length, WarrenFatalCause.values.length);
      expect(codes, isNot(contains('tunnel/failed')));
    });
  });
}
