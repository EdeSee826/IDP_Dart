import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/backend_service.dart';

class BackendStatusState {
  const BackendStatusState({
    required this.backendReady,
    required this.streamingActive,
    required this.connectedCount,
    required this.batteryVoltage,
    required this.batteryPercent,
    required this.batteryLastUpdated,
    required this.batteryConnected,
    required this.device1BatteryPercent,
    required this.device2BatteryPercent,
    required this.device1Connected,
    required this.device2Connected,
    this.device1StaticPassed,
    this.device2StaticPassed,
    this.calibrationPhase,
    this.calibrationMessage,
    this.calibrationRemainingSeconds,
    this.staticCalibrationPassed,
    this.functionalCalibrationPassed,
    this.isLoading = false,
    this.errorMessage,
    this.lastUpdated,
  });

  final bool backendReady;
  final bool streamingActive;
  final int connectedCount;
  final double? batteryVoltage;
  final int? batteryPercent;
  final DateTime? batteryLastUpdated;
  final bool batteryConnected;
  final int? device1BatteryPercent;
  final int? device2BatteryPercent;
  final bool device1Connected;
  final bool device2Connected;
  final bool? device1StaticPassed;
  final bool? device2StaticPassed;
  final String? calibrationPhase;
  final String? calibrationMessage;
  final int? calibrationRemainingSeconds;
  final bool? staticCalibrationPassed;
  final bool? functionalCalibrationPassed;
  final bool isLoading;
  final String? errorMessage;
  final DateTime? lastUpdated;

  const BackendStatusState.initial()
      : backendReady = false,
        streamingActive = false,
        connectedCount = 0,
        batteryVoltage = null,
        batteryPercent = null,
        batteryLastUpdated = null,
        batteryConnected = false,
        device1BatteryPercent = null,
        device2BatteryPercent = null,
        device1Connected = false,
        device2Connected = false,
        device1StaticPassed = null,
        device2StaticPassed = null,
        calibrationPhase = null,
        calibrationMessage = null,
        calibrationRemainingSeconds = null,
        staticCalibrationPassed = null,
        functionalCalibrationPassed = null,
        isLoading = false,
        errorMessage = null,
        lastUpdated = null;

