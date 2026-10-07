import 'dart:typed_data';

import 'package:eid/src/apdu.dart';
import 'package:eid/src/card_transport.dart';
import 'package:eid/src/secret_instruction.dart';

/// Receives every command a `CardChannel` sends and the card's answer.
typedef ApduListener = void Function(ApduExchange exchange);

/// One command sent to a card and its answer, as reported by a `CardChannel`.
///
/// PIN and PUK data is never reported: such a [command] is cut after its
/// header and length field, and [isRedacted] is true.
final class ApduExchange {
  /// An exchange of [command] for [response], or [failure] if it failed.
  ApduExchange({
    required Uint8List command,
    required DateTime time,
    required Duration duration,
    Uint8List? response,
    CardTransportException? failure,
  }) : this._(
          command,
          dataStart: command.length > 5 && isSecretInstruction(command[1])
              ? _dataStart(command)
              : null,
          time: time,
          duration: duration,
          response: response,
          failure: failure,
        );

  ApduExchange._(
    Uint8List command, {
    required int? dataStart,
    required this.time,
    required this.duration,
    this.response,
    this.failure,
  })  : isRedacted = dataStart != null,
        command = dataStart == null
            ? command
            : Uint8List.fromList(command.sublist(0, dataStart));

  // Where the data of [command] starts, or null when it carries none.
  static int? _dataStart(Uint8List command) {
    if (command[4] != 0) return 5;
    return command.length > 7 ? 7 : null;
  }

  /// The command as sent, or only its header when [isRedacted].
  final Uint8List command;

  /// Whether the data of [command] was left out because it holds a secret.
  final bool isRedacted;

  /// The answer, status word included, or null on [failure].
  final Uint8List? response;

  /// Why the card could not be reached, or null on success.
  final CardTransportException? failure;

  /// When the command was sent.
  final DateTime time;

  /// How long the card took to answer.
  final Duration duration;

  /// The status word of [response], or null.
  int? get statusWord {
    final bytes = response;
    if (bytes == null || bytes.length < 2) return null;
    return bytes[bytes.length - 2] << 8 | bytes[bytes.length - 1];
  }

  /// The bytes of data in [response], status word excluded.
  int get responseDataLength {
    final length = response?.length ?? 0;
    return length < 2 ? 0 : length - 2;
  }

  @override
  String toString() {
    final sent = '${hexString(command)}${isRedacted ? ' (redacted)' : ''}';
    final bytes = response;
    final received =
        bytes == null ? 'failed: ${failure?.message}' : hexString(bytes);
    return '>> $sent  << $received';
  }
}
