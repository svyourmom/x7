// x7 dashboard — Stark-Varg-inspired shell.
//
// Dark, minimal, big central readouts, ride-mode cards, a row of stat tiles, and a control
// strip (wheel-lift limiter + launch assist, then gear). Units follow Settings
// (metric/imperial). Layout is anchored top + bottom with a flexible gap so it reads well
// in portrait.

import 'package:flutter/material.dart';
import '../launch_assist.dart';
import '../model/telemetry.dart';
import '../settings.dart';

// amber = "temporary": the launch assist states
const Color _amber = Color(0xFFF5B942);

class Dashboard extends StatelessWidget {
  final Telemetry telemetry;
  final Settings settings;
  final void Function(bool race) onSetMode;
  final void Function(int level) onSetGear; // 0xFF=R, 0=N, 1..3 gears (0x5E4EB0)
  final LaunchAssist launch;
  final VoidCallback onLaunchTap;
  final VoidCallback onToggleLimiter;
  final VoidCallback onOpenSettings;

  const Dashboard({
    super.key,
    required this.telemetry,
    required this.settings,
    required this.onSetMode,
    required this.onSetGear,
    required this.launch,
    required this.onLaunchTap,
    required this.onToggleLimiter,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: OrientationBuilder(
            builder: (context, orientation) => orientation == Orientation.landscape
                ? _landscape(context)
                : _portrait(context),
          ),
        ),
      ),
    );
  }

  // Portrait: content anchored top, controls anchored bottom, flexible gap between.
  Widget _portrait(BuildContext context) {
    final bms = telemetry.bms;
    final ctrl = telemetry.ctrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(),
        const Spacer(),
        _heroRow(bms, ctrl),
        const SizedBox(height: 28),
        _tiles(bms, ctrl),
        const Spacer(),
        _modes(ctrl),
        const SizedBox(height: 12),
        _assist(ctrl, compact: false),
        const SizedBox(height: 12),
        _gear(ctrl),
      ],
    );
  }

  // Landscape (handlebar mount): readouts on the left, ride controls on the right, so the
  // short height never overflows.
  Widget _landscape(BuildContext context) {
    final bms = telemetry.bms;
    final ctrl = telemetry.ctrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(),
        const SizedBox(height: 8),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _heroRow(bms, ctrl),
                    const SizedBox(height: 20),
                    _tiles(bms, ctrl),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                flex: 2,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _modes(ctrl),
                    const SizedBox(height: 10),
                    _assist(ctrl, compact: true),
                    const SizedBox(height: 10),
                    _gear(ctrl),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // header: title · connection · settings
  Widget _header() {
    return Row(
      children: [
        const Text('x7', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const Spacer(),
        _Dot(label: 'BMS', ok: telemetry.bms.fresh),
        const SizedBox(width: 12),
        _Dot(label: 'X-9000', ok: telemetry.ctrl.fresh),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.settings, color: Colors.white54),
          onPressed: onOpenSettings,
          tooltip: 'Settings',
        ),
      ],
    );
  }

  Widget _heroRow(BmsState bms, CtrlState ctrl) {
    return Row(
      children: [
        Expanded(child: _Hero(label: 'SOC', value: _pct(bms.soc))),
        Expanded(child: _Hero(label: settings.speedUnit, value: _speed(ctrl.speedMs))),
      ],
    );
  }

  Widget _tiles(BmsState bms, CtrlState ctrl) {
    return Row(children: [
      _Tile('POWER', _power(ctrl)),
      _Tile('PACK', _fmt(bms.packV, ' V', 1)),
      _Tile('MOTOR ${settings.tempUnit}', settings.temp(ctrl.motorC)),
      _Tile('FET ${settings.tempUnit}', settings.temp(ctrl.fetC)),
    ]);
  }

  Widget _modes(CtrlState ctrl) {
    final live = ctrl.fresh; // only actionable when the controller is connected
    return Row(children: [
      _ModeCard('STREET', selected: ctrl.mode == 'street', enabled: live, onTap: () => onSetMode(false)),
      const SizedBox(width: 12),
      _ModeCard('RACE', selected: ctrl.mode == 'race', enabled: live, onTap: () => onSetMode(true)),
    ]);
  }

  // Wheel-lift limiter controls. WHEELIE = plain on/off, shown from the state read back
  // over the terminal. LAUNCH = on for one launch, then restored (see launch_assist.dart).
  // Stock firmware, no patch needed.
  Widget _assist(CtrlState ctrl, {required bool compact}) {
    final live = ctrl.fresh;
    final phase = launch.phase;
    final busy = phase != LaunchPhase.idle;
    final on = ctrl.limiterOn;

    // WHEELIE: needs a live link and a known state; hands off while a launch runs
    final wheelieEnabled = live && on != null && !busy;

    // LAUNCH: never lock the rider out of cancelling
    final launchEnabled = (live && !launch.redundant) || busy;
    String title, sub;
    Color? fill, border, fg;
    double? progress;
    switch (phase) {
      case LaunchPhase.idle:
        title = 'LAUNCH';
        sub = launch.redundant
            ? 'ALREADY ON'
            : (compact ? 'TAP TO ARM' : 'TAP TO ARM · ${settings.launchWindowS} s');
      case LaunchPhase.arming:
        title = 'ARMING…';
        sub = compact ? 'WAITING' : 'WAITING FOR CONTROLLER';
      case LaunchPhase.armed:
        title = 'ARMED';
        sub = compact ? 'ROLL TO START' : 'ROLL TO START · ${launch.windowS} s';
        border = _amber;
        fg = _amber;
        fill = _amber.withValues(alpha: 0.16);
      case LaunchPhase.active:
        final left = launch.secondsLeft ?? 0;
        title = '$left s';
        sub = 'LIMITER ON';
        border = _amber;
        fill = _amber;
        fg = const Color(0xFF0B0D10);
        progress = launch.windowS == 0 ? 0 : left / launch.windowS;
      case LaunchPhase.restoring:
        title = 'RESTORING…';
        sub = compact ? 'RESTORING' : 'PUTTING LIMITER BACK';
    }

    return Row(children: [
      _AssistButton(
        title: 'WHEELIE',
        subtitle: on == null ? 'READING…' : (compact ? (on ? 'ON' : 'OFF') : (on ? 'LIMITER ON' : 'LIMITER OFF')),
        enabled: wheelieEnabled,
        compact: compact,
        selected: on == true,
        onTap: onToggleLimiter,
      ),
      const SizedBox(width: 12),
      _AssistButton(
        title: title,
        subtitle: sub,
        enabled: launchEnabled,
        compact: compact,
        bigTitle: phase == LaunchPhase.active,
        fill: fill,
        border: border,
        fg: fg,
        progress: progress,
        onTap: onLaunchTap,
      ),
    ]);
  }

  // Gear/level selector (0x5E4EB0). Shows the live gear read back on selective bit 25.
  // Setting a gear needs the CAN-RX injector; it holds only with the display disconnected.
  Widget _gear(CtrlState ctrl) {
    final live = ctrl.fresh;
    // (label, level byte). R=reverse(0xFF), N=neutral(0), 1..3 gears.
    const items = [('R', 0xFF), ('N', 0), ('1', 1), ('2', 2), ('3', 3)];
    // map the read-back gear char to the label we highlight
    final cur = ctrl.gear; // 'R','N','1','2','3' or null
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('GEAR', style: TextStyle(color: Colors.white54, letterSpacing: 2)),
        Row(children: [
          for (final it in items)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _GearButton(
                label: it.$1,
                selected: cur == it.$1,
                enabled: live,
                onTap: () => onSetGear(it.$2),
              ),
            ),
        ]),
      ],
    );
  }

  static String _pct(double? v) => v == null ? '--' : '${v.round()}%';
  static String _fmt(double? v, String unit, int dp) =>
      v == null ? '--' : '${v.toStringAsFixed(dp)}$unit';

  String _power(CtrlState c) {
    if (c.inputV == null || c.inputA == null) return '--';
    return '${(c.inputV! * c.inputA!).toStringAsFixed(0)} W';
  }

  // Firmware-computed road speed: GET_VALUES_SETUP bit 6 gives m/s (the same value the
  // controller shows on the display), derived from the mcconf pole pairs / wheel / gearing.
  // Early on-bike testing looked correct; not yet verified against GPS across the range.
  // If it ever reads wrong, fall back to computing from the mcconf si_ constants.
  String _speed(double? speedMs) {
    if (speedMs == null) return '--';
    final kmh = speedMs.abs() * 3.6;
    return '${settings.speed(kmh)!.round()}';
  }
}

