import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/risk_event.dart';
import '../services/backend_service.dart';

final riskyEventsProvider = FutureProvider<List<RiskEvent>>((ref) async {
  final events = await BackendService.fetchTodayEvents();
  return events
      .map((e) => RiskEvent.fromBackend(
            id: e.id,
            eventType: e.eventType,
            timestamp: e.timestamp,
            riskLevel: e.riskLevel,
          ))
      .toList();
});

final riskyEventsRefreshProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    await Future.delayed(const Duration(milliseconds: 100));
    ref.invalidate(riskyEventsProvider);
  };
});
