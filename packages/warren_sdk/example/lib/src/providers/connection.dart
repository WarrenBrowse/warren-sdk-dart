import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:warren_sdk_riverpod/warren_sdk_riverpod.dart';

import 'activity_log.dart';

part 'connection.g.dart';

/// Owns the active [WarrenSession]: opening it through the live client,
/// swapping it on reconnect, and tearing it down. The session's reactive state
/// is mirrored by the package's `connectionStateProvider(session)`.
@Riverpod(keepAlive: true)
class ConnectionController extends _$ConnectionController {
  @override
  FutureOr<WarrenSession?> build() => null;

  /// Opens a connection to [exit] in [mode] with [options], replacing and
  /// disposing any previous session.
  Future<void> connect({
    required ExitInfo exit,
    required ConnectMode mode,
    required ConnectOptions options,
  }) async {
    final log = ref.read(activityLogProvider.notifier);
    final previous = state.asData?.value;
    state = const AsyncValue<WarrenSession?>.loading();
    try {
      final client = await ref.read(warrenClientProvider.future);
      log.info(
        'connection',
        'connect(${mode.name}) to ${exit.city}, ${exit.country}…',
      );
      final session = await client.connect(exit, mode: mode, options: options);
      if (previous != null) {
        await previous.disconnect();
      }
      state = AsyncValue.data(session);

      final endpoints = session.endpoints;
      if (endpoints != null) {
        final http = endpoints.http;
        log.success(
          'connection',
          'session up; SOCKS5 ${endpoints.socks5}'
              '${http != null ? ', HTTP $http' : ''}',
        );
      } else {
        log.success(
          'connection',
          'system-VPN session up; all OS traffic is captured',
        );
      }
    } on WarrenError catch (error, stackTrace) {
      log.error('connection', error.message, code: error.code);
      state = AsyncValue<WarrenSession?>.error(error, stackTrace);
    }
  }

  /// Tears the current session down, if any.
  Future<void> disconnect() async {
    final session = state.asData?.value;
    if (session != null) {
      await session.disconnect();
      ref.read(activityLogProvider.notifier).info('connection', 'disconnected');
    }
    state = const AsyncValue<WarrenSession?>.data(null);
  }
}
