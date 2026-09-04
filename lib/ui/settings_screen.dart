// Settings: units, keep-screen-on, launch assist, and per-role device selection.
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
          const _SectionHeader('LAUNCH ASSIST'),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'LAUNCH turns on the controller\'s wheel-lift limiter from the moment the wheel '
              'starts turning, for this many seconds, then puts it back.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
          _SliderTile(
            title: 'Launch window',
            valueLabel: '${s.launchWindowS} s',
            value: s.launchWindowS,
            min: Settings.launchWindowMin,
            max: Settings.launchWindowMax,
            onChanged: (v) => setState(() => s.setLaunchWindowS(v)),
          ),
          SwitchListTile(
            title: const Text('Lower start angle during launch'),
            subtitle: const Text('Off = use the controller\'s current angle'),
            value: s.launchStartOverride,
            onChanged: (v) => setState(() => s.setLaunchStartOverride(v)),
          ),
          if (s.launchStartOverride)
            _SliderTile(
              title: 'Start angle',
              valueLabel: '${s.launchStartDeg}°',
              value: s.launchStartDeg,
              min: Settings.launchStartMin,
              max: Settings.launchStartMax,
              onChanged: (v) => setState(() => s.setLaunchStartDeg(v)),
            ),
          const Divider(),
          const _SectionHeader('DEVICES'),
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

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text,
            style: const TextStyle(color: Colors.white54, letterSpacing: 2, fontSize: 12)),
      );
}

/// A labelled whole-number slider: title and current value on one line, slider below.
class _SliderTile extends StatelessWidget {
  final String title, valueLabel;
  final int value, min, max;
  final void Function(int) onChanged;
  const _SliderTile({
    required this.title,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(title),
            trailing: Text(valueLabel,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          Slider(
            value: value.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: max - min,
            onChanged: (v) => onChanged(v.round()),
          ),
        ],
      );
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
