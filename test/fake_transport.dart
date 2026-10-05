import 'dart:typed_data';

import 'package:eid/eid.dart';

/// Answers each command with the next scripted response, and records what it
/// was sent.
final class ScriptedTransport implements CardTransport {
  ScriptedTransport(List<String> responses)
      : _responses = responses.map(bytes).toList();

  final List<Uint8List> _responses;
  final List<String> sent = [];

  @override
  Future<Uint8List> transmit(Uint8List command) async {
    sent.add(hexString(command));
    if (_responses.isEmpty) {
      throw StateError('No response scripted for ${hexString(command)}');
    }
    return _responses.removeAt(0);
  }
}

/// A card holding one transparent file, answering READ BINARY the way a T=0
/// card does: `6C xx` when fewer bytes remain than asked for, `6B 00` past the
/// end.
final class OneFileCard implements CardTransport {
  OneFileCard(this.content);

  final Uint8List content;
  int reads = 0;

  @override
  Future<Uint8List> transmit(Uint8List command) async {
    reads++;
    final offset = command[2] << 8 | command[3];
    final le = command[4] == 0 ? 256 : command[4];
    if (offset >= content.length) return bytes('6B00');
    final left = content.length - offset;
    if (le > left) return Uint8List.fromList([0x6C, left]);
    return Uint8List.fromList([
      ...content.sublist(offset, offset + le),
      0x90,
      0x00,
    ]);
  }
}

Uint8List bytes(String hex) {
  final clean = hex.replaceAll(' ', '');
  return Uint8List.fromList([
    for (var i = 0; i < clean.length; i += 2)
      int.parse(clean.substring(i, i + 2), radix: 16),
  ]);
}
