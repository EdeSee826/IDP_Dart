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
    required this.symptomsChecked,
    required this.flushingCompleted,
    required this.catheterLengthChecked,
    required this.movementPrecautionsChecked,
    required this.lineSecuredChecked,
    required this.dressingConditionChecked,
    required this.drynessChecked,
    required this.medicationTimingCompleted,
    required this.dressingChangedToday,
    required this.checklistDate,
    required this.lastFlushAt,
    required this.lastMedicationAt,
    required this.nextAppointmentDate,
    required this.appointmentLocation,
    required this.lastDressingChangeAt,
    required this.flushMissedCount,
    required this.medicationMissedCount,
    required this.dressingMissedCount,
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
  final bool symptomsChecked;
  final bool flushingCompleted;
  final bool catheterLengthChecked;
  final bool movementPrecautionsChecked;
  final bool lineSecuredChecked;
  final bool dressingConditionChecked;
  final bool drynessChecked;
  final bool medicationTimingCompleted;
  final bool dressingChangedToday;
  final DateTime checklistDate;
  final DateTime? lastFlushAt;
  final DateTime? lastMedicationAt;
  final DateTime? nextAppointmentDate;
  final String? appointmentLocation;
  final DateTime? lastDressingChangeAt;
  final int flushMissedCount;
  final int medicationMissedCount;
  final int dressingMissedCount;
  final List<RiskEvent> events;
  final List<SensorSample> accelerometerSamples;
  final List<SensorSample> gyroscopeSamples;

  PatientState.initial()
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
        symptomsChecked = false,
        flushingCompleted = false,
        catheterLengthChecked = false,
        movementPrecautionsChecked = false,
        lineSecuredChecked = false,
        dressingConditionChecked = false,
        drynessChecked = false,
        medicationTimingCompleted = false,
        dressingChangedToday = false,
        checklistDate = DateTime(1970, 1, 1),
        lastFlushAt = null,
        lastMedicationAt = null,
        nextAppointmentDate = null,
        appointmentLocation = null,
        lastDressingChangeAt = null,
        flushMissedCount = 0,
        medicationMissedCount = 0,
        dressingMissedCount = 0,
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
    bool? symptomsChecked,
    bool? flushingCompleted,
    bool? catheterLengthChecked,
    bool? movementPrecautionsChecked,
    bool? lineSecuredChecked,
    bool? dressingConditionChecked,
    bool? drynessChecked,
    bool? medicationTimingCompleted,
    bool? dressingChangedToday,
    ValueGetter<DateTime>? checklistDate,
    ValueGetter<DateTime?>? lastFlushAt,
    ValueGetter<DateTime?>? lastMedicationAt,
    ValueGetter<DateTime?>? nextAppointmentDate,
    ValueGetter<String?>? appointmentLocation,
    ValueGetter<DateTime?>? lastDressingChangeAt,
    int? flushMissedCount,
    int? medicationMissedCount,
    int? dressingMissedCount,
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
      symptomsChecked: symptomsChecked ?? this.symptomsChecked,
      flushingCompleted: flushingCompleted ?? this.flushingCompleted,
      catheterLengthChecked:
          catheterLengthChecked ?? this.catheterLengthChecked,
      movementPrecautionsChecked:
          movementPrecautionsChecked ?? this.movementPrecautionsChecked,
      lineSecuredChecked: lineSecuredChecked ?? this.lineSecuredChecked,
      dressingConditionChecked:
          dressingConditionChecked ?? this.dressingConditionChecked,
      drynessChecked: drynessChecked ?? this.drynessChecked,
      medicationTimingCompleted:
          medicationTimingCompleted ?? this.medicationTimingCompleted,
      dressingChangedToday: dressingChangedToday ?? this.dressingChangedToday,
      checklistDate:
          checklistDate != null ? checklistDate() : this.checklistDate,
      lastFlushAt: lastFlushAt != null ? lastFlushAt() : this.lastFlushAt,
      lastMedicationAt:
          lastMedicationAt != null ? lastMedicationAt() : this.lastMedicationAt,
      nextAppointmentDate: nextAppointmentDate != null
          ? nextAppointmentDate()
          : this.nextAppointmentDate,
        appointmentLocation: appointmentLocation != null
          ? appointmentLocation()
          : this.appointmentLocation,
      lastDressingChangeAt: lastDressingChangeAt != null
          ? lastDressingChangeAt()
          : this.lastDressingChangeAt,
      flushMissedCount: flushMissedCount ?? this.flushMissedCount,
      medicationMissedCount:
          medicationMissedCount ?? this.medicationMissedCount,
      dressingMissedCount: dressingMissedCount ?? this.dressingMissedCount,
      events: events ?? this.events,
      accelerometerSamples: accelerometerSamples ?? this.accelerometerSamples,
      gyroscopeSamples: gyroscopeSamples ?? this.gyroscopeSamples,
    );
  }
}
