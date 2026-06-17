// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'client_config.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Holds the current [ClientConfig], or null before a client has been
/// configured. Setting it (re)builds [warrenClientProvider] downstream.

@ProviderFor(ClientConfigController)
const clientConfigControllerProvider = ClientConfigControllerProvider._();

/// Holds the current [ClientConfig], or null before a client has been
/// configured. Setting it (re)builds [warrenClientProvider] downstream.
final class ClientConfigControllerProvider
    extends $NotifierProvider<ClientConfigController, ClientConfig?> {
  /// Holds the current [ClientConfig], or null before a client has been
  /// configured. Setting it (re)builds [warrenClientProvider] downstream.
  const ClientConfigControllerProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'clientConfigControllerProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$clientConfigControllerHash();

  @$internal
  @override
  ClientConfigController create() => ClientConfigController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ClientConfig? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ClientConfig?>(value),
    );
  }
}

String _$clientConfigControllerHash() =>
    r'75e1222bb6a79702cbebb0b9e7b0532055ad6514';

/// Holds the current [ClientConfig], or null before a client has been
/// configured. Setting it (re)builds [warrenClientProvider] downstream.

abstract class _$ClientConfigController extends $Notifier<ClientConfig?> {
  ClientConfig? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<ClientConfig?, ClientConfig?>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<ClientConfig?, ClientConfig?>,
        ClientConfig?,
        Object?,
        Object?>;
    element.handleValue(ref, created);
  }
}
