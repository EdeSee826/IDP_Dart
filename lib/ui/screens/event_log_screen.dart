import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../state/patient_controller.dart';
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
        ref.invalidate(riskyEventsProvider);
        _startPeriodicRefresh();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(patientControllerProvider);
    final backendEvents = ref.watch(riskyEventsProvider);

    return backendEvents.when(
      loading: () => const Center(
        child: CircularProgressIndicator(),
      ),
      error: (error, stack) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Error loading events'),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                ref.invalidate(riskyEventsProvider);
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (backendEvents) {
        final events = backendEvents.isNotEmpty ? backendEvents : state.events;

        if (events.isEmpty) {
          return const Center(
            child: Text(
              'No risky events detected yet.',
              style: TextStyle(fontSize: 16, color: Color(0xFF657188)),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(riskyEventsProvider);
          },
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) {
              final event = events[index];
              final time =
                  DateFormat('yyyy-MM-dd hh:mm:ss a').format(event.timestamp);

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
                        '${event.eventNumber}',
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
                            time,
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
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemCount: events.length,
          ),
        );
      },
    );
  }
}
