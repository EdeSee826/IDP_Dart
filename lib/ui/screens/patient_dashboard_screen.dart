import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/patient_state.dart';
import '../../models/sensor_packet.dart';
import '../../state/patient_controller.dart';
import '../widgets/risk_events_time_chart.dart';
import '../widgets/risk_level_badge.dart';

class PatientDashboardScreen extends ConsumerStatefulWidget {
  const PatientDashboardScreen({super.key});

  @override
  ConsumerState<PatientDashboardScreen> createState() =>
      _PatientDashboardScreenState();
}

class _PatientDashboardScreenState
    extends ConsumerState<PatientDashboardScreen> {
  @override
  void initState() {
    super.initState();

    ref.listenManual<PatientState>(patientControllerProvider, (previous, next) {
      final oldCount = previous?.dailyEventCount ?? 0;
      if (next.dailyEventCount > oldCount) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFFD14343),
            content: Text(
                'Risk event detected at ${DateFormat('hh:mm:ss a').format(next.latestEventTimestamp!)}'),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(patientControllerProvider);
    final latestTimestamp = state.latestEventTimestamp == null
        ? 'No event yet'
        : DateFormat('hh:mm:ss a').format(state.latestEventTimestamp!);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _topSummary(state, latestTimestamp),
        const SizedBox(height: 12),
        _ringMetrics(state),
        const SizedBox(height: 14),
        _sensorImagePanel(state),
        const SizedBox(height: 14),
        RiskEventsTimeChart(events: state.events),
      ],
    );
  }

  Widget _sensorImagePanel(PatientState state) {
    return Container(
      padding: const EdgeInsets.all(10),
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
          const SizedBox(height: 8),
          Center(
            child: FractionallySizedBox(
              widthFactor: 0.56,
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
                        color: state.device1Connected
                            ? const Color(0xFF20B26C)
                            : const Color(0xFFE5484D),
                        label: '1',
                        onTap: () => _showSensorSheet(
                          slot: DeviceSlot.device1,
                          title: 'Upper Arm Sensor',
                          connected: state.device1Connected,
                          batteryLevel: state.device1BatteryLevel,
                          connecting: state.device1Connecting,
                        ),
                      ),
                      _sensorHotspot(
                        top: 0.80,
                        left: 0.18,
                        color: state.device2Connected
                            ? const Color(0xFF20B26C)
                            : const Color(0xFFE5484D),
                        label: '2',
                        onTap: () => _showSensorSheet(
                          slot: DeviceSlot.device2,
                          title: 'Wrist Sensor',
                          connected: state.device2Connected,
                          batteryLevel: state.device2BatteryLevel,
                          connecting: state.device2Connecting,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
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
    required DeviceSlot slot,
    required String title,
    required bool connected,
    required int? batteryLevel,
    required bool connecting,
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
                    connected ? '${batteryLevel ?? '--'}%' : '--',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (!connected)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: connecting
                        ? null
                        : () {
                            ref
                                .read(patientControllerProvider.notifier)
                                .connectSensor(slot);
                            Navigator.of(context).pop();
                          },
                    child:
                        Text(connecting ? 'Connecting...' : 'Connect Sensor'),
                  ),
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
          _metric(
            'Latest Event',
            latestTimestamp,
          ),
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

  Widget _ringMetrics(PatientState state) {
    final connectedCount =
        (state.device1Connected ? 1 : 0) + (state.device2Connected ? 1 : 0);
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
