import 'package:warren_sdk_platform_interface/warren_sdk_platform_interface.dart';

import 'rust/api/client.dart' show ExitInfoDto;
import 'rust/api/error.dart';

/// Maps the typed engine error to the sealed public [WarrenError].
///
/// The bridge carries a category plus an already-redacted message; this turns
/// it into the matching subtype with a stable, machine-readable code.
WarrenError mapEngineError(WarrenFfiError error) => switch (error.kind) {
      WarrenErrorKind.identity => WarrenIdentityError(
          code: 'identity/engine',
          message: error.message,
        ),
      WarrenErrorKind.api => WarrenApiError(
          code: 'api/engine',
          message: error.message,
        ),
      WarrenErrorKind.discovery => WarrenDiscoveryError(
          code: 'discovery/engine',
          message: error.message,
        ),
      WarrenErrorKind.tunnel => WarrenTunnelError(
          code: 'tunnel/engine',
          message: error.message,
        ),
      WarrenErrorKind.privilege => WarrenPrivilegeError(
          code: 'privilege/engine',
          message: error.message,
        ),
    };

/// Maps an engine exit DTO to the public [ExitInfo].
ExitInfo exitInfoFromDto(ExitInfoDto dto) => ExitInfo(
      id: dto.id,
      country: dto.country,
      city: dto.city,
      supportsIpv6: dto.supportsIpv6,
      supportsPortForwarding: dto.supportsPortForwarding,
      load: dto.load,
    );
