import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/risk_event.dart';
import '../../services/backend_service.dart';
import '../../state/language_controller.dart';
import '../../state/session_controller.dart';
import '../widgets/ai_risk_trend_section.dart';
import '../widgets/risk_events_time_chart.dart';

class CaregiverDashboardScreen extends ConsumerStatefulWidget {
  const CaregiverDashboardScreen({super.key});

  @override
  ConsumerState<CaregiverDashboardScreen> createState() =>
      _CaregiverDashboardScreenState();
}

class _CaregiverDashboardScreenState
    extends ConsumerState<CaregiverDashboardScreen> {
  List<CaregiverPatientSummary> _patients = const [];
  int _selectedIndex = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPatients();
  }

  Future<void> _loadPatients() async {
    final session = ref.read(sessionControllerProvider);
    final email = session.email;
    final accessToken = session.caregiverAccessToken;
    if (email == null || accessToken == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final patients = await BackendService.fetchCaregiverDashboard(
        email,
        accessToken,
      );
      if (!mounted) return;
      setState(() {
        _patients = patients;
        _selectedIndex =
            patients.isEmpty ? 0 : _selectedIndex.clamp(0, patients.length - 1);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final session = ref.watch(sessionControllerProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      appBar: AppBar(
        title: Text(strings.text('Caregiver Dashboard')),
        actions: [
          IconButton(
            tooltip: strings.text('Refresh'),
            onPressed: _loading ? null : _loadPatients,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: strings.text('Logout'),
            onPressed: () =>
                ref.read(sessionControllerProvider.notifier).logout(),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorView(strings)
              : _patients.isEmpty
                  ? _emptyView(strings)
                  : RefreshIndicator(
                      onRefresh: _loadPatients,
                      child: _dashboard(strings, session.name ?? ''),
                    ),
    );
  }

  Widget _dashboard(AppStrings strings, String caregiverName) {
    final patient = _patients[_selectedIndex];
    final events = patient.events.map(_toRiskEvent).toList();
    final latest = patient.latestEvent;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF4FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFC9DFF7)),
          ),
          child: Row(
            children: [
              const Icon(Icons.visibility_outlined, color: Color(0xFF175CD3)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${strings.text('Welcome')}, $caregiverName. ${strings.text('This is a read-only view of patients who shared access with you.')}',
                  style: const TextStyle(
                    color: Color(0xFF1849A9),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<int>(
          initialValue: _selectedIndex,
          decoration: InputDecoration(
            labelText: strings.text('Viewing patient'),
            prefixIcon: const Icon(Icons.person_search_outlined),
            border: const OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
          ),
          items: [
            for (var index = 0; index < _patients.length; index++)
              DropdownMenuItem(
                value: index,
                child: Text(
                  '${_patients[index].name} (${_patients[index].email})',
                ),
              ),
          ],
          onChanged: (index) {
            if (index != null) setState(() => _selectedIndex = index);
          },
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _summaryCard(
              strings.text('Risk Level'),
              strings.text(_titleCase(patient.riskLevel)),
              Icons.health_and_safety_outlined,
              _riskColor(patient.riskLevel),
            ),
            _summaryCard(
              strings.text('Risky Events Today'),
              '${patient.todayEventCount}',
              Icons.today_outlined,
              const Color(0xFF175CD3),
            ),
            _summaryCard(
              strings.text('Risky Events - Last 7 Days'),
              '${patient.weeklyEventCount}',
              Icons.date_range_outlined,
              const Color(0xFF7F56D9),
            ),
            _summaryCard(
              strings.text('Latest Event'),
              latest == null
                  ? strings.text('No event yet')
                  : DateFormat('dd MMM, hh:mm a').format(
                      DateTime.parse(latest.timestamp.replaceFirst(' ', 'T')),
                    ),
              Icons.schedule_outlined,
              const Color(0xFF0E9384),
            ),
          ],
        ),
        const SizedBox(height: 14),
        RiskEventsTimeChart(events: events),
        const SizedBox(height: 14),
        AiRiskTrendSection(events: events, useDemoRiskTrendData: false),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _summaryCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      width: 220,
      constraints: const BoxConstraints(minHeight: 112),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Color(0xFF475467))),
        ],
      ),
    );
  }

  Widget _errorView(AppStrings strings) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 42),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loadPatients,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(strings.text('Retry')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyView(AppStrings strings) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          strings.text(
            'No patient currently shares their PICC status with this caregiver account.',
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  RiskEvent _toRiskEvent(RiskyEvent event) {
    return RiskEvent.fromBackend(
      id: event.id,
      eventType: event.eventType,
      timestamp: event.timestamp,
      riskLevel: event.riskLevel,
    );
  }

  Color _riskColor(String level) {
    return switch (level.toLowerCase()) {
      'high' => const Color(0xFFD92D20),
      'medium' => const Color(0xFFDC6803),
      _ => const Color(0xFF087454),
    };
  }

  String _titleCase(String value) {
    if (value.isEmpty) return value;
    return '${value[0].toUpperCase()}${value.substring(1).toLowerCase()}';
  }
}
