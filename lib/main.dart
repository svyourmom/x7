// x7 — app entry point.
//
// Loads settings, applies the keep-screen-on preference, creates the two BLE clients + the
// ConnectionManager (discovery/reconnect honouring device selection), merges telemetry, and
// shows the dashboard with a route to Settings.

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'ble/bms_client.dart';
import 'ble/connection_manager.dart';
import 'ble/vesc_client.dart';
import 'model/telemetry.dart';
import 'settings.dart';
import 'ui/dashboard.dart';
import 'ui/settings_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = Settings();
  await settings.load();
  runApp(X7App(settings: settings));
}

class X7App extends StatelessWidget {
  final Settings settings;
  const X7App({super.key, required this.settings});

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
      home: HomePage(settings: settings),
    );
  }
}

class HomePage extends StatefulWidget {
  final Settings settings;
  const HomePage({super.key, required this.settings});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final Telemetry _t = Telemetry();
  late final VescClient _vesc;
  late final BmsClient _bms;
  late final ConnectionManager _conn;

  Settings get _s => widget.settings;

  @override
  void initState() {
    super.initState();
    _vesc = VescClient(
      onState: (s) => setState(() => _t.ctrl = s),
      onPrint: (line) => debugPrint('X9000: $line'),
    );
    _bms = BmsClient(onState: (s) => setState(() => _t.bms = s));
    _conn = ConnectionManager(
      vesc: _vesc,
      bms: _bms,
      settings: _s,
      log: (m) => debugPrint('x7/ble: $m'),
    );
    _s.addListener(_onSettings);
    _applyWakelock();
    WidgetsBinding.instance.addPostFrameCallback((_) => _conn.start());
  }

  void _onSettings() {
    _applyWakelock();
    setState(() {}); // units may have changed
  }

  Future<void> _applyWakelock() async {
    try {
      await WakelockPlus.toggle(enable: _s.keepScreenOn);
    } catch (_) {}
  }

  @override
  void dispose() {
    _s.removeListener(_onSettings);
    _conn.dispose();
    _vesc.disconnect();
    _bms.disconnect();
    super.dispose();
  }

  void _toast(String msg) {
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.showSnackBar(SnackBar(
      content: Text(msg),
      duration: const Duration(milliseconds: 1300),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Dashboard(
      telemetry: _t,
      settings: _s,
      onSetMode: (race) async {
        final ok = await _vesc.setMode(race: race);
        _toast(ok ? 'Sent: ${race ? 'RACE' : 'STREET'} mode' : 'Controller not connected');
      },
      onSetAssist: (level) async {
        final ok = await _vesc.setAssist(level);
        _toast(ok ? 'Sent: Assist $level' : 'Controller not connected');
      },
      onOpenSettings: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SettingsScreen(settings: _s)),
      ),
    );
  }
}
