# x7 architecture

<!-- Licensed CC BY 4.0 -->

```
  Greenway BMS ──BLE──►  BmsClient  ─┐
                                     ├─►  Telemetry (merged model) ──►  Dashboard (UI)
  EBMX X-9000  ──BLE──►  VescClient ─┘                                      │
        ▲                                                                   │
        └───────────── control (mode / assist / terminal) ◄────────────────┘
```

- **One phone, two simultaneous BLE connections.** Android/iOS centrals handle multiple GATT
  connections; x7 keeps one per device, each with its own connect/reconnect so a single drop can't
  take down the other.
- **VescClient** speaks the VESC packet protocol over the Nordic UART Service (polls `GET_VALUES`,
  runs terminal commands, and — with the optional firmware patch — injects CAN commands for
  mode/assist).
- **BmsClient** parses the Greenway BMS notifications (see the BMS reference).
- **Telemetry** is the single merged object the UI listens to; the protocol/parsing code is pure
  Dart and unit-testable without hardware.

## Layers, bottom-up
1. `vesc_protocol.dart` — framing, CRC, payload builders (no BLE).
2. `vesc_client.dart` / `bms_client.dart` — BLE connection + parsing → model callbacks.
3. `telemetry.dart` — merged state.
4. `ui/` — presentation + controls.

This keeps the risky/finicky part (BLE) thin and swappable, and the testable part (protocol) pure.
