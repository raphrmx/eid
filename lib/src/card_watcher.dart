import 'dart:async';
import 'dart:typed_data';

import 'package:eid/src/card_terminal.dart';
import 'package:eid/src/card_transport.dart';

/// Something that happened in a watched terminal.
sealed class CardEvent {
  const CardEvent();
}

/// A card went into the terminal.
final class CardInserted extends CardEvent {
  /// A card reached through [connection].
  const CardInserted(this.connection);

  /// The connection, open until the card is removed or the watcher stops.
  final CardConnection connection;
}

/// The card left the terminal.
final class CardRemoved extends CardEvent {
  /// The card left.
  const CardRemoved();
}

/// Watches a [CardTerminal] and reports cards going in and out.
///
/// Polls every [interval], sending [presenceProbe] while a card is in and no
/// command is under way. Commands that must follow one another, such as a
/// signature right after a PIN check or a secure messaging session, go in
/// `CardChannel.exclusive`.
final class CardWatcher {
  /// A watcher of [terminal], checking every [interval] once started.
  CardWatcher(
    this.terminal, {
    this.interval = const Duration(milliseconds: 400),
  });

  /// The harmless command sent to check the card is still there. Any answer,
  /// error status included, means it is.
  static final Uint8List presenceProbe =
      Uint8List.fromList(const [0x00, 0xCA, 0x00, 0x00, 0x01])
          .asUnmodifiableView();

  /// The terminal watched.
  final CardTerminal terminal;

  /// How often the terminal is checked.
  final Duration interval;

  // How long after a command the probe waits: longer than the gap between
  // the commands of one exchange, such as 61xx and its GET RESPONSE.
  Duration get _quiet => interval < const Duration(milliseconds: 100)
      ? interval
      : const Duration(milliseconds: 100);

  final _events = StreamController<CardEvent>.broadcast();
  _WatchedConnection? _connection;
  int _run = 0;
  bool _watching = false;
  Timer? _timer;
  Completer<void>? _wake;

  /// The insertions and removals.
  ///
  /// Failures other than a [CardTransportException], which counts as no
  /// card, arrive as stream errors; the watcher keeps running.
  Stream<CardEvent> get events => _events.stream;

  /// The connection to the card in the terminal, or null when there is none.
  CardConnection? get connection => _connection;

  /// Whether the watcher is running.
  bool get isWatching => _watching;

  /// Starts watching. Does nothing when already watching.
  void start() {
    if (_watching) return;
    _watching = true;
    _watch(++_run);
  }

  /// Stops watching and releases the card. A card still in is reported again
  /// on the next [start].
  Future<void> stop() async {
    _watching = false;
    _run++;
    _timer?.cancel();
    final wake = _wake;
    if (wake != null && !wake.isCompleted) wake.complete();
    final connection = _connection;
    _connection = null;
    if (connection != null) await _release(connection);
  }

  /// Stops watching for good and closes [events].
  Future<void> dispose() async {
    await stop();
    await _events.close();
  }

  bool _isCurrent(int run) => run == _run && !_events.isClosed;

  Future<void> _watch(int run) async {
    while (_isCurrent(run)) {
      try {
        await _check(run);
      } on Object catch (error, stackTrace) {
        if (_isCurrent(run)) _events.addError(error, stackTrace);
      }
      if (!_isCurrent(run)) return;
      await _sleep();
    }
  }

  Future<void> _check(int run) async {
    final connection = _connection;
    if (connection == null) {
      await _tryConnect(run);
      return;
    }
    if (connection.isBusy) return;
    if (await connection.probe() || !_isCurrent(run)) return;
    _connection = null;
    try {
      await _release(connection);
    } finally {
      if (_isCurrent(run)) _events.add(const CardRemoved());
    }
  }

  Future<void> _sleep() {
    final wake = _wake = Completer<void>();
    _timer = Timer(interval, wake.complete);
    return wake.future;
  }

  Future<void> _tryConnect(int run) async {
    final CardConnection connection;
    try {
      connection = await terminal.connect();
    } on CardTransportException {
      // No card yet.
      return;
    }
    if (!_isCurrent(run)) {
      await _release(connection);
      return;
    }
    final watched = _connection = _WatchedConnection(connection, _quiet);
    _events.add(CardInserted(watched));
  }

  static Future<void> _release(CardConnection connection) async {
    try {
      await connection.disconnect();
    } on Exception {
      // The card is already gone.
    }
  }
}

/// A card connection that keeps the presence probe out of the app's commands.
final class _WatchedConnection implements CardConnection, SharedCardTransport {
  _WatchedConnection(this._connection, this._quiet);

  final CardConnection _connection;
  final Duration _quiet;
  int _inFlight = 0;
  int _held = 0;
  bool _released = false;
  // A timer rather than a stopwatch, so that a test's fake clock drives it.
  Timer? _settling;
  Future<void>? _probing;

  /// Whether a command is in flight, an exclusive run is under way, or
  /// either ended less than the quiet time ago.
  bool get isBusy =>
      _inFlight > 0 || _held > 0 || (_settling?.isActive ?? false);

  /// Sends [CardWatcher.presenceProbe] and returns whether the card answered.
  Future<bool> probe() async {
    final done = Completer<void>();
    _probing = done.future;
    try {
      await _connection.transmit(CardWatcher.presenceProbe);
      return true;
    } on CardTransportException {
      return false;
    } finally {
      _probing = null;
      done.complete();
    }
  }

  @override
  Future<Uint8List> transmit(Uint8List command) async {
    _inFlight++;
    try {
      final probing = _probing;
      if (probing != null) await probing;
      return await _connection.transmit(command);
    } finally {
      _inFlight--;
      _settle();
    }
  }

  @override
  Future<T> exclusive<T>(Future<T> Function() action) async {
    _held++;
    try {
      final probing = _probing;
      if (probing != null) await probing;
      return await action();
    } finally {
      _held--;
      _settle();
    }
  }

  void _settle() {
    _settling?.cancel();
    if (!_released) _settling = Timer(_quiet, () {});
  }

  @override
  Future<void> disconnect() {
    _released = true;
    _settling?.cancel();
    return _connection.disconnect();
  }
}
