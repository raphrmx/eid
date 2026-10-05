## 0.1.0

- First release: APDUs, a `CardChannel` that handles T=0, ISO 7816-4 select
  and read, and the `PartialDate` and `Sex` values national cards share.
- `CardWatcher` reports cards going in and out; `AnyCardTerminal` watches
  every terminal at once.
- `onApdu` reports each exchange, the PIN left out.
