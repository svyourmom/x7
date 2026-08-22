// Greenway BMS BLE client — STUB.
//
// The Greenway BMS BLE parsing is documented in
// svyourmom/Talaria-Greenway-BMS-Protocol-Reference. This class provides the connection
// scaffold and the state callback; drop the real service/characteristic UUIDs and the frame
// parser in where marked TODO. Keeping the two BLE clients independent (each with its own
// reconnect) is deliberate — one device dropping must not take down the other.

import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../model/telemetry.dart';

class BmsClient {
  BluetoothDevice? _device;
  StreamSubscription? _notifySub;
  final void Function(BmsState) onState;

  BmsClient({required this.onState});

  bool get connected => _device?.isConnected ?? false;

  Future<void> connect(BluetoothDevice device) async {
    _device = device;
    await device.connect(autoConnect: false, timeout: const Duration(seconds: 20));
    final services = await device.discoverServices();

    // TODO(contributor): from Talaria-Greenway-BMS-Protocol-Reference —
    //   1. match the BMS service + notify characteristic UUID(s),
    //   2. setNotifyValue(true) and listen,
    //   3. parse frames into BmsState (soc, packV, current, cellMin/Max, tempC).
    // The reference documents the exact byte layout; this is a mechanical port.
    for (final s in services) {
      // if (s.uuid == bmsService) { ... }
    }
    // _notifySub = notifyChar.onValueReceived.listen(_onFrame);
  }

  Future<void> disconnect() async {
    await _notifySub?.cancel();
    await _device?.disconnect();
  }

  // ignore: unused_element
  void _onFrame(List<int> data) {
    // TODO(contributor): decode per the BMS reference, then:
    // onState(BmsState(soc: ..., packV: ..., current: ..., cellMin: ..., cellMax: ...,
    //                  tempC: ..., updated: DateTime.now()));
  }
}
