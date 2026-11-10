import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../generator/generator_exception.dart';

/// One message of the plugin protocol: a JSON header with a `type` and an
/// optional binary payload.
///
/// On the wire (both directions): `u32 headerLength`, `u32 payloadLength`
/// (little endian), the UTF-8 JSON header, then the payload bytes.
final class PluginMessage {
  /// Largest accepted header.
  static const maxHeaderBytes = 16 << 20;

  /// Largest accepted payload.
  static const maxPayloadBytes = 1 << 30;

  final Map<String, Object?> header;
  final Uint8List? payload;

  const PluginMessage(this.header, [this.payload]);

  /// The message type (`hello`, `manifest`, `bake`, `frames`, `done`,
  /// `error`), `''` when missing.
  String get type => header['type'] is String ? header['type'] as String : '';

  /// The encoded message.
  Uint8List encode() {
    final json = utf8.encode(jsonEncode(header));
    final body = payload ?? Uint8List(0);
    final out = Uint8List(8 + json.length + body.length);
    final view = ByteData.sublistView(out);
    view.setUint32(0, json.length, Endian.little);
    view.setUint32(4, body.length, Endian.little);
    out.setRange(8, 8 + json.length, json);
    out.setRange(8 + json.length, out.length, body);
    return out;
  }

  @override
  String toString() => 'PluginMessage($header${payload == null ? '' : ', ${payload!.length} bytes'})';
}

/// Splits a byte stream into [PluginMessage]s (chunks may split or join
/// messages). A malformed message ends the stream with a
/// [GeneratorException] of kind [GeneratorErrorKind.protocolError].
final class PluginMessageDecoder extends StreamTransformerBase<List<int>, PluginMessage> {
  const PluginMessageDecoder();

  @override
  Stream<PluginMessage> bind(Stream<List<int>> stream) {
    final controller = StreamController<PluginMessage>();
    var buffer = Uint8List(0);
    var length = 0;
    StreamSubscription<List<int>>? subscription;

    void fail(String message) {
      subscription?.cancel();
      controller.addError(GeneratorException(GeneratorErrorKind.protocolError, message));
      controller.close();
    }

    void onData(List<int> chunk) {
      if (length + chunk.length > buffer.length) {
        final grown = Uint8List((length + chunk.length) * 2);
        grown.setRange(0, length, buffer);
        buffer = grown;
      }
      buffer.setRange(length, length + chunk.length, chunk);
      length += chunk.length;
      var offset = 0;
      while (length - offset >= 8) {
        final view = ByteData.sublistView(buffer, offset, offset + 8);
        final headerLength = view.getUint32(0, Endian.little);
        final payloadLength = view.getUint32(4, Endian.little);
        if (headerLength > PluginMessage.maxHeaderBytes || payloadLength > PluginMessage.maxPayloadBytes) {
          return fail('Message too large: $headerLength + $payloadLength bytes.');
        }
        final total = 8 + headerLength + payloadLength;
        if (length - offset < total) break;
        final Object? header;
        try {
          header = jsonDecode(utf8.decode(Uint8List.sublistView(buffer, offset + 8, offset + 8 + headerLength)));
        } on FormatException catch (e) {
          return fail('Malformed message header: ${e.message}');
        }
        if (header is! Map<String, Object?>) return fail('The message header is not an object.');
        final payload = payloadLength == 0
            ? null
            : Uint8List.fromList(Uint8List.sublistView(buffer, offset + 8 + headerLength, offset + total));
        controller.add(PluginMessage(header, payload));
        offset += total;
      }
      if (offset > 0) {
        buffer.setRange(0, length - offset, buffer, offset);
        length -= offset;
      }
    }

    controller
      ..onListen = () {
        subscription = stream.listen(
          onData,
          onError: controller.addError,
          onDone: () {
            if (length > 0) {
              fail('The stream ended inside a message.');
            } else {
              controller.close();
            }
          },
        );
      }
      ..onPause = (() => subscription?.pause())
      ..onResume = (() => subscription?.resume())
      ..onCancel = (() => subscription?.cancel());
    return controller.stream;
  }
}

/// A duplex message channel over a byte stream pair (stdin/stdout of a
/// plugin process, or an in-memory pipe), used by both the host and the
/// plugin.
final class PluginConnection {
  /// The decoded incoming messages (single subscription); ends when the
  /// input ends.
  final Stream<PluginMessage> messages;
  final StreamSink<List<int>> _output;
  bool _closed = false;

  PluginConnection(Stream<List<int>> input, StreamSink<List<int>> output)
      : messages = input.transform(const PluginMessageDecoder()),
        _output = output;

  /// Sends [message]; ignored after [close].
  void send(PluginMessage message) {
    if (_closed) return;
    _output.add(message.encode());
  }

  /// Closes the output.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _output.close();
  }
}
