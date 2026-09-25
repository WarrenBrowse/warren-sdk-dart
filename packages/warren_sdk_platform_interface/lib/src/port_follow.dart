import 'package:meta/meta.dart';

/// How a forwarded port follows the client across reconnects and maintenance
/// migrations (doc 59 port-follow contract).
enum PortFollowPolicy {
  /// Re-suggest the last granted external port on every re-establish; when the
  /// new exit already holds it, degrade once to a server-assigned port instead
  /// of failing. A conflict never kills the forward (the default).
  followBestEffort,

  /// The external port never degrades silently: on a conflict the mapping
  /// stays unset for that epoch (surfaced as [PortConflictStayed]) and the pin
  /// is re-requested on the next one.
  keepPortOrStay,

  /// No follow: every epoch asks the exit for a fresh server-assigned port.
  disabled,
}

/// What happened to a forwarded port's external port on its latest
/// (re)establish, delivered as a stream by a forwarded port.
///
/// A sealed hierarchy so consumers can exhaustively `switch` over it.
@immutable
sealed class PortFollowOutcome {
  const PortFollowOutcome();
}

/// The previously-granted external port was re-granted: the public port
/// followed the client onto this exit.
final class PortKept extends PortFollowOutcome {
  /// Creates the kept outcome.
  const PortKept({required this.port});

  /// The external port that was preserved.
  final int port;

  @override
  bool operator ==(Object other) => other is PortKept && other.port == port;

  @override
  int get hashCode => Object.hash(runtimeType, port);

  @override
  String toString() => 'PortKept($port)';
}

/// The exit granted a different external port (first grant, an explicit server
/// pick, or a best-effort degrade after a conflict).
final class PortChanged extends PortFollowOutcome {
  /// Creates the changed outcome.
  const PortChanged({this.previousPort, required this.port});

  /// The previous external port, `null` on the first grant.
  final int? previousPort;

  /// The newly granted external port.
  final int port;

  @override
  bool operator ==(Object other) =>
      other is PortChanged &&
      other.previousPort == previousPort &&
      other.port == port;

  @override
  int get hashCode => Object.hash(runtimeType, previousPort, port);

  @override
  String toString() => 'PortChanged($previousPort -> $port)';
}

/// A pinned port was refused (held by another client) and the rule did not
/// degrade: no mapping exists this epoch, the pin stays requested for the next
/// one.
final class PortConflictStayed extends PortFollowOutcome {
  /// Creates the conflict-stayed outcome.
  const PortConflictStayed({required this.pinnedPort});

  /// The pinned external port that stays requested.
  final int pinnedPort;

  @override
  bool operator ==(Object other) =>
      other is PortConflictStayed && other.pinnedPort == pinnedPort;

  @override
  int get hashCode => Object.hash(runtimeType, pinnedPort);

  @override
  String toString() => 'PortConflictStayed($pinnedPort)';
}

/// The mapping could not be established this epoch (transport failure or a
/// non-conflict refusal); the engine keeps retrying.
final class PortFollowFailed extends PortFollowOutcome {
  /// Creates the failed outcome.
  const PortFollowFailed();

  @override
  bool operator ==(Object other) => other is PortFollowFailed;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'PortFollowFailed';
}

/// The exit refused the mapping as not authorized: the request presented no
/// port entitlement, or one the exit would not spend (warren-core doc 105).
/// The engine keeps retrying; the next entitlement refresh can stock one.
final class PortForwardNotAuthorized extends PortFollowOutcome {
  /// Creates the not-authorized outcome.
  const PortForwardNotAuthorized({required this.entitlementPresented});

  /// Whether the refused request carried an entitlement. `false` when the
  /// account held none for the current epoch: its batch is held by its other
  /// forwarded ports or devices, or the API has not answered.
  final bool entitlementPresented;

  @override
  bool operator ==(Object other) =>
      other is PortForwardNotAuthorized &&
      other.entitlementPresented == entitlementPresented;

  @override
  int get hashCode => Object.hash(runtimeType, entitlementPresented);

  @override
  String toString() => 'PortForwardNotAuthorized($entitlementPresented)';
}

/// Why an account is banned.
enum BanReason {
  /// Three port-forward abuse strikes inside the sliding window.
  portForwardingAbuse,

  /// Any other revocation, and any reason this build does not know.
  other,
}

/// The account is banned: the issuer refuses its port entitlements, so every
/// enforcing exit refuses its mappings until the ban lapses or is lifted. The
/// engine keeps retrying, which a lifted ban answers.
final class PortForwardBanned extends PortFollowOutcome {
  /// Creates the banned outcome.
  const PortForwardBanned({required this.reason, this.lapsesAtUnixSecs});

  /// Why the account is banned.
  final BanReason reason;

  /// When the ban lapses on its own, Unix seconds; `null` when it does not.
  final int? lapsesAtUnixSecs;

  @override
  bool operator ==(Object other) =>
      other is PortForwardBanned &&
      other.reason == reason &&
      other.lapsesAtUnixSecs == lapsesAtUnixSecs;

  @override
  int get hashCode => Object.hash(runtimeType, reason, lapsesAtUnixSecs);

  @override
  String toString() => 'PortForwardBanned($reason, $lapsesAtUnixSecs)';
}

/// Progress of one maintenance migration.
enum MigrationOutcome {
  /// The drain advisory arrived and the engine is moving off the exit.
  migrating,

  /// The post-drain reconnect landed on the new exit (forwarded ports re-map
  /// immediately; watch each rule's [PortFollowOutcome]).
  completed,

  /// Every migration candidate conflicted with a pinned port rule: the
  /// migration was cancelled, the client stays on the draining exit and keeps
  /// its port through the swap.
  cancelledPortConflict,
}

/// A maintenance-migration lifecycle event, delivered as a stream by a
/// session.
///
/// Richer than the bare `Draining` connection state: it carries the drain
/// advisory's deadline and reason plus where the migration stands, so an app
/// can render "switching server for maintenance" or "migration postponed,
/// port kept".
@immutable
class MigrationEvent {
  /// Creates a migration event.
  const MigrationEvent({
    this.deadlineUnixSecs,
    required this.reasonCode,
    required this.outcome,
  });

  /// Unix seconds after which the draining exit hard-closes stragglers, or
  /// `null` for a soft drain with no deadline.
  final int? deadlineUnixSecs;

  /// Opaque operator reason code from the drain advisory (0 = maintenance).
  final int reasonCode;

  /// Where the migration stands.
  final MigrationOutcome outcome;

  @override
  bool operator ==(Object other) =>
      other is MigrationEvent &&
      other.deadlineUnixSecs == deadlineUnixSecs &&
      other.reasonCode == reasonCode &&
      other.outcome == outcome;

  @override
  int get hashCode => Object.hash(deadlineUnixSecs, reasonCode, outcome);

  @override
  String toString() => 'MigrationEvent(${outcome.name}, reason: $reasonCode, '
      'deadline: ${deadlineUnixSecs ?? 'soft'})';
}
