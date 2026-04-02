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
    final ordered = List<RiskEvent>.from(events)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

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
            'Risky Events vs Time',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1F2D),
              fontSize: 15,
            ),
          ),
          SizedBox(height: compact ? 8 : 12),
          SizedBox(
            height: compact ? 150 : 210,
            child: ordered.isEmpty
                ? const Center(child: Text('No events yet.'))
                : LineChart(
                    _buildData(ordered, compact),
                  ),
          ),
        ],
      ),
    );
  }

  LineChartData _buildData(List<RiskEvent> ordered, bool compact) {
    final spots = <FlSpot>[];
    for (var i = 0; i < ordered.length; i++) {
      spots.add(FlSpot(i.toDouble(), (i + 1).toDouble()));
    }

    final maxX = (ordered.length - 1).toDouble();
    final maxY = ordered.length.toDouble();

    return LineChartData(
      minX: 0,
      maxX: maxX,
      minY: 0,
      maxY: maxY < 3 ? 3 : maxY + 1,
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
            reservedSize: compact ? 24 : 30,
            interval: maxX > 3 ? (maxX / 2).ceilToDouble() : 1,
            getTitlesWidget: (value, meta) {
              final index = value.toInt();
              if (index < 0 || index >= ordered.length) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: EdgeInsets.only(top: compact ? 2 : 6),
                child: Text(
                  DateFormat('HH:mm').format(ordered[index].timestamp),
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
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          barWidth: compact ? 2.4 : 3,
          color: const Color(0xFFD14343),
          dotData: FlDotData(show: !compact),
          belowBarData: BarAreaData(
            show: true,
            color: const Color(0xFFD14343).withValues(alpha: 0.15),
          ),
        ),
      ],
    );
  }
}
