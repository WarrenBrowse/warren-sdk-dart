// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session_settings.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(SessionSettingsController)
const sessionSettingsControllerProvider = SessionSettingsControllerProvider._();

final class SessionSettingsControllerProvider
    extends $NotifierProvider<SessionSettingsController, SessionSettings> {
  const SessionSettingsControllerProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'sessionSettingsControllerProvider',
          isAutoDispose: false,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$sessionSettingsControllerHash();

  @$internal
  @override
  SessionSettingsController create() => SessionSettingsController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SessionSettings value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SessionSettings>(value),
    );
  }
}

String _$sessionSettingsControllerHash() =>
    r'd3bfe38a5872e7f3edac6a439bdd4799a5d84e2c';

abstract class _$SessionSettingsController extends $Notifier<SessionSettings> {
  SessionSettings build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<SessionSettings, SessionSettings>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<SessionSettings, SessionSettings>,
        SessionSettings,
        Object?,
        Object?>;
    element.handleValue(ref, created);
  }
}
