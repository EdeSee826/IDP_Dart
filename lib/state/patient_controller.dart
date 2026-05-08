import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/patient_state.dart';
import '../models/risk_event.dart';
import '../state/risky_events_provider.dart';

// Patient state is now managed independently from BLE
// All real-time monitoring comes from backend via REST API
final patientControllerProvider =
    StateNotifierProvider<PatientController, PatientState>((ref) {
  return PatientController();
});

/// Derived provider that automatically updates patient state when risky events change
final patientStateWithEventsProvider = Provider<PatientState>((ref) {
  final controller = ref.watch(patientControllerProvider.notifier);
  final eventsAsync = ref.watch(riskyEventsProvider);

  // Update controller when events change
  eventsAsync.whenData((events) {
    controller.updateFromBackendEvents(events);
  });

  return ref.watch(patientControllerProvider);
});

class PatientController extends StateNotifier<PatientState> {
  PatientController() : super(PatientState.initial()) {
    _bootstrap();
  }

  static const Duration _careRefreshInterval = Duration(minutes: 5);
  Timer? _careTimer;

  Future<void> _bootstrap() async {
    _initializeCareSchedule();
    _syncDailyChecklist();
    _careTimer = Timer.periodic(_careRefreshInterval, (_) {
      _syncDailyChecklist();
    });
  }

  void _initializeCareSchedule() {
    if (state.lastFlushAt != null &&
        state.lastMedicationAt != null &&
        state.lastDressingChangeAt != null) {
      return;
    }

    final now = DateTime.now();
    state = state.copyWith(
      checklistDate: () => DateTime(now.year, now.month, now.day),
      lastFlushAt: () => now.subtract(const Duration(hours: 20)),
      lastMedicationAt: () => now.subtract(const Duration(hours: 10)),
      lastDressingChangeAt: () => now.subtract(const Duration(days: 6)),
    );
  }

  void _syncDailyChecklist() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (_isSameDay(state.checklistDate, today)) {
      return;
    }

    final hasPreviousChecklist =
        state.checklistDate.millisecondsSinceEpoch != 0;

    final nextFlushMissedCount =
        hasPreviousChecklist && !state.flushingCompleted
            ? state.flushMissedCount + 1
            : state.flushMissedCount;
    final nextMedicationMissedCount =
        hasPreviousChecklist && !state.medicationTimingCompleted
            ? state.medicationMissedCount + 1
            : state.medicationMissedCount;
    final nextDressingMissedCount =
        hasPreviousChecklist && !state.dressingConditionChecked
            ? state.dressingMissedCount + 1
            : state.dressingMissedCount;

    state = state.copyWith(
      checklistDate: () => today,
      symptomsChecked: false,
      dressingConditionChecked: false,
      flushingCompleted: false,
      drynessChecked: false,
      medicationTimingCompleted: false,
      catheterLengthChecked: false,
      movementPrecautionsChecked: false,
      lineSecuredChecked: false,
      dressingChangedToday: false,
      flushMissedCount: nextFlushMissedCount,
      medicationMissedCount: nextMedicationMissedCount,
      dressingMissedCount: nextDressingMissedCount,
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Update patient state from backend events
  void updateFromBackendEvents(List<RiskEvent> events) {
    if (events.isEmpty) {
      state = state.copyWith(
        dailyEventCount: 0,
        latestEventTimestamp: () => null,
        riskLevel: RiskLevel.low,
      );
      return;
    }

    // Sort by timestamp descending to get latest first
    final sortedEvents = [...events]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final latestEvent = sortedEvents.first;

    // Calculate risk level based on total risky events
    final RiskLevel newRiskLevel;
    final totalEvents = events.length;
    if (totalEvents > 50) {
      newRiskLevel = RiskLevel.high;
    } else if (totalEvents > 20) {
      newRiskLevel = RiskLevel.medium;
    } else {
      newRiskLevel = RiskLevel.low;
    }

    state = state.copyWith(
      dailyEventCount: events.length,
      latestEventTimestamp: () => latestEvent.timestamp,
      riskLevel: newRiskLevel,
      events: events,
    );
  }

  /// Patient care checklist management

  /// Temporarily mark both sensors as connected (used by onboarding mock flow).
  /// This does not touch any BLE layer and is safe when backend manages device state.
  void setMockSensorsConnected() {
    state = state.copyWith(
      device1Connected: true,
      device2Connected: true,
      device1BatteryLevel: () => state.device1BatteryLevel ?? 80,
      device2BatteryLevel: () => state.device2BatteryLevel ?? 80,
    );
  }
  void setPatientName(String name) {
    if (name.trim().isEmpty) {
      return;
    }
    state = state.copyWith(patientName: name.trim());
  }

  void setSymptomsChecked(bool value) {
    state = state.copyWith(symptomsChecked: value);
  }

  void setFlushingCompleted(bool value) {
    state = state.copyWith(
      flushingCompleted: value,
      lastFlushAt: value ? () => DateTime.now() : null,
    );
  }

  void setDressingConditionChecked(bool value) {
    state = state.copyWith(dressingConditionChecked: value);
  }

  void setDrynessChecked(bool value) {
    state = state.copyWith(drynessChecked: value);
  }

  void setMedicationTimingCompleted(bool value) {
    state = state.copyWith(
      medicationTimingCompleted: value,
      lastMedicationAt: value ? () => DateTime.now() : null,
    );
  }

  void setDressingChangedToday(bool value) {
    state = state.copyWith(
      dressingChangedToday: value,
      lastDressingChangeAt: value ? () => DateTime.now() : null,
    );
  }

  void setAppointmentDate(DateTime? date) {
    state = state.copyWith(
      nextAppointmentDate: () => date,
    );
  }

  void setAppointmentDetails({
    required DateTime date,
    String? location,
  }) {
    final cleanLocation = location?.trim();
    state = state.copyWith(
      nextAppointmentDate: () => date,
      appointmentLocation: () =>
          cleanLocation == null || cleanLocation.isEmpty ? null : cleanLocation,
    );
  }

  void setLastDressingChangeDate(DateTime? date) {
    state = state.copyWith(
      lastDressingChangeAt: () => date,
      dressingChangedToday:
          _isSameDay(date ?? DateTime(1970, 1, 1), DateTime.now()),
    );
  }

  void setCatheterLengthChecked(bool value) {
    state = state.copyWith(catheterLengthChecked: value);
  }

  void setMovementPrecautionsChecked(bool value) {
    state = state.copyWith(movementPrecautionsChecked: value);
  }

  void setLineSecuredChecked(bool value) {
    state = state.copyWith(lineSecuredChecked: value);
  }

  @override
  void dispose() {
    _careTimer?.cancel();
    super.dispose();
  }
}
