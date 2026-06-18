// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'exit_selection.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The current [ExitQuery] used to filter the exit list and drive
/// `WarrenClient.selectExit`.

@ProviderFor(ExitQueryController)
const exitQueryControllerProvider = ExitQueryControllerProvider._();

/// The current [ExitQuery] used to filter the exit list and drive
/// `WarrenClient.selectExit`.
final class ExitQueryControllerProvider
    extends $NotifierProvider<ExitQueryController, ExitQuery> {
  /// The current [ExitQuery] used to filter the exit list and drive
  /// `WarrenClient.selectExit`.
  const ExitQueryControllerProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'exitQueryControllerProvider',
          isAutoDispose: false,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$exitQueryControllerHash();

  @$internal
  @override
  ExitQueryController create() => ExitQueryController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ExitQuery value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ExitQuery>(value),
    );
  }
}

String _$exitQueryControllerHash() =>
    r'839ccd28f654adff03982f2b4301f6a49230c969';

/// The current [ExitQuery] used to filter the exit list and drive
/// `WarrenClient.selectExit`.

abstract class _$ExitQueryController extends $Notifier<ExitQuery> {
  ExitQuery build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<ExitQuery, ExitQuery>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<ExitQuery, ExitQuery>, ExitQuery, Object?, Object?>;
    element.handleValue(ref, created);
  }
}

/// The exit the user picked to connect through, or null.

@ProviderFor(SelectedExit)
const selectedExitProvider = SelectedExitProvider._();

/// The exit the user picked to connect through, or null.
final class SelectedExitProvider
    extends $NotifierProvider<SelectedExit, ExitInfo?> {
  /// The exit the user picked to connect through, or null.
  const SelectedExitProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'selectedExitProvider',
          isAutoDispose: false,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$selectedExitHash();

  @$internal
  @override
  SelectedExit create() => SelectedExit();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ExitInfo? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ExitInfo?>(value),
    );
  }
}

String _$selectedExitHash() => r'5b9991d535e6cf87d8f29fb25586934415eec483';

/// The exit the user picked to connect through, or null.

abstract class _$SelectedExit extends $Notifier<ExitInfo?> {
  ExitInfo? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<ExitInfo?, ExitInfo?>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<ExitInfo?, ExitInfo?>, ExitInfo?, Object?, Object?>;
    element.handleValue(ref, created);
  }
}
