// VESC packet protocol: framing + CRC-16/XMODEM + payload builders.
//
// Pure Dart, no BLE dependency, so it is unit-testable. Ported from the reference
// implementation in svyourmom/x7-vesc (tools/vesc-ble.py). All VESC integers are big-endian.
//
// Frame:
//   [0x02][len:u8]     [payload][crc:u16 BE][0x03]   len <= 255
//   [0x03][len:u16 BE] [payload][crc:u16 BE][0x03]   len <= 65535
// CRC-16/XMODEM (poly 0x1021, init 0) over the payload only. payload[0] is the command id.

import 'dart:typed_data';

/// VESC COMM_PACKET_IDs used by x7.
class Comm {
  static const int fwVersion = 0;
  static const int getValues = 4;
  static const int getMcconf = 14;
  static const int getAppconf = 17;
  static const int terminalCmd = 20;
  static const int comPrint = 21; // controller -> host terminal output
  static const int getValuesSetup = 47;
  static const int getValuesSetupSelective = 51;
  static const int pingCan = 62;
  static const int bmsGetValues = 96;
  // Implemented by the optional x7-vesc firmware patch (CAN-RX injector):
  static const int bmsFwdCanRx = 113;
}

int crc16(List<int> data) {
  int crc = 0;
  for (final b in data) {
    crc ^= b << 8;
    for (int i = 0; i < 8; i++) {
      crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) & 0xFFFF : (crc << 1) & 0xFFFF;
    }
  }
  return crc & 0xFFFF;
}

/// Wrap a payload in a VESC frame (start byte + length + payload + crc + stop).
Uint8List frame(List<int> payload) {
  final n = payload.length;
  final b = BytesBuilder();
  if (n <= 255) {
    b.add([0x02, n]);
  } else {
    b.add([0x03, (n >> 8) & 0xFF, n & 0xFF]);
  }
  b.add(payload);
  final c = crc16(payload);
  b.add([(c >> 8) & 0xFF, c & 0xFF, 0x03]);
  return b.toBytes();
}

/// Reassembles VESC packets out of the 20-byte BLE notification chunks.
/// Call [feed] with each notification; returns any complete payloads.
class Unframer {
  final List<int> _buf = [];

  List<Uint8List> feed(List<int> chunk) {
    _buf.addAll(chunk);
    final out = <Uint8List>[];
    while (true) {
      while (_buf.isNotEmpty && _buf[0] != 0x02 && _buf[0] != 0x03 && _buf[0] != 0x04) {
        _buf.removeAt(0);
      }
      if (_buf.isEmpty) break;
      final start = _buf[0];
      final nlen = start - 1; // 1, 2 or 3 length bytes
      if (_buf.length < 1 + nlen) break;
      int n = 0;
      for (int i = 0; i < nlen; i++) {
        n = (n << 8) | _buf[1 + i];
      }
      final total = 1 + nlen + n + 3;
      if (_buf.length < total) break;
      final payload = Uint8List.fromList(_buf.sublist(1 + nlen, 1 + nlen + n));
      final rxCrc = (_buf[1 + nlen + n] << 8) | _buf[1 + nlen + n + 1];
      final stop = _buf[total - 1];
      if (stop == 0x03 && rxCrc == crc16(payload)) {
        out.add(payload);
        _buf.removeRange(0, total);
      } else {
        _buf.removeAt(0); // bad frame: resync
      }
    }
    return out;
  }
}

/// Build the CAN-RX injection payload for the optional firmware patch (cmd 113).
/// Sends a synthetic CAN frame: [113][extId:u32 BE][8 data bytes].
Uint8List canRxInject(int extId, List<int> data8) {
  assert(data8.length == 8);
  return Uint8List.fromList([
    Comm.bmsFwdCanRx,
    (extId >> 24) & 0xFF,
    (extId >> 16) & 0xFF,
    (extId >> 8) & 0xFF,
    extId & 0xFF,
    ...data8,
  ]);
}

/// EBMX proprietary CAN command helpers (see x7-vesc docs/02-ebmx-can-protocol.md).
class Ebmx {
  /// Ride mode via 0x5E4EA3: data[6] = flag (0 = Street, non-zero = Race).
  static Uint8List setMode({required bool race}) =>
      canRxInject(0x5E4EA3, [0, 0, 0, 0, 0, 0, race ? 2 : 0, 0]);

  /// Assist level via 0x5E4EB0: data[0] = level.
  static Uint8List setAssist(int level) =>
      canRxInject(0x5E4EB0, [level & 0xFF, 0, 0, 0, 0, 0, 0, 0]);
}
