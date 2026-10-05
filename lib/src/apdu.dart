import 'dart:typed_data';

import 'package:eid/src/secret_instruction.dart';

/// An ISO 7816-4 command APDU.
///
/// Short APDUs only: at most 255 bytes of data and 256 bytes expected back.
final class CommandApdu {
  /// A command with class [cla], instruction [ins] and parameters [p1], [p2].
  ///
  /// [le] is the number of bytes expected back, 1 to 256, or null for none.
  /// Throws a [RangeError] when a value is out of range.
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
    RangeError.checkValueInInterval(this.data.length, 0, 255, 'data.length');
    if (le != null) RangeError.checkValueInInterval(le!, 1, 256, 'le');
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

  /// The same command expecting [le] bytes back.
  CommandApdu withLe(int le) =>
      CommandApdu(cla, ins, p1, p2, data: data, le: le);

  /// The command as the bytes a transport sends.
  Uint8List toBytes() {
    final bytes = BytesBuilder(copy: false)..add([cla, ins, p1, p2]);
    if (data.isNotEmpty) {
      bytes
        ..addByte(data.length)
        ..add(data);
    }
    // An Le of 256 is encoded as 00.
    if (le != null) bytes.addByte(le! & 0xFF);
    return bytes.takeBytes();
  }

  /// The command as hexadecimal, only its header when the data holds a PIN.
  @override
  String toString() => data.isNotEmpty && isSecretInstruction(ins)
      ? '${hexString([cla, ins, p1, p2, data.length])} (redacted)'
      : hexString(toBytes());
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
