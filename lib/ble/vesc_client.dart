// EBMX X-9000 (VESC) BLE client.
//
// Connects to the controller's Nordic UART Service, sends VESC frames, parses replies,
// and exposes control (terminal commands + optional CAN-RX injection). Ported from
// svyourmom/x7-vesc tools/vesc-ble.py.
//
// Holds the latest controller state and re-emits a merged CtrlState whenever any source
// updates (GET_VALUES for power/temps; the `tcstrength` terminal read for the ride mode).

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../model/telemetry.dart';
import 'vesc_protocol.dart';

// Nordic UART Service on the X-9000 (advertises as "CYCMOTOR").
final Guid nusService = Guid('6e400001-b5a3-f393-e0a9-e50e24dcca9e');
final Guid nusRx = Guid('6e400002-b5a3-f393-e0a9-e50e24dcca9e'); // host -> controller
final Guid nusTx = Guid('6e400003-b5a3-f393-e0a9-e50e24dcca9e'); // controller -> host

final RegExp _modeRe = RegExp(r'\bmode=(\d)');

class _R {
  final Uint8List b;
  int i = 0;
  _R(this.b);
  int i8() { final v = b[i++]; return v >= 128 ? v - 256 : v; }
  int i16() { final v = (b[i] << 8) | b[i + 1]; i += 2; return v >= 32768 ? v - 65536 : v; }
  int i32() {
    final v = (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
    i += 4;
    return v >= 0x80000000 ? v - 0x100000000 : v;
  }
  void u8() => i++;
}

class VescClient {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _rx, _tx;
  final Unframer _un = Unframer();
  StreamSubscription? _notifySub;
  Timer? _pollTimer;
  int _tick = 0;

  // latest controller state (merged from GET_VALUES + the tcstrength mode read)
  int? _erpm;
  double? _motorA, _inputA, _duty, _inputV, _fetC, _motorC;
  List<String> _faults = const [];
  String? _mode; // 'street' | 'race'
  int? _assist; // last-commanded assist level (no read-back exists on the X-9000)

  // --- hold-to-reverse (momentary; motion) ---
  // SET_DUTY at a small negative duty = slow reverse creep (SET_RPM id 8 is repurposed on this fw).
  static const double reverseDuty = -0.05; // ~5% duty; tune after the wheel-off test
  static const int _engageMaxErpm = 1200; // refuse to engage reverse while rolling faster than this
  bool _reverse = false;
  bool get reverseActive => _reverse;

  final void Function(CtrlState) onState;
  final void Function(String line) onPrint;
  VescClient({required this.onState, required this.onPrint});

  bool get connected => _device?.isConnected ?? false;

  Future<void> connect(BluetoothDevice device) async {
    _device = device;
    _assist = null; // no read-back; don't carry a stale commanded level across connections
    await device.connect(autoConnect: false, timeout: const Duration(seconds: 20));
    final services = await device.discoverServices();
    for (final s in services) {
      if (s.uuid != nusService) continue;
      for (final c in s.characteristics) {
        if (c.uuid == nusRx) _rx = c;
        if (c.uuid == nusTx) _tx = c;
      }
    }
    if (_rx == null || _tx == null) throw StateError('X-9000 NUS characteristics not found');
    await _tx!.setNotifyValue(true);
    _notifySub = _tx!.onValueReceived.listen(_onNotify);
    _startPolling();
  }

  Future<void> disconnect() async {
    stopReverse(); // never leave the motor commanded
    _pollTimer?.cancel();
    await _notifySub?.cancel();
    await _device?.disconnect();
  }

  /// Sends a framed payload. Returns false (rather than throwing) if the controller
  /// isn't connected or the write fails, so control taps never fail silently.
  Future<bool> _send(List<int> payload) async {
    final rx = _rx;
    if (!connected || rx == null) return false;
    try {
      final pkt = frame(payload);
      for (int off = 0; off < pkt.length; off += 20) {
        final end = (off + 20 < pkt.length) ? off + 20 : pkt.length;
        await rx.write(pkt.sublist(off, end), withoutResponse: true);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  // --- commands ---
  Future<void> requestValues() => _send([Comm.getValues]);
  Future<void> terminal(String cmd) => _send([Comm.terminalCmd, ...cmd.codeUnits]);
  Future<bool> setMode({required bool race}) => _send(Ebmx.setMode(race: race));

  /// Engage momentary reverse. Only while the button is held. Refuses if disconnected or
  /// if the wheel is already rolling above [_engageMaxErpm]. The poll loop keeps it alive.
  bool startReverse() {
    if (!connected) return false;
    if (_erpm != null && _erpm!.abs() > _engageMaxErpm) return false;
    _reverse = true;
    _send(Motor.setDuty(reverseDuty)); // immediate; poll loop resends as keep-alive
    return true;
  }

  /// Release reverse — coast the motor. Safe to call redundantly. Also invoked on
  /// disconnect/dispose so the motor never stays commanded.
  void stopReverse() {
    final was = _reverse;
    _reverse = false;
    if (was && connected) _send(Motor.release());
  }
  Future<bool> setAssist(int level) async {
    final ok = await _send(Ebmx.setAssist(level));
    if (!ok) return false;
    _assist = level; // optimistic: the controller exposes no assist read-back
    _emit();
    return true;
  }

  // --- polling ---
  void _startPolling() {
    _pollTimer?.cancel();
    _tick = 0;
    _pollTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!connected) {
        _reverse = false; // link lost — drop reverse; controller's own timeout zeroes the motor
        return;
      }
      if (_reverse) _send(Motor.setDuty(reverseDuty)); // keep-alive (<1s VESC command timeout)
      requestValues();
      if (_tick % 8 == 0) terminal('tcstrength'); // read the ride mode ~every 1.6 s (read-only)
      _tick++;
    });
  }

  void _emit() {
    onState(CtrlState(
      erpm: _erpm,
      motorA: _motorA,
      inputA: _inputA,
      duty: _duty,
      inputV: _inputV,
      fetC: _fetC,
      motorC: _motorC,
      mode: _mode,
      assist: _assist,
      faults: _faults,
      updated: DateTime.now(),
    ));
  }

  void _onNotify(List<int> chunk) {
    for (final pl in _un.feed(chunk)) {
      if (pl.isEmpty) continue;
      switch (pl[0]) {
        case Comm.getValues:
          _parseValues(pl);
          break;
        case Comm.comPrint:
          final line = String.fromCharCodes(pl.sublist(1)).trimRight();
          onPrint(line);
          final m = _modeRe.firstMatch(line);
          if (m != null) {
            _mode = m.group(1) == '2' ? 'race' : 'street';
            _emit();
          }
          break;
      }
    }
  }

  void _parseValues(Uint8List pl) {
    // VESC GET_VALUES layout (5.x). Only the fields x7 shows are read.
    final r = _R(pl);
    r.u8(); // command id
    _fetC = r.i16() / 10.0;
    _motorC = r.i16() / 10.0;
    _motorA = r.i32() / 100.0;
    _inputA = r.i32() / 100.0;
    r.i32(); // avg_id
    r.i32(); // avg_iq
    _duty = r.i16() / 1000.0;
    _erpm = r.i32();
    _inputV = r.i16() / 10.0;
    r.i += 4 * 7; // amp_h, amp_h_chg, wh, wh_chg, tacho, tacho_abs, (pad)
    _faults = (r.i < pl.length && r.i8() != 0) ? const ['fault'] : const [];
    _emit();
  }
}
