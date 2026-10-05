import 'dart:typed_data';

import 'package:eid/eid.dart';
import 'package:test/test.dart';

final class _Slot implements CardTerminal {
  _Slot(this.name);

  @override
  final String name;

  bool cardIn = false;

  @override
  Future<CardConnection> connect() async {
    if (!cardIn) throw CardTransportException('No card in $name');
    return _Connection(this);
  }
}

final class _BrokenSlot implements CardTerminal {
  @override
  String get name => 'Broken';

  @override
  Future<CardConnection> connect() async =>
      throw const FormatException('bad reader');
}

final class _Connection implements CardConnection {
  _Connection(this.slot);

  final _Slot slot;

  @override
  Future<Uint8List> transmit(Uint8List command) async {
    if (!slot.cardIn) throw const CardTransportException('Card removed');
    return Uint8List.fromList([0x90, 0x00]);
  }

  @override
  Future<void> disconnect() async {}
}

void main() {
  test('connects to the terminal that holds a card', () async {
    final first = _Slot('First');
    final second = _Slot('Second')..cardIn = true;
    final any = AnyCardTerminal(() async => [first, second]);

    final connection = await any.connect();
    expect((connection as _Connection).slot, same(second));
    expect(any.current, same(second));
    expect(any.terminals, [first, second]);
  });

  test('finds a terminal plugged in later', () async {
    final slots = <_Slot>[];
    final any = AnyCardTerminal(() async => slots);
    await expectLater(
      any.connect(),
      throwsA(isA<CardTransportException>()
          .having((e) => e.message, 'message', 'No terminal')),
    );

    slots.add(_Slot('Plugged in')..cardIn = true);
    await any.connect();
    expect(any.current?.name, 'Plugged in');
  });

  test('forgets the current terminal once the card is gone', () async {
    final slot = _Slot('Only')..cardIn = true;
    final any = AnyCardTerminal(() async => [slot]);
    await any.connect();
    expect(any.current, same(slot));

    slot.cardIn = false;
    await expectLater(any.connect(), throwsA(isA<CardTransportException>()));
    expect(any.current, isNull);
  });

  test('skips a terminal that fails', () async {
    final slot = _Slot('Working')..cardIn = true;
    final any = AnyCardTerminal(() async => [_BrokenSlot(), slot]);
    await any.connect();
    expect(any.current, same(slot));
  });

  test('reports the first failure when every terminal fails', () async {
    final any = AnyCardTerminal(() async => [_BrokenSlot(), _BrokenSlot()]);
    await expectLater(
      any.connect(),
      throwsA(isA<CardTransportException>()
          .having((e) => e.cause, 'cause', isA<FormatException>())),
    );
    expect(any.current, isNull);

    final mixed = AnyCardTerminal(() async => [_BrokenSlot(), _Slot('Empty')]);
    await expectLater(
      mixed.connect(),
      throwsA(isA<CardTransportException>()
          .having((e) => e.message, 'message', 'No card in any terminal')),
    );
  });

  test('reports a terminal list it cannot get as no card', () async {
    final failing = AnyCardTerminal(
      () async => throw const FormatException('bad list'),
    );
    await expectLater(
      failing.connect(),
      throwsA(isA<CardTransportException>()),
    );
  });

  test('lets a watcher follow cards across terminals', () async {
    final first = _Slot('First');
    final second = _Slot('Second');
    final watcher = CardWatcher(
      AnyCardTerminal(() async => [first, second]),
      interval: const Duration(milliseconds: 5),
    );
    final events = <CardEvent>[];
    watcher.events.listen(events.add);
    watcher.start();

    second.cardIn = true;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    second.cardIn = false;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    first.cardIn = true;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await watcher.dispose();

    expect(events.map((e) => e.runtimeType), [
      CardInserted,
      CardRemoved,
      CardInserted,
    ]);
  });
}
