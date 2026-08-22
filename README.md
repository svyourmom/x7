# x7 — open dashboard & control center for Talaria (Greenway BMS + EBMX X-9000)

**x7** is an open-source **Flutter** app that turns a phone into a live dashboard and control
center for a Talaria-class ebike, by talking **over Bluetooth** to two devices at once:

- the **Greenway BMS** (state of charge, cell voltages, temperatures, current), and
- the **EBMX X-9000** motor controller (speed, power, temps, ride mode, and control).

It's a **repeatable, wire-free, fully reversible mod**: install the app, connect, ride. The baseline
app changes **nothing** on the bike — it only reads and uses features that are already reachable
over Bluetooth. (Ride-mode control is an optional advanced feature; see below.)

> Early stage / work in progress. The protocol layers are ported from working reference
> implementations; the UI is a starting point meant to grow with contributions. See
> [CONTRIBUTING.md](CONTRIBUTING.md).

## Companion references

x7 is built on two open protocol references — read these to understand what the app is talking to:

- **[svyourmom/x7-vesc](https://github.com/svyourmom/x7-vesc)** — EBMX X-9000 BLE / CAN / firmware
  reverse-engineering reference (the controller side).
- **[svyourmom/Talaria-Greenway-BMS-Protocol-Reference](https://github.com/svyourmom/Talaria-Greenway-BMS-Protocol-Reference)**
  — the battery/BMS side.

## What it does (and doesn't need a firmware change)

**Baseline — zero firmware modification, fully reversible:**
- Live merged telemetry from BMS + controller on one screen.
- Read/adjust what's already exposed over the controller's VESC terminal (traction-control
  strength, wheel-lift limiter, etc.).

**Optional advanced — ride-mode / assist control:**
- The controller only accepts mode/assist as CAN frames from the handlebar. A small, reversible
  firmware patch (documented in **x7-vesc**) makes those commands reachable over Bluetooth; x7 will
  drive them when present. This is opt-in and not required for the dashboard.

## Tech

- **Flutter** (Android first; iOS later from the same codebase).
- BLE via `flutter_blue_plus` — **two simultaneous connections** (BMS + controller).
- VESC packet protocol (framing + CRC-16/XMODEM), ported from the reference tools.

## Status & roadmap

Very early. Working toward: solid dual-BLE connect/reconnect, live telemetry, a clean
Stark-Varg-inspired dashboard, and mode/assist controls. Good first issues will be tagged as the
skeleton lands. Not affiliated with EBMX, VESC, Greenway, Talaria, or Stark.

## License

- **Code:** GPLv3 (see [LICENSE](LICENSE)) — aligns with VESC and keeps the mod ecosystem open.
- **Docs** (`docs/`): CC BY 4.0.

## Safety

Interacting with a motor controller can be dangerous and can damage hardware. Use at your own risk,
on hardware you own, wheel off the ground when testing. This project is provided **as-is, without
warranty**.
