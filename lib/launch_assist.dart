// Launch assist: turn the controller's wheel-lift limiter on for one launch.
//
// Tap = arm (limiter on). The window starts when the wheel begins to turn, runs for the
// number of seconds set in Settings, then puts the limiter back the way it was found.
// Runs on stock firmware: it only sends terminal commands the controller already accepts.
//
// Phases:
//   idle -> arming -> armed -> active -> restoring -> idle
// Arming waits for the controller to confirm "on" (read back in CtrlState). Cancel from
// armed/active goes through restoring. If the link is lost the limiter is left as-is: it
// then stays on until reconnect or power cycle, which is the low-power (safe) side.

import 'dart:async';
import 'package:flutter/foundation.dart';

import 'ble/vesc_client.dart';
import 'model/telemetry.dart';
import 'settings.dart';

enum LaunchPhase { idle, arming, armed, active, restoring }

class LaunchAssist extends ChangeNotifier {
  /// Wheel counts as turning above this motor speed (ERPM) or road speed (m/s).
  static const int moveErpm = 500;
  static const double moveSpeedMs = 0.5;
  static const Duration confirmTimeout = Duration(seconds: 2);
  static const Duration linkCheck = Duration(milliseconds: 500);

  final LimiterPort port;
  final Settings settings;
  final void Function(String msg) notify;

  LaunchAssist(
      {required this.port, required this.settings, required this.notify});

  LaunchPhase _phase = LaunchPhase.idle;
  CtrlState _ctrl = const CtrlState();

  // what the limiter looked like before we touched it
  bool _wasOn = false;
  String? _prevStart;
  bool _changedStart = false;
  String? _wantStart; // start angle we sent, waiting for the echo

  int _windowS = 5;
  int? _secondsLeft;
  Timer? _window, _confirm, _link;

  LaunchPhase get phase => _phase;
  int get windowS => _windowS;

  /// Whole seconds left in the window, or null when no window is running.
  int? get secondsLeft => _phase == LaunchPhase.active ? _secondsLeft : null;

  /// True when the limiter is already on and arming would change nothing.
  bool get redundant =>
      _phase == LaunchPhase.idle &&
      _ctrl.limiterOn == true &&
      !settings.launchStartOverride;

  /// Button tap: arm when idle, cancel when armed or active.
  Future<void> toggle() async {
    switch (_phase) {
      case LaunchPhase.idle:
        await _arm();
      case LaunchPhase.armed:
      case LaunchPhase.active:
        await cancel('Launch cancelled');
      case LaunchPhase.arming:
      case LaunchPhase.restoring:
        break; // busy, ignore the tap
    }
  }

  /// Feed every controller state update here (motion + confirmation come from it).
  void onTelemetry(CtrlState s) {
    _ctrl = s;
    switch (_phase) {
      case LaunchPhase.arming:
        final onOk = s.limiterOn == true;
        final startOk =
            _wantStart == null || _matches(s.limiterStart, _wantStart!);
        if (onOk && startOk) _armed();
      case LaunchPhase.armed:
        if (_moving(s)) _startWindow();
      default:
        break;
    }
  }

  /// Called when the app leaves the foreground. Only an armed launch is dropped; a running
  /// window is left to finish on its own timer.
  void onBackground() {
    if (_phase == LaunchPhase.armed) {
      cancel('Launch cancelled (app in background)');
    }
  }

  Future<void> cancel(String reason) async {
    if (_phase != LaunchPhase.armed && _phase != LaunchPhase.active) return;
    _window?.cancel();
    await _restore(reason);
  }

  @override
  void dispose() {
    _window?.cancel();
    _confirm?.cancel();
    _link?.cancel();
    if (_phase == LaunchPhase.armed || _phase == LaunchPhase.active) {
      _sendRestore(); // best effort, not awaited
    }
    super.dispose();
  }

  // --- internals ---

  Future<void> _arm() async {
    if (!port.connected || !_ctrl.fresh) {
      notify('Controller not connected');
      return;
    }
    if (_ctrl.limiterOn == null) {
      notify('Limiter state not read yet, try again');
      return;
    }
    if (_ctrl.limiterRunning == false) {
      notify('Limiter not running on controller');
      return;
    }
    _wasOn = _ctrl.limiterOn!;
    _prevStart = _ctrl.limiterStart;
    _changedStart = false;
    _wantStart = null;
    _windowS = settings.launchWindowS;
    _set(LaunchPhase.arming);

    if (!await port.setLimiter(true)) return _fail('Controller not connected');
    if (settings.launchStartOverride) {
      final deg = settings.launchStartDeg.toString();
      if (_prevStart == null || !_matches(_prevStart, deg)) {
        if (!await port.setLimiterStart(deg)) {
          return _fail('Controller not connected');
        }
        _wantStart = deg;
        _changedStart = true;
      }
    }
    _startLinkWatch();
    _confirm = Timer(confirmTimeout, () {
      if (_phase == LaunchPhase.arming) {
        _fail('No confirmation from controller');
      }
    });
  }

  void _armed() {
    _confirm?.cancel();
    _set(LaunchPhase.armed);
    notify('Launch armed, roll to start');
  }

  Future<void> _fail(String msg) async {
    _confirm?.cancel();
    _stopLinkWatch();
    if (_phase == LaunchPhase.arming) await _sendRestore();
    _set(LaunchPhase.idle);
    notify(msg);
  }

  void _startWindow() {
    _secondsLeft = _windowS;
    _window = Timer.periodic(const Duration(seconds: 1), (t) {
      _secondsLeft = (_secondsLeft ?? 1) - 1;
      if (_secondsLeft! <= 0) {
        t.cancel();
        _restore('Launch window over');
      } else {
        notifyListeners();
      }
    });
    _set(LaunchPhase.active);
  }

  Future<void> _restore(String reason) async {
    _stopLinkWatch();
    _secondsLeft = null;
    _set(LaunchPhase.restoring);
    final ok = await _sendRestore();
    _set(LaunchPhase.idle);
    if (!ok) {
      notify('$reason. Controller lost, limiter stays on until power cycle');
    } else if (_wasOn) {
      notify('$reason, limiter left on');
    } else {
      notify('$reason, limiter off');
    }
  }

  /// Put the limiter back: off if it was off, previous start angle if we changed it.
  Future<bool> _sendRestore() async {
    var ok = true;
    if (!_wasOn) ok = await port.setLimiter(false) && ok;
    if (_changedStart && _prevStart != null) {
      ok = await port.setLimiterStart(_prevStart!) && ok;
    }
    _changedStart = false;
    return ok;
  }

  void _startLinkWatch() {
    _link?.cancel();
    _link = Timer.periodic(linkCheck, (_) {
      if (port.connected) return;
      _link?.cancel();
      _window?.cancel();
      _confirm?.cancel();
      _secondsLeft = null;
      _set(LaunchPhase.idle);
      notify('Controller lost, limiter stays on until power cycle');
    });
  }

  void _stopLinkWatch() {
    _link?.cancel();
    _link = null;
  }

  static bool _moving(CtrlState s) =>
      (s.erpm ?? 0).abs() > moveErpm || (s.speedMs ?? 0).abs() > moveSpeedMs;

  // "12" and "12.00" are the same angle
  static bool _matches(String? printed, String wanted) {
    final a = double.tryParse(printed ?? '');
    final b = double.tryParse(wanted);
    return a != null && b != null && (a - b).abs() < 0.01;
  }

  void _set(LaunchPhase p) {
    _phase = p;
    notifyListeners();
  }
}
