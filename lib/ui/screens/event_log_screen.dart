import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/risk_event.dart';
import '../../state/risky_events_provider.dart';

class EventLogScreen extends ConsumerStatefulWidget {
  const EventLogScreen({super.key});

  @override
  ConsumerState<EventLogScreen> createState() => _EventLogScreenState();
}

class _EventLogScreenState extends ConsumerState<EventLogScreen> {
  @override
  void initState() {
    super.initState();
    _startPeriodicRefresh();
  }

  void _startPeriodicRefresh() {
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        ref.invalidate(riskyGroupedEventsProvider);
        _startPeriodicRefresh();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final grouped = ref.watch(riskyGroupedEventsProvider);

    return grouped.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Error loading events'),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () => ref.invalidate(riskyGroupedEventsProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (groups) {
        if (groups.isEmpty) {
          return const Center(
            child: Text(
              'No risky events detected yet.',
              style: TextStyle(fontSize: 16, color: Color(0xFF657188)),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(riskyGroupedEventsProvider);
          },
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: groups.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              if (index == 0) {
                return const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Tap a day to open the events recorded on that date.',
                    style: TextStyle(color: Color(0xFF667085), fontSize: 13),
                  ),
                );
              }

              final group = groups[index - 1];

              return _DayEventButton(
                label: group.label,
                eventCount: group.count,
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => EventDayDetailScreen(
                      label: group.label,
                      events: group.events,
                    ),
                  ));
                },
              );
            },
          ),
        );
      },
    );
  }
}

// Uses grouped events from backend via `riskyGroupedEventsProvider`.

class _DayEventButton extends StatelessWidget {
  const _DayEventButton({
    required this.label,
    required this.eventCount,
    required this.onTap,
  });

  final String label;
  final int eventCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE3E8F0)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFDDE6F5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.calendar_today_outlined,
                  color: Color(0xFF24314C),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1F2D),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$eventCount event${eventCount == 1 ? '' : 's'}',
                      style: const TextStyle(color: Color(0xFF667085)),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF98A2B3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EventDayDetailScreen extends StatelessWidget {
  const EventDayDetailScreen({
    super.key,
    required this.label,
    required this.events,
  });

  final String label;
  final List<RiskEvent> events;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      appBar: AppBar(
        title: Text(label),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: events.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final event = events[index];
          final time = DateFormat('hh:mm:ss a').format(event.timestamp);

          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE3E8F0)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: const Color(0xFFDDE6F5),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Color(0xFF24314C),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.eventType,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1F2D),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$time • ${DateFormat('yyyy-MM-dd').format(event.timestamp)}',
                        style: const TextStyle(color: Color(0xFF667085)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Risk Level: ${event.riskLevel}',
                        style: const TextStyle(color: Color(0xFF667085)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
