import 'dart:typed_data';

/// Carries raw bytes to a card and back: a USB reader, NFC, a test double.
///
/// Status words are not interpreted here; `CardChannel` does that.
/// `eid_ccid` provides a transport for USB and PC/SC readers.
abstract interface class CardTransport {
  /// Sends [command] and returns the response, data then status bytes.
  ///
  /// Throws a [CardTransportException] when the card cannot be reached.
  Future<Uint8List> transmit(Uint8List command);
}

/// A transport something else also sends commands over, such as the
/// presence probe of a `CardWatcher`.
abstract interface class SharedCardTransport implements CardTransport {
  /// Runs [action] with no other command reaching the card until it ends.
  ///
  /// For commands that must follow one another, such as a secure messaging
  /// session, which a stray command would end.
  Future<T> exclusive<T>(Future<T> Function() action);
}

/// The card could not be reached: no reader, no card, or a lost connection.
///
/// An error status from the card is a `CardException` instead.
final class CardTransportException implements Exception {
  /// A failure described by [message], caused by [cause] if known.
  const CardTransportException(this.message, {this.cause});

  /// What went wrong.
  final String message;

  /// The error the transport caught, when there was one.
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'CardTransportException: $message'
      : 'CardTransportException: $message ($cause)';
}
