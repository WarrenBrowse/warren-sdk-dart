import 'dart:async';

/// A broadcast view over a source stream that replays the most recent event to
/// every new listener.
///
/// The source is subscribed once, eagerly, so its latest event stays cached even
/// while nobody is listening. A subscriber that attaches late (for example a UI
/// that starts observing after the tunnel is already `Connected`) therefore still
/// sees the current value immediately, instead of waiting for the next
/// transition. This is what the platform contract means by "latest-state on
/// listen"; a plain broadcast stream drops events emitted before each listener
/// attaches.
///
/// Errors are forwarded to current listeners but never cached: they are
/// transient, so a late listener is not replayed a stale error. Call [close] to
/// release the upstream subscription when the owner is disposed.
class LatestBroadcast<T> {
  /// Subscribes to [source] eagerly and begins caching its latest event.
  LatestBroadcast(Stream<T> source) {
    _upstream = source.listen(
      (event) {
        _hasLatest = true;
        _latest = event;
        _controller.add(event);
      },
      onError: _controller.addError,
      onDone: _controller.close,
    );
  }

  final StreamController<T> _controller = StreamController<T>.broadcast();
  late final StreamSubscription<T> _upstream;
  bool _hasLatest = false;
  late T _latest;

  /// The replaying broadcast stream. Each new listener first receives the cached
  /// latest event (if any), then every subsequent event.
  Stream<T> get stream => Stream<T>.multi((controller) {
        if (_hasLatest) controller.add(_latest);
        final sub = _controller.stream.listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
        controller.onCancel = sub.cancel;
      });

  /// Releases the upstream subscription and closes the stream.
  Future<void> close() async {
    await _upstream.cancel();
    if (!_controller.isClosed) await _controller.close();
  }
}
