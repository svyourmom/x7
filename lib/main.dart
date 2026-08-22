// x7 — app entry point.
//
// Creates the two BLE clients, hands them to the ConnectionManager (discovery + reconnect),
// merges their callbacks into one Telemetry model, and shows the dashboard.

import 'package:flutter/material.dart';

import 'ble/bms_client.dart';
import 'ble/connection_manager.dart';
import 'ble/vesc_client.dart';
import 'model/telemetry.dart';
import 'ui/dashboard.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const X7App());
}

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
          primary: Color(0xFF35E0A1),
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
  late final ConnectionManager _conn;

  @override
  void initState() {
    super.initState();
    _vesc = VescClient(
      onState: (s) => setState(() => _t.ctrl = s),
      onPrint: (line) => debugPrint('X9000: $line'),
    );
    _bms = BmsClient(onState: (s) => setState(() => _t.bms = s));
    _conn = ConnectionManager(vesc: _vesc, bms: _bms, log: (m) => debugPrint('x7/ble: $m'));
    // kick off discovery after first frame so context/permissions UI is ready
    WidgetsBinding.instance.addPostFrameCallback((_) => _conn.start());
  }

  @override
  void dispose() {
    _conn.dispose();
    _vesc.disconnect();
    _bms.disconnect();
    super.dispose();
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
