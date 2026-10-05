import 'package:eid/src/card_transport.dart';

/// A connection to the card in a terminal.
abstract interface class CardConnection implements CardTransport {
  /// Releases the card. The connection cannot be used afterwards.
  Future<void> disconnect();
}

/// Where a card goes: a reader's slot, or a simulated card.
///
/// Use a `CardWatcher` to get insertion and removal events.
abstract interface class CardTerminal {
  /// The name of the terminal, such as the name of the reader.
  String get name;

  /// Connects to the card in the terminal.
  ///
  /// Throws a [CardTransportException] when there is no card or terminal.
  Future<CardConnection> connect();
}