  BackendStatusState copyWith({
    bool? backendReady,
    bool? streamingActive,
    int? connectedCount,
    ValueGetter<double?>? batteryVoltage,
    ValueGetter<int?>? batteryPercent,
    ValueGetter<DateTime?>? batteryLastUpdated,
    bool? batteryConnected,
    ValueGetter<int?>? device1BatteryPercent,
    ValueGetter<int?>? device2BatteryPercent,
    bool? device1Connected,
    bool? device2Connected,
    ValueGetter<bool?>? device1StaticPassed,
    ValueGetter<bool?>? device2StaticPassed,
    ValueGetter<String?>? calibrationPhase,
    ValueGetter<String?>? calibrationMessage,
    ValueGetter<int?>? calibrationRemainingSeconds,
    ValueGetter<bool?>? staticCalibrationPassed,
    ValueGetter<bool?>? functionalCalibrationPassed,
    bool? isLoading,
    ValueGetter<String?>? errorMessage,
    DateTime? lastUpdated,
  }) {
    return BackendStatusState(
      backendReady: backendReady ?? this.backendReady,
      streamingActive: streamingActive ?? this.streamingActive,
      connectedCount: connectedCount ?? this.connectedCount,
      batteryVoltage:
          batteryVoltage != null ? batteryVoltage() : this.batteryVoltage,
      batteryPercent:
          batteryPercent != null ? batteryPercent() : this.batteryPercent,
      batteryLastUpdated: batteryLastUpdated != null
          ? batteryLastUpdated()
          : this.batteryLastUpdated,
      batteryConnected: batteryConnected ?? this.batteryConnected,
      device1BatteryPercent: device1BatteryPercent != null
          ? device1BatteryPercent()
          : this.device1BatteryPercent,
      device2BatteryPercent: device2BatteryPercent != null
          ? device2BatteryPercent()
          : this.device2BatteryPercent,
      device1Connected: device1Connected ?? this.device1Connected,
      device2Connected: device2Connected ?? this.device2Connected,
      device1StaticPassed: device1StaticPassed != null
          ? device1StaticPassed()
          : this.device1StaticPassed,
      device2StaticPassed: device2StaticPassed != null
          ? device2StaticPassed()
          : this.device2StaticPassed,
      calibrationPhase:
          calibrationPhase != null ? calibrationPhase() : this.calibrationPhase,
      calibrationMessage: calibrationMessage != null
          ? calibrationMessage()
          : this.calibrationMessage,
      calibrationRemainingSeconds: calibrationRemainingSeconds != null
          ? calibrationRemainingSeconds()
          : this.calibrationRemainingSeconds,
      staticCalibrationPassed: staticCalibrationPassed != null
          ? staticCalibrationPassed()
          : this.staticCalibrationPassed,
      functionalCalibrationPassed: functionalCalibrationPassed != null
          ? functionalCalibrationPassed()
          : this.functionalCalibrationPassed,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}

final backendStatusProvider =
    StateNotifierProvider<BackendStatusController, BackendStatusState>((ref) {
  final controller = BackendStatusController();
  ref.onDispose(controller.dispose);
  return controller;
});

class BackendStatusController extends StateNotifier<BackendStatusState> {
  BackendStatusController() : super(const BackendStatusState.initial()) {
    _bootstrap();
  }

  static const Duration _pollInterval = Duration(seconds: 2);

  Timer? _timer;

  Future<void> _bootstrap() async {
    await refreshStatus();
    _timer = Timer.periodic(_pollInterval, (_) {
      refreshStatus();
    });
  }

  Future<void> refreshStatus() async {
    try {
      final runtimeStatus = await BackendService.fetchRuntimeStatus();
      state = state.copyWith(
        backendReady: runtimeStatus.backendReady,
        streamingActive: runtimeStatus.streamingActive,
        connectedCount: runtimeStatus.connectedCount,
        batteryVoltage: () => runtimeStatus.batteryVoltage,
        batteryPercent: () => runtimeStatus.batteryPercent,
        batteryLastUpdated: () => runtimeStatus.batteryLastUpdated,
        batteryConnected: runtimeStatus.batteryConnected,
        device1BatteryPercent: () =>
            runtimeStatus.battery?.sensor1BatteryPercent,
        device2BatteryPercent: () =>
            runtimeStatus.battery?.sensor2BatteryPercent,
        device1Connected: runtimeStatus.device1Connected,
        device2Connected: runtimeStatus.device2Connected,
        device1StaticPassed: () => runtimeStatus.device1StaticPassed,
        device2StaticPassed: () => runtimeStatus.device2StaticPassed,
        calibrationPhase: () => runtimeStatus.calibrationPhase,
        calibrationMessage: () => runtimeStatus.calibrationMessage,
        calibrationRemainingSeconds: () =>
            runtimeStatus.calibrationRemainingSeconds,
        staticCalibrationPassed: () => runtimeStatus.staticCalibrationPassed,
        functionalCalibrationPassed: () =>
            runtimeStatus.functionalCalibrationPassed,
        isLoading: false,
        errorMessage: () => runtimeStatus.errorMessage,
        lastUpdated: DateTime.now(),
      );
    } catch (e) {
      state = state.copyWith(
        backendReady: false,
        streamingActive: false,
        connectedCount: 0,
        batteryVoltage: () => null,
        batteryPercent: () => null,
        batteryLastUpdated: () => null,
        batteryConnected: false,
        device1BatteryPercent: () => null,
        device2BatteryPercent: () => null,
        device1Connected: false,
        device2Connected: false,
        calibrationRemainingSeconds: () => null,
        staticCalibrationPassed: () => null,
        functionalCalibrationPassed: () => null,
        isLoading: false,
        errorMessage: () => 'Failed to load backend status',
        lastUpdated: DateTime.now(),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
