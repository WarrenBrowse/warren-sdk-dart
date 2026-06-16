import 'dart:async';
import 'dart:convert';

import 'package:warren_sdk_platform_interface/warren_sdk_platform_interface.dart';

import 'framing.dart';
import 'messages.dart';

/// Speaks the Warren daemon IPC protocol over a duplex byte channel.
///
/// Transport-agnostic on purpose: it takes an `incoming` byte stream and a
/// `send` sink, so it works over a Unix socket, a named pipe or an in-memory
/// pair in tests. It frames outgoing requests, reassembles incoming frames, and
/// surfaces connection-state transitions (errors arrive as a stream error).
class DaemonClient {
  /// Binds the client to a transport.
  DaemonClient({
    required Stream<List<int>> incoming,
    required void Function(List<int> frame) send,
    FrameReader? reader,
    Future<void> Function()? onClose,
  })  : _send = send,
        _reader = reader ?? FrameReader(),
        _onClose = onClose {
    _subscription = incoming.listen(
      _onChunk,
      onError: _states.addError,
      onDone: _states.close,
    );
  }

  final void Function(List<int> frame) _send;
  final FrameReader _reader;
  final Future<void> Function()? _onClose;
  late final StreamSubscription<List<int>> _subscription;
  final StreamController<ConnectionState> _states =
      StreamController<ConnectionState>.broadcast();

  /// Connection-state transitions reported by the daemon. An [ErrorEvent] from
  /// the daemon arrives as a stream error carrying the mapped [WarrenError].
  Stream<ConnectionState> get states => _states.stream;

  /// Binds an identity and account API in the daemon.
  void configure(ConfigureRequest request) => _sendMessage(request);

  /// Opens a system-VPN session to an exit.
  void connect(ConnectRequest request) => _sendMessage(request);

  /// Tears the current session down.
  void disconnect() => _sendMessage(const DisconnectRequest());

  /// Releases the transport subscription, the underlying transport, and the
  /// state stream.
  Future<void> close() async {
    await _subscription.cancel();
    await _onClose?.call();
    if (!_states.isClosed) await _states.close();
  }

  void _sendMessage(DaemonMessage message) {
    final payload = utf8.encode(jsonEncode(message.toJson()));
    _send(FrameCodec.encode(payload));
  }

  void _onChunk(List<int> chunk) {
    for (final payload in _reader.addChunk(chunk)) {
      final json = jsonDecode(utf8.decode(payload)) as Map<String, Object?>;
      final message = DaemonMessage.fromJson(json);
      switch (message) {
        case StateEvent(:final state):
          _states.add(_toConnectionState(state));
        case ErrorEvent():
          _states.addError(_toError(message));
        case ConfigureRequest():
        case ConnectRequest():
        case DisconnectRequest():
          // Requests never flow daemon to app; ignore defensively.
          break;
      }
    }
  }
}

ConnectionState _toConnectionState(DaemonConnectionState state) =>
    switch (state) {
      DaemonConnectionState.connecting => const Connecting(),
      DaemonConnectionState.connected => const Connected(),
      DaemonConnectionState.reconnecting => const Reconnecting(),
      DaemonConnectionState.disconnected => const Disconnected(),
      DaemonConnectionState.failed => const ConnectionFailed(
          code: 'tunnel/failed',
          message: 'the connection failed and will not be retried',
        ),
    };

WarrenError _toError(ErrorEvent event) => warrenErrorOfKind(
      event.kind,
      code: '${event.kind}/daemon',
      message: event.message,
    );
