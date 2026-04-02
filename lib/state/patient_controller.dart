import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/patient_state.dart';
import '../models/risk_event.dart';
import '../models/sensor_packet.dart';
import '../services/ble_service.dart';

final bleServiceProvider = Provider<BleService>((ref) {
  final service = BleService();
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});

final patientControllerProvider =
    StateNotifierProvider<PatientController, PatientState>((ref) {
  return PatientController(ref.read(bleServiceProvider));
});

class PatientController extends StateNotifier<PatientState> {
  PatientController(this._bleService) : super(const PatientState.initial()) {
    _bootstrap();
  }

  static const Duration _fusionWindow = Duration(milliseconds: 1200);
  static const Duration _eventCooldown = Duration(seconds: 3);

  final BleService _bleService;
  StreamSubscription<SensorPacket>? _sensorSub;
  StreamSubscription<DeviceConnectionUpdate>? _connectionSub;
  final Map<DeviceSlot, DateTime?> _lastRiskSignalAt = {
    DeviceSlot.device1: null,
    DeviceSlot.device2: null,
  };
  DateTime? _lastFusedEventAt;

  Future<void> _bootstrap() async {
    _connectionSub =
        _bleService.connectionStream.listen(_handleConnectionUpdate);
    _sensorSub = _bleService.sensorStream.listen(_handleSensorPacket);
    await _bleService.start();
  }

  void _handleConnectionUpdate(DeviceConnectionUpdate update) {
    if (update.slot == DeviceSlot.device1) {
      state = state.copyWith(
        device1Connected: update.connected,
        device1Connecting: false,
        device1BatteryLevel: update.connected
            ? (() => state.device1BatteryLevel ?? _initialBattery())
            : (() => null),
      );
    } else {
      state = state.copyWith(
        device2Connected: update.connected,
        device2Connecting: false,
        device2BatteryLevel: update.connected
            ? (() => state.device2BatteryLevel ?? _initialBattery())
            : (() => null),
      );
    }
  }

  void _handleSensorPacket(SensorPacket packet) {
    final nextAcc = _appendSample(
      state.accelerometerSamples,
      SensorSample(
        timestamp: packet.timestamp,
        x: packet.accX,
        y: packet.accY,
        z: packet.accZ,
      ),
    );

    final nextGyro = _appendSample(
      state.gyroscopeSamples,
      SensorSample(
        timestamp: packet.timestamp,
        x: packet.gyroX,
        y: packet.gyroY,
        z: packet.gyroZ,
      ),
    );

    state = state.copyWith(
      accelerometerSamples: nextAcc,
      gyroscopeSamples: nextGyro,
      device1BatteryLevel: packet.slot == DeviceSlot.device1
          ? (() => _drainBattery(state.device1BatteryLevel))
          : null,
      device2BatteryLevel: packet.slot == DeviceSlot.device2
          ? (() => _drainBattery(state.device2BatteryLevel))
          : null,
    );

    final riskyDetected = packet.riskFlag || _thresholdRisk(packet);
    if (!riskyDetected) {
      return;
    }

    _lastRiskSignalAt[packet.slot] = packet.timestamp;

    if (!_isTwoSensorRiskConfirmed(packet.timestamp)) {
      return;
    }

    final nextCount = state.dailyEventCount + 1;
    final nextEvents = List<RiskEvent>.from(state.events)
      ..insert(
        0,
        RiskEvent(
          eventNumber: nextCount,
          timestamp: packet.timestamp,
          sourceDevice: 'Device 1 + Device 2',
        ),
      );

    _lastFusedEventAt = packet.timestamp;
    _lastRiskSignalAt[DeviceSlot.device1] = null;
    _lastRiskSignalAt[DeviceSlot.device2] = null;

    state = state.copyWith(
      dailyEventCount: nextCount,
      latestEventTimestamp: () => packet.timestamp,
      events: nextEvents,
      riskLevel: _riskLevelForCount(nextCount),
    );
  }

  bool _isTwoSensorRiskConfirmed(DateTime timestamp) {
    final risk1At = _lastRiskSignalAt[DeviceSlot.device1];
    final risk2At = _lastRiskSignalAt[DeviceSlot.device2];

    if (risk1At == null || risk2At == null) {
      return false;
    }

    final alignedInTime = risk1At.difference(risk2At).abs() <= _fusionWindow;
    if (!alignedInTime) {
      return false;
    }

    if (_lastFusedEventAt == null) {
      return true;
    }

    return timestamp.difference(_lastFusedEventAt!) >= _eventCooldown;
  }

  Future<void> connectSensor(DeviceSlot slot) async {
    if (slot == DeviceSlot.device1) {
      state = state.copyWith(device1Connecting: true);
    } else {
      state = state.copyWith(device2Connecting: true);
    }

    try {
      await _bleService.connectSlot(slot);
    } finally {
      if (slot == DeviceSlot.device1) {
        state = state.copyWith(device1Connecting: false);
      } else {
        state = state.copyWith(device2Connecting: false);
      }
    }
  }

  void setPatientName(String name) {
    if (name.trim().isEmpty) {
      return;
    }
    state = state.copyWith(patientName: name.trim());
  }

  bool _thresholdRisk(SensorPacket packet) {
    final accMagnitude = sqrt(
      packet.accX * packet.accX +
          packet.accY * packet.accY +
          packet.accZ * packet.accZ,
    );
    final gyroMagnitude = sqrt(
      packet.gyroX * packet.gyroX +
          packet.gyroY * packet.gyroY +
          packet.gyroZ * packet.gyroZ,
    );

    return accMagnitude > 2.7 || gyroMagnitude > 4.5;
  }

  RiskLevel _riskLevelForCount(int count) {
    if (count >= 6) {
      return RiskLevel.high;
    }
    if (count >= 3) {
      return RiskLevel.medium;
    }
    return RiskLevel.low;
  }

  List<SensorSample> _appendSample(
      List<SensorSample> current, SensorSample next) {
    const maxSamples = 40;
    final updated = List<SensorSample>.from(current)..add(next);
    if (updated.length > maxSamples) {
      return updated.sublist(updated.length - maxSamples);
    }
    return updated;
  }

  int _initialBattery() {
    return 75 + Random().nextInt(21);
  }

  int? _drainBattery(int? current) {
    if (current == null) {
      return null;
    }
    if (Random().nextInt(7) != 0) {
      return current;
    }
    return (current - 1).clamp(5, 100);
  }

  // Useful for testing alert flow manually from UI.
  void injectRiskEvent() {
    final now = DateTime.now();
    _handleSensorPacket(
      SensorPacket(
        slot: DeviceSlot.device1,
        deviceLabel: 'Device 1',
        timestamp: now,
        accX: 3.1,
        accY: 0.2,
        accZ: 0.8,
        gyroX: 5.0,
        gyroY: 0.4,
        gyroZ: 0.2,
        riskFlag: true,
      ),
    );

    _handleSensorPacket(
      SensorPacket(
        slot: DeviceSlot.device2,
        deviceLabel: 'Device 2',
        timestamp: now,
        accX: 3.0,
        accY: 0.1,
        accZ: 0.9,
        gyroX: 5.2,
        gyroY: 0.3,
        gyroZ: 0.2,
        riskFlag: true,
      ),
    );
  }

  @override
  void dispose() {
    _sensorSub?.cancel();
    _connectionSub?.cancel();
    super.dispose();
  }
}
