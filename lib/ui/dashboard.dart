// x7 dashboard — Stark-Varg-inspired shell.
//
// Dark, minimal, big central readouts, ride-mode cards, a row of stat tiles, and a control
// strip. This is a starting point meant to grow with contributions (charts, gauges, config).

import 'package:flutter/material.dart';
import '../model/telemetry.dart';

class Dashboard extends StatelessWidget {
  final Telemetry telemetry;
  final void Function(bool race) onSetMode;
  final void Function(int level) onSetAssist;

  const Dashboard({
    super.key,
    required this.telemetry,
    required this.onSetMode,
    required this.onSetAssist,
  });

  @override
  Widget build(BuildContext context) {
    final bms = telemetry.bms;
    final ctrl = telemetry.ctrl;
    final race = ctrl.mode == 'race';

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // header: connection status
              Row(
                children: [
                  const Text('x7', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  _Dot(label: 'BMS', ok: bms.fresh),
                  const SizedBox(width: 12),
                  _Dot(label: 'X-9000', ok: ctrl.fresh),
                ],
              ),
              const SizedBox(height: 24),

              // hero: SoC + speed
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: _Hero(label: 'SOC', value: _fmt(bms.soc, '%', 0))),
                    Expanded(child: _Hero(label: 'KM/H', value: _speed(ctrl.erpm))),
                  ],
                ),
              ),

              // stat tiles
              const SizedBox(height: 12),
              Row(children: [
                _Tile('POWER', _power(ctrl)),
                _Tile('PACK', _fmt(bms.packV, ' V', 1)),
                _Tile('MOTOR °C', _fmt(ctrl.motorC, '', 0)),
                _Tile('FET °C', _fmt(ctrl.fetC, '', 0)),
              ]),

              // ride-mode cards
              const SizedBox(height: 20),
              Row(children: [
                _ModeCard('STREET', selected: ctrl.mode == 'street', onTap: () => onSetMode(false)),
                const SizedBox(width: 12),
                _ModeCard('RACE', selected: race, onTap: () => onSetMode(true)),
              ]),

              // assist strip
              const SizedBox(height: 16),
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

  static String _fmt(double? v, String unit, int dp) =>
      v == null ? '--' : '${v.toStringAsFixed(dp)}$unit';

  static String _power(CtrlState c) {
    if (c.inputV == null || c.inputA == null) return '--';
    return '${(c.inputV! * c.inputA!).toStringAsFixed(0)} W';
  }

  // erpm -> km/h needs pole pairs + wheel/gearing; left as a stub for calibration.
  static String _speed(int? erpm) => erpm == null ? '--' : '${(erpm.abs() / 1000).round()}';
}

class _Hero extends StatelessWidget {
  final String label, value;
  const _Hero({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(value, style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w800)),
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
            color: selected ? accent.withOpacity(0.15) : const Color(0xFF14181D),
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
    return Row(children: [
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
