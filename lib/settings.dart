// User settings: persisted with shared_preferences, exposed as a ChangeNotifier.
// Covers units (metric/imperial), keep-screen-on, launch assist, and per-role device selection.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Settings extends ChangeNotifier {
  bool imperial = false; // false = °C / km-h ; true = °F / mph
  bool keepScreenOn = false;

  // Launch assist: how long the wheel-lift limiter stays on after the wheel starts turning,
  // and an optional lower start angle for that window only.
  static const int launchWindowMin = 2, launchWindowMax = 15;
  static const int launchStartMin = 5, launchStartMax = 30;
  int launchWindowS = 5;
  bool launchStartOverride = false;
  int launchStartDeg = 12;

  // roleId (from device_profiles) -> chosen device remoteId. null / missing = auto (first match).
  final Map<String, String> _devices = {};

  SharedPreferences? _p;

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    imperial = _p!.getBool('imperial') ?? false;
    keepScreenOn = _p!.getBool('keepScreenOn') ?? false;
    launchWindowS = (_p!.getInt('launchWindowS') ?? 5).clamp(launchWindowMin, launchWindowMax);
    launchStartOverride = _p!.getBool('launchStartOverride') ?? false;
    launchStartDeg = (_p!.getInt('launchStartDeg') ?? 12).clamp(launchStartMin, launchStartMax);
    for (final k in _p!.getKeys()) {
      if (k.startsWith('dev.')) {
        final v = _p!.getString(k);
        if (v != null) _devices[k.substring(4)] = v;
      }
    }
    notifyListeners();
  }

  void setImperial(bool v) {
    imperial = v;
    _p?.setBool('imperial', v);
    notifyListeners();
  }

  void setKeepScreenOn(bool v) {
    keepScreenOn = v;
    _p?.setBool('keepScreenOn', v);
    notifyListeners();
  }

  void setLaunchWindowS(int v) {
    launchWindowS = v.clamp(launchWindowMin, launchWindowMax);
    _p?.setInt('launchWindowS', launchWindowS);
    notifyListeners();
  }

  void setLaunchStartOverride(bool v) {
    launchStartOverride = v;
    _p?.setBool('launchStartOverride', v);
    notifyListeners();
  }

  void setLaunchStartDeg(int v) {
    launchStartDeg = v.clamp(launchStartMin, launchStartMax);
    _p?.setInt('launchStartDeg', launchStartDeg);
    notifyListeners();
  }

  /// The chosen device remoteId for a role, or null for auto.
  String? deviceFor(String role) => _devices[role];

  void setDeviceFor(String role, String? remoteId) {
    if (remoteId == null) {
      _devices.remove(role);
      _p?.remove('dev.$role');
    } else {
      _devices[role] = remoteId;
      _p?.setString('dev.$role', remoteId);
    }
    notifyListeners();
  }

  // --- unit conversion helpers (UI-facing) ---
  String get tempUnit => imperial ? '°F' : '°C';
  String get speedUnit => imperial ? 'MPH' : 'KM/H';

  /// Format a Celsius value in the chosen unit (no decimals).
  String temp(double? c) {
    if (c == null) return '--';
    final v = imperial ? c * 9 / 5 + 32 : c;
    return '${v.round()}';
  }

  /// Convert a km/h value to the chosen unit.
  double? speed(double? kmh) {
    if (kmh == null) return null;
    return imperial ? kmh * 0.621371 : kmh;
  }
}
