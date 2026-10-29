// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'warren_sdk_riverpod.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The live [WarrenClient]. Must be overridden by the app (see library docs);
/// the default throws to make a missing override obvious.

@ProviderFor(warrenClient)
const warrenClientProvider = WarrenClientProvider._();

/// The live [WarrenClient]. Must be overridden by the app (see library docs);
/// the default throws to make a missing override obvious.

final class WarrenClientProvider extends $FunctionalProvider<
        AsyncValue<WarrenClient>, WarrenClient, FutureOr<WarrenClient>>
    with $FutureModifier<WarrenClient>, $FutureProvider<WarrenClient> {
  /// The live [WarrenClient]. Must be overridden by the app (see library docs);
  /// the default throws to make a missing override obvious.
  const WarrenClientProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'warrenClientProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$warrenClientHash();

  @$internal
  @override
  $FutureProviderElement<WarrenClient> $createElement(
          $ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<WarrenClient> create(Ref ref) {
    return warrenClient(ref);
  }
}

String _$warrenClientHash() => r'697feb85cb5c807788339e09c98feaae39bf17f1';

/// The current subscription snapshot, refreshed on demand.

@ProviderFor(subscription)
const subscriptionProvider = SubscriptionProvider._();

/// The current subscription snapshot, refreshed on demand.

final class SubscriptionProvider extends $FunctionalProvider<
        AsyncValue<SubscriptionInfo>,
        SubscriptionInfo,
        FutureOr<SubscriptionInfo>>
    with $FutureModifier<SubscriptionInfo>, $FutureProvider<SubscriptionInfo> {
  /// The current subscription snapshot, refreshed on demand.
  const SubscriptionProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'subscriptionProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$subscriptionHash();

  @$internal
  @override
  $FutureProviderElement<SubscriptionInfo> $createElement(
          $ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<SubscriptionInfo> create(Ref ref) {
    return subscription(ref);
  }
}

String _$subscriptionHash() => r'ce9b69a4703851a5a90786d288f0cee91ef53d71';

/// The verified list of available exits.

@ProviderFor(exits)
const exitsProvider = ExitsProvider._();

/// The verified list of available exits.

final class ExitsProvider extends $FunctionalProvider<
        AsyncValue<List<ExitInfo>>, List<ExitInfo>, FutureOr<List<ExitInfo>>>
    with $FutureModifier<List<ExitInfo>>, $FutureProvider<List<ExitInfo>> {
  /// The verified list of available exits.
  const ExitsProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'exitsProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$exitsHash();

  @$internal
  @override
  $FutureProviderElement<List<ExitInfo>> $createElement(
          $ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<List<ExitInfo>> create(Ref ref) {
    return exits(ref);
  }
}

String _$exitsHash() => r'68f2457581caebfb8a866299278f872626d4bef4';

/// The account's devices, this install's marked. Invalidate it after a
/// rename or a disconnect to read the registry again.

@ProviderFor(devices)
const devicesProvider = DevicesProvider._();

/// The account's devices, this install's marked. Invalidate it after a
/// rename or a disconnect to read the registry again.

final class DevicesProvider extends $FunctionalProvider<
        AsyncValue<WarrenDeviceList>,
        WarrenDeviceList,
        FutureOr<WarrenDeviceList>>
    with $FutureModifier<WarrenDeviceList>, $FutureProvider<WarrenDeviceList> {
  /// The account's devices, this install's marked. Invalidate it after a
  /// rename or a disconnect to read the registry again.
  const DevicesProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'devicesProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$devicesHash();

  @$internal
  @override
  $FutureProviderElement<WarrenDeviceList> $createElement(
          $ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<WarrenDeviceList> create(Ref ref) {
    return devices(ref);
  }
}

String _$devicesHash() => r'1ae9cbd54652bb2663d0d187b926df66db757787';

/// Whether this install's device was revoked from another device of the
/// account. Once `true` the app disconnects, forgets the device and asks for
/// the recovery phrase again.

@ProviderFor(deviceRevoked)
const deviceRevokedProvider = DeviceRevokedProvider._();

/// Whether this install's device was revoked from another device of the
/// account. Once `true` the app disconnects, forgets the device and asks for
/// the recovery phrase again.

final class DeviceRevokedProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, Stream<bool>>
    with $FutureModifier<bool>, $StreamProvider<bool> {
  /// Whether this install's device was revoked from another device of the
  /// account. Once `true` the app disconnects, forgets the device and asks for
  /// the recovery phrase again.
  const DeviceRevokedProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'deviceRevokedProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$deviceRevokedHash();

  @$internal
  @override
  $StreamProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<bool> create(Ref ref) {
    return deviceRevoked(ref);
  }
}

String _$deviceRevokedHash() => r'4a016250068f388f3517409614a36f91efa6711c';

/// The live connection state for a [WarrenSession]. Pass the active session as
/// the family argument; the provider mirrors its broadcast state stream.

@ProviderFor(connectionState)
const connectionStateProvider = ConnectionStateFamily._();

/// The live connection state for a [WarrenSession]. Pass the active session as
/// the family argument; the provider mirrors its broadcast state stream.

final class ConnectionStateProvider extends $FunctionalProvider<
        AsyncValue<ConnectionState>, ConnectionState, Stream<ConnectionState>>
    with $FutureModifier<ConnectionState>, $StreamProvider<ConnectionState> {
  /// The live connection state for a [WarrenSession]. Pass the active session as
  /// the family argument; the provider mirrors its broadcast state stream.
  const ConnectionStateProvider._(
      {required ConnectionStateFamily super.from,
      required WarrenSession super.argument})
      : super(
          retry: null,
          name: r'connectionStateProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$connectionStateHash();

  @override
  String toString() {
    return r'connectionStateProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<ConnectionState> $createElement(
          $ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<ConnectionState> create(Ref ref) {
    final argument = this.argument as WarrenSession;
    return connectionState(
      ref,
      argument,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ConnectionStateProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$connectionStateHash() => r'b938bcce7876586c36f8a99e3bde7402d04b75cc';

/// The live connection state for a [WarrenSession]. Pass the active session as
/// the family argument; the provider mirrors its broadcast state stream.

final class ConnectionStateFamily extends $Family
    with $FunctionalFamilyOverride<Stream<ConnectionState>, WarrenSession> {
  const ConnectionStateFamily._()
      : super(
          retry: null,
          name: r'connectionStateProvider',
          dependencies: null,
          $allTransitiveDependencies: null,
          isAutoDispose: true,
        );

  /// The live connection state for a [WarrenSession]. Pass the active session as
  /// the family argument; the provider mirrors its broadcast state stream.

  ConnectionStateProvider call(
    WarrenSession session,
  ) =>
      ConnectionStateProvider._(argument: session, from: this);

  @override
  String toString() => r'connectionStateProvider';
}
