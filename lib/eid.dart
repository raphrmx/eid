/// Talks to electronic identity cards over any transport.
///
/// A [CardTransport] exchanges raw bytes with a card. A [CardChannel] sends
/// [CommandApdu]s over it and offers the common ISO 7816-4 commands. Country
/// packages such as `eid_belgium` read the card's content.
library;

export 'src/any_card_terminal.dart';
export 'src/apdu.dart';
export 'src/apdu_exchange.dart';
export 'src/card_channel.dart';
export 'src/card_exception.dart';
export 'src/card_terminal.dart';
export 'src/card_transport.dart';
export 'src/card_watcher.dart';
export 'src/iso7816.dart';
export 'src/partial_date.dart';
export 'src/sex.dart';
