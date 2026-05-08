import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/backend_service.dart';

class BackendStatusState {
  const BackendStatusState({
    required this.backendReady,
    required this.streamingActive,
    required this.connectedCount,
    required this.device1Connected,
    required this.device2Connected,
    this.isLoading = false,
    this.errorMessage,
    this.lastUpdated,
  });

  final bool backendReady;
  final bool streamingActive;
  final int connectedCount;
  final bool device1Connected;
  final bool device2Connected;
  final bool isLoading;
  final String? errorMessage;
  final DateTime? lastUpdated;

  const BackendStatusState.initial()
      : backendReady = false,
        streamingActive = false,
        connectedCount = 0,
        device1Connected = false,
        device2Connected = false,
        isLoading = false,
        errorMessage = null,
        lastUpdated = null;

  BackendStatusState copyWith({
    bool? backendReady,
    bool? streamingActive,
    int? connectedCount,
    bool? device1Connected,
    bool? device2Connected,
    bool? isLoading,
    String? errorMessage,
    DateTime? lastUpdated,
  }) {
    return BackendStatusState(
      backendReady: backendReady ?? this.backendReady,
      streamingActive: streamingActive ?? this.streamingActive,
      connectedCount: connectedCount ?? this.connectedCount,
      device1Connected: device1Connected ?? this.device1Connected,
      device2Connected: device2Connected ?? this.device2Connected,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
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
        device1Connected: runtimeStatus.device1Connected,
        device2Connected: runtimeStatus.device2Connected,
        isLoading: false,
        errorMessage: runtimeStatus.errorMessage,
        lastUpdated: DateTime.now(),
      );
    } catch (e) {
      state = state.copyWith(
        backendReady: false,
        streamingActive: false,
        connectedCount: 0,
        device1Connected: false,
        device2Connected: false,
        isLoading: false,
        errorMessage: 'Failed to load backend status',
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
