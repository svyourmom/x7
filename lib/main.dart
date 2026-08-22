// x7 — app entry point.
//
// Wires up the two BLE clients (controller + BMS) into one merged telemetry model and
// shows the dashboard. Scanning/permission flow is intentionally minimal here — the focus
// of this skeleton is the data path and the UI shell. See CONTRIBUTING.md.

import 'package:flutter/material.dart';

import 'ble/bms_client.dart';
import 'ble/vesc_client.dart';
import 'model/telemetry.dart';
import 'ui/dashboard.dart';

void main() => runApp(const X7App());

class X7App extends StatelessWidget {
  const X7App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'x7',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0D10),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF35E0A1), // accent
          surface: Color(0xFF14181D),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final Telemetry _t = Telemetry();
  late final VescClient _vesc;
  late final BmsClient _bms;

  @override
  void initState() {
    super.initState();
    _vesc = VescClient(
      onState: (s) => setState(() => _t.ctrl = s),
      onPrint: (line) => debugPrint('X9000: $line'),
    );
    _bms = BmsClient(onState: (s) => setState(() => _t.bms = s));
    // TODO(contributor): scan + connect flow (permissions, device pick, auto-reconnect).
  }

  @override
  Widget build(BuildContext context) {
    return Dashboard(
      telemetry: _t,
      onSetMode: (race) => _vesc.setMode(race: race),
      onSetAssist: (level) => _vesc.setAssist(level),
    );
  }
}
