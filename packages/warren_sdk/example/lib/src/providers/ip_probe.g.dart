// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ip_probe.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Runs the network check and re-runs it whenever the session changes, so the
/// displayed IP stays live across connect / disconnect. Invalidate the provider
/// to force a manual re-check.

@ProviderFor(netCheck)
const netCheckProvider = NetCheckProvider._();

/// Runs the network check and re-runs it whenever the session changes, so the
/// displayed IP stays live across connect / disconnect. Invalidate the provider
/// to force a manual re-check.

final class NetCheckProvider extends $FunctionalProvider<AsyncValue<NetCheck>,
        NetCheck, FutureOr<NetCheck>>
    with $FutureModifier<NetCheck>, $FutureProvider<NetCheck> {
  /// Runs the network check and re-runs it whenever the session changes, so the
  /// displayed IP stays live across connect / disconnect. Invalidate the provider
  /// to force a manual re-check.
  const NetCheckProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'netCheckProvider',
          isAutoDispose: false,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$netCheckHash();

  @$internal
  @override
  $FutureProviderElement<NetCheck> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<NetCheck> create(Ref ref) {
    return netCheck(ref);
  }
}

String _$netCheckHash() => r'3d072b9f4e16975e4ae2ceb493cc13536e15f644';

/// The account server's authoritative view of this device, via the SDK's
/// `checkTunnel()` (signed `/v1/check`). Re-runs when the session changes.
///
/// This reflects the CONTROL-PLANE path (the account API): direct in proxy mode,
/// tunneled in system-VPN mode. So `isExit` is the real backend confirmation for
/// system-VPN; in proxy mode it reports the device's own IP (the SOCKS/HTTP
/// proxy carries app traffic, not the signed account calls).

@ProviderFor(serverCheck)
const serverCheckProvider = ServerCheckProvider._();

/// The account server's authoritative view of this device, via the SDK's
/// `checkTunnel()` (signed `/v1/check`). Re-runs when the session changes.
///
/// This reflects the CONTROL-PLANE path (the account API): direct in proxy mode,
/// tunneled in system-VPN mode. So `isExit` is the real backend confirmation for
/// system-VPN; in proxy mode it reports the device's own IP (the SOCKS/HTTP
/// proxy carries app traffic, not the signed account calls).

final class ServerCheckProvider extends $FunctionalProvider<
        AsyncValue<TunnelCheck>, TunnelCheck, FutureOr<TunnelCheck>>
    with $FutureModifier<TunnelCheck>, $FutureProvider<TunnelCheck> {
  /// The account server's authoritative view of this device, via the SDK's
  /// `checkTunnel()` (signed `/v1/check`). Re-runs when the session changes.
  ///
  /// This reflects the CONTROL-PLANE path (the account API): direct in proxy mode,
  /// tunneled in system-VPN mode. So `isExit` is the real backend confirmation for
  /// system-VPN; in proxy mode it reports the device's own IP (the SOCKS/HTTP
  /// proxy carries app traffic, not the signed account calls).
  const ServerCheckProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'serverCheckProvider',
          isAutoDispose: false,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$serverCheckHash();

  @$internal
  @override
  $FutureProviderElement<TunnelCheck> $createElement(
          $ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<TunnelCheck> create(Ref ref) {
    return serverCheck(ref);
  }
}

String _$serverCheckHash() => r'9879b6776e4734e1784a0c8efc2c363590e52d3c';
