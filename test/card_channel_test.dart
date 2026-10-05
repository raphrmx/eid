import 'dart:typed_data';

import 'package:eid/eid.dart';
import 'package:test/test.dart';

import 'fake_transport.dart';

void main() {
  group('CardChannel.send', () {
    test('passes an ordinary answer through', () async {
      final transport = ScriptedTransport(['AABB9000']);
      final response =
          await CardChannel(transport).send(CommandApdu(0, 0xB0, 0, 0, le: 2));
      expect(response.data, [0xAA, 0xBB]);
      expect(transport.sent, ['00B0000002']);
    });

    test('sends the command again with the length a 6C asks for', () async {
      final transport = ScriptedTransport(['6C03', '0102039000']);
      final response = await CardChannel(transport)
          .send(CommandApdu(0, 0xB0, 0, 0, le: 248));
      expect(response.data, [1, 2, 3]);
      expect(transport.sent, ['00B00000F8', '00B0000003']);
    });

    test('fetches and joins what a 61 says is waiting', () async {
      final transport =
          ScriptedTransport(['0102 6102', '0304 6101', '05 9000']);
      final response = await CardChannel(transport).send(
        CommandApdu(0, 0xA4, 4, 0, data: [0xA0, 0, 0, 0, 0x30]),
      );
      expect(response.data, [1, 2, 3, 4, 5]);
      expect(response.isSuccess, isTrue);
      expect(transport.sent.skip(1), ['00C0000002', '00C0000001']);
    });

    test('gives up on a card that never stops asking for GET RESPONSE',
        () async {
      final transport = ScriptedTransport(
        List.filled(CardChannel.maxResponseRounds + 2, '6101'),
      );
      await expectLater(
        CardChannel(transport).send(CommandApdu(0, 0xCA, 0, 0, le: 1)),
        throwsA(isA<CardException>()),
      );
    });

    test('returns an error status without throwing', () async {
      final response = await CardChannel(ScriptedTransport(['6A82']))
          .send(CommandApdu(0, 0xA4, 2, 0x0C, data: [0x40, 0x31]));
      expect(response.statusWord, 0x6A82);
    });
  });

  group('Iso7816Commands', () {
    test('selects a path one file identifier at a time', () async {
      final transport = ScriptedTransport(['9000', '9000', '9000']);
      await CardChannel(transport).selectPath([0x3F00, 0xDF01, 0x4031]);
      expect(transport.sent, [
        '00A4020C023F00',
        '00A4020C02DF01',
        '00A4020C024031',
      ]);
    });

    test('throws when a select fails', () async {
      final channel = CardChannel(ScriptedTransport(['6A82']));
      await expectLater(
        channel.selectFile(0x4031),
        throwsA(
          isA<CardException>()
              .having((e) => e.command, 'command', 'SELECT FILE 4031')
              .having((e) => e.isNotFound, 'isNotFound', isTrue),
        ),
      );
    });

    test('reads a file that ends inside a block', () async {
      final content = Uint8List.fromList(List.generate(600, (i) => i & 0xFF));
      final card = OneFileCard(content);
      expect(await CardChannel(card).readTransparentFile(), content);
      // 248 + 248, then 6C 68 and the last 104 bytes.
      expect(card.reads, 4);
    });

    test('reports the bytes read after each block', () async {
      final card = OneFileCard(Uint8List(600));
      final progress = <int>[];
      await CardChannel(card).readTransparentFile(onProgress: progress.add);
      expect(progress, [248, 496, 600]);
    });

    test('reads a file that ends exactly on a block', () async {
      final content = Uint8List.fromList(List.generate(496, (i) => i & 0xFF));
      final card = OneFileCard(content);
      expect(await CardChannel(card).readTransparentFile(), content);
      // Two full blocks, then 6B 00 past the end.
      expect(card.reads, 3);
    });

    test('refuses an offset error on the first block', () async {
      final card = OneFileCard(Uint8List(0));
      await expectLater(
        CardChannel(card).readTransparentFile(),
        throwsA(isA<CardException>()),
      );
    });

    test('reports a file it may not read', () async {
      final channel = CardChannel(ScriptedTransport(['6982']));
      await expectLater(
        channel.readTransparentFile(),
        throwsA(
          isA<CardException>().having(
            (e) => e.isSecurityStatusNotSatisfied,
            'isSecurityStatusNotSatisfied',
            isTrue,
          ),
        ),
      );
    });
  });

  group('onApdu', () {
    test('reports every exchange, GET RESPONSE included', () async {
      final exchanges = <ApduExchange>[];
      final transport = ScriptedTransport(['6102', 'AABB9000']);
      await CardChannel(transport, onApdu: exchanges.add)
          .send(CommandApdu(0, 0xB0, 0, 0, le: 2));

      expect(exchanges.map((e) => hexString(e.command)), [
        '00B0000002',
        '00C0000002',
      ]);
      expect(exchanges.last.statusWord, 0x9000);
      expect(exchanges.last.responseDataLength, 2);
      expect(exchanges.last.toString(), '>> 00C0000002  << AABB9000');
    });

    test('leaves the PIN out', () async {
      final exchanges = <ApduExchange>[];
      final transport = ScriptedTransport(['63C2']);
      await CardChannel(transport, onApdu: exchanges.add).send(
        CommandApdu(0, 0x20, 0, 1, data: bytes('241234FFFFFFFFFF')),
      );

      final verify = exchanges.single;
      expect(verify.isRedacted, isTrue);
      expect(hexString(verify.command), '0020000108');
      expect(verify.toString(), isNot(contains('1234')));
    });

    test('reports a card that could not be reached', () async {
      final exchanges = <ApduExchange>[];
      final channel = CardChannel(_Unreachable(), onApdu: exchanges.add);
      await expectLater(
        channel.send(CommandApdu(0, 0xB0, 0, 0, le: 2)),
        throwsA(isA<CardTransportException>()),
      );
      expect(exchanges.single.response, isNull);
      expect(exchanges.single.failure?.message, 'Card removed');
    });
  });
}

final class _Unreachable implements CardTransport {
  @override
  Future<Uint8List> transmit(Uint8List command) async =>
      throw const CardTransportException('Card removed');
}
