import 'dart:typed_data';

/// Length-prefixed framing for the daemon IPC stream.
///
/// Each frame is a 4-byte big-endian unsigned length followed by that many
/// payload bytes (a UTF-8 JSON message). A stream socket delivers arbitrary
/// chunks, so the reader reassembles frames across chunk boundaries.
abstract final class FrameCodec {
  /// The default ceiling on a single frame, guarding against a hostile or
  /// desynchronized peer claiming a huge length.
  static const int defaultMaxFrameBytes = 16 * 1024 * 1024;

  /// Encodes [payload] as one length-prefixed frame.
  static Uint8List encode(List<int> payload) {
    final frame = Uint8List(4 + payload.length);
    ByteData.view(frame.buffer).setUint32(0, payload.length, Endian.big);
    frame.setRange(4, frame.length, payload);
    return frame;
  }
}

/// Reassembles length-prefixed frames from a byte stream.
///
/// Feed raw chunks to [addChunk]; it returns every complete frame payload that
/// became available, buffering any partial remainder for the next chunk.
class FrameReader {
  /// Creates a reader that rejects frames larger than [maxFrameBytes].
  FrameReader({this.maxFrameBytes = FrameCodec.defaultMaxFrameBytes});

  /// The largest frame this reader will accept before throwing.
  final int maxFrameBytes;

  final BytesBuilder _buffer = BytesBuilder(copy: false);
  Uint8List _pending = Uint8List(0);

  /// Adds a chunk and returns the frame payloads now complete.
  ///
  /// Throws a [FormatException] if a frame declares a length above
  /// [maxFrameBytes].
  List<Uint8List> addChunk(List<int> chunk) {
    _buffer
      ..add(_pending)
      ..add(chunk);
    _pending = _buffer.takeBytes();

    final frames = <Uint8List>[];
    var offset = 0;
    while (_pending.length - offset >= 4) {
      final length =
          ByteData.view(_pending.buffer, _pending.offsetInBytes + offset)
              .getUint32(0, Endian.big);
      if (length > maxFrameBytes) {
        throw FormatException('frame too large: $length > $maxFrameBytes');
      }
      if (_pending.length - offset - 4 < length) break;
      final start = offset + 4;
      frames.add(Uint8List.sublistView(_pending, start, start + length));
      offset = start + length;
    }
    _pending = Uint8List.sublistView(_pending, offset);
    return frames;
  }
}
