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
  static const int setDuty = 5; // motor command — reverse creep (duty ~ speed under no load)
  static const int setCurrent = 6; // motor command — reverse uses this to release (0 A = coast)
  static const int setRpm = 8; // REPURPOSED on X9KV3 (mode/display broadcast, not set_pid_speed)
  static const int getMcconf = 14;
  static const int getAppconf = 17;
  static const int terminalCmd = 20;
  static const int comPrint = 21; // controller -> host terminal output
  static const int getValuesSetup = 47;
  static const int getValuesSetupSelective = 51;
  static const int getValuesSelective = 50; // GET_VALUES field subset by 32-bit mask

  static const int pingCan = 62;
  static const int bmsGetValues = 96;
  // Implemented by the optional x7-vesc firmware patch (CAN-RX injector):
  static const int bmsFwdCanRx = 113;
}

/// Native VESC motor commands. Motion — used only by the momentary hold-to-reverse control.
///
/// NOTE: COMM id 8 (SET_RPM) is REPURPOSED on X9KV3 — its handler doesn't drive the motor,
/// it calls the mode/display broadcast (0x801ab80), so sending it does nothing to the wheel
/// and toggles the ride mode. Reverse therefore uses SET_DUTY (id 5), which is a real handler
/// (mc_interface_set_duty). Duty ~ speed under no load, so it's a predictable slow creep.
class Motor {
  /// Duty-cycle control. duty in [-1, 1]; negative = reverse. VESC wire units: duty * 1e5.
  static Uint8List setDuty(double duty) {
    final v = (duty * 100000).round();
    return Uint8List.fromList([
      Comm.setDuty,
      (v >> 24) & 0xFF,
      (v >> 16) & 0xFF,
      (v >> 8) & 0xFF,
      v & 0xFF,
    ]);
  }

  /// SET_CURRENT 0 mA — releases the motor to coast (used on reverse release).
  static Uint8List release() => Uint8List.fromList([Comm.setCurrent, 0, 0, 0, 0]);
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

/// Build a terminal command payload: [20] + the command text (no trailing NUL).
/// Replies come back as COMM_PRINT (21) packets, one per printed line.
Uint8List terminalCmd(String cmd) => Uint8List.fromList([Comm.terminalCmd, ...cmd.codeUnits]);

/// One parsed line of `vwheelie_diag` output. Only the fields x7 uses.
class WheelieLine {
  final bool? running; // limiter thread alive (IMU present)
  final bool? enabled; // limiter switched on
  final String? start; // start angle exactly as the controller printed it, e.g. "20.00"
  const WheelieLine({this.running, this.enabled, this.start});
}

/// The controller's built-in wheel-lift limiter, driven over the terminal.
/// Command syntax and reply format: x7-vesc docs/04-terminal-commands.md.
class Wheelie {
  static const String read = 'vwheelie_diag';
  static const String on = 'vwheelie_diag on';
  static const String off = 'vwheelie_diag off';

  /// Set the pitch angle (degrees) where the limiter starts acting.
  static String start(String deg) => 'vwheelie_diag start $deg';

  // Reply formats, verbatim from the firmware strings:
  //   vwheelie_diag #1  running=1  enabled=0  active=0
  //     params: start=20.00 end=43.00 kd=0.005
  //   vwheelie: ENABLED   /   vwheelie: DISABLED
  //   vwheelie start -> 12.00 deg
  static final RegExp _header = RegExp(r'running=(\d)\s+enabled=(\d)');
  static final RegExp _params = RegExp(r'start=(\d+\.\d+)\s+end=');
  static final RegExp _switched = RegExp(r'vwheelie:\s+(ENABLED|DISABLED)');
  static final RegExp _startSet = RegExp(r'vwheelie start\s+->\s+(\d+\.\d+)');