class _Hero extends StatelessWidget {
  final String label, value;
  const _Hero({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: const TextStyle(fontSize: 60, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.white38, letterSpacing: 3)),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final String label, value;
  const _Tile(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF14181D),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(children: [
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.white38)),
        ]),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  const _ModeCard(this.label, {required this.selected, required this.onTap, this.enabled = true});
  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Expanded(
      child: Opacity(
        opacity: enabled ? 1 : 0.35,
        child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.15) : const Color(0xFF14181D),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? accent : Colors.white12, width: 1.5),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: selected ? accent : Colors.white70,
                  letterSpacing: 2)),
        ),
      ),
      ),
    );
  }
}

/// Card-style button with a title and a small caption. Used for the WHEELIE / LAUNCH pair.
class _AssistButton extends StatelessWidget {
  final String title, subtitle;
  final bool enabled, compact, selected, bigTitle;
  final Color? fill, border, fg; // override colours (launch states); null = default look
  final double? progress; // 0..1 bar along the bottom, or null
  final VoidCallback onTap;
  const _AssistButton({
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.compact,
    required this.onTap,
    this.selected = false,
    this.bigTitle = false,
    this.fill,
    this.border,
    this.fg,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final bg = fill ?? (selected ? accent.withValues(alpha: 0.15) : const Color(0xFF14181D));
    final edge = border ?? (selected ? accent : Colors.white12);
    final text = fg ?? (selected ? accent : Colors.white70);
    final subText = fg != null ? fg!.withValues(alpha: 0.75) : (selected ? accent.withValues(alpha: 0.8) : Colors.white38);
    return Expanded(
      child: Opacity(
        opacity: enabled ? 1 : 0.35,
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: compact ? 44 : 54,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: edge, width: 1.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(children: [
              Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(title,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.fade,
                      style: TextStyle(
                          fontSize: bigTitle ? (compact ? 18 : 22) : (compact ? 13 : 15),
                          fontWeight: FontWeight.w700,
                          color: text,
                          letterSpacing: bigTitle ? 0.5 : 2)),
                  if (!compact || !bigTitle)
                    Text(subtitle,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.fade,
                        style: TextStyle(fontSize: 9, color: subText, letterSpacing: 1)),
                ]),
              ),
              if (progress != null)
                Align(
                  alignment: Alignment.bottomLeft,
                  child: FractionallySizedBox(
                    widthFactor: progress!.clamp(0.0, 1.0),
                    child: Container(height: 4, color: const Color(0x8C0B0D10)),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _GearButton extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  const _GearButton(
      {required this.label, required this.selected, required this.onTap, this.enabled = true});
  @override
  Widget build(BuildContext context) {
    final isRev = label == 'R';
    final accent = isRev ? const Color(0xFFE0574B) : Theme.of(context).colorScheme.primary;
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 46,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? accent : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: selected ? accent : Colors.white24, width: 1.5),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: selected ? const Color(0xFF0B0D10) : accent)),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final String label;
  final bool ok;
  const _Dot({required this.label, required this.ok});
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
            color: ok ? const Color(0xFF35E0A1) : Colors.white24, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontSize: 12, color: Colors.white54)),
    ]);
  }
}
