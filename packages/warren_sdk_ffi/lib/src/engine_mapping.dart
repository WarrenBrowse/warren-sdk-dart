import 'package:warren_sdk_platform_interface/warren_sdk_platform_interface.dart';

import 'rust/api/client.dart' show ExitInfoDto;
import 'rust/api/datapath.dart' show ConnectionStateDto;
import 'rust/api/error.dart';

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
/// after it tears a session down.
ConnectionState mapConnectionState(ConnectionStateDto state) => switch (state) {
      ConnectionStateDto.connecting => const Connecting(),
      ConnectionStateDto.connected => const Connected(),
      ConnectionStateDto.reconnecting => const Reconnecting(),
      ConnectionStateDto.failed => const ConnectionFailed(
          code: 'tunnel/failed',
          message: 'the connection failed and will not be retried',
        ),
    };

/// Maps an engine exit DTO to the public [ExitInfo].
ExitInfo exitInfoFromDto(ExitInfoDto dto) => ExitInfo(
      id: dto.id,
      country: dto.country,
      city: dto.city,
      supportsIpv6: dto.supportsIpv6,
    );
