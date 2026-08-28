# Setup: what the bike needs for x7 to control it

x7 talks to a **stock** X-9000 out of the box for *reading*, but the control features unlock in
tiers, and the top tier needs a firmware change **and** a hardware change. This page explains each
tier so you know what x7 can and can't do on your bike.

The firmware how-to itself lives in the controller reference —
[svyourmom/x7-vesc](https://github.com/svyourmom/x7-vesc) (`docs/06`, `docs/08`). This page is only
about what x7 requires and why.

## Tier 1 — stock bike, zero changes

Works immediately, fully reversible, nothing to flash:

- Live merged telemetry (BMS + controller) on one screen.
- Read ride **mode** and **gear** — x7 reads both over Bluetooth
  (`GET_VALUES_SELECTIVE`), so the dashboard always shows the real gear/mode even with no mods.
- Adjust what the controller already exposes over its VESC terminal (traction-control strength,
  wheel-lift limiter, etc.).

At this tier the **control** buttons (mode, gear) are inert — the controller only accepts those as
CAN frames from the display, not over Bluetooth.

## Tier 2 — CAN-RX injector firmware (software change)

Flash the small, reversible **CAN-RX injector** patch (x7-vesc `docs/06`). It turns a Bluetooth
packet into a synthetic CAN frame, so x7 can send the frames the handlebar/display normally sends.
Then:

- **Ride mode** (Street/Race) is fully controllable from x7 and **sticks**.
- **Gear** can be sent, **but** while the SW102T display is connected it re-broadcasts the true gear
  every ~20–35 ms and overwrites x7 within a few hundred ms. So at this tier the gear buttons work
  momentarily but the display wins — treat gear as read-only.
- Reverse works (a native motor command; no injector needed).

The injector firmware is **inert unless x7 sends it a frame**, so flashing it changes nothing about
how the bike behaves on its own.

## Tier 3 — injector firmware + display disconnected (software + hardware change)

**Physically disconnect the SW102T display** from the handlebar CAN bus (leave it on a connector so
you can plug it back in). With no display competing:

- **x7 is the sole source of the gear/level frames**, so a gear you set **holds** — the gear buttons
  (R / N / 1 / 2 / 3) become real control.
- The bike drives at whatever gear x7 selects; mode is controlled as in Tier 2.
- The controller runs fine with no display attached (no fault).

This is the **app-as-cockpit** configuration: the phone replaces the handlebar display entirely.
Verified on an X-9000 V3 with the wheel off the ground.

> ⚠️ **The bike boots to level 0, which does NOT drive.** With the display removed, x7 (or a fallback
> — below) must send a gear before the throttle does anything. That is a safe default, but plan for
> it: no phone connected, no gear, no motion.

## The display is your backup — reconnect any time

Because the injector firmware is inert on its own and the display wins the level race whenever it is
present, the two configurations are cleanly exclusive and switch with a connector, no re-flash:

| display | gear/level | mode | if Bluetooth fails |
|---|---|---|---|
| **disconnected** | x7 controls it | x7 controls it | bike stuck at last gear; power-cycle → level 0 (no drive) |
| **reconnected** | display controls it (x7 reads) | x7 or display | display keeps the bike fully rideable |

So the recommended rig is: **injector firmware flashed permanently, display on a pull-off
connector.** Ride app-only day to day; plug the display back in as a hardwired fallback if your
phone dies or BLE drops. If you want the bike drivable with no phone *and* no display, a tiny
always-on CAN node broadcasting a fixed gear is an option (x7-vesc `docs/08`).

## What x7 does when it can't control

x7 degrades gracefully: control buttons that require a tier you don't have simply don't take effect
(the gear won't hold on a stock bike; it will report what it reads). The dashboard's readouts —
telemetry, mode, gear — work at every tier, because they only *read*.

## Safety

- Every control here changes real ride state on a real vehicle. Bench each change with the **wheel
  off the ground** before trusting it on the road.
- Reverse and low gears engage instantly. Level 0 not driving is the one safe default — don't
  defeat it.
- You are modifying a vehicle you own, at your own risk. This voids warranties and can be dangerous.