  /// Parse one printed line. Returns null for lines that say nothing about the limiter.
  static WheelieLine? parseLine(String line) {
    var m = _header.firstMatch(line);
    if (m != null) return WheelieLine(running: m[1] == '1', enabled: m[2] == '1');
    m = _params.firstMatch(line);
    if (m != null) return WheelieLine(start: m[1]);
    m = _switched.firstMatch(line);
    if (m != null) return WheelieLine(enabled: m[1] == 'ENABLED');
    m = _startSet.firstMatch(line);
    if (m != null) return WheelieLine(start: m[1]);
    return null;
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
///
/// These emulate the handlebar module, which drives the bike over the priority-prefixed
/// `0x0300_32xx` id family. Empirically (garagepc, X9KV3), the older `0x5E4EA3` mode path
/// set only the ride-mode flag (`0x2001c8c0`, what `tcstrength` reads) but NOT the display
/// byte (`0x1000000c`) — its `set_displays_mode` call is behind a gate that stays shut over
/// injection — so the bike kept *reporting* the old mode. Node `0x3203` calls
/// `set_displays_mode` directly and moves both, matching the physical button.
class Ebmx {
  /// Ride mode via handlebar node 0x03003203: data[0] = 1 (Street) / 2 (Race).
  /// Updates both the ride-mode flag and the display byte (verified: prints
  /// "set displays_mode 0/1" and flips `tcstrength mode=`).
  static Uint8List setMode({required bool race}) =>
      canRxInject(0x03003203, [race ? 2 : 1, 0, 0, 0, 0, 0, 0, 0]);

  /// Assist level via handlebar node 0x03003201: data[0] = level (1..3),
  /// data[1] = 0xE4 selector flag. (Distinct from the gear/level selector below.)
  static Uint8List setAssist(int level) =>
      canRxInject(0x03003201, [level & 0xFF, 0xE4, 0, 0, 0, 0, 0, 0]);

  // --- Gear / level (the SW102T display's up/down selection) ---
  // Emulates the display's level frame 0x5E4EB0. data[0] = level byte.
  // NOTE: with a physical display connected this is OVERWRITTEN within ~50-400ms
  // (the display re-broadcasts every ~20-35ms). It STICKS only when the display is
  // disconnected — then the app is the sole level source. See x7-vesc docs/08.
  static const int gearReverse = 0xFF;
  static const int gearNeutral = 0x00;
  static const int gearOff = 0x00; // alias: level 0 does not drive

  /// Set gear/level via 0x5E4EB0. level: 0xFF=Reverse, 0=neutral/off, 1..3 = gears.
  static Uint8List setGear(int level) =>
      canRxInject(0x005E4EB0, [level & 0xFF, 0, 0, 0, 0, 0, 0, 0]);

  // --- Reading gear + mode back (works with or without the injector patch) ---
  // GET_VALUES_SELECTIVE (50) with mask (1<<24)|(1<<25): reply is
  //   [50][mask:u32 BE][mode:u8][level:s8]
  static const int selMask = (1 << 24) | (1 << 25); // 0x03000000

  // GET_VALUES_SETUP_SELECTIVE (id 51), mask (1<<6) = speed (bit 6, ahead of the EBMX
  // divergence at bit 7). Reply: [51][mask:u32 BE][speed:i32 BE] where speed/1000 = m/s.
  static const int setupSpeedMask = 1 << 6; // 0x40
  static Uint8List readSpeed() => Uint8List.fromList([
        Comm.getValuesSetupSelective,
        (setupSpeedMask >> 24) & 0xFF,
        (setupSpeedMask >> 16) & 0xFF,
        (setupSpeedMask >> 8) & 0xFF,
        setupSpeedMask & 0xFF,
      ]);

  /// Decode m/s from a setup-selective speed reply payload (excludes id). null if short.
  static double? decodeSpeedMs(List<int> pl) {
    if (pl.length < 9) return null; // [51][4 mask][i32 speed]
    int v = (pl[5] << 24) | (pl[6] << 16) | (pl[7] << 8) | pl[8];
    if (v & 0x80000000 != 0) v -= 0x100000000; // signed
    return v / 1000.0;
  }

  static Uint8List readGearMode() => Uint8List.fromList([
        Comm.getValuesSelective,
        (selMask >> 24) & 0xFF,
        (selMask >> 16) & 0xFF,
        (selMask >> 8) & 0xFF,
        selMask & 0xFF,
      ]);

  /// Decode the two custom bytes from a selective reply payload (excludes the id).
  /// Returns (mode, gearName) or null if the reply is too short.
  /// Level byte: -1=Reverse, 0=neutral, 3/6/9 = gear 1/2/3.
  static ({String mode, String gear})? decodeGearMode(List<int> pl) {
    if (pl.length < 7) return null; // [50][4 mask][mode][level]
    final modeByte = pl[5];
    int lvl = pl[6];
    if (lvl > 127) lvl -= 256; // s8
    const gearNames = {-1: 'R', 0: 'N', 3: '1', 6: '2', 9: '3'};
    return (
      mode: modeByte == 1 ? 'race' : 'street',
      gear: gearNames[lvl] ?? '?',
    );
  }
}
