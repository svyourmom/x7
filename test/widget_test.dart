// Protocol unit tests — pure Dart, no BLE/hardware needed.

import 'package:flutter_test/flutter_test.dart';
import 'package:x7/ble/vesc_protocol.dart';
import 'package:x7/ble/bms_client.dart';

void main() {
  test('CRC-16/XMODEM check value', () {
    expect(crc16('123456789'.codeUnits), 0x31C3);
  });

  test('VESC frame + Unframer round-trip', () {
    final payload = [Comm.getValues, 0x01, 0x02, 0x03];
    final wire = frame(payload);
    final out = Unframer().feed(wire);
    expect(out.length, 1);
    expect(out.first, payload);
  });

  test('CAN-RX injector packet for set-mode (handlebar 0x03003203, data[0]=mode)', () {
    // [113][03 00 32 03][8 data], data[0] = 2 (Race) / 1 (Street).
    // Emulates the handlebar so both the ride flag and the display byte move.
    final race = Ebmx.setMode(race: true);
    expect(race[0], Comm.bmsFwdCanRx);
    expect(race.sublist(1, 5), [0x03, 0x00, 0x32, 0x03]);
    expect(race[5 + 0], 2);
    expect(Ebmx.setMode(race: false)[5 + 0], 1);
  });

  test('CAN-RX injector packet for set-assist (handlebar 0x03003201)', () {
    final a = Ebmx.setAssist(2);
    expect(a.sublist(1, 5), [0x03, 0x00, 0x32, 0x01]);
    expect(a[5 + 0], 2); // level
    expect(a[5 + 1], 0xE4); // selector flag
  });

  test('SET_DUTY encodes negative duty as i32 BE (duty*1e5)', () {
    // -0.05 * 1e5 = -5000 = 0xFFFFEC78
    expect(Motor.setDuty(-0.05), [Comm.setDuty, 0xFF, 0xFF, 0xEC, 0x78]);
    expect(Motor.release(), [Comm.setCurrent, 0, 0, 0, 0]);
  });

  test('terminal command payload: id 20 + ASCII, no trailing NUL', () {
    final p = terminalCmd('vwheelie_diag');
    expect(p.first, Comm.terminalCmd);
    expect(String.fromCharCodes(p.sublist(1)), 'vwheelie_diag');
    expect(p.length, 1 + 13);
    expect(Wheelie.on, 'vwheelie_diag on');
    expect(Wheelie.off, 'vwheelie_diag off');
    expect(Wheelie.start('12'), 'vwheelie_diag start 12');
  });

  test('vwheelie_diag reply lines parse (formats from the firmware strings)', () {
    // status header
    var w = Wheelie.parseLine('vwheelie_diag #1  running=1  enabled=0  active=0')!;
    expect(w.running, true);
    expect(w.enabled, false);
    expect(w.start, null);
    // params: keep the printed text so a restore sends exactly what was there
    w = Wheelie.parseLine('  params: start=20.00 end=43.00 kd=0.005')!;
    expect(w.start, '20.00');
    expect(w.enabled, null);
    // on/off confirmations
    expect(Wheelie.parseLine('vwheelie: ENABLED')!.enabled, true);
    expect(Wheelie.parseLine('vwheelie: DISABLED')!.enabled, false);
    // start angle echo
    expect(Wheelie.parseLine('vwheelie start -> 12.00 deg')!.start, '12.00');
    // unrelated terminal output
    expect(Wheelie.parseLine('  live:   pitch=1.23 deg  rate=0.00 deg/s'), null);
    expect(Wheelie.parseLine('tcstrength: mode=2  active=0%'), null);
  });

  test('BMS read request framing (BatteryVoltage, param 9)', () {
    // 46 16 01 09 04 6A  (from the Greenway reference)
    expect(bmsRead(9, 4), [0x46, 0x16, 0x01, 0x09, 0x04, 0x6A]);
  });
}
