// EBMX X-9000 (VESC) BLE client.
//
// Connects to the controller's Nordic UART Service, sends VESC frames, parses replies,
// and exposes control (terminal commands + optional CAN-RX injection). Ported from
// svyourmom/x7-vesc tools/vesc-ble.py.
//
// NOTE: connection lifecycle uses flutter_blue_plus; the parsing/framing is in
// vesc_protocol.dart and is unit-testable without hardware.

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../model/telemetry.dart';
import 'vesc_protocol.dart';

// Nordic UART Service on the X-9000 (advertises as "CYCMOTOR").
final Guid nusService = Guid('6e400001-b5a3-f393-e0a9-e50e24dcca9e');
final Guid nusRx = Guid('6e400002-b5a3-f393-e0a9-e50e24dcca9e'); // host -> controller
final Guid nusTx = Guid('6e400003-b5a3-f393-e0a9-e50e24dcca9e'); // controller -> host

class _R {
  final Uint8List b;
  int i = 0;
  _R(this.b);
  int u8() => b[i++];
  int i8() { final v = b[i++]; return v >= 128 ? v - 256 : v; }
  int i16() { final v = (b[i] << 8) | b[i + 1]; i += 2; return v >= 32768 ? v - 65536 : v; }
  int i32() {
    final v = (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
    i += 4;
    return v >= 0x80000000 ? v - 0x100000000 : v;
  }
}

class VescClient {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _rx, _tx;
  final Unframer _un = Unframer();
  StreamSubscription? _notifySub;

  final void Function(CtrlState) onState;
  final void Function(String line) onPrint;

  VescClient({required this.onState, required this.onPrint});

  bool get connected => _device?.isConnected ?? false;

  /// Connect to a device (found by scanning for the NUS / "CYCMOTOR"), discover the
  /// characteristics, subscribe to notifications, and start polling GET_VALUES.
  Future<void> connect(BluetoothDevice device) async {
    _device = device;
    await device.connect(autoConnect: false, timeout: const Duration(seconds: 20));
    final services = await device.discoverServices();
    for (final s in services) {
      if (s.uuid != nusService) continue;
      for (final c in s.characteristics) {
        if (c.uuid == nusRx) _rx = c;
        if (c.uuid == nusTx) _tx = c;
      }
    }
    if (_rx == null || _tx == null) {
      throw StateError('X-9000 NUS characteristics not found');
    }
    await _tx!.setNotifyValue(true);
    _notifySub = _tx!.onValueReceived.listen(_onNotify);
    _startPolling();
  }

  Future<void> disconnect() async {
    _pollTimer?.cancel();
    await _notifySub?.cancel();
    await _device?.disconnect();
  }

  Future<void> _send(List<int> payload) async {
    final pkt = frame(payload);
    // MTU 23 -> 20-byte writes.
    for (int off = 0; off < pkt.length; off += 20) {
      final end = (off + 20 < pkt.length) ? off + 20 : pkt.length;
      await _rx!.write(pkt.sublist(off, end), withoutResponse: true);
    }
  }

  // --- commands -------------------------------------------------------------

  Future<void> requestValues() => _send([Comm.getValues]);
  Future<void> terminal(String cmd) => _send([Comm.terminalCmd, ...cmd.codeUnits]);

  /// Optional: requires the x7-vesc CAN-RX injector firmware patch.
  Future<void> setMode({required bool race}) => _send(Ebmx.setMode(race: race));
  Future<void> setAssist(int level) => _send(Ebmx.setAssist(level));

  // --- polling & parsing ----------------------------------------------------

  Timer? _pollTimer;
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (connected) requestValues();
    });
  }

  void _onNotify(List<int> chunk) {
    for (final pl in _un.feed(chunk)) {
      if (pl.isEmpty) continue;
      switch (pl[0]) {
        case Comm.getValues:
          _parseValues(pl);
          break;
        case Comm.comPrint:
          onPrint(String.fromCharCodes(pl.sublist(1)).trimRight());
          break;
      }
    }
  }

  void _parseValues(Uint8List pl) {
    // VESC GET_VALUES layout (5.x). Only the fields x7 shows are read.
    final r = _R(pl);
    r.u8(); // command id
    final fetC = r.i16() / 10.0;
    final motorC = r.i16() / 10.0;
    final motorA = r.i32() / 100.0;
    final inputA = r.i32() / 100.0;
    r.i32(); // avg_id
    r.i32(); // avg_iq
    final duty = r.i16() / 1000.0;
    final erpm = r.i32();
    final inputV = r.i16() / 10.0;
    // amp_hours..tachometer follow; skip to fault code.
    r.i += 4 * 7; // amp_h, amp_h_chg, wh, wh_chg, tacho, tacho_abs, (pad)
    int fault = 0;
    if (r.i < pl.length) fault = r.i8();
    onState(CtrlState(
      erpm: erpm,
      motorA: motorA,
      inputA: inputA,
      duty: duty,
      inputV: inputV,
      fetC: fetC,
      motorC: motorC,
      faults: fault == 0 ? const [] : ['fault $fault'],
      updated: DateTime.now(),
    ));
  }
}
