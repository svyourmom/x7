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
  final void Function(int level) onSetAssist;
  final VoidCallback onOpenSettings;

  const Dashboard({
    super.key,
    required this.telemetry,
    required this.settings,
    required this.onSetMode,
    required this.onSetAssist,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final bms = telemetry.bms;
    final ctrl = telemetry.ctrl;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // header: title · connection · settings
              Row(
                children: [
                  const Text('x7', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  _Dot(label: 'BMS', ok: bms.fresh),
                  const SizedBox(width: 12),
                  _Dot(label: 'X-9000', ok: ctrl.fresh),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.settings, color: Colors.white54),
                    onPressed: onOpenSettings,
                    tooltip: 'Settings',
                  ),
                ],
              ),

              const SizedBox(height: 28),
              // hero: SOC + speed
              Row(
                children: [
                  Expanded(child: _Hero(label: 'SOC', value: _pct(bms.soc))),
                  Expanded(child: _Hero(label: settings.speedUnit, value: _speed(ctrl.erpm))),
                ],
              ),

              const SizedBox(height: 28),
              // stat tiles
              Row(children: [
                _Tile('POWER', _power(ctrl)),
                _Tile('PACK', _fmt(bms.packV, ' V', 1)),
                _Tile('MOTOR ${settings.tempUnit}', settings.temp(ctrl.motorC)),
                _Tile('FET ${settings.tempUnit}', settings.temp(ctrl.fetC)),
              ]),

              const Spacer(),
              // ride-mode cards
              Row(children: [
                _ModeCard('STREET', selected: ctrl.mode == 'street', onTap: () => onSetMode(false)),
                const SizedBox(width: 12),
                _ModeCard('RACE', selected: ctrl.mode == 'race', onTap: () => onSetMode(true)),
              ]),

              const SizedBox(height: 16),
              // assist strip
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('ASSIST', style: TextStyle(color: Colors.white54, letterSpacing: 2)),
                  Row(children: [
                    for (final l in [1, 2, 3])
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: OutlinedButton(onPressed: () => onSetAssist(l), child: Text('$l')),
                      ),
                  ]),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _pct(double? v) => v == null ? '--' : '${v.round()}%';
  static String _fmt(double? v, String unit, int dp) =>
      v == null ? '--' : '${v.toStringAsFixed(dp)}$unit';

  String _power(CtrlState c) {
    if (c.inputV == null || c.inputA == null) return '--';
    return '${(c.inputV! * c.inputA!).toStringAsFixed(0)} W';
  }

  // erpm -> speed needs pole pairs + wheel/gearing (calibration TODO). Placeholder in the
  // chosen unit; shows 0 when parked.
  String _speed(int? erpm) {
    if (erpm == null) return '--';
    final kmh = erpm.abs() / 1000.0; // uncalibrated stub
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
  final VoidCallback onTap;
  const _ModeCard(this.label, {required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
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
