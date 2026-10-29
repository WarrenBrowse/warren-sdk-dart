import 'package:warren_sdk_platform_interface/warren_sdk_platform_interface.dart';

import 'rust/api/client.dart' show ExitInfoDto, TunnelCheckDto;
import 'rust/api/datapath.dart'
    show
        BanReasonDto,
        ConnectionStateDto,
        MigrationEventDto,
        MigrationOutcomeDto,
        PortFollowOutcomeDto,
        PortFollowOutcomeKindDto,
        PortFollowPolicyDto,
        WarrenFatalCauseDto;
import 'rust/api/device.dart';
import 'rust/api/error.dart';

/// The engine's `u64::MAX` drain-deadline sentinel: a soft drain with no
/// hard-close deadline.
final BigInt _softDrainSentinel = (BigInt.one << 64) - BigInt.one;

/// Maps the typed engine error to the sealed public [WarrenError].
///
/// The bridge carries a category plus an already-redacted message; this turns
/// it into the matching subtype with a stable, machine-readable code. A ban
/// refusal becomes a [WarrenAccountBannedError], a clock refusal a
/// [WarrenClockSkewError], and a device registry refusal its own device error.
WarrenError mapEngineError(WarrenFfiError error) => switch (error.device) {
      DeviceRefusalDto.revoked => const WarrenDeviceRevokedError(),
      DeviceRefusalDto.limitReached => const WarrenDeviceLimitReachedError(),
      DeviceRefusalDto.invalidId => const WarrenInvalidDeviceIdError(),
      null => _mapUntypedDevice(error),
    };

WarrenError _mapUntypedDevice(WarrenFfiError error) =>
    switch ((error.ban, error.clockSkew)) {
      (final BanRefusalDto ban, _) => WarrenAccountBannedError(
          message: error.message,
          reason: mapBanReason(ban.reason),
          lapsesAtUnixSecs: ban.lapsesAtUnixSecs?.toInt(),
        ),
      (null, final ClockSkewDto skew) =>
        WarrenClockSkewError(offsetSecs: skew.offsetSecs?.toInt()),
      (null, null) => warrenErrorOfKind(
          error.kind.name,
          code: '${error.kind.name}/engine',
          message: error.message,
        ),
    };

/// Maps the bridge ban reason to the public [BanReason]; an absent reason is
/// still a ban, of an unnamed kind.
BanReason mapBanReason(BanReasonDto? reason) => switch (reason) {
      BanReasonDto.portForwardingAbuse => BanReason.portForwardingAbuse,
      BanReasonDto.other || null => BanReason.other,
    };

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
      WarrenFatalCauseDto.banned => WarrenFatalCause.banned,
      WarrenFatalCauseDto.noReachableEntry => WarrenFatalCause.noReachableEntry,
    };

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
    PortFollowOutcomeKindDto.notAuthorized => PortForwardNotAuthorized(
        entitlementPresented: dto.entitlementPresented ?? false,
      ),
    PortFollowOutcomeKindDto.banned => PortForwardBanned(
        reason: mapBanReason(dto.banReason),
        lapsesAtUnixSecs: dto.banLapsesAtUnixSecs?.toInt(),
      ),
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

/// Maps the engine's account device list to the public [WarrenDeviceList].
///
/// Throws a [WarrenApiError] when the registry answered a day that is not
/// `YYYY-MM-DD`, rather than inventing one.
WarrenDeviceList deviceListFromDto(DeviceListDto dto) => WarrenDeviceList(
      devices: dto.devices.map(deviceFromDto).toList(growable: false),
      olderClientSeenOn: switch (dto.olderClientSeenOn) {
        final String day => registryDay(day),
        null => null,
      },
    );

/// Maps one engine device to the public [WarrenDevice].
WarrenDevice deviceFromDto(DeviceDto dto) => WarrenDevice(
      deviceId: dto.deviceId,
      name: dto.name,
      platform: devicePlatformFromDto(dto.platform),
      appVersion: dto.appVersion,
      registeredOn: registryDay(dto.registeredOn),
      lastSeenOn: registryDay(dto.lastSeenOn),
      isThisDevice: dto.thisDevice,
    );

/// Maps the engine's device platform to the public [WarrenDevicePlatform].
WarrenDevicePlatform devicePlatformFromDto(DevicePlatformDto platform) =>
    switch (platform) {
      DevicePlatformDto.android => WarrenDevicePlatform.android,
      DevicePlatformDto.ios => WarrenDevicePlatform.ios,
      DevicePlatformDto.macos => WarrenDevicePlatform.macos,
      DevicePlatformDto.windows => WarrenDevicePlatform.windows,
      DevicePlatformDto.linux => WarrenDevicePlatform.linux,
      DevicePlatformDto.cli => WarrenDevicePlatform.cli,
      DevicePlatformDto.browser => WarrenDevicePlatform.browser,
      DevicePlatformDto.other => WarrenDevicePlatform.other,
    };

final RegExp _registryDayShape = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// Parses a registry day (`YYYY-MM-DD`) as UTC midnight.
///
/// Throws a [WarrenApiError] for anything else.
DateTime registryDay(String day) {
  final parsed =
      _registryDayShape.hasMatch(day) ? DateTime.tryParse(day) : null;
  if (parsed == null) {
    throw const WarrenApiError(
      code: 'api/malformed-device-list',
      message: 'the device registry answered a malformed day',
    );
  }
  return DateTime.utc(parsed.year, parsed.month, parsed.day);
}
