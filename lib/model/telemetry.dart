// Unified telemetry model — the single merged view of BMS + controller that the UI renders.

class BmsState {
  final double? soc; // 0..100 %
  final double? packV; // volts
  final double? current; // amps (+ discharge / - charge, per BMS convention)
  final double? cellMin; // volts
  final double? cellMax; // volts
  final double? tempC;
  final DateTime? updated;

  const BmsState({
    this.soc,
    this.packV,
    this.current,
    this.cellMin,
    this.cellMax,
    this.tempC,
    this.updated,
  });

  bool get fresh =>
      updated != null && DateTime.now().difference(updated!).inSeconds < 3;
}

class CtrlState {
  final int? erpm;
  final double? motorA; // motor current
  final double? inputA; // input (battery) current
  final double? duty; // 0..1
  final double? inputV; // volts
  final double? fetC; // MOSFET temp
  final double? motorC; // motor temp
  final String? mode; // "street" | "race"
  final String? gear; // 'R','N','1','2','3' — read from GET_VALUES_SELECTIVE bit 25
  final List<String> faults;
  final DateTime? updated;

  const CtrlState({
    this.erpm,
    this.motorA,
    this.inputA,
    this.duty,
    this.inputV,
    this.fetC,
    this.motorC,
    this.mode,
    this.gear,
    this.faults = const [],
    this.updated,
  });

  bool get fresh =>
      updated != null && DateTime.now().difference(updated!).inSeconds < 2;
}

/// The one object the dashboard listens to.
class Telemetry {
  BmsState bms;
  CtrlState ctrl;
  Telemetry({this.bms = const BmsState(), this.ctrl = const CtrlState()});
}
