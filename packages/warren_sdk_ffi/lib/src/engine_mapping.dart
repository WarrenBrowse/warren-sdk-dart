import 'package:warren_sdk_platform_interface/warren_sdk_platform_interface.dart';

import 'rust/api/client.dart' show ExitInfoDto, TunnelCheckDto;
import 'rust/api/datapath.dart'
    show
        ConnectionStateDto,
        MigrationEventDto,
        MigrationOutcomeDto,
        PortFollowOutcomeDto,
        PortFollowOutcomeKindDto,
        PortFollowPolicyDto,
        WarrenFatalCauseDto;
import 'rust/api/error.dart';

/// The engine's `u64::MAX` drain-deadline sentinel: a soft drain with no
/// hard-close deadline.
final BigInt _softDrainSentinel = (BigInt.one << 64) - BigInt.one;

/// Maps the typed engine error to the sealed public [WarrenError].
///
/// The bridge carries a category plus an already-redacted message; this turns
/// it into the matching subtype with a stable, machine-readable code.
WarrenError mapEngineError(WarrenFfiError error) => warrenErrorOfKind(
      error.kind.name,
      code: '${error.kind.name}/engine',
      message: error.message,
    );

/// Maps an engine connection-state to the sealed public [ConnectionState].
///
/// The engine never emits [Disconnected]; that state is the app's own concept
/// after it tears a session down. A bare [ConnectionStateDto.failed] carries no
/// cause here (retry exhaustion); the FFI session enriches the terminal state
/// with the engine's [WarrenFatalCause] via [connectionFailed] when one is
/// latched.
ConnectionState mapConnectionState(ConnectionStateDto state) => switch (state) {
      ConnectionStateDto.connecting => const Connecting(),
      ConnectionStateDto.connected => const Connected(),
      ConnectionStateDto.reconnecting => const Reconnecting(),
      ConnectionStateDto.draining => const Draining(),
      ConnectionStateDto.failed => connectionFailed(null),
    };

/// Maps the engine's fatal cause to the sealed public [WarrenFatalCause].
///
/// A `null` bridge cause (nothing latched) stays `null`: the failure was mere
/// retry exhaustion, not a definitive refusal. The engine owns the
/// classification; this maps it one-to-one, never re-deciding.
WarrenFatalCause? mapFatalCause(WarrenFatalCauseDto? cause) => switch (cause) {
      null => null,
      WarrenFatalCauseDto.notAuthorized => WarrenFatalCause.notAuthorized,
      WarrenFatalCauseDto.deviceLimit => WarrenFatalCause.deviceLimit,
      WarrenFatalCauseDto.policyRefused => WarrenFatalCause.policyRefused,
    };

/// Builds the terminal [ConnectionFailed] for a fatal [cause].
///
/// A non-null [cause] means no redial or other exit helps, so the code and
/// message name the reason and a consumer stops instead of looping
/// "reconnecting"; a `null` cause is plain retry exhaustion. The message is
/// generic and redacted (no pubkey, address, IP, nonce or seed).
ConnectionState connectionFailed(WarrenFatalCause? cause) => ConnectionFailed(
      code: switch (cause) {
        null => 'tunnel/failed',
        WarrenFatalCause.notAuthorized => 'tunnel/not-authorized',
        WarrenFatalCause.deviceLimit => 'tunnel/device-limit',
        WarrenFatalCause.policyRefused => 'tunnel/policy-refused',
      },
      message: switch (cause) {
        null => 'the connection failed and will not be retried',
        WarrenFatalCause.notAuthorized =>
          'the subscription is inactive or this device is not authorized',
        WarrenFatalCause.deviceLimit =>
          'the account already has its maximum number of connected devices',
        WarrenFatalCause.policyRefused =>
          'the exit refused the connection for policy reasons',
      },
      cause: cause,
    );

/// Maps an engine exit DTO to the public [ExitInfo].
ExitInfo exitInfoFromDto(ExitInfoDto dto) => ExitInfo(
      id: dto.id,
      country: dto.country,
      city: dto.city,
      supportsIpv6: dto.supportsIpv6,
      coverDomain: dto.coverDomain,
      weight: dto.weight.toInt(),
      isActive: dto.isActive,
    );

/// Maps the engine tunnel-check DTO to the public [TunnelCheck].
TunnelCheck tunnelCheckFromDto(TunnelCheckDto dto) => TunnelCheck(
      ip: dto.ip,
      isExit: dto.isExit,
      country: dto.country,
      city: dto.city,
    );

/// Maps an engine migration event to the public [MigrationEvent].
///
/// The engine encodes "soft drain, no hard-close deadline" as `u64::MAX`;
/// publicly that is a `null` deadline.
MigrationEvent mapMigrationEvent(MigrationEventDto dto) => MigrationEvent(
      deadlineUnixSecs: dto.deadlineUnixSecs == _softDrainSentinel
          ? null
          : dto.deadlineUnixSecs.toInt(),
      reasonCode: dto.reasonCode,
      outcome: switch (dto.outcome) {
        MigrationOutcomeDto.migrating => MigrationOutcome.migrating,
        MigrationOutcomeDto.completed => MigrationOutcome.completed,
        MigrationOutcomeDto.cancelledPortConflict =>
          MigrationOutcome.cancelledPortConflict,
      },
    );

/// Maps an engine port-follow outcome to the sealed public [PortFollowOutcome].
///
/// The bridge flattens the outcome to a kind plus optional ports; a
/// port-bearing kind arriving without its port is malformed and degrades to
/// [PortFollowFailed] ("not established, retrying") instead of throwing.
PortFollowOutcome mapPortFollowOutcome(PortFollowOutcomeDto dto) {
  final port = dto.port;
  return switch (dto.kind) {
    PortFollowOutcomeKindDto.kept when port != null => PortKept(port: port),
    PortFollowOutcomeKindDto.changed when port != null =>
      PortChanged(previousPort: dto.previousPort, port: port),
    PortFollowOutcomeKindDto.conflictStayed when port != null =>
      PortConflictStayed(pinnedPort: port),
    _ => const PortFollowFailed(),
  };
}

/// Maps the public follow policy to its bridge DTO.
PortFollowPolicyDto portFollowPolicyToDto(PortFollowPolicy policy) =>
    switch (policy) {
      PortFollowPolicy.followBestEffort => PortFollowPolicyDto.followBestEffort,
      PortFollowPolicy.keepPortOrStay => PortFollowPolicyDto.keepPortOrStay,
      PortFollowPolicy.disabled => PortFollowPolicyDto.disabled,
    };
