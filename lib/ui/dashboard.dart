// x7 dashboard — Stark-Varg-inspired shell.
//
// Dark, minimal, big central readouts, ride-mode cards, a row of stat tiles, and a control
// strip. Units follow Settings (metric/imperial). Layout is anchored top + bottom with a
// flexible gap so it reads well in portrait.

import 'package:flutter/material.dart';
import '../model/telemetry.dart';
import '../settings.dart';

class Dashboard extends StatelessWidget {
  final Telemetry telemetry;
  final Settings settings;
  final void Function(bool race) onSetMode;
  final void Function(int level) onSetGear; // 0xFF=R, 0=N, 1..3 gears (0x5E4EB0)
  final VoidCallback onOpenSettings;

  const Dashboard({
    super.key,
    required this.telemetry,
    required this.settings,
    required this.onSetMode,
    required this.onSetGear,
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
        const SizedBox(height: 16),
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
                    const SizedBox(height: 16),
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
        Expanded(child: _Hero(label: settings.speedUnit, value: _speed(ctrl.erpm))),
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

  // KNOWN ISSUE: the speed readout is UNCALIBRATED and reads incorrectly.
  // erpm -> road speed needs the motor pole pairs, wheel diameter, and gearing ratio;
  // the divisor below is a placeholder, not a real conversion. Everything else on the
  // dashboard is verified against the bike. Calibration is the next task — until then
  // treat MPH/KM-H as a non-representative stub (0 when parked is still correct).
  String _speed(int? erpm) {
    if (erpm == null) return '--';
    final kmh = erpm.abs() / 1000.0; // TODO(calibration): placeholder divisor — value is wrong
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
