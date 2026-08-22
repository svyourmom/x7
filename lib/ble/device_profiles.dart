// Device registry — the extensible list of device "roles" x7 can bind to.
//
// To support a new device later (another controller, another BMS, an accessory), add a
// DeviceProfile here and give ConnectionManager a client + connect function for its roleId.
// Nothing else in the UI/settings needs to change — the settings screen iterates this list.

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'vesc_client.dart'; // nusService
import 'bms_client.dart'; // bmsService

class DeviceProfile {
  final String roleId; // stable key, used in settings + connection manager
  final String label; // shown in the settings UI
  final bool Function(ScanResult r) matches;
  const DeviceProfile(this.roleId, this.label, this.matches);
}

/// Ordered list of supported device roles.
final List<DeviceProfile> deviceProfiles = [
  DeviceProfile(
    'controller',
    'Controller — EBMX X-9000 (VESC)',
    (r) =>
        r.advertisementData.advName == 'CYCMOTOR' ||
        r.advertisementData.serviceUuids.contains(nusService),
  ),
  DeviceProfile(
    'bms',
    'Battery — Greenway BMS',
    (r) => r.advertisementData.serviceUuids.contains(bmsService),
  ),
  // Future devices go here, e.g.:
  // DeviceProfile('controller2', 'Controller — <other>', (r) => ...),
];

DeviceProfile? profileById(String roleId) {
  for (final p in deviceProfiles) {
    if (p.roleId == roleId) return p;
  }
  return null;
}
