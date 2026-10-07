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
  ///
  /// Past offset 32767, the command is READ BINARY with the odd instruction
  /// B1, which not every card supports; [length] then excludes the data
  /// object that wraps the answer.
  Future<Uint8List> readBinary({
    required int offset,
    required int length,
  }) async {
    RangeError.checkValueInInterval(offset, 0, maxReadOffset, 'offset');
    final odd = offset > _maxEvenOffset;
    final response = await send(
      _readCommand(offset, odd ? length + _wrapperSize(length) : length),
    );
    if (!response.isSuccess) {
      throw CardException('READ BINARY at $offset', response.statusWord);
    }
    return odd ? _unwrapOddRead(response.data) : response.data;
  }

  /// The highest offset [readBinary] reaches.
  static const maxReadOffset = 0xFFFFFF;

  /// Reads the whole selected file, [blockSize] bytes at a time.
  ///
  /// [onProgress] is called after each block with the bytes read so far.
  /// Past offset 32767, blocks are read as [readBinary] does.
  Future<Uint8List> readTransparentFile({
    int blockSize = 248,
    void Function(int bytesRead)? onProgress,
  }) async {
    RangeError.checkValueInInterval(blockSize, 1, 256, 'blockSize');
    final content = BytesBuilder(copy: false);
    while (true) {
      final offset = content.length;
      if (offset > maxReadOffset) {
        throw const CardException('READ BINARY past offset 16777215', 0x6B00);
      }
      final odd = offset > _maxEvenOffset;
      // Past 32767 the answer is wrapped: ask for less so the whole still
      // fits in [blockSize].
      final wanted = odd ? _oddBlock(blockSize) : blockSize;
      final response = await send(
        _readCommand(offset, odd ? wanted + _wrapperSize(wanted) : wanted),
      );
      if (response.statusWord == 0x6B00 && offset > 0) break;
      if (!response.isSuccess) {
        throw CardException('READ BINARY at $offset', response.statusWord);
      }
      final data = odd ? _unwrapOddRead(response.data) : response.data;
      content.add(data);
      onProgress?.call(content.length);
      if (data.length < wanted) break;
    }
    return content.takeBytes();
  }
}

// READ BINARY B0 carries the offset in P1-P2, bit 8 of P1 cleared.
const _maxEvenOffset = 0x7FFF;

CommandApdu _readCommand(int offset, int le) {
  if (offset <= _maxEvenOffset) {
    return CommandApdu(0x00, 0xB0, offset >> 8, offset & 0xFF, le: le);
  }
  // B1: the offset in data object 54, on two bytes, or three past 65535.
  return CommandApdu(0x00, 0xB1, 0x00, 0x00, le: le, data: [
    0x54,
    if (offset > 0xFFFF) ...[3, offset >> 16] else 2,
    offset >> 8 & 0xFF,
    offset & 0xFF,
  ]);
}

// The bytes data object 53 adds around [length] bytes.
int _wrapperSize(int length) => length < 0x80
    ? 2
    : length < 0x100
        ? 3
        : 4;

// The data a B1 answer of at most [blockSize] bytes can carry.
int _oddBlock(int blockSize) {
  if (blockSize <= 2) return 1;
  return blockSize - (blockSize > 129 ? 3 : 2);
}

// A B1 answer holds the data in data object 53.
Uint8List _unwrapOddRead(Uint8List answer) {
  if (answer.isEmpty) return answer;
  if (answer[0] != 0x53 || answer.length < 2) {
    throw FormatException('READ BINARY B1 did not answer with tag 53', answer);
  }
  var start = 2;
  var length = answer[1];
  if (length > 0x80) {
    final count = length & 0x7F;
    if (count > 3 || answer.length < 2 + count) {
      throw FormatException('Unsupported length in tag 53', answer);
    }
    length = 0;
    for (var i = 0; i < count; i++) {
      length = length << 8 | answer[2 + i];
    }
    start += count;
  } else if (length == 0x80) {
    throw FormatException('Unsupported length in tag 53', answer);
  }
  if (start + length > answer.length) {
    throw FormatException('Tag 53 runs past the answer', answer);
  }
  return Uint8List.sublistView(answer, start, start + length);
}

String _fileId(int fileId) => hexString([fileId >> 8, fileId & 0xFF]);
