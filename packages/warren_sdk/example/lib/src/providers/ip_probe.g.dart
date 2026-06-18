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

String _$netCheckHash() => r'1446b9d1ba29ca4560c5df0eb505c57d9383d40b';
