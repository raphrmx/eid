## 0.1.1

- Extended length APDUs, written only when the data or Le need them, and
  `CommandApdu.parse`.
- `readBinary` and `readTransparentFile` go past offset 32767 with READ
  BINARY B1.
- `CardChannel.exclusive` keeps the `CardWatcher` presence probe out of
  commands that must follow one another, such as a secure messaging session.

## 0.1.0

- First release: APDUs, a `CardChannel` that handles T=0, ISO 7816-4 select
  and read, and the `PartialDate` and `Sex` values national cards share.
- `CardWatcher` reports cards going in and out; `AnyCardTerminal` watches
  every terminal at once.
- `onApdu` reports each exchange, the PIN left out.
