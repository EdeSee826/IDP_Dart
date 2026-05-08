import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/patient_state.dart';
import '../../services/backend_service.dart';
import '../../state/backend_status_provider.dart';
import '../../state/patient_controller.dart';
import '../../state/risky_events_provider.dart';
import '../widgets/device_status_tile.dart';
import '../widgets/risk_events_time_chart.dart';
import '../widgets/risk_level_badge.dart';
import '../widgets/streaming_control_panel.dart';

class PatientDashboardScreen extends ConsumerStatefulWidget {
  const PatientDashboardScreen({super.key});

  @override
  ConsumerState<PatientDashboardScreen> createState() =>
      _PatientDashboardScreenState();
}

class _PatientDashboardScreenState
    extends ConsumerState<PatientDashboardScreen> {
  static const Duration _flushInterval = Duration(days: 1);
  static const Duration _medicationInterval = Duration(hours: 12);
  static const Duration _dressingInterval = Duration(days: 7);

  String? _movingTaskTitle;
  DateTime _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month);

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
    ref.listen<PatientState>(patientStateWithEventsProvider, (previous, next) {
      final oldCount = previous?.dailyEventCount ?? 0;
      if (next.dailyEventCount > oldCount && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFFD14343),
            content: Text(
              'Risk event detected at ${DateFormat('hh:mm:ss a').format(next.latestEventTimestamp!)}',
            ),
          ),
        );
      }
    });

    final state = ref.watch(patientStateWithEventsProvider);
    final backendStatus = ref.watch(backendStatusProvider);
    final latestTimestamp = state.latestEventTimestamp == null
        ? 'No event yet'
        : DateFormat('hh:mm:ss a').format(state.latestEventTimestamp!);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _backendNoticeBanner(backendStatus),
        const SizedBox(height: 12),
        const StreamingControlPanel(),
        const SizedBox(height: 14),
        _topSummary(state, latestTimestamp),
        const SizedBox(height: 12),
        _ringMetrics(state, backendStatus),
        const SizedBox(height: 14),
        _sensorAndRiskSection(state, backendStatus),
      ],
    );
  }

  Widget _patientTodoCard(PatientState state) {
    final reminders = _buildSmartReminders(state);
    final missedAlerts = _buildMissedTaskAlerts(state);
    final tasks = _buildChecklistItems(state);
    final pendingTasks = tasks.where((task) => !task.value).toList();
    final completedTasks = tasks.where((task) => task.value).toList();
    final orderedTasks = [...pendingTasks, ...completedTasks];
    final completedCount = _completedChecklistItems(state);
    final progress = completedCount / _totalChecklistItems;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7ECF4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Patient To-Do Checklist',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1D2738),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFE6F4EA), Color(0xFFD5EEF7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '$completedCount / $_totalChecklistItems completed',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1D2738),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${(progress * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F7B6C),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 7,
                    value: progress,
                    backgroundColor: const Color(0xFFBFD9CB),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Color(0xFF0F7B6C)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 360,
            child: Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    if (missedAlerts.isNotEmpty) ...[
                      _infoBox(
                        title: 'Missed Task Alerts',
                        messages: missedAlerts,
                        background: const Color(0xFFFFF1F1),
                        border: const Color(0xFFF9CACA),
                        text: const Color(0xFFB42318),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (reminders.isNotEmpty) ...[
                      _infoBox(
                        title: 'Smart Reminders',
                        messages: reminders,
                        background: const Color(0xFFEFF8FF),
                        border: const Color(0xFFD1E9FF),
                        text: const Color(0xFF1849A9),
                      ),
                      const SizedBox(height: 10),
                    ],
                    for (final task in orderedTasks)
                      _todoTile(
                        title: task.title,
                        subtitle: task.subtitle,
                        value: task.value,
                        icon: task.icon,
                        isMoving: _movingTaskTitle == task.title,
                        onChanged: (_) => _onTaskToggle(task),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoBox({
    required String title,
    required List<String> messages,
    required Color background,
    required Color border,
    required Color text,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontWeight: FontWeight.w700, color: text),
          ),
          const SizedBox(height: 6),
          for (final message in messages)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('- $message', style: TextStyle(color: text)),
            ),
        ],
      ),
    );
  }

  List<String> _buildMissedTaskAlerts(PatientState state) {
    final alerts = <String>[];
    if (state.flushMissedCount > 0) {
      alerts.add('Flushing was missed $state.flushMissedCount day(s).');
    }
    if (state.medicationMissedCount > 0) {
      alerts.add(
          'Medication timing was missed $state.medicationMissedCount day(s).');
    }
    if (state.dressingMissedCount > 0) {
      alerts.add(
          'Dressing condition check was missed $state.dressingMissedCount day(s).');
    }
    return alerts;
  }

  List<String> _buildSmartReminders(PatientState state) {
    final reminders = <String>[];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final flushLeadMins = _adaptiveLeadMinutes(state.flushMissedCount);
    final medLeadMins = _adaptiveLeadMinutes(state.medicationMissedCount);
    final dressingLeadMins = _adaptiveLeadMinutes(state.dressingMissedCount);

    final flushDue = state.lastFlushAt?.add(_flushInterval);
    if (flushDue != null &&
        now.isAfter(flushDue.subtract(Duration(minutes: flushLeadMins))) &&
        !state.flushingCompleted) {
      reminders.add(
        'Flush schedule due at ${DateFormat('hh:mm a').format(flushDue)} (adaptive lead $flushLeadMins min).',
      );
    }

    final medicationDue = state.lastMedicationAt?.add(_medicationInterval);
    if (medicationDue != null &&
        now.isAfter(medicationDue.subtract(Duration(minutes: medLeadMins))) &&
        !state.medicationTimingCompleted) {
      reminders.add(
        'Medication timing due at ${DateFormat('hh:mm a').format(medicationDue)} (adaptive lead $medLeadMins min).',
      );
    }

    final dressingDue = state.lastDressingChangeAt?.add(_dressingInterval);
    if (dressingDue != null) {
      final dressingDueDay =
          DateTime(dressingDue.year, dressingDue.month, dressingDue.day);
      final daysUntilDue = dressingDueDay.difference(today).inDays;

      if (daysUntilDue == 1) {
        reminders.add(
          'Dressing was changed 6 days ago. Please change dressing tomorrow (${DateFormat('dd MMM').format(dressingDue)}).',
        );
      } else if (daysUntilDue <= 0 &&
          now.isAfter(
              dressingDue.subtract(Duration(minutes: dressingLeadMins)))) {
        reminders.add(
          'Dressing change target is ${DateFormat('dd MMM').format(dressingDue)} (every 7 days, adaptive lead $dressingLeadMins min).',
        );
      }
    }

    final appointmentDate = state.nextAppointmentDate;
    if (appointmentDate != null) {
      final appointmentDay = DateTime(
          appointmentDate.year, appointmentDate.month, appointmentDate.day);
      final daysToAppointment = appointmentDay.difference(today).inDays;
      if (daysToAppointment == 0) {
        reminders.add('Appointment is scheduled for today.');
      } else if (daysToAppointment == 1) {
        reminders.add('Appointment is scheduled for tomorrow.');
      }
    }

    return reminders;
  }

  int _adaptiveLeadMinutes(int missedCount) {
    if (missedCount <= 0) {
      return 0;
    }
    return (missedCount * 20).clamp(20, 120);
  }

  int get _totalChecklistItems => 8;

  int _completedChecklistItems(PatientState state) {
    final values = [
      state.symptomsChecked,
      state.dressingConditionChecked,
      state.flushingCompleted,
      state.drynessChecked,
      state.medicationTimingCompleted,
      state.catheterLengthChecked,
      state.movementPrecautionsChecked,
      state.lineSecuredChecked,
    ];

    return values.where((item) => item).length;
  }

  Future<void> _onTaskToggle(_ChecklistTask task) async {
    if (_movingTaskTitle != null) {
      return;
    }

    setState(() {
      _movingTaskTitle = task.title;
    });

    await Future<void>.delayed(const Duration(milliseconds: 120));
    task.onChanged(!task.value);

    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) {
      return;
    }
    setState(() {
      _movingTaskTitle = null;
    });
  }

  List<_ChecklistTask> _buildChecklistItems(PatientState state) {
    return [
      _ChecklistTask(
        title: 'Site check (redness, swelling, pain)',
        value: state.symptomsChecked,
        icon: Icons.health_and_safety_outlined,
        onChanged: (value) => ref
            .read(patientControllerProvider.notifier)
            .setSymptomsChecked(value ?? false),
      ),
      _ChecklistTask(
        title: 'Dressing condition',
        subtitle: 'Keep dressing clean, dry, and intact',
        value: state.dressingConditionChecked,
        icon: Icons.checkroom_outlined,
        onChanged: (value) => ref
            .read(patientControllerProvider.notifier)
            .setDressingConditionChecked(value ?? false),
      ),
      _ChecklistTask(
        title: 'Flushing reminder',
        subtitle: 'Flush line at prescribed schedule',
        value: state.flushingCompleted,
        icon: Icons.water_drop_outlined,
        onChanged: (value) => ref
            .read(patientControllerProvider.notifier)
            .setFlushingCompleted(value ?? false),
      ),
      _ChecklistTask(
        title: 'Dryness check',
        value: state.drynessChecked,
        icon: Icons.wb_sunny_outlined,
        onChanged: (value) => ref
            .read(patientControllerProvider.notifier)
            .setDrynessChecked(value ?? false),
      ),
      _ChecklistTask(
        title: 'Medication timing',
        value: state.medicationTimingCompleted,
        icon: Icons.medication_outlined,
        onChanged: (value) => ref
            .read(patientControllerProvider.notifier)
            .setMedicationTimingCompleted(value ?? false),
      ),
      _ChecklistTask(
        title: 'Check catheter length (VERY IMPORTANT)',
        subtitle: 'Look at external line and confirm same length as before',
        value: state.catheterLengthChecked,
        icon: Icons.straighten_outlined,
        onChanged: (value) => ref
            .read(patientControllerProvider.notifier)
            .setCatheterLengthChecked(value ?? false),
      ),
      _ChecklistTask(
        title: 'Avoid heavy movement or strain',
        subtitle: 'Heavy lifting, sudden arm pulling, repetitive motion',
        value: state.movementPrecautionsChecked,
        icon: Icons.accessibility_new_outlined,
        onChanged: (value) => ref
            .read(patientControllerProvider.notifier)
            .setMovementPrecautionsChecked(value ?? false),
      ),
      _ChecklistTask(
        title: 'Secure the line at all times',
        value: state.lineSecuredChecked,
        icon: Icons.link_outlined,
        onChanged: (value) => ref
            .read(patientControllerProvider.notifier)
            .setLineSecuredChecked(value ?? false),
      ),
    ];
  }

  Widget _calendarPlannerCard(PatientState state) {
    final monthLabel = DateFormat('MMMM yyyy').format(_calendarMonth);
    final gridDates = _monthGridDates(_calendarMonth);
    const weekLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5EAF3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Calendar',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: Color(0xFF1D2738),
                ),
              ),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                padding: EdgeInsets.zero,
                onPressed: () {
                  setState(() {
                    _calendarMonth = DateTime(
                      _calendarMonth.year,
                      _calendarMonth.month - 1,
                    );
                  });
                },
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Text(
                monthLabel,
                style: const TextStyle(
                  color: Color(0xFF344054),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                padding: EdgeInsets.zero,
                tooltip: 'Add event',
                onPressed: () => _showAddCalendarEventDialog(state),
                icon: const Icon(Icons.add_rounded),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                padding: EdgeInsets.zero,
                onPressed: () {
                  setState(() {
                    _calendarMonth = DateTime(
                      _calendarMonth.year,
                      _calendarMonth.month + 1,
                    );
                  });
                },
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final label in weekLabels)
                Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF8A9099),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: gridDates.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
              childAspectRatio: 0.92,
            ),
            itemBuilder: (context, index) {
              final date = gridDates[index];
              final inCurrentMonth = date.month == _calendarMonth.month;
              final isToday = _isSameDay(DateTime.now(), date);
              final events = _eventsForDate(state, date);
              final hasAppointment =
                  _isSameDay(state.nextAppointmentDate, date);

              return InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () =>
                    _showAddCalendarEventDialog(state, initialDate: date),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(2, 2, 2, 1),
                  decoration: BoxDecoration(
                    color: hasAppointment
                        ? const Color(0xFFF2EEFF)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: isToday || hasAppointment
                        ? Border.all(
                            color: hasAppointment
                                ? const Color(0xFF6D4AE2)
                                : const Color(0xFF5B3FD6),
                            width: hasAppointment ? 1.2 : 1.1,
                          )
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '${date.day}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isToday || hasAppointment
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: hasAppointment
                                  ? const Color(0xFF4A2FC8)
                                  : inCurrentMonth
                                      ? const Color(0xFF2B2F38)
                                      : const Color(0xFFBABFC8),
                            ),
                          ),
                          const Spacer(),
                          if (hasAppointment)
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0xFF6D4AE2),
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 1),
                      for (final event in events.take(2))
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 1),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 2, vertical: 1),
                          decoration: BoxDecoration(
                            color: event.background,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            event.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 7.5,
                              color: event.foreground,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if (events.length > 2)
                        Text(
                          '+${events.length - 2} more',
                          style: const TextStyle(
                            fontSize: 7,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF667085),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  List<_CalendarCellEvent> _eventsForDate(PatientState state, DateTime date) {
    final events = <_CalendarCellEvent>[];

    final appointment = state.nextAppointmentDate;
    if (_isSameDay(appointment, date)) {
      final timeText =
          appointment == null ? '' : DateFormat('h:mm a').format(appointment);
      events.add(
        _CalendarCellEvent(
          label: timeText.isEmpty ? 'Appt' : 'Appt $timeText',
          background: const Color(0xFFE8E1FF),
          foreground: const Color(0xFF4A2FC8),
        ),
      );
      if (state.appointmentLocation != null &&
          state.appointmentLocation!.isNotEmpty) {
        events.add(
          _CalendarCellEvent(
            label: state.appointmentLocation!,
            background: const Color(0xFFF2F4F7),
            foreground: const Color(0xFF475467),
          ),
        );
      }
    }

    if (_isSameDay(state.lastDressingChangeAt, date)) {
      events.add(
        const _CalendarCellEvent(
          label: 'Dressing',
          background: Color(0xFFE6F4EA),
          foreground: Color(0xFF0F7B6C),
        ),
      );
    }

    return events;
  }

  List<DateTime> _monthGridDates(DateTime month) {
    final firstOfMonth = DateTime(month.year, month.month, 1);
    final firstWeekdayIndex = (firstOfMonth.weekday + 6) % 7;
    final startDate = firstOfMonth.subtract(Duration(days: firstWeekdayIndex));
    final lastOfMonth = DateTime(month.year, month.month + 1, 0);
    final trailingDays = 7 - lastOfMonth.weekday;
    final endDate = lastOfMonth.add(Duration(days: trailingDays));
    final totalDays = endDate.difference(startDate).inDays + 1;
    return List<DateTime>.generate(
      totalDays,
      (index) =>
          DateTime(startDate.year, startDate.month, startDate.day + index),
    );
  }

  Future<void> _showAddCalendarEventDialog(
    PatientState state, {
    DateTime? initialDate,
  }) async {
    final formKey = GlobalKey<FormState>();
    DateTime pickedDate = initialDate ?? DateTime.now();
    TimeOfDay pickedTime =
        TimeOfDay.fromDateTime(state.nextAppointmentDate ?? DateTime.now());
    var eventType = 'appointment';
    final locationController = TextEditingController(
      text: state.appointmentLocation ?? '',
    );

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add Calendar Event'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: eventType,
                      decoration:
                          const InputDecoration(labelText: 'Event type'),
                      items: const [
                        DropdownMenuItem(
                          value: 'appointment',
                          child: Text('Appointment'),
                        ),
                        DropdownMenuItem(
                          value: 'dressing',
                          child: Text('Dressing change'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setDialogState(() {
                          eventType = value;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final selected = await showDatePicker(
                          context: context,
                          initialDate: pickedDate,
                          firstDate: DateTime(2024),
                          lastDate: DateTime(2100),
                        );
                        if (selected == null) {
                          return;
                        }
                        setDialogState(() {
                          pickedDate = selected;
                        });
                      },
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(DateFormat('dd MMM yyyy').format(pickedDate)),
                    ),
                    if (eventType == 'appointment') ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final selected = await showTimePicker(
                            context: context,
                            initialTime: pickedTime,
                          );
                          if (selected == null) {
                            return;
                          }
                          setDialogState(() {
                            pickedTime = selected;
                          });
                        },
                        icon: const Icon(Icons.schedule_outlined),
                        label: Text(pickedTime.format(context)),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: locationController,
                        decoration: const InputDecoration(
                          labelText: 'Location',
                          hintText: 'Clinic / hospital / room',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (!(formKey.currentState?.validate() ?? true)) {
                      return;
                    }

                    final controller =
                        ref.read(patientControllerProvider.notifier);
                    if (eventType == 'appointment') {
                      final dateTime = DateTime(
                        pickedDate.year,
                        pickedDate.month,
                        pickedDate.day,
                        pickedTime.hour,
                        pickedTime.minute,
                      );
                      controller.setAppointmentDetails(
                        date: dateTime,
                        location: locationController.text,
                      );

                      // Sync to Teams calendar
                      await BackendService.syncAppointmentToTeams(
                        title: 'Medical Appointment',
                        startTime: dateTime,
                        location: locationController.text,
                      );
                    } else {
                      controller.setLastDressingChangeDate(
                        DateTime(
                            pickedDate.year, pickedDate.month, pickedDate.day),
                      );
                    }

                    setState(() {
                      _calendarMonth =
                          DateTime(pickedDate.year, pickedDate.month);
                    });
                    Navigator.of(context).pop();
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    locationController.dispose();
  }

  bool _isSameDay(DateTime? a, DateTime b) {
    if (a == null) {
      return false;
    }
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Widget _todoTile({
    required String title,
    required bool value,
    required ValueChanged<bool?> onChanged,
    required IconData icon,
    required bool isMoving,
    String? subtitle,
  }) {
    return AnimatedSlide(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      offset: isMoving ? Offset(value ? 0.10 : -0.10, 0) : Offset.zero,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        scale: isMoving ? 0.985 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: value ? const Color(0xFFEFFAF6) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: value ? const Color(0xFFA8DCC6) : const Color(0xFFE5EAF1),
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onChanged(!value),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: value,
                    activeColor: const Color(0xFF0F7B6C),
                    onChanged: onChanged,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF1D2738),
                              decoration:
                                  value ? TextDecoration.lineThrough : null,
                            ),
                          ),
                          if (subtitle != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                subtitle,
                                style:
                                    const TextStyle(color: Color(0xFF667085)),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 9, right: 6),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: value
                          ? const Color(0xFF0F7B6C)
                          : const Color(0xFFE2E8F0),
                      child: Icon(
                        icon,
                        size: 17,
                        color: value ? Colors.white : const Color(0xFF475467),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sensorAndRiskSection(
    PatientState state,
    BackendStatusState backendStatus,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            children: [
              _calendarPlannerCard(state),
              const SizedBox(height: 12),
              _patientTodoCard(state),
              const SizedBox(height: 12),
              _sensorImagePanel(backendStatus),
              const SizedBox(height: 12),
              RiskEventsTimeChart(events: state.events, compact: true),
            ],
          );
        }

        return Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 4,
                  child: _calendarPlannerCard(state),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 6,
                  child: _patientTodoCard(state),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: _sensorImagePanel(backendStatus),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 5,
                  child:
                      RiskEventsTimeChart(events: state.events, compact: true),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _sensorImagePanel(BackendStatusState backendStatus) {
    final connectedCount = backendStatus.connectedCount;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7ECF4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Wearable Sensors',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
              color: Color(0xFF1D2738),
            ),
          ),
          const SizedBox(height: 10),
          DeviceStatusTile(
            title: 'Upper Arm IMU',
            connected: backendStatus.device1Connected,
          ),
          const SizedBox(height: 8),
          DeviceStatusTile(
            title: 'Wrist IMU',
            connected: backendStatus.device2Connected,
          ),
          const SizedBox(height: 8),
          Text(
            'Connected IMU devices: $connectedCount / 2',
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: FractionallySizedBox(
              widthFactor: 0.40,
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        'image_1.png',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFFEEF2F7), Color(0xFFDDE4EE)],
                              ),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.accessibility_new_rounded,
                                size: 74,
                                color: Color(0xFF7A8698),
                              ),
                            ),
                          );
                        },
                      ),
                      _sensorHotspot(
                        top: 0.30,
                        left: 0.24,
                        color: backendStatus.device1Connected
                            ? const Color(0xFF20B26C)
                            : const Color(0xFFE5484D),
                        label: '1',
                        onTap: () => _showSensorSheet(
                          title: 'Upper Arm Sensor',
                          connected: backendStatus.device1Connected,
                          batteryLevel: null,
                        ),
                      ),
                      _sensorHotspot(
                        top: 0.80,
                        left: 0.18,
                        color: backendStatus.device2Connected
                            ? const Color(0xFF20B26C)
                            : const Color(0xFFE5484D),
                        label: '2',
                        onTap: () => _showSensorSheet(
                          title: 'Wrist Sensor',
                          connected: backendStatus.device2Connected,
                          batteryLevel: null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tap sensor marker to view connection and battery details.',
            style: TextStyle(
              color: Color(0xFF667085),
              fontSize: 13,
              letterSpacing: 0.15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sensorHotspot({
    required double top,
    required double left,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return Align(
      alignment: Alignment(left * 2 - 1, top * 2 - 1),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x4D000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 20,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showSensorSheet({
    required String title,
    required bool connected,
    required int? batteryLevel,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Status:',
                      style: TextStyle(color: Color(0xFF667085))),
                  const SizedBox(width: 8),
                  Text(
                    connected ? 'Connected' : 'Disconnected',
                    style: TextStyle(
                      color: connected
                          ? const Color(0xFF20B26C)
                          : const Color(0xFFE5484D),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Battery:',
                      style: TextStyle(color: Color(0xFF667085))),
                  const SizedBox(width: 8),
                  Text(
                    batteryLevel != null ? '$batteryLevel%' : 'Not exposed',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Connection status is managed by the backend.',
                style: TextStyle(color: Color(0xFF667085)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _topSummary(PatientState state, String latestTimestamp) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F5BA8), Color(0xFF1A8D9D)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Patient: ${state.patientName}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 10),
          _metric('Latest Event', latestTimestamp),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text(
                'Risk Level',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 10),
              RiskLevelBadge(level: state.riskLevel),
            ],
          ),
        ],
      ),
    );
  }

  Widget _backendNoticeBanner(BackendStatusState backendStatus) {
    final isWeb = kIsWeb;
    final backendReady = backendStatus.backendReady;
    final backgroundColor =
        backendReady ? const Color(0xFFEAF7F1) : const Color(0xFFFFF4E5);
    final borderColor =
        backendReady ? const Color(0xFFB7E4C7) : const Color(0xFFF2C66D);
    final accentColor =
        backendReady ? const Color(0xFF0F7B6C) : const Color(0xFFB76E00);

    final message = backendReady
        ? isWeb
            ? 'Chrome is connected to the Flask backend. Press Start to run BLE streaming on the backend host.'
            : 'Backend is online. Press Start to run BLE streaming on the backend host.'
        : 'Backend is offline. Start the Python server first, then use Start to connect the IMU sensors.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            backendReady ? Icons.link_rounded : Icons.cloud_off_rounded,
            color: accentColor,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: TextStyle(
                    color: accentColor,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                if (backendStatus.errorMessage != null &&
                    backendStatus.errorMessage!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    backendStatus.errorMessage!,
                    style: TextStyle(
                      color: accentColor.withValues(alpha: 0.9),
                      fontSize: 12.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ringMetrics(PatientState state, BackendStatusState backendStatus) {
    final connectedCount = backendStatus.connectedCount;
    final riskScore = switch (state.riskLevel) {
      RiskLevel.low => 1,
      RiskLevel.medium => 2,
      RiskLevel.high => 3,
    };

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7ECF4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ringMetricItem(
              valueText: '${state.dailyEventCount}',
              unitText: 'events',
              label: 'Risky Events',
              progress: (state.dailyEventCount / 10).clamp(0.0, 1.0),
              color: const Color(0xFFE9818C),
            ),
          ),
          Expanded(
            child: _ringMetricItem(
              valueText: '$connectedCount',
              unitText: '/2',
              label: 'Connected',
              progress: connectedCount / 2,
              color: const Color(0xFF8CCF2F),
            ),
          ),
          Expanded(
            child: _ringMetricItem(
              valueText: '$riskScore',
              unitText: '/3',
              label: 'Risk Level',
              progress: riskScore / 3,
              color: const Color(0xFFC7B3F2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(String title, String value) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _ringMetricItem({
    required String valueText,
    required String unitText,
    required String label,
    required double progress,
    required Color color,
  }) {
    return Column(
      children: [
        SizedBox(
          width: 86,
          height: 86,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const SizedBox(
                width: 86,
                height: 86,
                child: CircularProgressIndicator(
                  value: 1,
                  strokeWidth: 9,
                  color: Color(0xFFF1F3F7),
                ),
              ),
              SizedBox(
                width: 86,
                height: 86,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 9,
                  color: color,
                  strokeCap: StrokeCap.round,
                  backgroundColor: Colors.transparent,
                ),
              ),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: valueText,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(
                      text: '\n$unitText',
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Color(0xFF1F2937),
          ),
        ),
      ],
    );
  }
}

class _CalendarCellEvent {
  const _CalendarCellEvent({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;
}

class _ChecklistTask {
  _ChecklistTask({
    required this.title,
    required this.value,
    required this.icon,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final IconData icon;
  final ValueChanged<bool?> onChanged;
}
