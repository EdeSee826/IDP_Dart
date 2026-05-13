import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/risk_event.dart';

class RiskEventsTimeChart extends StatelessWidget {
  const RiskEventsTimeChart({
    super.key,
    required this.events,
    this.compact = false,
  });

  final List<RiskEvent> events;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final dailyBars = _buildDailyBars(events);

    return Container(
      padding: EdgeInsets.all(compact ? 10 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Risky Events - Last 7 Days',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1F2D),
              fontSize: 15,
            ),
          ),
          SizedBox(height: compact ? 8 : 12),
          SizedBox(
            height: compact ? 150 : 210,
            child: dailyBars.isEmpty
                ? const Center(child: Text('No events yet.'))
                : BarChart(
                    _buildData(dailyBars, compact),
                  ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _ChartLegend(
                  color: const Color(0xFF2563EB), label: 'Elbow flexion'),
              _ChartLegend(
                color: const Color(0xFFF97316),
                label: 'Shoulder adduction',
              ),
            ],
          ),
        ],
      ),
    );
  }

  BarChartData _buildData(List<_DailyBarData> dailyBars, bool compact) {
    final maxY = dailyBars
        .map((bar) => bar.elbowFlexionCount > bar.shoulderAdductionCount
            ? bar.elbowFlexionCount
            : bar.shoulderAdductionCount)
        .fold<int>(
            0, (previous, current) => current > previous ? current : previous)
        .toDouble();

    return BarChartData(
      maxY: maxY < 3 ? 3 : maxY + 1,
      alignment: BarChartAlignment.spaceAround,
      barTouchData: BarTouchData(enabled: false),
      gridData: FlGridData(
        show: true,
        horizontalInterval: 1,
        getDrawingHorizontalLine: (_) =>
            const FlLine(color: Color(0xFFF0F3F9), strokeWidth: 1),
        drawVerticalLine: false,
      ),
      borderData: FlBorderData(
        show: true,
        border: Border.all(color: const Color(0xFFE3E8F0)),
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: compact ? 22 : 28,
            interval: 1,
            getTitlesWidget: (value, meta) => Text(
              value.toInt().toString(),
              style: TextStyle(
                fontSize: compact ? 9 : 10,
                color: const Color(0xFF667085),
              ),
            ),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: compact ? 28 : 36,
            getTitlesWidget: (value, meta) {
              final index = value.toInt();
              if (index < 0 || index >= dailyBars.length) {
                return const SizedBox.shrink();
              }

              return Padding(
                padding: EdgeInsets.only(top: compact ? 2 : 6),
                child: Text(
                  DateFormat('MMM d').format(dailyBars[index].date),
                  style: TextStyle(
                    fontSize: compact ? 8 : 10,
                    color: const Color(0xFF667085),
                  ),
                ),
              );
            },
          ),
        ),
      ),
      barGroups: [
        for (final bar in dailyBars)
          BarChartGroupData(
            x: bar.index,
            barsSpace: 4,
            barRods: [
              BarChartRodData(
                toY: bar.elbowFlexionCount.toDouble(),
                width: compact ? 8 : 12,
                borderRadius: BorderRadius.circular(4),
                color: const Color(0xFF2563EB),
              ),
              BarChartRodData(
                toY: bar.shoulderAdductionCount.toDouble(),
                width: compact ? 8 : 12,
                borderRadius: BorderRadius.circular(4),
                color: const Color(0xFFF97316),
              ),
            ],
          ),
      ],
    );
  }

  List<_DailyBarData> _buildDailyBars(List<RiskEvent> events) {
    final today = DateTime.now();
    final startDay = DateTime(today.year, today.month, today.day)
        .subtract(const Duration(days: 6));
    final groupedEvents = <String, List<RiskEvent>>{};

    for (final event in events) {
      final eventDay = DateTime(
          event.timestamp.year, event.timestamp.month, event.timestamp.day);
      if (eventDay.isBefore(startDay)) {
        continue;
      }

      final dayKey = DateFormat('yyyy-MM-dd').format(eventDay);
      groupedEvents.putIfAbsent(dayKey, () => <RiskEvent>[]).add(event);
    }

    return List.generate(7, (index) {
      final day = startDay.add(Duration(days: index));
      final dayKey = DateFormat('yyyy-MM-dd').format(day);
      final dayEvents = groupedEvents[dayKey] ?? const <RiskEvent>[];
      return _DailyBarData(
        index: index,
        date: day,
        elbowFlexionCount: dayEvents
            .where((event) => event.eventType == 'elbow_flexion')
            .length,
        shoulderAdductionCount: dayEvents
            .where((event) => event.eventType == 'shoulder_adduction')
            .length,
      );
    });
  }
}

class _DailyBarData {
  const _DailyBarData({
    required this.index,
    required this.date,
    required this.elbowFlexionCount,
    required this.shoulderAdductionCount,
  });

  final int index;
  final DateTime date;
  final int elbowFlexionCount;
  final int shoulderAdductionCount;
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF667085),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
