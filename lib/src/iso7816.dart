import 'dart:typed_data';

import 'package:eid/src/apdu.dart';
import 'package:eid/src/card_channel.dart';
import 'package:eid/src/card_exception.dart';

/// Common ISO 7816-4 commands: select a file or application, read a file.
///
/// Each throws a [CardException] when the card returns an error status.
extension Iso7816Commands on CardChannel {
  /// Selects the file or directory [fileId] in the current directory.
  Future<void> selectFile(int fileId) async {
    RangeError.checkValueInInterval(fileId, 0, 0xFFFF, 'fileId');
    await expect(
      CommandApdu(0x00, 0xA4, 0x02, 0x0C, data: [fileId >> 8, fileId & 0xFF]),
      'SELECT FILE ${_fileId(fileId)}',
    );
  }

  /// Selects [path] from the master file down, one [selectFile] per
  /// identifier.
  Future<void> selectPath(List<int> path) async {
    for (final fileId in path) {
      await selectFile(fileId);
    }
  }

  /// Selects the application [aid].
  ///
  /// Set [returnFci] for cards that require it; the answer is discarded.
  Future<void> selectApplication(List<int> aid,
      {bool returnFci = false}) async {
    RangeError.checkValueInInterval(aid.length, 5, 16, 'aid.length');
    await expect(
      CommandApdu(0x00, 0xA4, 0x04, returnFci ? 0x00 : 0x0C, data: aid),
      'SELECT APPLICATION ${hexString(aid)}',
    );
  }

  /// Reads up to [length] bytes of the selected file, from [offset].
  Future<Uint8List> readBinary({required int offset, required int length}) {
    RangeError.checkValueInInterval(offset, 0, 0x7FFF, 'offset');
    return expect(
      CommandApdu(0x00, 0xB0, offset >> 8, offset & 0xFF, le: length),
      'READ BINARY at $offset',
    );
  }

  /// Reads the whole selected file, [blockSize] bytes at a time.
  ///
  /// [onProgress] is called after each block with the bytes read so far.
  Future<Uint8List> readTransparentFile({
    int blockSize = 248,
    void Function(int bytesRead)? onProgress,
  }) async {
    RangeError.checkValueInInterval(blockSize, 1, 256, 'blockSize');
    final content = BytesBuilder(copy: false);
    for (var offset = 0;; offset += blockSize) {
      final response = await send(
        CommandApdu(0x00, 0xB0, offset >> 8, offset & 0xFF, le: blockSize),
      );
      if (response.statusWord == 0x6B00 && offset > 0) break;
      if (!response.isSuccess) {
        throw CardException('READ BINARY at $offset', response.statusWord);
      }
      content.add(response.data);
      onProgress?.call(content.length);
      if (response.data.length < blockSize) break;
      if (offset + blockSize > 0x7FFF) {
        throw const CardException('READ BINARY past offset 32767', 0x6B00);
      }
    }
    return content.takeBytes();
  }
}

String _fileId(int fileId) => hexString([fileId >> 8, fileId & 0xFF]);
