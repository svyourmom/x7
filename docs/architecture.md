# x7 architecture

<!-- Licensed CC BY 4.0 -->

```
  Greenway BMS ──BLE──►  BmsClient  ─┐
                                     ├─►  Telemetry (merged model) ──►  Dashboard (UI)
  EBMX X-9000  ──BLE──►  VescClient ─┘              │                       │
        ▲                                           ▼                       │
        │                                     LaunchAssist ◄────────────────┤
        │                                    (timed limiter)                │
        └───────────── control (mode / gear / limiter / terminal) ◄─────────┘
```

- **One phone, two simultaneous BLE connections.** Android/iOS centrals handle multiple GATT
  connections; x7 keeps one per device, each with its own connect/reconnect so a single drop can't
  take down the other.
- **VescClient** speaks the VESC packet protocol over the Nordic UART Service (polls `GET_VALUES`,
  the selective mode/gear/speed reads and the `vwheelie_diag` limiter status; runs terminal
  commands; and — with the optional firmware patch — injects CAN commands for mode/gear). Frame
  writes are queued so two frames' 20-byte chunks never interleave.
- **LaunchAssist** is control policy, not transport: the arm → roll → countdown → restore state
  machine for the wheel-lift limiter. It reads motion and confirmations from `CtrlState` and sends
  through a tiny `LimiterPort` interface, so it is unit-tested with a fake link and fake time.
- **BmsClient** parses the Greenway BMS notifications (see the BMS reference).
- **Telemetry** is the single merged object the UI listens to; the protocol/parsing code is pure
  Dart and unit-testable without hardware.

## Layers, bottom-up
1. `vesc_protocol.dart` — framing, CRC, payload builders (no BLE).
2. `vesc_client.dart` / `bms_client.dart` — BLE connection + parsing → model callbacks.
3. `telemetry.dart` — merged state.
4. `launch_assist.dart` — control policy on top of the merged state.
5. `ui/` — presentation + controls.

This keeps the risky/finicky part (BLE) thin and swappable, and the testable part (protocol) pure.
