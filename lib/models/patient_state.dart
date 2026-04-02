import 'package:flutter/material.dart';

import 'risk_event.dart';

enum RiskLevel { low, medium, high }

class SensorSample {
  const SensorSample({
    required this.timestamp,
    required this.x,
    required this.y,
    required this.z,
  });

  final DateTime timestamp;
  final double x;
  final double y;
  final double z;
}

class PatientState {
  const PatientState({
    required this.patientName,
    required this.dailyEventCount,
    required this.latestEventTimestamp,
    required this.riskLevel,
    required this.device1Connected,
    required this.device2Connected,
    required this.device1BatteryLevel,
    required this.device2BatteryLevel,
    required this.device1Connecting,
    required this.device2Connecting,
    required this.events,
    required this.accelerometerSamples,
    required this.gyroscopeSamples,
  });

  final String patientName;
  final int dailyEventCount;
  final DateTime? latestEventTimestamp;
  final RiskLevel riskLevel;
  final bool device1Connected;
  final bool device2Connected;
  final int? device1BatteryLevel;
  final int? device2BatteryLevel;
  final bool device1Connecting;
  final bool device2Connecting;
  final List<RiskEvent> events;
  final List<SensorSample> accelerometerSamples;
  final List<SensorSample> gyroscopeSamples;

  const PatientState.initial()
      : patientName = 'James',
        dailyEventCount = 0,
        latestEventTimestamp = null,
        riskLevel = RiskLevel.low,
        device1Connected = false,
        device2Connected = false,
        device1BatteryLevel = null,
        device2BatteryLevel = null,
        device1Connecting = false,
        device2Connecting = false,
        events = const [],
        accelerometerSamples = const [],
        gyroscopeSamples = const [];

  PatientState copyWith({
    String? patientName,
    int? dailyEventCount,
    ValueGetter<DateTime?>? latestEventTimestamp,
    RiskLevel? riskLevel,
    bool? device1Connected,
    bool? device2Connected,
    ValueGetter<int?>? device1BatteryLevel,
    ValueGetter<int?>? device2BatteryLevel,
    bool? device1Connecting,
    bool? device2Connecting,
    List<RiskEvent>? events,
    List<SensorSample>? accelerometerSamples,
    List<SensorSample>? gyroscopeSamples,
  }) {
    return PatientState(
      patientName: patientName ?? this.patientName,
      dailyEventCount: dailyEventCount ?? this.dailyEventCount,
      latestEventTimestamp: latestEventTimestamp != null
          ? latestEventTimestamp()
          : this.latestEventTimestamp,
      riskLevel: riskLevel ?? this.riskLevel,
      device1Connected: device1Connected ?? this.device1Connected,
      device2Connected: device2Connected ?? this.device2Connected,
      device1BatteryLevel: device1BatteryLevel != null
          ? device1BatteryLevel()
          : this.device1BatteryLevel,
      device2BatteryLevel: device2BatteryLevel != null
          ? device2BatteryLevel()
          : this.device2BatteryLevel,
      device1Connecting: device1Connecting ?? this.device1Connecting,
      device2Connecting: device2Connecting ?? this.device2Connecting,
      events: events ?? this.events,
      accelerometerSamples: accelerometerSamples ?? this.accelerometerSamples,
      gyroscopeSamples: gyroscopeSamples ?? this.gyroscopeSamples,
    );
  }
}
