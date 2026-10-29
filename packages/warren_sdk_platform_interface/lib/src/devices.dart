import 'dart:async';

import 'package:meta/meta.dart';

import 'connection_state.dart';

/// Where a device of the account runs (warren-core doc 115).
enum WarrenDevicePlatform {
  /// Android app.
  android,

  /// iOS app.
  ios,

  /// macOS desktop app.
  macos,

  /// Windows desktop app.
  windows,

  /// Linux desktop app.
  linux,

  /// A command-line client (warren-cli, wclaude).
  cli,

  /// The browser extension's helper.
  browser,

  /// A platform this SDK version does not know yet.
  other,
}

/// One device of the account, as the account's device registry lists it.
///
/// [deviceId] and [name] belong in the account's own UI and never in a log:
/// [toString] renders neither.
@immutable
class WarrenDevice {
  /// Creates a device description.
  const WarrenDevice({
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.appVersion,
    required this.registeredOn,
    required this.lastSeenOn,
    required this.isThisDevice,
  });

  /// The install's identifier: what the rename and revoke calls take.
  final String deviceId;

  /// The device's name, generated at install time and renamable. Strip
  /// bidirectional control characters before displaying it.
  final String name;

  /// Where it runs.
  final WarrenDevicePlatform platform;

  /// The app version it last registered with.
  final String appVersion;

  /// The day it registered (UTC midnight; the registry keeps days only).
  final DateTime registeredOn;

  /// The last day it was seen (UTC midnight; the registry keeps days only).
  final DateTime lastSeenOn;

  /// Whether it is the install this client runs on.
  final bool isThisDevice;

  @override
  bool operator ==(Object other) =>
      other is WarrenDevice &&
      other.deviceId == deviceId &&
      other.name == name &&
      other.platform == platform &&
      other.appVersion == appVersion &&
      other.registeredOn == registeredOn &&
      other.lastSeenOn == lastSeenOn &&
      other.isThisDevice == isThisDevice;

  @override
  int get hashCode => Object.hash(
        deviceId,
        name,
        platform,
        appVersion,
        registeredOn,
        lastSeenOn,
        isThisDevice,
      );

  @override
  String toString() =>
      'WarrenDevice(${platform.name}, $appVersion, thisDevice: $isThisDevice)';
}

/// The account's devices, and whether an older client of the account was seen.
@immutable
class WarrenDeviceList {
  /// Creates a device list.
  const WarrenDeviceList({required this.devices, this.olderClientSeenOn});

  /// The account's active devices.
  final List<WarrenDevice> devices;

  /// The last day a device of the account running a Warren version that does
  /// not register (older than 1.1.36) was superseded by a registered device,
  /// or `null` when none ever was. When set, the list shows an "older version
  /// of Warren" line advising to update or uninstall it.
  final DateTime? olderClientSeenOn;

  /// The install this client runs on, when the registry lists it.
  WarrenDevice? get thisDevice {
    for (final device in devices) {
      if (device.isThisDevice) return device;
    }
    return null;
  }

  @override
  bool operator ==(Object other) {
    if (other is! WarrenDeviceList ||
        other.olderClientSeenOn != olderClientSeenOn ||
        other.devices.length != devices.length) {
      return false;
    }
    for (var i = 0; i < devices.length; i++) {
      if (other.devices[i] != devices[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(devices), olderClientSeenOn);

  @override
  String toString() => 'WarrenDeviceList(${devices.length} devices)';
}

/// Ends [states] on [ConnectionFailed] with [WarrenFatalCause.deviceRevoked]
/// once [revoked] reports this install's device revoked.
///
/// A revoked device can keep its tunnel up on credentials it already holds,
/// so the session's own states do not say it. After the revocation the
/// session reports nothing else: the app disconnects, forgets the device and
/// asks for the recovery phrase again.
Stream<ConnectionState> withDeviceRevocation(
  Stream<ConnectionState> states,
  Stream<bool> revoked,
) =>
    Stream<ConnectionState>.multi((controller) {
      StreamSubscription<ConnectionState>? stateSub;
      StreamSubscription<bool>? revokedSub;
      var ended = false;

      Future<void> end({required bool revokedNow}) async {
        if (ended) return;
        ended = true;
        if (revokedNow) {
          controller.add(connectionFailed(WarrenFatalCause.deviceRevoked));
        }
        await controller.close();
        await stateSub?.cancel();
        await revokedSub?.cancel();
      }

      stateSub = states.listen(
        (state) {
          if (!ended) controller.add(state);
        },
        onError: (Object error, StackTrace stack) {
          if (!ended) controller.addError(error, stack);
        },
        // The session is over: the revocation watch alone keeps nothing open.
        onDone: () => unawaited(end(revokedNow: false)),
      );
      revokedSub = revoked.listen(
        (isRevoked) {
          if (isRevoked) unawaited(end(revokedNow: true));
        },
        // A failed revocation check says nothing about the session.
        onError: (Object _) {},
      );
      controller.onCancel = () async {
        await stateSub?.cancel();
        await revokedSub?.cancel();
      };
    });
