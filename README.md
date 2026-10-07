# eid

[![Video tour](https://img.shields.io/badge/Video-Guided_tour-c4302b?logo=youtube&logoColor=white)](https://www.youtube.com/watch?v=oH_-1EU7DNc)
[![Pub Version](https://img.shields.io/pub/v/eid?color=0175C2)](https://pub.dev/packages/eid)
[![Build](https://img.shields.io/github/actions/workflow/status/raphrmx/eid/ci.yml?branch=main&label=build)](https://github.com/raphrmx/eid/actions/workflows/ci.yml)
![Maintainer](https://img.shields.io/badge/Maintainer-Raphael_Vrient-733d90)
[![Licence](https://img.shields.io/badge/Licence-MIT-8C6A3F)](LICENSE)
![Platforms](https://img.shields.io/badge/Platforms-Android,_iOS,_macOS,_Windows,_Linux,_Web-22375C.svg)
[![Donate with PayPal](https://img.shields.io/badge/Donate-PayPal-00457C?logo=paypal&logoColor=white)](https://www.paypal.com/donate/?hosted_button_id=ZN6D382YQAV5N)

The common ground of electronic identity cards, in pure Dart: commands, file
reading, card insertion and the values national cards share. Document
packages such as `eid_belgium` and `eid_icao` read the cards themselves.

## Install

```yaml
dependencies:
  eid: ^0.1.0
```

## Transports

A `CardTransport` carries bytes to a card. Adapters:

| | |
| --- | --- |
| [eid_ccid](https://pub.dev/packages/eid_ccid) | A USB or PC/SC card reader |
| [eid_nfc](https://pub.dev/packages/eid_nfc) | The NFC of an Android phone or an iPhone |

Any other is one method:

```dart
final class MyTransport implements CardTransport {
  @override
  Future<Uint8List> transmit(Uint8List command) async {
    // Return the response, status bytes included.
  }
}
```

## Read a file

```dart
final channel = CardChannel(transport, onApdu: print);
await channel.selectPath([0x3F00, 0xDF01, 0x4031]);
final file = await channel.readTransparentFile();
```

A refused command throws a `CardException`, an unreachable card a
`CardTransportException`. `onApdu` never sees a PIN. Commands longer than
255 bytes, or expecting more than 256 back, go in extended length; files
larger than 32 KB are read with READ BINARY B1.

## Cards going in and out

```dart
final watcher = CardWatcher(AnyCardTerminal(listTerminals))..start();
watcher.events.listen((event) {
  switch (event) {
    case CardInserted inserted:
      read(inserted.connection);
    case CardRemoved _:
      clear();
  }
});
```

`AnyCardTerminal` watches every terminal, those plugged in later included.

The watcher checks the card is still there with a harmless command, sent
when the card is idle. Commands that must follow one another, such as a
secure messaging session, go in `exclusive`:

```dart
await channel.exclusive(() async {
  // No probe reaches the card until this ends.
});
```

## Shared values

`PartialDate` is a birth date whose day or month may be unknown, with
`ageOn` and `minimumAgeOn`. `Sex` holds the three values of ICAO 9303.

## Documents

![Which packages for which document: a Belgian card in a USB reader takes eid_belgium and eid_ccid and needs no key; a passport or an EU identity card takes eid_icao, with eid_nfc on a phone or eid_ccid on a contactless USB reader, and needs the CAN or the MRZ](https://public.comapps.be/packages/eid/eid_situations.svg)

| | |
| --- | --- |
| [eid_belgium](https://pub.dev/packages/eid_belgium) | The Belgian eID, Kids ID and residence cards |
| [eid_icao](https://pub.dev/packages/eid_icao) | Passports and identity cards with an ICAO 9303 chip |

## License

Released under the [MIT licence](https://pub.dev/packages/eid/license).

## More from COMAPPS

Every package COMAPPS publishes is listed at
[packages.comapps.be](https://packages.comapps.be).
