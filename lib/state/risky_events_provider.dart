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

final riskyEventsLogProvider = FutureProvider<List<RiskEvent>>((ref) async {
  final events = await BackendService.fetchAllEvents();
  return events
      .map((e) => RiskEvent.fromBackend(
            id: e.id,
            eventType: e.eventType,
            timestamp: e.timestamp,
            riskLevel: e.riskLevel,
          ))
      .toList();
});

class GroupedRiskEvents {
  GroupedRiskEvents({
    required this.date,
    required this.label,
    required this.count,
    required this.events,
  });

  final DateTime date;
  final String label;
  final int count;
  final List<RiskEvent> events;
}

final riskyGroupedEventsProvider =
    FutureProvider<List<GroupedRiskEvents>>((ref) async {
  final grouped = await BackendService.fetchGroupedEvents();
  final mapped = <GroupedRiskEvents>[];

  for (final g in grouped) {
    final dateStr = g['date'] as String? ?? '';
    final label = g['label'] as String? ?? dateStr;
    final count = (g['count'] as int?) ?? 0;
    final rawEvents = (g['events'] as List<dynamic>?) ?? [];

    final events = rawEvents
        .map((e) => RiskEvent.fromBackend(
              id: e['id'] as int,
              eventType: e['event_type'] as String,
              timestamp: e['timestamp'] as String,
              riskLevel: e['risk_level'] as String,
            ))
        .toList();

    mapped.add(GroupedRiskEvents(
      date: DateTime.parse(dateStr),
      label: label,
      count: count,
      events: events,
    ));
  }

  return mapped;
});

final riskyEventsRefreshProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    await Future.delayed(const Duration(milliseconds: 100));
    ref.invalidate(riskyEventsProvider);
  };
});
