import 'dart:typed_data';

import 'package:eid/src/apdu.dart';
import 'package:eid/src/apdu_exchange.dart';
import 'package:eid/src/card_exception.dart';
import 'package:eid/src/card_transport.dart';

/// Sends commands over a [CardTransport] and returns the final answer.
///
/// Handles the T=0 status words itself: `61 xx` (fetches the rest with GET
/// RESPONSE) and `6C xx` (resends with the right length).
final class CardChannel {
  /// A channel over [transport], reporting each exchange to [onApdu].
  CardChannel(this.transport, {this.onApdu});

  /// The most GET RESPONSE rounds one command may take.
  static const maxResponseRounds = 64;

  /// The transport the commands go through.
  final CardTransport transport;

  /// Called after each command sent, PIN data left out. Should not throw.
  final ApduListener? onApdu;

  /// Sends [command] and returns the card's final answer, whatever its
  /// status. Use [expect] to throw on an error status.
  ///
  /// Throws a [CardException] when GET RESPONSE exceeds [maxResponseRounds].
  Future<ResponseApdu> send(CommandApdu command) async {
    var response = await _exchange(command);

    if (response.sw1 == 0x6C) {
      response = await _exchange(command.withLe(_length(response.sw2)));
    }

    if (response.sw1 != 0x61) return response;

    final data = BytesBuilder(copy: false);
    var rounds = 0;
    while (response.sw1 == 0x61) {
      if (++rounds > maxResponseRounds) {
        throw CardException('GET RESPONSE after $command', response.statusWord);
      }
      data.add(response.data);
      response = await _exchange(
        CommandApdu(0x00, 0xC0, 0x00, 0x00, le: _length(response.sw2)),
      );
    }
    data.add(response.data);
    return ResponseApdu.of(data.takeBytes(), response.statusWord);
  }

  /// Runs [action] with no other command reaching the card until it ends,
  /// when [transport] is a [SharedCardTransport]; otherwise just runs it.
  Future<T> exclusive<T>(Future<T> Function() action) => switch (transport) {
        final SharedCardTransport shared => shared.exclusive(action),
        _ => action(),
      };

  /// Sends [command] and returns its data.
  ///
  /// Throws a [CardException] named [name] unless the status is 0x9000.
  Future<Uint8List> expect(CommandApdu command, String name) async {
    final response = await send(command);
    if (!response.isSuccess) throw CardException(name, response.statusWord);
    return response.data;
  }

  Future<ResponseApdu> _exchange(CommandApdu command) async {
    final listener = onApdu;
    final bytes = command.toBytes();
    if (listener == null) return ResponseApdu(await transport.transmit(bytes));

    final time = DateTime.now();
    final watch = Stopwatch()..start();
    try {
      final response = await transport.transmit(bytes);
      listener(ApduExchange(
        command: bytes,
        response: response,
        time: time,
        duration: watch.elapsed,
      ));
      return ResponseApdu(response);
    } on CardTransportException catch (failure) {
      listener(ApduExchange(
        command: bytes,
        failure: failure,
        time: time,
        duration: watch.elapsed,
      ));
      rethrow;
    }
  }

  // A length byte of 00 stands for 256.
  static int _length(int byte) => byte == 0 ? 256 : byte;
}
