import 'package:warren_sdk_platform_interface/warren_sdk_platform_interface.dart';

import 'engine_mapping.dart';
import 'rust/api/client.dart' as rust;
import 'rust/api/error.dart';

/// A live engine client handle backed by the in-process Rust client.
///
/// Wraps the opaque `WarrenClientFrb`. The bound address is read once at
/// creation so the synchronous [address] getter needs no bridge round-trip.
/// Every fallible call maps the typed engine error to a sealed [WarrenError].
class FfiClientHandle implements WarrenClientHandle {
  /// Wraps an opaque engine client and its already-resolved [address].
  FfiClientHandle(this._client, this.address);

  final rust.WarrenClientFrb _client;
  bool _disposed = false;

  @override
  final String address;

  @override
  Future<SubscriptionInfo> subscription() => _mapped(() async {
        final expiry = await _client.subscriptionExpiry();
        return SubscriptionInfo(expiresAtUnix: expiry.toInt());
      });

  @override
  Future<void> redeemVoucher(String secret) =>
      _mapped(() => _client.redeemVoucher(secret: secret));

  @override
  Future<List<ExitInfo>> listExits() => _mapped(() async {
        final dtos = await _client.listExits();
        return dtos.map(exitInfoFromDto).toList(growable: false);
      });

  @override
  Future<WarrenSessionHandle> connect(
    ExitInfo exit,
    ConnectMode mode,
    ConnectOptions options,
  ) async =>
      throw const WarrenUnsupportedError(
        code: 'datapath/not-yet',
        message: 'The proxy datapath lands in roadmap P3.',
      );

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _client.dispose();
  }

  Future<T> _mapped<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on WarrenFfiError catch (error) {
      throw mapEngineError(error);
    }
  }
}
