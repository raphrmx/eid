import 'dart:async';
import 'dart:typed_data';

import 'package:eid/eid.dart';
import 'package:test/test.dart';

/// A terminal whose card is put in and taken out by the test.
final class FakeTerminal implements CardTerminal {
  bool cardIn = false;
  int connections = 0;
  int disconnections = 0;
  int probes = 0;

  /// Thrown by the next [connect], then cleared.
  Object? connectFailure;

  /// Completes the pending transmits when set.
  Completer<void>? answer;

  /// Completes the pending disconnections when set.
  Completer<void>? release;

  @override
  String get name => 'Fake reader';

  @override
  Future<CardConnection> connect() async {
    final failure = connectFailure;
    if (failure != null) {
      connectFailure = null;
      throw failure;
    }
    if (!cardIn) throw const CardTransportException('No card');
    connections++;
    return _FakeConnection(this);
  }
}

final class _FakeConnection implements CardConnection {
  _FakeConnection(this.terminal);

  final FakeTerminal terminal;

  @override
  Future<Uint8List> transmit(Uint8List command) async {
    if (hexString(command) == hexString(CardWatcher.presenceProbe)) {
      terminal.probes++;
    }
    await terminal.answer?.future;
    if (!terminal.cardIn) throw const CardTransportException('Card removed');
    return Uint8List.fromList([0x6D, 0x00]);
  }

  @override
  Future<void> disconnect() async {
    await terminal.release?.future;
    terminal.disconnections++;
  }
}

void main() {
  const tick = Duration(milliseconds: 5);
  Future<void> settle() => Future<void>.delayed(tick * 6);

  test('reports a card going in and out', () async {
    final terminal = FakeTerminal();
    final watcher = CardWatcher(terminal, interval: tick)..start();
    final events = <CardEvent>[];
    watcher.events.listen(events.add);

    await settle();
    expect(events, isEmpty);
    expect(watcher.connection, isNull);

    terminal.cardIn = true;
    await settle();
    expect(events.single, isA<CardInserted>());
    expect(watcher.connection, isNotNull);
    expect(terminal.connections, 1,
        reason: 'one connection while the card stays');

    terminal.cardIn = false;
    await settle();
    expect(events.last, isA<CardRemoved>());
    expect(watcher.connection, isNull);
    expect(terminal.disconnections, 1);

    await watcher.dispose();
  });

  test('releases the card when stopped, and reports it again on restart',
      () async {
    final terminal = FakeTerminal()..cardIn = true;
    final watcher = CardWatcher(terminal, interval: tick);
    final events = <CardEvent>[];
    watcher.events.listen(events.add);

    watcher.start();
    await settle();
    await watcher.stop();
    expect(watcher.isWatching, isFalse);
    expect(terminal.disconnections, 1);

    watcher.start();
    await settle();
    expect(events.whereType<CardInserted>(), hasLength(2));

    await watcher.dispose();
  });

  test('probes with a command that changes nothing on the card', () {
    expect(hexString(CardWatcher.presenceProbe), '00CA000001');
    expect(() => CardWatcher.presenceProbe[0] = 0x20, throwsUnsupportedError);
  });

  test('reports an error thrown by the terminal and keeps watching', () async {
    final terminal = FakeTerminal()..connectFailure = StateError('broken');
    final watcher = CardWatcher(terminal, interval: tick)..start();
    final events = <CardEvent>[];
    final errors = <Object>[];
    watcher.events.listen(events.add, onError: (Object e) => errors.add(e));

    await settle();
    expect(errors.single, isA<StateError>());
    expect(watcher.isWatching, isTrue);

    terminal.cardIn = true;
    await settle();
    expect(events.single, isA<CardInserted>());

    await watcher.dispose();
  });

  test('can be disposed while releasing a removed card', () async {
    final terminal = FakeTerminal()..cardIn = true;
    final watcher = CardWatcher(terminal, interval: tick)..start();
    final events = <CardEvent>[];
    watcher.events.listen(events.add);
    await settle();

    final release = terminal.release = Completer<void>();
    terminal.cardIn = false;
    await settle();
    expect(watcher.connection, isNull);
    expect(terminal.disconnections, 0, reason: 'release still pending');

    await watcher.dispose();
    release.complete();
    await settle();
    expect(terminal.disconnections, 1);
    expect(events.single, isA<CardInserted>());
  });

  group('presence probe', () {
    const interval = Duration(milliseconds: 40);

    test('waits while a command is in flight', () async {
      final terminal = FakeTerminal()..cardIn = true;
      final watcher = CardWatcher(terminal, interval: interval)..start();
      final inserted = await watcher.events.first as CardInserted;

      final answer = terminal.answer = Completer<void>();
      final sending = inserted.connection.transmit(Uint8List.fromList([0]));
      final before = terminal.probes;
      await Future<void>.delayed(interval * 4);
      expect(terminal.probes, before);

      terminal.answer = null;
      answer.complete();
      await sending;
      await watcher.dispose();
    });

    test('waits for silence after a command, then resumes', () async {
      final terminal = FakeTerminal()..cardIn = true;
      final watcher = CardWatcher(terminal, interval: interval)..start();
      final events = <CardEvent>[];
      watcher.events.listen(events.add);
      await Future<void>.delayed(interval);
      final connection = watcher.connection!;

      for (var i = 0; i < 8; i++) {
        await connection.transmit(Uint8List.fromList([0]));
        final before = terminal.probes;
        await Future<void>.delayed(interval ~/ 2);
        expect(terminal.probes, before, reason: 'command ${i + 1}');
      }

      final before = terminal.probes;
      await Future<void>.delayed(interval * 4);
      expect(terminal.probes, greaterThan(before));

      terminal.cardIn = false;
      await Future<void>.delayed(interval * 3);
      expect(events.last, isA<CardRemoved>());
      expect(terminal.disconnections, 1);

      await watcher.dispose();
    });

    test('stays out of an exclusive run, pauses included', () async {
      final terminal = FakeTerminal()..cardIn = true;
      final watcher = CardWatcher(terminal, interval: interval)..start();
      final inserted = await watcher.events.first as CardInserted;
      final channel = CardChannel(inserted.connection);

      final before = terminal.probes;
      final result = await channel.exclusive(() async {
        await channel.send(CommandApdu(0, 0xB0, 0, 0, le: 1));
        // Longer than the quiet time, as a key agreement may take.
        await Future<void>.delayed(interval * 4);
        await channel.send(CommandApdu(0, 0xB0, 0, 0, le: 1));
        return 42;
      });
      expect(result, 42);
      expect(terminal.probes, before);

      await Future<void>.delayed(interval * 4);
      expect(terminal.probes, greaterThan(before), reason: 'probes resume');
      await watcher.dispose();
    });

    test('holds a command sent during the probe until the probe ends',
        () async {
      final terminal = FakeTerminal()..cardIn = true;
      final watcher = CardWatcher(terminal, interval: tick)..start();
      final inserted = await watcher.events.first as CardInserted;

      final answer = terminal.answer = Completer<void>();
      while (terminal.probes == 0) {
        await Future<void>.delayed(tick);
      }
      var sent = false;
      final sending = inserted.connection
          .transmit(Uint8List.fromList([0]))
          .then((_) => sent = true);
      await Future<void>.delayed(tick * 2);
      expect(sent, isFalse);

      terminal.answer = null;
      answer.complete();
      await sending;
      expect(sent, isTrue);
      await watcher.dispose();
    });
  });
}
