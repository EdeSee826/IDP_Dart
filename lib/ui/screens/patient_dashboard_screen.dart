import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/patient_state.dart';
import '../../services/backend_service.dart';
import '../../state/backend_status_provider.dart';
import '../../state/language_controller.dart';
import '../../state/patient_controller.dart';
import '../../state/risky_events_provider.dart';
import '../../state/session_controller.dart';
import '../widgets/camera_button.dart';
import '../widgets/ai_risk_trend_section.dart';
import '../widgets/sensor_connection_panel.dart';
import '../widgets/risk_events_time_chart.dart';

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
  static const double _piccStableDifferenceCm = 1.0;
  final bool useDemoRiskTrendData = true;
  final ScrollController _checklistScrollController = ScrollController();

  String? _movingTaskTitle;
  DateTime _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month);
  bool _piccAnalyzing = false;
  PiccAnalysisResult? _piccAnalysisResult;
  String? _piccAnalysisError;
  String? _piccCycleKey;
  bool _piccCycleLoading = false;
  bool _nextPiccScanSetsBaseline = false;
  double? _baselinePiccLengthCm;
  double? _latestPiccLengthCm;
  DateTime? _baselinePiccScannedAt;
  DateTime? _latestPiccScannedAt;

  @override
  void initState() {
    super.initState();
    _startPeriodicRefresh();
  }

  void _startPeriodicRefresh() {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        ref.invalidate(riskyEventsProvider);
        _startPeriodicRefresh();
      }
    });
  }

  @override
  void dispose() {
    _checklistScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PatientState>(patientStateWithEventsProvider, (previous, next) {
      final oldCount = previous?.dailyEventCount ?? 0;
      if (next.dailyEventCount > oldCount && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF1A8D9D),
            content: Text(
              'Gentle care note at ${DateFormat('hh:mm:ss a').format(next.latestEventTimestamp!)}. Please move your PICC arm comfortably.',
            ),
          ),
        );
      }
    });

    final state = ref.watch(patientStateWithEventsProvider);
    final backendStatus = ref.watch(backendStatusProvider);
    final strings = ref.watch(appStringsProvider);
    final latestTimestamp = state.latestEventTimestamp == null
        ? strings.text('No event yet')
        : DateFormat('hh:mm:ss a').format(state.latestEventTimestamp!);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _backendNoticeBanner(backendStatus),
        const SizedBox(height: 12),
        _topSummaryAndCareOverview(state, latestTimestamp),
        const SizedBox(height: 12),
        _ringMetrics(state, backendStatus),
        const SizedBox(height: 14),
        _sensorAndRiskSection(state, backendStatus),
      ],
    );
  }

  Widget _topSummaryAndCareOverview(
    PatientState state,
    String latestTimestamp,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return Column(
            children: [
              _topSummary(state, latestTimestamp),
              const SizedBox(height: 12),
              _careOverviewCard(state),
            ],
          );
        }

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 5,
                child: _topSummary(state, latestTimestamp),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 5,
                child: _careOverviewCard(state),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _careOverviewCard(PatientState state) {
    final strings = ref.watch(appStringsProvider);
    final dressingReminder = _dressingReminderText(state, strings);
    final completedCount = _completedChecklistItems(state);
    final progress = completedCount / _totalChecklistItems;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 193, 206, 207),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color.fromARGB(255, 174, 186, 182)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.text('Today\'s Care Overview'),
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Color.fromARGB(255, 44, 48, 53),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 231, 244, 245),
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: const Color.fromARGB(255, 173, 193, 195)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.text('Dressing reminder'),
                  style: const TextStyle(
                    color: Color(0xFF475467),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  dressingReminder,
                  style: const TextStyle(
                    color: Color.fromARGB(255, 52, 128, 103),
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE5EAF1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.dailyChecklistProgress(
                    completedCount,
                    _totalChecklistItems,
                  ),
                  style: const TextStyle(
                    color: Color(0xFF334155),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 7,
                    value: progress,
                    backgroundColor: const Color(0xFFD7E5F0),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF2D8E90),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF8FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFD6E9F8)),
            ),
            child: Text(
              strings.text(
                'You are doing well. Keep your PICC arm comfortable and continue your daily care routine.',
              ),
              style: const TextStyle(
                color: Color(0xFF234A63),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _dressingReminderText(PatientState state, AppStrings strings) {
    final lastChange = state.lastDressingChangeAt;
    if (lastChange == null) {
      return strings.text('Please schedule your first dressing check');
    }

    final dueDate = DateTime(
      lastChange.year,
      lastChange.month,
      lastChange.day,
    ).add(_dressingInterval);
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final daysLeft = dueDate.difference(todayDate).inDays;

    if (daysLeft > 1) {
      return strings.nextChangeInDays(daysLeft);
    }
    if (daysLeft == 1) {
      return strings.text('Next change tomorrow');
    }
    if (daysLeft == 0) {
      return strings.text('Dressing change due today');
    }
    return strings.text('Dressing change overdue');
  }

  Widget _patientTodoCard(PatientState state) {
    final strings = ref.watch(appStringsProvider);
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
          Text(
            strings.text('Patient To-Do Checklist'),
            style: const TextStyle(
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
                      strings.completedCount(
                        completedCount,
                        _totalChecklistItems,
                      ),
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
              controller: _checklistScrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _checklistScrollController,
                child: Column(
                  children: [
                    if (missedAlerts.isNotEmpty) ...[
                      _infoBox(
                        title: strings.text('Missed Task Alerts'),
                        messages: missedAlerts,
                        background: const Color(0xFFFFF1F1),
                        border: const Color(0xFFF9CACA),
                        text: const Color(0xFFB42318),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (reminders.isNotEmpty) ...[
                      _infoBox(
                        title: strings.text('Smart Reminders'),
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
    final strings = ref.watch(appStringsProvider);
    final alerts = <String>[];
    if (state.flushMissedCount > 0) {
      alerts.add(strings.flushingMissed(state.flushMissedCount));
    }
    if (state.medicationMissedCount > 0) {
      alerts.add(strings.medicationMissed(state.medicationMissedCount));
    }
    if (state.dressingMissedCount > 0) {
      alerts.add(strings.dressingCheckMissed(state.dressingMissedCount));
    }
    return alerts;
  }

  List<String> _buildSmartReminders(PatientState state) {
    final strings = ref.watch(appStringsProvider);
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
        strings.flushDue(
          DateFormat('hh:mm a').format(flushDue),
          flushLeadMins,
        ),
      );
    }

    final medicationDue = state.lastMedicationAt?.add(_medicationInterval);
    if (medicationDue != null &&
        now.isAfter(medicationDue.subtract(Duration(minutes: medLeadMins))) &&
        !state.medicationTimingCompleted) {
      reminders.add(
        strings.medicationDue(
          DateFormat('hh:mm a').format(medicationDue),
          medLeadMins,
        ),
      );
    }

    final dressingDue = state.lastDressingChangeAt?.add(_dressingInterval);
    if (dressingDue != null) {
      final dressingDueDay =
          DateTime(dressingDue.year, dressingDue.month, dressingDue.day);
      final daysUntilDue = dressingDueDay.difference(today).inDays;

      if (daysUntilDue == 1) {
        reminders.add(
          strings.dressingTomorrow(DateFormat('dd MMM').format(dressingDue)),
        );
      } else if (daysUntilDue <= 0 &&
          now.isAfter(
              dressingDue.subtract(Duration(minutes: dressingLeadMins)))) {
        reminders.add(
          strings.dressingTarget(
            DateFormat('dd MMM').format(dressingDue),
            dressingLeadMins,
          ),
        );
      }
    }

    final appointmentDate = state.nextAppointmentDate;
    if (appointmentDate != null) {
      final appointmentDay = DateTime(
          appointmentDate.year, appointmentDate.month, appointmentDate.day);
      final daysToAppointment = appointmentDay.difference(today).inDays;
      if (daysToAppointment == 0) {
        reminders.add(strings.appointmentScheduled(false));
      } else if (daysToAppointment == 1) {
        reminders.add(strings.appointmentScheduled(true));
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
    final strings = ref.watch(appStringsProvider);
    return [
      _ChecklistTask(
        title: strings.text('Site check (redness, swelling, pain)'),
        value: state.symptomsChecked,
        icon: Icons.health_and_safety_outlined,
        onChanged: (value) => ref
            .read(patientControllerProvider.notifier)
            .setSymptomsChecked(value ?? false),
      ),
      _ChecklistTask(
        title: strings.text('Dressing condition'),
        subtitle: strings.text('Keep dressing clean, dry, and intact'),
        value: state.dressingConditionChecked,
        icon: Icons.checkroom_outlined,
        onChanged: (value) => ref
            .read(patientControllerProvider.notifier)
            .setDressingConditionChecked(value ?? false),
      ),
      _ChecklistTask(
        title: strings.text('Flushing reminder'),
        subtitle: strings.text('Flush line at prescribed schedule'),
        value: state.flushingCompleted,
        icon: Icons.water_drop_outlined,
        onChanged: (value) => ref
            .read(patientControllerProvider.notifier)
            .setFlushingCompleted(value ?? false),
      ),
      _ChecklistTask(
        title: strings.text('Dryness check'),
        value: state.drynessChecked,
        icon: Icons.wb_sunny_outlined,
        onChanged: (value) => ref
            .read(patientControllerProvider.notifier)
            .setDrynessChecked(value ?? false),
      ),
      _ChecklistTask(
        title: strings.text('Medication timing'),
        value: state.medicationTimingCompleted,
        icon: Icons.medication_outlined,
        onChanged: (value) => ref
            .read(patientControllerProvider.notifier)
            .setMedicationTimingCompleted(value ?? false),
      ),
      _ChecklistTask(
        title: strings.text('Check catheter length (VERY IMPORTANT)'),
        subtitle: strings.text(
          'Look at external line and confirm same length as before',
        ),
        value: state.catheterLengthChecked,
        icon: Icons.straighten_outlined,
        onChanged: (value) => ref
            .read(patientControllerProvider.notifier)
            .setCatheterLengthChecked(value ?? false),
      ),
      _ChecklistTask(
        title: strings.text('Avoid heavy movement or strain'),
        subtitle: strings.text(
          'Heavy lifting, sudden arm pulling, repetitive motion',
        ),
        value: state.movementPrecautionsChecked,
        icon: Icons.accessibility_new_outlined,
        onChanged: (value) => ref
            .read(patientControllerProvider.notifier)
            .setMovementPrecautionsChecked(value ?? false),
      ),
      _ChecklistTask(
        title: strings.text('Secure the line at all times'),
        value: state.lineSecuredChecked,
        icon: Icons.link_outlined,
        onChanged: (value) => ref
            .read(patientControllerProvider.notifier)
            .setLineSecuredChecked(value ?? false),
      ),
    ];
  }

  Widget _calendarPlannerCard(PatientState state) {
    final strings = ref.watch(appStringsProvider);
    final monthLabel = strings.monthYear(_calendarMonth);
    final gridDates = _monthGridDates(_calendarMonth);
    final weekLabels = strings.weekLabels;

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
              Text(
                strings.text('Calendar'),
                style: const TextStyle(
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
                tooltip: strings.text('Add event'),
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
                          strings.moreEvents(events.length - 2),
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
    final strings = ref.watch(appStringsProvider);
    final events = <_CalendarCellEvent>[];

    final appointment = state.nextAppointmentDate;
    if (_isSameDay(appointment, date)) {
      final timeText =
          appointment == null ? '' : DateFormat('h:mm a').format(appointment);
      events.add(
        _CalendarCellEvent(
          label: timeText.isEmpty
              ? strings.text('Appt')
              : '${strings.text('Appt')} $timeText',
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
        _CalendarCellEvent(
          label: strings.text('Dressing'),
          background: const Color(0xFFE6F4EA),
          foreground: const Color(0xFF0F7B6C),
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
    final strings = ref.read(appStringsProvider);
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
        final navigator = Navigator.of(context);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(strings.text('Add Calendar Event')),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: eventType,
                      decoration: InputDecoration(
                        labelText: strings.text('Event type'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'appointment',
                          child: Text(strings.text('Appointment')),
                        ),
                        DropdownMenuItem(
                          value: 'dressing',
                          child: Text(strings.text('Dressing change')),
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
                        decoration: InputDecoration(
                          labelText: strings.text('Location'),
                          hintText: strings.text('Clinic / hospital / room'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: navigator.pop,
                  child: Text(strings.text('Cancel')),
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
                    navigator.pop();
                  },
                  child: Text(strings.text('Save')),
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
              _sensorImagePanel(state, backendStatus),
              const SizedBox(height: 12),
              _cameraCapturePanel(state),
              const SizedBox(height: 12),
              _calendarPlannerCard(state),
              const SizedBox(height: 12),
              _patientTodoCard(state),
              const SizedBox(height: 12),
              RiskEventsTimeChart(events: state.events, compact: true),
              const SizedBox(height: 12),
              AiRiskTrendSection(
                events: state.events,
                useDemoRiskTrendData: useDemoRiskTrendData,
              ),
            ],
          );
        }

        return Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: _sensorImagePanel(state, backendStatus),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _cameraCapturePanel(state),
                      const SizedBox(height: 12),
                      RiskEventsTimeChart(
                        events: state.events,
                        compact: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
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
            AiRiskTrendSection(
              events: state.events,
              useDemoRiskTrendData: useDemoRiskTrendData,
            ),
          ],
        );
      },
    );
  }

  Widget _sensorImagePanel(
      PatientState state, BackendStatusState backendStatus) {
    final strings = ref.watch(appStringsProvider);
    return SensorConnectionPanel(
      onSensorTap1: () => _showSensorSheet(
        title: strings.text('Sensor 1: Upper Arm Sensor'),
        connected: backendStatus.device1Connected,
        batteryLevel: backendStatus.device1BatteryPercent,
      ),
      onSensorTap2: () => _showSensorSheet(
        title: strings.text('Sensor 2: Wrist Sensor'),
        connected: backendStatus.device2Connected,
        batteryLevel: backendStatus.device2BatteryPercent,
      ),
      showContinueButton: false,
      showImage: true,
    );
  }

  Widget _cameraCapturePanel(PatientState state) {
    final strings = ref.watch(appStringsProvider);
    _ensurePiccCycleLoaded(state);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE3E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFB9D3FF)),
                ),
                child: const Icon(
                  Icons.add_photo_alternate_outlined,
                  color: Color(0xFF0B63E5),
                  size: 23,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.text('PICC Length Tracker'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1A1F2D),
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      strings.text(
                        'Upload a site photo to compare visible line length across this dressing cycle.',
                      ),
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Center(
            child: CameraButton(onImageTaken: _analyzePiccImage),
          ),
          if (_piccAnalyzing) ...[
            const SizedBox(height: 14),
            const LinearProgressIndicator(minHeight: 3),
          ],
          if (_baselinePiccLengthCm != null || _latestPiccLengthCm != null) ...[
            const SizedBox(height: 14),
            _piccLengthDashboard(),
          ],
          if (_piccAnalysisError != null) ...[
            const SizedBox(height: 14),
            _piccAnalysisErrorBox(_piccAnalysisError!),
          ],
        ],
      ),
    );
  }

  Future<void> _analyzePiccImage(XFile image) async {
    setState(() {
      _piccAnalyzing = true;
      _piccAnalysisResult = null;
      _piccAnalysisError = null;
    });

    try {
      final result = await BackendService.analyzePiccImage(image);
      final patientState = ref.read(patientStateWithEventsProvider);
      final cycleKey = _dressingCycleKey(patientState.lastDressingChangeAt);
      final now = DateTime.now();
      final setsBaseline =
          _nextPiccScanSetsBaseline || _baselinePiccLengthCm == null;

      if (!mounted) return;
      setState(() {
        _piccCycleKey = cycleKey;
        _piccAnalysisResult = result;
        if (setsBaseline) {
          _baselinePiccLengthCm = result.measurementCm;
          _baselinePiccScannedAt = now;
          _nextPiccScanSetsBaseline = false;
        }
        _latestPiccLengthCm = result.measurementCm;
        _latestPiccScannedAt = now;
      });
      await _savePiccCycle(cycleKey);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _nextPiccScanSetsBaseline = false;
        _piccAnalysisError = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _piccAnalyzing = false;
        });
      }
    }
  }

  void _ensurePiccCycleLoaded(PatientState state) {
    final key = _dressingCycleKey(state.lastDressingChangeAt);
    if (_piccCycleKey == key || _piccCycleLoading) return;

    _piccCycleLoading = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadPiccCycle(key);
      if (!mounted) return;
      setState(() {
        _piccCycleKey = key;
        _piccCycleLoading = false;
      });
    });
  }

  String _dressingCycleKey(DateTime? dressingDate) {
    return 'active-baseline';
  }

  String _piccPrefKey(String cycleKey, String field) {
    final accountId =
        ref.read(sessionControllerProvider).email?.toLowerCase() ?? 'default';
    return 'picc_length_cycle.$accountId.$cycleKey.$field';
  }

  Future<void> _loadPiccCycle(String cycleKey) async {
    final prefs = await SharedPreferences.getInstance();
    var baseline = prefs.getDouble(_piccPrefKey(cycleKey, 'baselineLength'));
    var latest = prefs.getDouble(_piccPrefKey(cycleKey, 'latestLength'));
    var baselineAt = prefs.getString(_piccPrefKey(cycleKey, 'baselineAt'));
    var latestAt = prefs.getString(_piccPrefKey(cycleKey, 'latestAt'));

    if (baseline == null) {
      final accountId =
          ref.read(sessionControllerProvider).email?.toLowerCase() ?? 'default';
      final prefix = 'picc_length_cycle.$accountId.';
      final legacyBaselineKeys = prefs
          .getKeys()
          .where((key) =>
              key.startsWith(prefix) &&
              key.endsWith('.baselineLength') &&
              !key.contains('.active-baseline.'))
          .toList();
      legacyBaselineKeys.sort((a, b) {
        final aAt =
            prefs.getString(a.replaceAll('baselineLength', 'baselineAt'));
        final bAt =
            prefs.getString(b.replaceAll('baselineLength', 'baselineAt'));
        return (aAt ?? '').compareTo(bAt ?? '');
      });
      if (legacyBaselineKeys.isNotEmpty) {
        final oldestKey = legacyBaselineKeys.first;
        baseline = prefs.getDouble(oldestKey);
        baselineAt = prefs
            .getString(oldestKey.replaceAll('baselineLength', 'baselineAt'));

        final latestKey = legacyBaselineKeys.last.replaceAll(
          'baselineLength',
          'latestLength',
        );
        latest = prefs.getDouble(latestKey) ?? baseline;
        latestAt =
            prefs.getString(latestKey.replaceAll('latestLength', 'latestAt')) ??
                baselineAt;
      }
    }

    if (!mounted) return;
    setState(() {
      _baselinePiccLengthCm = baseline;
      _latestPiccLengthCm = latest;
      _baselinePiccScannedAt =
          baselineAt == null ? null : DateTime.tryParse(baselineAt);
      _latestPiccScannedAt =
          latestAt == null ? null : DateTime.tryParse(latestAt);
      _piccAnalysisResult = null;
      _piccAnalysisError = null;
    });
    if (baseline != null) {
      await _savePiccCycle(cycleKey);
    }
  }

  Future<void> _captureNewPiccBaseline() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (!mounted || image == null) return;

    setState(() {
      _nextPiccScanSetsBaseline = true;
      _piccAnalysisError = null;
    });
    await _analyzePiccImage(image);
  }

  Future<void> _savePiccCycle(String cycleKey) async {
    final prefs = await SharedPreferences.getInstance();
    final baseline = _baselinePiccLengthCm;
    final latest = _latestPiccLengthCm;
    final baselineAt = _baselinePiccScannedAt;
    final latestAt = _latestPiccScannedAt;

    if (baseline != null) {
      await prefs.setDouble(_piccPrefKey(cycleKey, 'baselineLength'), baseline);
    }
    if (latest != null) {
      await prefs.setDouble(_piccPrefKey(cycleKey, 'latestLength'), latest);
    }
    if (baselineAt != null) {
      await prefs.setString(
          _piccPrefKey(cycleKey, 'baselineAt'), baselineAt.toIso8601String());
    }
    if (latestAt != null) {
      await prefs.setString(
          _piccPrefKey(cycleKey, 'latestAt'), latestAt.toIso8601String());
    }
  }

  Widget _piccLengthDashboard() {
    final strings = ref.watch(appStringsProvider);
    final baseline = _baselinePiccLengthCm;
    final latest = _latestPiccLengthCm ?? baseline;
    final difference =
        baseline == null || latest == null ? null : latest - baseline;
    final isWarning =
        difference != null && difference.abs() > _piccStableDifferenceCm;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: _piccAnalyzing ? null : _captureNewPiccBaseline,
            icon: const Icon(Icons.health_and_safety_outlined, size: 17),
            label: Text(strings.text('I have changed my dressing')),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _piccMetricCard(
              title: strings.text('Today\'s Length'),
              value: latest == null ? '--' : latest.toStringAsFixed(2),
              suffix: 'cm',
              caption: strings.text('Scanned on'),
              date: _latestPiccScannedAt,
              icon: Icons.fit_screen_outlined,
              color: const Color(0xFF0B63E5),
              background: const Color(0xFFF3F7FF),
              border: const Color(0xFFB9D3FF),
            ),
            _piccMetricCard(
              title: strings.text('Baseline Length'),
              value: baseline == null ? '--' : baseline.toStringAsFixed(2),
              suffix: 'cm',
              caption: strings.text('First scan'),
              date: _baselinePiccScannedAt,
              icon: Icons.verified_rounded,
              color: const Color(0xFF087454),
              background: const Color(0xFFF0FAF6),
              border: const Color(0xFFB8E4D2),
            ),
            _piccMetricCard(
              title: strings.text('Length Difference'),
              value: difference == null
                  ? '--'
                  : '${difference >= 0 ? '+' : ''}${difference.toStringAsFixed(2)}',
              suffix: 'cm',
              caption: strings.text('Latest - baseline'),
              icon: Icons.trending_up_rounded,
              color: const Color(0xFF6D35D4),
              background: const Color(0xFFF7F2FF),
              border: const Color(0xFFD8C7FF),
            ),
            _piccStatusCard(isWarning: isWarning, difference: difference),
          ],
        ),
        if (_piccAnalysisResult != null) ...[
          const SizedBox(height: 10),
          Text(
            'PICC pixels: ${_piccAnalysisResult!.piccPixels.toStringAsFixed(1)} | Mark spacing: ${_piccAnalysisResult!.markDistancePixels.toStringAsFixed(1)} px',
            style: const TextStyle(color: Color(0xFF667085), fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _piccMetricCard({
    required String title,
    required String value,
    required String suffix,
    required String caption,
    DateTime? date,
    required IconData icon,
    required Color color,
    required Color background,
    required Color border,
  }) {
    return Container(
      width: 180,
      constraints: const BoxConstraints(minHeight: 120),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF1D2738),
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              Icon(icon, color: color, size: 24),
            ],
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              text: value,
              style: TextStyle(
                color: color,
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
              children: [
                TextSpan(
                  text: ' $suffix',
                  style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            caption,
            style: const TextStyle(
              color: Color(0xFF3B4A66),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (date != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.calendar_month_outlined, color: color, size: 14),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    DateFormat('dd MMM yyyy  hh:mm a').format(date),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF1F2A44),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _piccStatusCard(
      {required bool isWarning, required double? difference}) {
    final strings = ref.watch(appStringsProvider);
    final color = isWarning ? const Color(0xFFD92D20) : const Color(0xFF087454);
    return Container(
      width: 200,
      constraints: const BoxConstraints(minHeight: 120),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isWarning ? const Color(0xFFFFF4ED) : const Color(0xFFEFFAF6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isWarning ? const Color(0xFFFFD0B5) : const Color(0xFFB8E4D2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  strings.text('Status'),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              Icon(
                isWarning ? Icons.warning_rounded : Icons.check_circle_rounded,
                color: color,
                size: 28,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isWarning
                ? strings.text('PICC LENGTH REQUIRES ATTENTION')
                : strings.text('PICC LENGTH STABLE'),
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              height: 1.12,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              isWarning
                  ? strings.text(
                      'Difference is greater than 1.0 cm. Please contact your healthcare provider.',
                    )
                  : difference == null
                      ? strings.text(
                          'Upload a photo to begin tracking this dressing cycle.',
                        )
                      : strings.text(
                          'Difference is within the expected range for this dressing cycle.',
                        ),
              style: TextStyle(
                color: isWarning
                    ? const Color(0xFF7A271A)
                    : const Color(0xFF064E3B),
                fontSize: 12,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _piccAnalysisErrorBox(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4ED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD0B5)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFFB54708),
          fontSize: 13,
          height: 1.35,
        ),
      ),
    );
  }

  Future<void> _showSensorSheet({
    required String title,
    required bool connected,
    required int? batteryLevel,
  }) async {
    final strings = ref.read(appStringsProvider);
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
                  Text(strings.text('Status:'),
                      style: const TextStyle(color: Color(0xFF667085))),
                  const SizedBox(width: 8),
                  Text(
                    connected
                        ? strings.text('Connected')
                        : strings.text('Disconnected'),
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
                  Text(strings.text('Battery:'),
                      style: const TextStyle(color: Color(0xFF667085))),
                  const SizedBox(width: 8),
                  Text(
                    batteryLevel != null
                        ? '$batteryLevel%'
                        : strings.text('Not exposed'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                strings.text('Connection status is managed by the backend.'),
                style: const TextStyle(color: Color(0xFF667085)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _topSummary(PatientState state, [String? latestTimestamp]) {
    final strings = ref.watch(appStringsProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A7FB7), Color(0xFF2D8E90)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${strings.text('Patient')}: ${state.patientName}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            strings.text('PICC Arm Status: Stable'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 23,
            ),
          ),
          const SizedBox(height: 8),
          if (latestTimestamp != null)
            _metric(strings.text('Latest Event'), latestTimestamp),
          const SizedBox(height: 8),
          Text(
            strings.text(
              'Your monitoring is active and your care routine is on track today.',
            ),
            style: const TextStyle(
              color: Color(0xFFEAF7FF),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              strings.text(
                'Friendly tip: keep your PICC arm movements smooth and relaxed.',
              ),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(String title, String value) {
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _backendNoticeBanner(BackendStatusState backendStatus) {
    final strings = ref.watch(appStringsProvider);
    final backendReady = backendStatus.backendReady;
    final backgroundColor =
        backendReady ? const Color(0xFFEAF7F1) : const Color(0xFFF6F8FB);
    final borderColor =
        backendReady ? const Color(0xFFB7E4C7) : const Color(0xFFD7E2EA);
    final accentColor =
        backendReady ? const Color(0xFF0F7B6C) : const Color(0xFF5F6C7B);

    final message = backendReady
        ? strings.text(
            'Monitoring services are ready. Use the Wearable Sensors panel to connect or pause monitoring.',
          )
        : strings.text(
            'Monitoring services are not ready yet. The app will reconnect when the backend is available.',
          );

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
    final strings = ref.watch(appStringsProvider);
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
              unitText: strings.text('events'),
              label: strings.text('Today\'s Movement Count'),
              progress: (state.dailyEventCount / 10).clamp(0.0, 1.0),
              color: const Color(0xFFE9818C),
            ),
          ),
          Expanded(
            child: _ringMetricItem(
              valueText: '$connectedCount',
              unitText: '/2',
              label: strings.text('Sensors Connected'),
              progress: connectedCount / 2,
              color: const Color(0xFF8CCF2F),
            ),
          ),
          Expanded(
            child: _ringMetricItem(
              valueText: '$riskScore',
              unitText: '/3',
              label: strings.text('Care Attention Level'),
              progress: riskScore / 3,
              color: const Color(0xFFC7B3F2),
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
