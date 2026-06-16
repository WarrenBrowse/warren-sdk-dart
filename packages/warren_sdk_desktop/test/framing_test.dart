import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:warren_sdk_desktop/warren_sdk_desktop.dart';

void main() {
  group('FrameCodec.encode', () {
    test('prefixes a 4-byte big-endian length', () {
      final frame = FrameCodec.encode([1, 2, 3]);
      expect(frame.sublist(0, 4), [0, 0, 0, 3]);
      expect(frame.sublist(4), [1, 2, 3]);
    });
  });

  group('FrameReader', () {
    test('reads a single whole frame', () {
      final reader = FrameReader();
      final frames = reader.addChunk(FrameCodec.encode(utf8.encode('hi')));
      expect(frames, hasLength(1));
      expect(utf8.decode(frames.single), 'hi');
    });

    test('reassembles a frame split across chunks', () {
      final reader = FrameReader();
      final whole = FrameCodec.encode(utf8.encode('hello'));
      expect(reader.addChunk(whole.sublist(0, 3)), isEmpty);
      final frames = reader.addChunk(whole.sublist(3));
      expect(frames, hasLength(1));
      expect(utf8.decode(frames.single), 'hello');
    });

    test('returns every frame packed into one chunk', () {
      final reader = FrameReader();
      final chunk = <int>[
        ...FrameCodec.encode([1]),
        ...FrameCodec.encode([2, 3]),
      ];
      final frames = reader.addChunk(chunk);
      expect(frames.map((f) => f.toList()), [
        [1],
        [2, 3],
      ]);
    });

    test('keeps a trailing partial frame for the next chunk', () {
      final reader = FrameReader();
      final chunk = <int>[
        ...FrameCodec.encode([9]),
        ...FrameCodec.encode([8, 7]).sublist(0, 5),
      ];
      expect(reader.addChunk(chunk), hasLength(1));
      final rest = reader.addChunk(FrameCodec.encode([8, 7]).sublist(5));
      expect(rest, hasLength(1));
    });

    test('rejects a frame larger than the limit', () {
      final reader = FrameReader(maxFrameBytes: 2);
      expect(
        () => reader.addChunk(FrameCodec.encode([1, 2, 3])),
        throwsFormatException,
      );
    });
  });
}
