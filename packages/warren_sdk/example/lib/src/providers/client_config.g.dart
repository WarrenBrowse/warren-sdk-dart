// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'client_config.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Holds the current `ClientConfig`. Defaults to the Warren network (baked
/// pin + API base), so a client builds as soon as a wallet exists; the advanced
/// settings can override the pins, DAITA and IPv6 knobs.

@ProviderFor(ClientConfigController)
const clientConfigControllerProvider = ClientConfigControllerProvider._();

/// Holds the current `ClientConfig`. Defaults to the Warren network (baked
/// pin + API base), so a client builds as soon as a wallet exists; the advanced
/// settings can override the pins, DAITA and IPv6 knobs.
final class ClientConfigControllerProvider
    extends $NotifierProvider<ClientConfigController, ClientConfig> {
  /// Holds the current `ClientConfig`. Defaults to the Warren network (baked
  /// pin + API base), so a client builds as soon as a wallet exists; the advanced
  /// settings can override the pins, DAITA and IPv6 knobs.
  const ClientConfigControllerProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'clientConfigControllerProvider',
          isAutoDispose: false,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$clientConfigControllerHash();

  @$internal
  @override
  ClientConfigController create() => ClientConfigController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ClientConfig value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ClientConfig>(value),
    );
  }
}

String _$clientConfigControllerHash() =>
    r'e54b7fc6c8f337e9dc95782eb02365c9be239272';

/// Holds the current `ClientConfig`. Defaults to the Warren network (baked
/// pin + API base), so a client builds as soon as a wallet exists; the advanced
/// settings can override the pins, DAITA and IPv6 knobs.

abstract class _$ClientConfigController extends $Notifier<ClientConfig> {
  ClientConfig build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<ClientConfig, ClientConfig>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<ClientConfig, ClientConfig>,
        ClientConfig,
        Object?,
        Object?>;
    element.handleValue(ref, created);
  }
}
