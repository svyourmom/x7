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

  test('CAN-RX injector packet for set-mode (0x5E4EA3, data[6]=mode)', () {
    final race = Ebmx.setMode(race: true);
    // [113][00 5E 4E A3][8 data], data[6] = 2
    expect(race[0], Comm.bmsFwdCanRx);
    expect(race.sublist(1, 5), [0x00, 0x5E, 0x4E, 0xA3]);
    expect(race[5 + 6], 2);
    expect(Ebmx.setMode(race: false)[5 + 6], 0);
  });

  test('BMS read request framing (BatteryVoltage, param 9)', () {
    // 46 16 01 09 04 6A  (from the Greenway reference)
    expect(bmsRead(9, 4), [0x46, 0x16, 0x01, 0x09, 0x04, 0x6A]);
  });
}
