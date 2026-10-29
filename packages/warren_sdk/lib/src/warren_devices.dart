import 'package:warren_sdk_platform_interface/warren_sdk_platform_interface.dart';

/// The account's devices (warren-core doc 115): the installs signed in to the
/// account, which the user can rename and disconnect from any one of them.
///
/// Obtained from `WarrenClient.devices`. This install registers as a device
/// only when the client was created with an `appVersion`.
///
/// When [revoked] turns `true`, or a session ends on
/// [WarrenFatalCause.deviceRevoked], this install was disconnected from
/// another device of the account: disconnect, call [forgetThisDevice], and
/// show "This device was disconnected from another device of your account.
/// Sign in with your recovery phrase to use it again."
class WarrenDevices {
  /// Wraps a platform client handle. Internal to the facade.
  WarrenDevices(this._handle);

  final WarrenClientHandle _handle;

  /// This install's device identifier, or `null` when the client registers no
  /// device. It names the install to its own account only: keep it out of
  /// logs.
  String? get thisDeviceId => _handle.deviceId;

  /// The account's devices, this install's marked
  /// ([WarrenDevice.isThisDevice]), and the last day an older Warren client of
  /// the account was seen ([WarrenDeviceList.olderClientSeenOn]).
  ///
  /// Throws a [WarrenApiError] on a network or server failure.
  Future<WarrenDeviceList> list() => _handle.listDevices();

  /// Renames the account's device [deviceId] to [name] (1 to 40 characters
  /// once trimmed, no control character).
  ///
  /// Throws a [WarrenInvalidDeviceIdError] for a malformed identifier, and a
  /// [WarrenApiError] for a name or a device the account refuses.
  Future<void> rename(String deviceId, String name) =>
      _handle.renameDevice(deviceId, name);

  /// Disconnects the account's device [deviceId]: it is signed out within one
  /// credential refresh (10 minutes) and needs the recovery phrase to sign in
  /// again. Revoking [thisDeviceId] is a logout.
  ///
  /// A device that keeps the recovery phrase can sign in again, so a lost or
  /// stolen device needs a new account instead.
  ///
  /// Throws a [WarrenInvalidDeviceIdError] for a malformed identifier, and a
  /// [WarrenApiError] on a network or server failure.
  Future<void> revoke(String deviceId) => _handle.revokeDevice(deviceId);

  /// Erases this install's kept device identity, once it was revoked or
  /// logged out. The next client created over the same state directory draws
  /// a new identity, which the account lists as a new device.
  Future<void> forgetThisDevice() => _handle.forgetDevice();

  /// Whether the last credential refresh found the account's device cap
  /// reached: this install is issued no session credential until another
  /// device of the account is disconnected. Open the device list when it
  /// reads `true`.
  Future<bool> limitReached() => _handle.deviceLimitReached();

  /// Whether this install's device was revoked from another device of the
  /// account. Broadcast, latest on listen; once `true`, it stays `true`.
  Stream<bool> get revoked => _handle.deviceRevoked;
}
