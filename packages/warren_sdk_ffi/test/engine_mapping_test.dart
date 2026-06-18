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
      const dto = ExitInfoDto(
        id: 'exit-1',
        country: 'RO',
        city: 'Bucharest',
        supportsIpv6: true,
        supportsPortForwarding: false,
        load: 0.42,
      );
      final info = exitInfoFromDto(dto);
      expect(info.id, 'exit-1');
      expect(info.country, 'RO');
      expect(info.city, 'Bucharest');
      expect(info.supportsIpv6, isTrue);
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
      expect(
        mapConnectionState(ConnectionStateDto.failed),
        isA<ConnectionFailed>().having((s) => s.code, 'code', 'tunnel/failed'),
      );
    });
  });
}
