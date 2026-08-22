// Greenway BMS BLE client.
//
// Protocol (see svyourmom/Talaria-Greenway-BMS-Protocol-Reference):
//   Service 0000fff0-..., data characteristic 0000fff1-... (read/write/notify).
//   Polled request/response, little-endian:
//     Request:  46 <addr:u16 LE> <param> <len> <cksum>
//     Response: 47 <addr:u16 LE> <param> <len> <data...> <cksum>
//   BMS address 0x0116 (wire "16 01"); cksum = sum(preceding bytes) & 0xFF.
//   Params: 9=BatteryVoltage(u32 LE mV) 10=BatteryCurrent(s32 LE mA)
//           13=BatteryPercent(u8 %)     36=CellVoltages1(16 × u16 LE mV)

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../model/telemetry.dart';

final Guid bmsService = Guid('0000fff0-0000-1000-8000-00805f9b34fb');
final Guid bmsChar = Guid('0000fff1-0000-1000-8000-00805f9b34fb');

const int _addrLo = 0x16, _addrHi = 0x01; // 0x0116 little-endian on the wire
const int pVoltage = 9, pCurrent = 10, pSoc = 13, pCells = 36;

int _cksum(List<int> bytes) {
  int s = 0;
  for (final b in bytes) {
    s += b;
  }
  return s & 0xFF;
}

/// Build a read request for [param] returning [len] data bytes.
Uint8List bmsRead(int param, int len) {
  final body = [0x46, _addrLo, _addrHi, param, len];
  return Uint8List.fromList([...body, _cksum(body)]);
}

class BmsClient {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _ch;
  StreamSubscription? _notifySub;
  Timer? _pollTimer;
  final List<int> _buf = [];

  // latest decoded values, merged into one BmsState on each update
  double? _soc, _packV, _current, _cellMin, _cellMax;

  final void Function(BmsState) onState;
  BmsClient({required this.onState});

  bool get connected => _device?.isConnected ?? false;

  Future<void> connect(BluetoothDevice device) async {
    _device = device;
    await device.connect(autoConnect: false, timeout: const Duration(seconds: 20));
    final services = await device.discoverServices();
    for (final s in services) {
      if (s.uuid != bmsService) continue;
      for (final c in s.characteristics) {
        if (c.uuid == bmsChar) _ch = c;
      }
    }
    if (_ch == null) throw StateError('Greenway BMS characteristic (fff1) not found');
    await _ch!.setNotifyValue(true);
    _notifySub = _ch!.onValueReceived.listen(_onNotify);
    _startPolling();
  }

  Future<void> disconnect() async {
    _pollTimer?.cancel();
    await _notifySub?.cancel();
    await _device?.disconnect();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (!connected || _ch == null) return;
      // stagger the four reads within the 500 ms tick
      await _req(bmsRead(pSoc, 1));
      await _req(bmsRead(pVoltage, 4));
      await _req(bmsRead(pCurrent, 4));
      await _req(bmsRead(pCells, 32));
    });
  }

  Future<void> _req(List<int> bytes) async {
    try {
      await _ch!.write(bytes, withoutResponse: false);
    } catch (_) {/* transient; next tick retries */}
  }

  void _onNotify(List<int> chunk) {
    _buf.addAll(chunk);
    // parse any complete 47-frames in the buffer
    while (true) {
      // resync to a 0x47 response start
      while (_buf.isNotEmpty && _buf[0] != 0x47) {
        _buf.removeAt(0);
      }
      if (_buf.length < 6) break; // 47 addr(2) param len ... cksum
      final param = _buf[3];
      final len = _buf[4];
      final total = 5 + len + 1; // header(5) + data + cksum
      if (_buf.length < total) break;
      final data = _buf.sublist(5, 5 + len);
      _buf.removeRange(0, total);
      _decode(param, data);
    }
  }

  void _decode(int param, List<int> d) {
    final bd = ByteData.sublistView(Uint8List.fromList(d));
    switch (param) {
      case pSoc:
        if (d.isNotEmpty) _soc = d[0].toDouble();
        break;
      case pVoltage:
        if (d.length >= 4) _packV = bd.getUint32(0, Endian.little) / 1000.0;
        break;
      case pCurrent:
        if (d.length >= 4) _current = bd.getInt32(0, Endian.little) / 1000.0;
        break;
      case pCells:
        if (d.length >= 32) {
          double lo = double.infinity, hi = 0;
          for (int i = 0; i < 16; i++) {
            final v = bd.getUint16(i * 2, Endian.little) / 1000.0;
            if (v > 0) {
              if (v < lo) lo = v;
              if (v > hi) hi = v;
            }
          }
          if (hi > 0) {
            _cellMin = lo;
            _cellMax = hi;
          }
        }
        break;
      default:
        return;
    }
    onState(BmsState(
      soc: _soc,
      packV: _packV,
      current: _current,
      cellMin: _cellMin,
      cellMax: _cellMax,
      updated: DateTime.now(),
    ));
  }
}
