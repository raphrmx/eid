import 'dart:typed_data';

import 'package:eid/src/secret_instruction.dart';

/// An ISO 7816-4 command APDU.
///
/// Short when it can be: up to 255 bytes of data and 256 expected back.
/// Beyond that it is written in extended length, up to 65535 bytes of data
/// and 65536 expected back, which not every card or reader accepts.
final class CommandApdu {
  /// A command with class [cla], instruction [ins] and parameters [p1], [p2].
  ///
  /// [le] is the number of bytes expected back, 1 to 65536, or null for
  /// none. Throws a [RangeError] when a value is out of range.
  CommandApdu(
    this.cla,
    this.ins,
    this.p1,
    this.p2, {
    List<int>? data,
    this.le,
  }) : data = Uint8List.fromList(data ?? const []) {
    _checkByte(cla, 'cla');
    _checkByte(ins, 'ins');
    _checkByte(p1, 'p1');
    _checkByte(p2, 'p2');
    RangeError.checkValueInInterval(this.data.length, 0, 0xFFFF, 'data.length');
    if (le != null) RangeError.checkValueInInterval(le!, 1, 0x10000, 'le');
  }

  /// Reads a command from the [bytes] a transport would send.
  ///
  /// Throws a [FormatException] when they are not a command of one of the
  /// four ISO 7816-4 cases, short or extended.
  factory CommandApdu.parse(List<int> bytes) {
    final length = bytes.length;
    if (length < 4) {
      throw FormatException('A command has a four byte header', bytes);
    }
    final header = bytes.sublist(0, 4);
    CommandApdu build({List<int>? data, int? le}) =>
        CommandApdu(header[0], header[1], header[2], header[3],
            data: data, le: le);
    if (length == 4) return build();
    final first = bytes[4];
    if (length == 5) return build(le: first == 0 ? 256 : first);
    if (first != 0) {
      // Short: Lc, data, then Le if one byte is left.
      final end = 5 + first;
      if (length == end) return build(data: bytes.sublist(5, end));
      if (length == end + 1) {
        final le = bytes[end];
        return build(data: bytes.sublist(5, end), le: le == 0 ? 256 : le);
      }
      throw FormatException('Lc does not match the length', bytes);
    }
    if (length < 7) throw FormatException('Truncated length field', bytes);
    final value = bytes[5] << 8 | bytes[6];
    if (length == 7) return build(le: value == 0 ? 0x10000 : value);
    // Extended: 00, Lc on two bytes, data, then Le on two bytes if left.
    final end = 7 + value;
    if (value == 0 || length != end && length != end + 2) {
      throw FormatException('Lc does not match the length', bytes);
    }
    if (length == end) return build(data: bytes.sublist(7, end));
    final le = bytes[end] << 8 | bytes[end + 1];
    return build(data: bytes.sublist(7, end), le: le == 0 ? 0x10000 : le);
  }

  /// The class byte.
  final int cla;

  /// The instruction byte.
  final int ins;

  /// The first parameter byte.
  final int p1;

  /// The second parameter byte.
  final int p2;

  /// The data sent with the command, empty when there is none.
  final Uint8List data;

  /// The number of bytes expected back, or null when none are.
  final int? le;

  /// Whether the command is written in extended length.
  bool get isExtended => data.length > 255 || (le ?? 0) > 256;

  /// The same command expecting [le] bytes back.
  CommandApdu withLe(int le) =>
      CommandApdu(cla, ins, p1, p2, data: data, le: le);

  /// The command as the bytes a transport sends.
  Uint8List toBytes() {
    final bytes = BytesBuilder(copy: false)..add([cla, ins, p1, p2]);
    final extended = isExtended;
    if (extended) bytes.addByte(0);
    if (data.isNotEmpty) {
      bytes
        ..add(_lengthField(data.length, extended: extended))
        ..add(data);
    }
    if (le != null) bytes.add(_lengthField(le!, extended: extended));
    return bytes.takeBytes();
  }

  /// The command as hexadecimal, only its header and Lc when the data holds
  /// a PIN.
  @override
  String toString() {
    if (data.isEmpty || !isSecretInstruction(ins)) return hexString(toBytes());
    final extended = isExtended;
    return '${hexString([
          cla,
          ins,
          p1,
          p2,
          if (extended) 0,
          ..._lengthField(data.length, extended: extended),
        ])} (redacted)';
  }

  // A length of 256, or 65536 in extended length, is written as zeros.
  static List<int> _lengthField(int length, {required bool extended}) =>
      extended ? [length >> 8 & 0xFF, length & 0xFF] : [length & 0xFF];
}

/// A response from a card: the data, then the two status bytes.
final class ResponseApdu {
  /// Parses the raw [bytes] a transport returned.
  ///
  /// Throws a [FormatException] when there are fewer than two bytes.
  factory ResponseApdu(Uint8List bytes) {
    if (bytes.length < 2) {
      throw FormatException(
        'A response carries at least two status bytes',
        hexString(bytes),
      );
    }
    final end = bytes.length - 2;
    return ResponseApdu.of(
      Uint8List.sublistView(bytes, 0, end),
      bytes[end] << 8 | bytes[end + 1],
    );
  }

  /// A response carrying [data] and ending on [statusWord].
  ResponseApdu.of(this.data, this.statusWord);

  /// The data the card returned, empty when there is none.
  final Uint8List data;

  /// The two status bytes as one value, 0x9000 on success.
  final int statusWord;

  /// The first status byte.
  int get sw1 => statusWord >> 8;

  /// The second status byte.
  int get sw2 => statusWord & 0xFF;

  /// Whether the card completed the command normally.
  bool get isSuccess => statusWord == 0x9000;

  @override
  String toString() {
    final status = hexString([sw1, sw2]);
    return data.isEmpty ? status : '${hexString(data)} $status';
  }
}

/// [bytes] as upper case hexadecimal, two digits per byte.
String hexString(List<int> bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString().toUpperCase();
}

void _checkByte(int value, String name) =>
    RangeError.checkValueInInterval(value, 0, 255, name);
