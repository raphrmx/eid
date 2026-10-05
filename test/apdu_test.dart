import 'package:eid/eid.dart';
import 'package:test/test.dart';

import 'fake_transport.dart';

void main() {
  group('CommandApdu', () {
    test('writes the four cases of ISO 7816-4', () {
      expect(CommandApdu(0x80, 0xE6, 0, 0).toString(), '80E60000');
      expect(CommandApdu(0, 0xB0, 1, 2, le: 248).toString(), '00B00102F8');
      expect(
        CommandApdu(0, 0xA4, 2, 0x0C, data: [0x40, 0x31]).toString(),
        '00A4020C024031',
      );
      expect(
        CommandApdu(0, 0x88, 2, 0x81, data: [1, 2], le: 128).toString(),
        '0088028102010280',
      );
    });

    test('leaves PIN and PUK data out of its text', () {
      final pin = [0x24, 0x12, 0x34, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF];
      expect(
        CommandApdu(0, 0x20, 0, 1, data: pin).toString(),
        '0020000108 (redacted)',
      );
      expect(
        CommandApdu(0, 0x24, 0, 1, data: pin + pin).toString(),
        '0024000110 (redacted)',
      );
      expect(
        CommandApdu(0, 0x2C, 0, 1, data: pin).toString(),
        '002C000108 (redacted)',
      );
      expect(CommandApdu(0, 0x20, 0, 1).toString(), '00200001');
    });

    test('writes an expected length of 256 as 00', () {
      expect(CommandApdu(0, 0xB0, 0, 0, le: 256).toString(), '00B0000000');
    });

    test('refuses what a short APDU cannot carry', () {
      expect(() => CommandApdu(0x100, 0, 0, 0), throwsRangeError);
      expect(() => CommandApdu(0, 0, 0, 0, le: 0), throwsRangeError);
      expect(() => CommandApdu(0, 0, 0, 0, le: 257), throwsRangeError);
      expect(
        () => CommandApdu(0, 0, 0, 0, data: List.filled(256, 0)),
        throwsRangeError,
      );
    });
  });

  group('ResponseApdu', () {
    test('splits the data from the status bytes', () {
      final response = ResponseApdu(bytes('0102039000'));
      expect(response.data, [1, 2, 3]);
      expect(response.statusWord, 0x9000);
      expect(response.isSuccess, isTrue);
      expect(response.toString(), '010203 9000');
    });

    test('reads a bare status word', () {
      final response = ResponseApdu(bytes('6A82'));
      expect(response.data, isEmpty);
      expect(response.sw1, 0x6A);
      expect(response.sw2, 0x82);
      expect(response.isSuccess, isFalse);
    });

    test('refuses a response shorter than the status bytes', () {
      expect(() => ResponseApdu(bytes('90')), throwsFormatException);
    });
  });

  test('CardException names the status word', () {
    const error = CardException('SELECT FILE 4031', 0x6A82);
    expect(error.isNotFound, isTrue);
    expect(
      error.toString(),
      'CardException: SELECT FILE 4031 returned 6A82, '
      'file or application not found',
    );
  });
}
