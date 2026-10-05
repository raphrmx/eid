import 'package:eid/src/card_terminal.dart';
import 'package:eid/src/card_transport.dart';

/// All the terminals [list] returns, as one: connects to the card in
/// whichever terminal holds one.
///
/// The terminals are listed again on each connection attempt, so readers
/// plugged in later are found. When several hold a card, the first listed
/// wins.
///
/// ```dart
/// final watcher = CardWatcher(AnyCardTerminal(CcidTerminal.list));
/// ```
final class AnyCardTerminal implements CardTerminal {
  /// Combines the terminals [list] returns.
  AnyCardTerminal(this.list, {this.name = 'Any terminal'});

  /// Lists the terminals currently there.
  final Future<List<CardTerminal>> Function() list;

  @override
  final String name;

  List<CardTerminal> _terminals = const [];
  CardTerminal? _current;

  /// The terminals found by the last connection attempt.
  List<CardTerminal> get terminals => _terminals;

  /// The terminal the last connection went to, or null when the last attempt
  /// found no card.
  CardTerminal? get current => _current;

  /// Connects to the card in the first terminal that holds one, skipping
  /// terminals that fail.
  ///
  /// Throws a [CardTransportException] when none does, or when listing fails.
  @override
  Future<CardConnection> connect() async {
    final List<CardTerminal> terminals;
    try {
      terminals = _terminals = List.unmodifiable(await list());
    } on CardTransportException {
      _terminals = const [];
      _current = null;
      rethrow;
    } on Exception catch (error) {
      _terminals = const [];
      _current = null;
      throw CardTransportException('Could not list the terminals',
          cause: error);
    }
    Exception? firstFailure;
    var failures = 0;
    for (final terminal in terminals) {
      try {
        final connection = await terminal.connect();
        _current = terminal;
        return connection;
      } on CardTransportException {
        // No card in this one.
      } on Exception catch (error) {
        firstFailure ??= error;
        failures++;
      }
    }
    _current = null;
    if (firstFailure != null && failures == terminals.length) {
      throw CardTransportException(
        'Could not connect to any terminal',
        cause: firstFailure,
      );
    }
    throw CardTransportException(
      terminals.isEmpty ? 'No terminal' : 'No card in any terminal',
    );
  }

  @override
  String toString() => 'AnyCardTerminal($name)';
}
