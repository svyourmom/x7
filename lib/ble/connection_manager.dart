// Discovery + connection for all device roles (see device_profiles.dart).
// Each role connects independently with its own reconnect, honours the user's device
// selection from Settings, and switches device when the selection changes.

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../settings.dart';
import 'device_profiles.dart';
import 'vesc_client.dart';
import 'bms_client.dart';

class _Role {
  final bool Function() isConnected;
  final Future<void> Function(BluetoothDevice) connect;
  final Future<void> Function() disconnect;
  bool busy = false;
  String? connectedId;
  _Role(this.isConnected, this.connect, this.disconnect);
}

class ConnectionManager {
  final VescClient vesc;
  final BmsClient bms;
  final Settings settings;
  final void Function(String) log;

  late final Map<String, _Role> _roles;
  StreamSubscription? _scanSub, _adapterSub;
  Timer? _rescan;

  ConnectionManager({
    required this.vesc,
    required this.bms,
    required this.settings,
    required this.log,
  }) {
    _roles = {
      'controller': _Role(() => vesc.connected, (d) => vesc.connect(d), () => vesc.disconnect()),
      'bms': _Role(() => bms.connected, (d) => bms.connect(d), () => bms.disconnect()),
    };
    settings.addListener(_onSettingsChanged);
  }

  Future<void> start() async {
    // iOS has one Bluetooth permission. Android 12+ splits it into scan + connect, and
    // older Android needs location to scan. Asking iOS for location would show an
    // unwanted prompt.
    final perms = Platform.isIOS
        ? <Permission>[Permission.bluetooth]
        : <Permission>[
            Permission.bluetoothScan,
            Permission.bluetoothConnect,
            Permission.locationWhenInUse,
          ];
    await perms.request();
    _adapterSub = FlutterBluePlus.adapterState.listen((s) {
      log('adapter: $s');
      if (s == BluetoothAdapterState.on) _begin();
    });
    if (await FlutterBluePlus.adapterState.first == BluetoothAdapterState.on) _begin();
  }

  void _begin() {
    _scanSub ??= FlutterBluePlus.scanResults.listen(_onResults);
    _rescan ??= Timer.periodic(const Duration(seconds: 8), (_) => scanOnce());
    scanOnce();
  }

  Future<void> scanOnce() async {
    if (_roles.values.every((r) => r.isConnected())) return;
    if (FlutterBluePlus.isScanningNow) return;
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 6));
    } catch (e) {
      log('scan error: $e');
    }
  }

  void _onSettingsChanged() {
    // If a role is connected to a device that no longer matches the new selection, drop it
    // so it reconnects to the chosen one.
    for (final entry in _roles.entries) {
      final chosen = settings.deviceFor(entry.key);
      final role = entry.value;
      if (role.isConnected() &&
          role.connectedId != null &&
          chosen != null &&
          chosen != role.connectedId) {
        log('${entry.key}: selection changed -> disconnect ${role.connectedId}');
        role.disconnect();
        role.connectedId = null;
        scanOnce();
      }
    }
  }

  void _onResults(List<ScanResult> results) {
    for (final r in results) {
      for (final profile in deviceProfiles) {
        final role = _roles[profile.roleId];
        if (role == null || role.busy || role.isConnected()) continue;
        if (!profile.matches(r)) continue;
        final chosen = settings.deviceFor(profile.roleId);
        if (chosen != null && chosen != r.device.remoteId.str) continue; // wait for the chosen one
        _connect(profile.roleId, r.device, role);
      }
    }
  }

  Future<void> _connect(String roleId, BluetoothDevice d, _Role role) async {
    role.busy = true;
    try {
      log('connecting $roleId ${d.remoteId}');
      if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
      await role.connect(d);
      role.connectedId = d.remoteId.str;
      log('$roleId connected');
      d.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) {
          log('$roleId dropped');
          role.connectedId = null;
          scanOnce();
        }
      });
    } catch (e) {
      log('$roleId connect failed: $e');
    }
    role.busy = false;
  }

  void dispose() {
    settings.removeListener(_onSettingsChanged);
    _rescan?.cancel();
    _scanSub?.cancel();
    _adapterSub?.cancel();
  }
}
