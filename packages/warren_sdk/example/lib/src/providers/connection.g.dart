// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'connection.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Owns the active [WarrenSession]: opening it through the live client,
/// swapping it on reconnect, and tearing it down. The session's reactive state
/// is mirrored by the package's `connectionStateProvider(session)`.

@ProviderFor(ConnectionController)
const connectionControllerProvider = ConnectionControllerProvider._();

/// Owns the active [WarrenSession]: opening it through the live client,
/// swapping it on reconnect, and tearing it down. The session's reactive state
/// is mirrored by the package's `connectionStateProvider(session)`.
final class ConnectionControllerProvider
    extends $AsyncNotifierProvider<ConnectionController, WarrenSession?> {
  /// Owns the active [WarrenSession]: opening it through the live client,
  /// swapping it on reconnect, and tearing it down. The session's reactive state
  /// is mirrored by the package's `connectionStateProvider(session)`.
  const ConnectionControllerProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'connectionControllerProvider',
          isAutoDispose: false,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$connectionControllerHash();

  @$internal
  @override
  ConnectionController create() => ConnectionController();
}

String _$connectionControllerHash() =>
    r'a999aa5c97f5f92786d0d2e3e703cf8badd88f8d';

/// Owns the active [WarrenSession]: opening it through the live client,
/// swapping it on reconnect, and tearing it down. The session's reactive state
/// is mirrored by the package's `connectionStateProvider(session)`.

abstract class _$ConnectionController extends $AsyncNotifier<WarrenSession?> {
  FutureOr<WarrenSession?> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<AsyncValue<WarrenSession?>, WarrenSession?>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<AsyncValue<WarrenSession?>, WarrenSession?>,
        AsyncValue<WarrenSession?>,
        Object?,
        Object?>;
    element.handleValue(ref, created);
  }
}
