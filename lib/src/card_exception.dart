/// A card answered a command with an error status.
final class CardException implements Exception {
  /// The card ended [command] on [statusWord].
  const CardException(this.command, this.statusWord);

  /// The command that failed, such as `SELECT FILE 4031`.
  final String command;

  /// The two status bytes the card returned.
  final int statusWord;

  /// Whether the file or application selected does not exist on this card.
  bool get isNotFound => statusWord == 0x6A82;

  /// Whether the command needs a PIN or another condition first.
  bool get isSecurityStatusNotSatisfied => statusWord == 0x6982;

  /// What ISO 7816-4 says [statusWord] means, when it is a common one.
  String? get description => switch (statusWord) {
        0x6281 => 'part of the returned data may be corrupted',
        0x6282 => 'end of file reached before reading the expected length',
        0x6700 => 'wrong length',
        0x6981 => 'command incompatible with the file structure',
        0x6982 => 'security status not satisfied',
        0x6983 => 'authentication method blocked',
        0x6985 => 'conditions of use not satisfied',
        0x6986 => 'command not allowed, no current file',
        0x6A80 => 'incorrect data',
        0x6A82 => 'file or application not found',
        0x6A86 => 'incorrect parameters P1-P2',
        0x6A87 => 'data length inconsistent with P1-P2',
        0x6B00 => 'offset outside the file',
        0x6D00 => 'instruction not supported',
        0x6E00 => 'class not supported',
        _ => null,
      };

  @override
  String toString() {
    final status = statusWord.toRadixString(16).padLeft(4, '0').toUpperCase();
    final meaning = description;
    return meaning == null
        ? 'CardException: $command returned $status'
        : 'CardException: $command returned $status, $meaning';
  }
}
