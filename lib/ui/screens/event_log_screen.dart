import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../state/patient_controller.dart';

class EventLogScreen extends ConsumerWidget {
  const EventLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(patientControllerProvider);

    if (state.events.isEmpty) {
      return const Center(
        child: Text(
          'No risky events detected yet.',
          style: TextStyle(fontSize: 16, color: Color(0xFF657188)),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        final event = state.events[index];
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
                      'Event ${event.eventNumber}',
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
                      'Source: ${event.sourceDevice}',
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
      itemCount: state.events.length,
    );
  }
}
