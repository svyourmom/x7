// Settings: units, keep-screen-on, and per-role device selection.
// The Devices list iterates the device_profiles registry, so future device types show up here
// with no UI changes.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../settings.dart';
import '../ble/device_profiles.dart';

class SettingsScreen extends StatefulWidget {
  final Settings settings;
  const SettingsScreen({super.key, required this.settings});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Imperial units'),
            subtitle: Text(s.imperial ? '°F · MPH' : '°C · KM/H'),
            value: s.imperial,
            onChanged: (v) => setState(() => s.setImperial(v)),
          ),
          SwitchListTile(
            title: const Text('Keep screen on'),
            subtitle: const Text('Prevent the display from sleeping'),
            value: s.keepScreenOn,
            onChanged: (v) => setState(() => s.setKeepScreenOn(v)),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('DEVICES', style: TextStyle(color: Colors.white54, letterSpacing: 2, fontSize: 12)),
          ),
          for (final p in deviceProfiles)
            ListTile(
              title: Text(p.label),
              subtitle: Text(s.deviceFor(p.roleId) ?? 'Auto (first found)'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => DevicePicker(profile: p, settings: s)),
                );
                setState(() {});
              },
            ),
        ],
      ),
    );
  }
}

class DevicePicker extends StatefulWidget {
  final DeviceProfile profile;
  final Settings settings;
  const DevicePicker({super.key, required this.profile, required this.settings});
  @override
  State<DevicePicker> createState() => _DevicePickerState();
}

class _DevicePickerState extends State<DevicePicker> {
  final Map<String, ScanResult> _found = {};
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    _sub = FlutterBluePlus.scanResults.listen((rs) {
      var changed = false;
      for (final r in rs) {
        if (widget.profile.matches(r)) {
          _found[r.device.remoteId.str] = r;
          changed = true;
        }
      }
      if (changed && mounted) setState(() {});
    });
    try {
      if (!FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 12));
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    final role = widget.profile.roleId;
    final sel = s.deviceFor(role);
    return Scaffold(
      appBar: AppBar(title: Text(widget.profile.label)),
      // RadioGroup owns the selection + change callback; the tiles just declare their
      // value. The 'Auto' tile's value is null, so it lands in the same handler.
      body: RadioGroup<String?>(
        groupValue: sel,
        onChanged: (v) {
          s.setDeviceFor(role, v);
          Navigator.of(context).pop();
        },
        child: ListView(
          children: [
            const RadioListTile<String?>(
              title: Text('Auto (first found)'),
              value: null,
            ),
            for (final r in _found.values)
              RadioListTile<String?>(
                title: Text(r.advertisementData.advName.isNotEmpty
                    ? r.advertisementData.advName
                    : '(unnamed)'),
                subtitle: Text('${r.device.remoteId.str}  ·  ${r.rssi} dBm'),
                value: r.device.remoteId.str,
              ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: Text('Scanning…', style: TextStyle(color: Colors.white38))),
            ),
          ],
        ),
      ),
    );
  }
}
