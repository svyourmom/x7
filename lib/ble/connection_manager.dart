// Owns discovery + connection for BOTH devices (X-9000 controller + Greenway BMS),
// each with independent reconnect so one dropping never takes down the other.

import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'vesc_client.dart';
import 'bms_client.dart';

class ConnectionManager {
  final VescClient vesc;
  final BmsClient bms;
  final void Function(String) log;
  ConnectionManager({required this.vesc, required this.bms, required this.log});

  bool _vescBusy = false, _bmsBusy = false;
  StreamSubscription? _scanSub, _adapterSub;
  Timer? _rescan;

  Future<void> start() async {
    // Runtime permissions (Android 12+: SCAN/CONNECT; older also wants location).
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    _adapterSub = FlutterBluePlus.adapterState.listen((s) {
      log('adapter: $s');
      if (s == BluetoothAdapterState.on) _begin();
    });
    if (await FlutterBluePlus.adapterState.first == BluetoothAdapterState.on) _begin();
  }

  void _begin() {
    _scanSub ??= FlutterBluePlus.scanResults.listen(_onResults);
    _rescan ??= Timer.periodic(const Duration(seconds: 8), (_) => _scanOnce());
    _scanOnce();
  }

  Future<void> _scanOnce() async {
    if (vesc.connected && bms.connected) return; // both up — nothing to find
    if (FlutterBluePlus.isScanningNow) return;
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 6));
    } catch (e) {
      log('scan error: $e');
    }
  }

  void _onResults(List<ScanResult> results) {
    for (final r in results) {
      final uuids = r.advertisementData.serviceUuids;
      final name = r.advertisementData.advName;

      if (!vesc.connected && !_vescBusy &&
          (name == 'CYCMOTOR' || uuids.contains(nusService))) {
        _connect('X-9000', r.device, () => vesc.connect(r.device),
            () => vesc.connected, (b) => _vescBusy = b);
      }
      if (!bms.connected && !_bmsBusy && uuids.contains(bmsService)) {
        _connect('BMS', r.device, () => bms.connect(r.device),
            () => bms.connected, (b) => _bmsBusy = b);
      }
    }
  }

  Future<void> _connect(String tag, BluetoothDevice d, Future<void> Function() doConnect,
      bool Function() isConnected, void Function(bool) setBusy) async {
    setBusy(true);
    try {
      log('connecting $tag ${d.remoteId}');
      if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
      await doConnect();
      log('$tag connected');
      d.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) {
          log('$tag dropped — will rescan');
          _scanOnce();
        }
      });
    } catch (e) {
      log('$tag connect failed: $e');
    }
    setBusy(false);
  }

  void dispose() {
    _rescan?.cancel();
    _scanSub?.cancel();
    _adapterSub?.cancel();
  }
}
