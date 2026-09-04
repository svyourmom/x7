# Wheel-lift control: WHEELIE and LAUNCH

<!-- Licensed CC BY 4.0 -->

The X-9000 has a built-in **wheel-lift limiter**. It watches the bike's pitch with the on-board IMU
and, when the front rises past a start angle, caps motor speed to bring it back down. From the
factory it is **off**, and it can only be switched from the controller's terminal. x7 puts that
switch on the dashboard in two forms, side by side between the ride-mode cards and the gear row.

| button | what it does | how long it lasts |
|---|---|---|
| **WHEELIE** | Turns the limiter on or off. The button shows the live state read back from the controller. | Until you tap it again or the bike is power-cycled. |
| **LAUNCH** | Arms the limiter for one launch. The window starts when the wheel begins to turn, runs for the set number of seconds, then restores whatever state the limiter was in before you tapped. | One launch. Armed waits indefinitely; the window is 2–15 s. |

> **Works on a stock bike.** These buttons use commands the controller already accepts over
> Bluetooth. No injector firmware, no display change. This is a Tier 1 feature (see
> [setup-hardware-software.md](setup-hardware-software.md)).

## Operational configurations

The limiter has one state on the controller: on or off, plus a start angle. The two buttons are
just different ways of driving it. Every combination you can be in and what the bike does:

| you | limiter | what the bike does | how it ends |
|---|---|---|---|
| Nothing tapped | OFF | Stock. Front wheel lifts as much as the throttle allows. | — |
| WHEELIE on | ON | Limiter active for the whole ride, at the controller's current start angle (factory 20°). | Tap WHEELIE again, or power-cycle the bike. |
| LAUNCH armed, stopped | ON, waiting | Limiter on. Clock has not started. Sit at the line as long as you like. | Roll to start the window, or tap LAUNCH to cancel. |
| LAUNCH window running | ON, N s | Limiter on while the countdown runs. Front stays down through the hard part of the launch. | At zero, limiter goes back to how it was (off, unless WHEELIE was on). |
| LAUNCH with lower start angle | ON, e.g. 12° | Same as above, but the limiter steps in earlier (Settings › Launch assist › Start angle). Firmer hold-down for the window only. | Angle is restored to its previous value with the on/off state. |
| WHEELIE on, then LAUNCH | ON | Nothing extra: LAUNCH is greyed out ("ALREADY ON"). If a lower start angle is set, LAUNCH is available and only changes the angle for the window. | WHEELIE stays on after the window. |

## Button states

- **Outlined** — off / idle. Tap to act. Faded when the controller is not connected or the
  limiter state has not been read yet.
- **Green** — WHEELIE on. Same green as the selected ride mode and gear.
- **Amber outline, "ARMED"** — LAUNCH armed. Limiter on, clock waiting for the wheel to turn.
- **Amber filled, "3 s"** — LAUNCH window running. Seconds left plus a shrinking bar.
- WHEELIE is greyed out while a launch is in progress so the two can't fight.

## Settings

| setting | default | range | notes |
|---|---|---|---|
| Launch window | 5 s | 2–15 s | Read at the moment you arm. Changing it mid-launch does not affect the current window. |
| Lower start angle | off | on / off | Off means LAUNCH uses whatever angle the controller has now. |
| Start angle | 12° | 5–30° | Only shown when the switch above is on. Lower = limiter steps in sooner. |

## What happens if…

| situation | result |
|---|---|
| Controller not connected | Both buttons are faded and do nothing. |
| x7 has not read the limiter state yet | LAUNCH refuses to arm and says so. It never turns the limiter on without knowing how to put it back. The state is polled about once a second, so this clears quickly. |
| The controller does not confirm "on" within 2 s | Arming is abandoned, `off` is sent back, and a toast says there was no confirmation. |
| Bluetooth drops mid-window | The window ends on the phone, but the app can't send `off`. The limiter stays **on** until reconnect or power cycle. The toast tells you. Staying on is the low-power, safe side. |
| App goes to background while armed | Launch is cancelled and the limiter restored. |
| App goes to background while the window runs | The window runs out on its own and restores. If the phone kills the app first, the limiter stays on until power cycle. |
| You push the bike while armed | The wheel turning starts the window. Cancel and re-arm if that wasn't intended. |
| Bike power-cycled | Everything reverts to factory: limiter off, start angle 20°. WHEELIE shows OFF once reconnected. |

## Under the hood

x7 sends the controller's own terminal commands over Bluetooth (`COMM_TERMINAL_CMD`) and parses
the printed replies (`COMM_PRINT`). Syntax and reply formats are documented in
[x7-vesc docs/04-terminal-commands.md](https://github.com/svyourmom/x7-vesc/blob/main/docs/04-terminal-commands.md).

```
vwheelie_diag            # read: running=1  enabled=0  active=0 / start=20.00 end=43.00
vwheelie_diag on         # WHEELIE on, or LAUNCH arm      -> "vwheelie: ENABLED"
vwheelie_diag start 12   # LAUNCH with lower start angle  -> "vwheelie start -> 12.00 deg"
vwheelie_diag off        # WHEELIE off, or LAUNCH restore -> "vwheelie: DISABLED"
```

- `VescClient` polls the read command about once a second and parses every printed line into
  `CtrlState.limiterOn / limiterRunning / limiterStart`, the same way gear and mode are read back.
  The on/off and start-angle confirmations are parsed the same way, so a command is confirmed
  within a poll cycle at most.
- `LaunchAssist` (`lib/launch_assist.dart`) is the state machine:
  `idle → arming → armed → (wheel turns) → active N s → restoring → idle`. Motion is motor speed
  above 500 ERPM or road speed above 0.5 m/s. It restores the printed start-angle text verbatim
  (e.g. `20.00`) so nothing is rounded.
- The limiter's on/off flag and angles live in the controller's RAM only. Nothing here is written
  to flash.

## Safety

- Enabling the limiter changes how the bike behaves under power. Bench every setting with the
  **wheel off the ground** first.
- The limiter needs the IMU horizon to be sane; if the bike booted on a steep slope the start
  angle will be off (`BMI270_ResetHorizon` in x7-vesc docs/04).
- The ERPM threshold and the default start angle are first guesses, not measured values. Tune
  them to your bike.
- You are modifying a vehicle you own, at your own risk.
