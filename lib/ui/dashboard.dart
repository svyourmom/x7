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
  final VoidCallback onReverseStart;
  final VoidCallback onReverseStop;
  final VoidCallback onOpenSettings;

  const Dashboard({
    super.key,
    required this.telemetry,
    required this.settings,
    required this.onSetMode,
    required this.onSetAssist,
    required this.onReverseStart,
    required this.onReverseStop,
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
        const SizedBox(height: 28),
        _heroRow(bms, ctrl),
        const SizedBox(height: 28),
        _tiles(bms, ctrl),
        const Spacer(),
        _modes(ctrl),
        const SizedBox(height: 16),
        _assist(ctrl),
        const SizedBox(height: 12),
        _reverse(ctrl),
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
                    _assist(ctrl),
                    const SizedBox(height: 12),
                    _reverse(ctrl),
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

  Widget _reverse(CtrlState ctrl) {
    return _ReverseButton(
      enabled: ctrl.fresh,
      onStart: onReverseStart,
      onStop: onReverseStop,
    );
  }

  Widget _assist(CtrlState ctrl) {
    final live = ctrl.fresh;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('ASSIST', style: TextStyle(color: Colors.white54, letterSpacing: 2)),
        Row(children: [
          for (final l in [1, 2, 3])
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _AssistButton(
                level: l,
                selected: ctrl.assist == l,
                enabled: live,
                onTap: () => onSetAssist(l),
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

// Momentary hold-to-reverse. Spins only while the pointer is down; releases (coast) on up,
// cancel, or dispose. Colour goes solid red while active.
class _ReverseButton extends StatefulWidget {
  final bool enabled;
  final VoidCallback onStart;
  final VoidCallback onStop;
  const _ReverseButton({required this.enabled, required this.onStart, required this.onStop});
  @override
  State<_ReverseButton> createState() => _ReverseButtonState();
}

class _ReverseButtonState extends State<_ReverseButton> {
  static const _red = Color(0xFFE0483B);
  bool _held = false;

  void _down() {
    if (!widget.enabled || _held) return;
    setState(() => _held = true);
    widget.onStart();
  }

  void _up() {
    if (!_held) return;
    setState(() => _held = false);
    widget.onStop();
  }

  @override
  void dispose() {
    if (_held) widget.onStop(); // never leave reverse engaged if the screen goes away mid-press
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: widget.enabled ? 1 : 0.35,
      child: Listener(
        onPointerDown: (_) => _down(),
        onPointerUp: (_) => _up(),
        onPointerCancel: (_) => _up(),
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _held ? _red : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _red, width: 1.5),
          ),
          child: Text(
            _held ? 'REVERSING…' : 'HOLD TO REVERSE',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: _held ? Colors.white : _red,
            ),
          ),
        ),
      ),
    );
  }
}

class _AssistButton extends StatelessWidget {
  final int level;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  const _AssistButton(
      {required this.level, required this.selected, required this.onTap, this.enabled = true});
  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 52,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? accent : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: selected ? accent : Colors.white24, width: 1.5),
          ),
          child: Text('$level',
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
