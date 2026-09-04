// Launch assist state machine — pure Dart with a fake controller link and fake time.

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:x7/ble/vesc_client.dart';
import 'package:x7/launch_assist.dart';
import 'package:x7/model/telemetry.dart';
import 'package:x7/settings.dart';

class FakePort implements LimiterPort {
  @override
  bool connected = true;
  final List<String> sent = [];
  @override
  Future<bool> setLimiter(bool on) async {
    sent.add(on ? 'on' : 'off');
    return connected;
  }

  @override
  Future<bool> setLimiterStart(String deg) async {
    sent.add('start $deg');
    return connected;
  }
}

CtrlState ctrl(
        {bool? on = false,
        bool? running = true,
        String? start = '20.00',
        int erpm = 0}) =>
    CtrlState(
      erpm: erpm,
      limiterOn: on,
      limiterRunning: running,
      limiterStart: start,
      updated: DateTime.now(),
    );

void main() {
  late FakePort port;
  late Settings settings;
  late List<String> toasts;
  late LaunchAssist la;

  setUp(() {
    port = FakePort();
    settings = Settings(); // not loaded: plain defaults, no shared_preferences
    toasts = [];
    la = LaunchAssist(port: port, settings: settings, notify: toasts.add);
  });

  // Tap, let the async arm run, then feed the controller's confirmation.
  void arm(FakeAsync fa,
      {bool? on = false, String? start = '20.00', String? confirmStart}) {
    la.onTelemetry(ctrl(on: on, start: start));
    la.toggle();
    fa.flushMicrotasks();
    la.onTelemetry(ctrl(on: true, start: confirmStart ?? start));
  }

  test('arm sends on, waits for confirmation, then armed', () {
    fakeAsync((fa) {
      la.onTelemetry(ctrl());
      la.toggle();
      fa.flushMicrotasks();
      expect(port.sent, ['on']);
      expect(la.phase, LaunchPhase.arming);
      la.onTelemetry(ctrl(on: true));
      expect(la.phase, LaunchPhase.armed);
    });
  });

  test('no confirmation within 2 s: sends off and returns to idle', () {
    fakeAsync((fa) {
      la.onTelemetry(ctrl());
      la.toggle();
      fa.flushMicrotasks();
      fa.elapse(const Duration(seconds: 3));
      expect(la.phase, LaunchPhase.idle);
      expect(port.sent, ['on', 'off']);
      expect(toasts.last, contains('No confirmation'));
    });
  });

  test('refuses when the limiter state is not known or not running', () {
    fakeAsync((fa) {
      la.onTelemetry(ctrl(on: null));
      la.toggle();
      fa.flushMicrotasks();
      expect(la.phase, LaunchPhase.idle);
      expect(port.sent, isEmpty);

      la.onTelemetry(ctrl(running: false));
      la.toggle();
      fa.flushMicrotasks();
      expect(la.phase, LaunchPhase.idle);
      expect(port.sent, isEmpty);
      expect(toasts.length, 2);
    });
  });

  test(
      'stays armed at standstill, starts the window on motion, then restores off',
      () {
    fakeAsync((fa) {
      arm(fa);
      for (final e in [0, 100, 400]) {
        la.onTelemetry(ctrl(on: true, erpm: e));
        expect(la.phase, LaunchPhase.armed);
      }
      fa.elapse(const Duration(seconds: 30)); // armed waits indefinitely
      expect(la.phase, LaunchPhase.armed);

      la.onTelemetry(ctrl(on: true, erpm: 600));
      expect(la.phase, LaunchPhase.active);
      expect(la.secondsLeft, 5);
      fa.elapse(const Duration(seconds: 2));
      expect(la.secondsLeft, 3);
      fa.elapse(const Duration(seconds: 3));
      fa.flushMicrotasks();
      expect(la.phase, LaunchPhase.idle);
      expect(port.sent, ['on', 'off']);
      expect(toasts.last, contains('limiter off'));
    });
  });

  test('limiter already on before the tap: left on at the end', () {
    fakeAsync((fa) {
      settings.launchStartOverride =
          true; // otherwise arming would be redundant
      settings.launchStartDeg = 12;
      arm(fa, on: true, confirmStart: '12.00');
      expect(la.phase, LaunchPhase.armed);
      la.onTelemetry(ctrl(on: true, erpm: 900, start: '12.00'));
      fa.elapse(const Duration(seconds: 5));
      fa.flushMicrotasks();
      expect(port.sent, ['on', 'start 12', 'start 20.00']);
      expect(toasts.last, contains('left on'));
    });
  });

  test('start-angle override: sent on arm, previous value restored after', () {
    fakeAsync((fa) {
      settings.launchStartOverride = true;
      settings.launchStartDeg = 12;
      arm(fa, confirmStart: '12.00');
      expect(la.phase, LaunchPhase.armed);
      la.onTelemetry(ctrl(on: true, erpm: 900, start: '12.00'));
      fa.elapse(const Duration(seconds: 5));
      fa.flushMicrotasks();
      expect(port.sent, ['on', 'start 12', 'off', 'start 20.00']);
    });
  });

  test('override equal to the current angle sends no start command', () {
    fakeAsync((fa) {
      settings.launchStartOverride = true;
      settings.launchStartDeg = 20;
      arm(fa);
      expect(la.phase, LaunchPhase.armed);
      expect(port.sent, ['on']);
    });
  });

  test('cancel from armed and from active both restore', () {
    fakeAsync((fa) {
      arm(fa);
      la.toggle();
      fa.flushMicrotasks();
      expect(la.phase, LaunchPhase.idle);
      expect(port.sent, ['on', 'off']);

      port.sent.clear();
      arm(fa);
      la.onTelemetry(ctrl(on: true, erpm: 900));
      expect(la.phase, LaunchPhase.active);
      la.toggle();
      fa.flushMicrotasks();
      expect(la.phase, LaunchPhase.idle);
      expect(port.sent, ['on', 'off']);
      fa.elapse(const Duration(seconds: 10)); // window timer must be dead
      expect(port.sent, ['on', 'off']);
    });
  });

  test('tap while arming is ignored', () {
    fakeAsync((fa) {
      la.onTelemetry(ctrl());
      la.toggle();
      fa.flushMicrotasks();
      la.toggle();
      fa.flushMicrotasks();
      expect(la.phase, LaunchPhase.arming);
      expect(port.sent, ['on']);
    });
  });

  test('background cancels an armed launch but lets a running window finish',
      () {
    fakeAsync((fa) {
      arm(fa);
      la.onBackground();
      fa.flushMicrotasks();
      expect(la.phase, LaunchPhase.idle);
      expect(port.sent, ['on', 'off']);

      port.sent.clear();
      arm(fa);
      la.onTelemetry(ctrl(on: true, erpm: 900));
      la.onBackground();
      fa.flushMicrotasks();
      expect(la.phase, LaunchPhase.active);
      fa.elapse(const Duration(seconds: 5));
      fa.flushMicrotasks();
      expect(port.sent, ['on', 'off']);
    });
  });

  test('link lost mid-window: idle, nothing sent, limiter reported as left on',
      () {
    fakeAsync((fa) {
      arm(fa);
      la.onTelemetry(ctrl(on: true, erpm: 900));
      port.connected = false;
      fa.elapse(const Duration(seconds: 1));
      expect(la.phase, LaunchPhase.idle);
      expect(port.sent, ['on']);
      expect(toasts.last, contains('stays on'));
      fa.elapse(const Duration(seconds: 10));
      expect(port.sent, ['on']); // window timer was cancelled too
    });
  });

  test('redundant when the limiter is already on and no override is set', () {
    la.onTelemetry(ctrl(on: true));
    expect(la.redundant, true);
    settings.launchStartOverride = true;
    expect(la.redundant, false);
  });
}
