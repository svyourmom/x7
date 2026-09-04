# Contributing to x7

x7 is an open dashboard/control center for Talaria-class ebikes (Greenway BMS + EBMX X-9000) over
Bluetooth. It's early — the protocol layers are ported from working reference tools, the UI is a
starting shell. Help is very welcome.

## Getting set up

```bash
flutter pub get
flutter run              # against a real Android device (BLE can't be emulated)
flutter build apk        # release/debug APK to sideload
```

You need a real phone with Bluetooth — an emulator has no BLE radio, so it can't talk to the bike.

## Where things are

- `lib/ble/vesc_protocol.dart` — VESC framing + CRC-16/XMODEM + payload builders (pure Dart, unit-testable).
- `lib/ble/vesc_client.dart` — EBMX X-9000 BLE connection, polling, parsing, control.
- `lib/ble/bms_client.dart` — Greenway BMS client **(stub — port the parser from the BMS reference)**.
- `lib/model/telemetry.dart` — the merged telemetry model the UI renders.
- `lib/launch_assist.dart` — the timed wheel-lift limiter (LAUNCH) state machine, tested with a fake link.
- `lib/ui/dashboard.dart` — the dashboard shell.

## Good first issues (help wanted)

- **BMS parser:** implement `bms_client.dart` from
  [Talaria-Greenway-BMS-Protocol-Reference](https://github.com/svyourmom/Talaria-Greenway-BMS-Protocol-Reference).
- **Scan + connect + auto-reconnect** for both devices (independent per link).
- **Runtime permissions** (Bluetooth/location) via `permission_handler`.
- **Speed calibration:** ERPM → km/h (pole pairs + wheel/gearing).
- **UI:** gauges/charts, cell-voltage bar, temperature trends, kiosk/full-screen mode.
- **Unit tests** for `vesc_protocol.dart` (framing/CRC round-trips are easy wins).

## Ground rules

- **Only interact with hardware you own.** Keep the wheel off the ground when testing controls.
- The baseline app must stay **zero-firmware-modification** — read + already-BLE-reachable features
  only. Anything requiring the optional firmware patch is opt-in and clearly gated.
- Code is **GPLv3**; docs are **CC BY 4.0**. By contributing you agree your contributions are
  licensed the same way.
