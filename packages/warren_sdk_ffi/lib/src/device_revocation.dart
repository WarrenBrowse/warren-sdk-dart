import 'dart:async';

/// Whether this install's device was revoked, as a broadcast stream that
/// replays the latest answer on listen.
///
/// The engine learns a revocation from its credential refresh and keeps it as
/// a sticky flag; nothing pushes it. This asks the flag on listen and then
/// at every period while someone listens, emits only changes, and stops
/// asking once the answer is `true`, since a revocation is never lifted.
class DeviceRevocationWatch {
  /// Watches the flag the check function reads, asking at every period.
  DeviceRevocationWatch(this._check, {required Duration every})
      : _every = every;

  final Future<bool> Function() _check;
  final Duration _every;
  late final StreamController<bool> _changes = StreamController<bool>.broadcast(
    onListen: _start,
    onCancel: _stop,
  );
  Timer? _timer;
  bool? _latest;
  bool _closed = false;

  /// The revocation flag: the latest answer first, if any, then each change.
  Stream<bool> get stream => Stream<bool>.multi((controller) {
        final latest = _latest;
        if (latest != null) controller.add(latest);
        if (_closed) {
          controller.close();
          return;
        }
        final sub = _changes.stream.listen(
          controller.add,
          onDone: controller.close,
        );
        controller.onCancel = sub.cancel;
      });

  void _start() {
    if (_latest ?? false) return;
    unawaited(_ask());
    _timer = Timer.periodic(_every, (_) => unawaited(_ask()));
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _ask() async {
    final bool revoked;
    try {
      revoked = await _check();
    } on Object {
      // A check that failed (a disposed client, a bridge fault) says nothing
      // about the device; the next tick asks again.
      return;
    }
    if (_closed || revoked == _latest) return;
    _latest = revoked;
    _changes.add(revoked);
    if (revoked) _stop();
  }

  /// Stops asking and ends the stream.
  Future<void> close() async {
    _closed = true;
    _stop();
    await _changes.close();
  }
}
