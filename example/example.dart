// ignore_for_file: avoid_print

import 'dart:typed_data';

import 'package:eid/eid.dart';

/// Reads a transparent file by path, over whatever transport is at hand.
///
/// In an application the transport comes from an adapter package, such as
/// `eid_ccid` for a USB reader. Country packages such as `eid_belgium` know
/// the paths and decode the files.
Future<Uint8List> readFile(CardTransport transport, List<int> path) async {
  final channel = CardChannel(transport);
  await channel.selectPath(path);
  return await channel.readTransparentFile();
}

/// A card that holds one four byte file, to run the example without a reader.
final class DemoCard implements CardTransport {
  @override
  Future<Uint8List> transmit(Uint8List command) async {
    final isRead = command[1] == 0xB0;
    return Uint8List.fromList(isRead ? [1, 2, 3, 4, 0x90, 0x00] : [0x90, 0x00]);
  }
}

Future<void> main() async {
  final content = await readFile(DemoCard(), [0x3F00, 0xDF01, 0x4031]);
  print(hexString(content)); // 01020304
}
