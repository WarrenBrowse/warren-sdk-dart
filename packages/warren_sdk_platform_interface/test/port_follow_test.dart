import 'package:flutter_test/flutter_test.dart';
import 'package:warren_sdk_platform_interface/warren_sdk_platform_interface.dart';

void main() {
  group('PortFollowOutcome value equality', () {
    test('PortKept compares by port', () {
      expect(const PortKept(port: 51820), const PortKept(port: 51820));
      expect(
        const PortKept(port: 51820),
        isNot(equals(const PortKept(port: 51821))),
      );
    });

    test('PortChanged compares by both ports, previous may be absent', () {
      expect(
        const PortChanged(previousPort: 51820, port: 40000),
        const PortChanged(previousPort: 51820, port: 40000),
      );
      expect(
        const PortChanged(port: 40000),
        const PortChanged(port: 40000),
      );
      expect(
        const PortChanged(previousPort: 51820, port: 40000),
        isNot(equals(const PortChanged(port: 40000))),
      );
    });

    test('PortConflictStayed compares by the pinned port', () {
      expect(
        const PortConflictStayed(pinnedPort: 51820),
        const PortConflictStayed(pinnedPort: 51820),
      );
      expect(
        const PortConflictStayed(pinnedPort: 51820),
        isNot(equals(const PortConflictStayed(pinnedPort: 51821))),
      );
    });

    test('PortFollowFailed instances are all equal', () {
      expect(const PortFollowFailed(), const PortFollowFailed());
      // A non-const instance must still equal the canonical const one.
      // ignore: prefer_const_constructors
      expect(PortFollowFailed(), const PortFollowFailed());
    });

    test('different subtypes never compare equal', () {
      expect(
        const PortKept(port: 51820),
        isNot(equals(const PortConflictStayed(pinnedPort: 51820))),
      );
    });
  });

  group('MigrationEvent', () {
    test('compares by deadline, reason and outcome', () {
      const a = MigrationEvent(
        deadlineUnixSecs: 1767225600,
        reasonCode: 0,
        outcome: MigrationOutcome.migrating,
      );
      const b = MigrationEvent(
        deadlineUnixSecs: 1767225600,
        reasonCode: 0,
        outcome: MigrationOutcome.migrating,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a,
        isNot(
          equals(
            const MigrationEvent(
              deadlineUnixSecs: 1767225600,
              reasonCode: 0,
              outcome: MigrationOutcome.completed,
            ),
          ),
        ),
      );
    });

    test('a soft drain has no deadline', () {
      const event = MigrationEvent(
        reasonCode: 0,
        outcome: MigrationOutcome.migrating,
      );
      expect(event.deadlineUnixSecs, isNull);
    });
  });
}
