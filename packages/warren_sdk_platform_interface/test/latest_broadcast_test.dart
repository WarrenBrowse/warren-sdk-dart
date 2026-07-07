import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:warren_sdk_platform_interface/warren_sdk_platform_interface.dart';

void main() {
  group(LatestBroadcast, () {
    late StreamController<int> source;
    late LatestBroadcast<int> subject;

    setUp(() {
      source = StreamController<int>();
      subject = LatestBroadcast<int>(source.stream);
    });

    tearDown(() async {
      await subject.close();
      if (!source.isClosed) await source.close();
    });

    test('replays the latest event to a listener that attaches late', () async {
      source
        ..add(1)
        ..add(2);
      // Let the eager upstream subscription drain the events into the cache.
      await pumpEventQueue();

      expect(await subject.stream.first, 2);
    });

    test('delivers subsequent events to every listener', () async {
      final a = <int>[];
      final b = <int>[];
      final subA = subject.stream.listen(a.add);
      final subB = subject.stream.listen(b.add);

      source
        ..add(10)
        ..add(20);
      await pumpEventQueue();

      expect(a, [10, 20]);
      expect(b, [10, 20]);
      await subA.cancel();
      await subB.cancel();
    });

    test('a late listener sees the cached value then live events', () async {
      source.add(1);
      await pumpEventQueue();

      final seen = <int>[];
      final sub = subject.stream.listen(seen.add);
      source.add(2);
      await pumpEventQueue();

      expect(seen, [1, 2]);
      await sub.cancel();
    });

    test('does not replay a transient error to a late listener', () async {
      source.addError(StateError('boom'));
      await pumpEventQueue();

      // A listener attaching after the error must not be re-delivered it; it is
      // transient, unlike the latest value.
      var errored = false;
      final sub = subject.stream.listen(
        (_) {},
        onError: (Object _) => errored = true,
      );
      source.add(7);
      await pumpEventQueue();

      expect(errored, isFalse);
      await sub.cancel();
    });

    test('subscribes to the source only once regardless of listeners',
        () async {
      var subscriptions = 0;
      final counted = StreamController<int>(onListen: () => subscriptions++);
      final broadcast = LatestBroadcast<int>(counted.stream);
      addTearDown(broadcast.close);

      await broadcast.stream.listen((_) {}).cancel();
      await broadcast.stream.listen((_) {}).cancel();
      await pumpEventQueue();

      expect(subscriptions, 1);
      await counted.close();
    });
  });
}
