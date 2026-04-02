import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/risk_event.dart';

class RiskEventsTimeChart extends StatelessWidget {
  const RiskEventsTimeChart({
    super.key,
    required this.events,
  });

  final List<RiskEvent> events;

  @override
  Widget build(BuildContext context) {
    final ordered = List<RiskEvent>.from(events)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return Container(
      padding: const EdgeInsets.all(14),
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
          const SizedBox(height: 12),
          SizedBox(
            height: 210,
            child: ordered.isEmpty
                ? const Center(child: Text('No events yet.'))
                : LineChart(
                    _buildData(ordered),
                  ),
          ),
        ],
      ),
    );
  }

  LineChartData _buildData(List<RiskEvent> ordered) {
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
            reservedSize: 28,
            interval: 1,
            getTitlesWidget: (value, meta) => Text(
              value.toInt().toString(),
              style: const TextStyle(fontSize: 10, color: Color(0xFF667085)),
            ),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            interval: maxX > 3 ? (maxX / 2).ceilToDouble() : 1,
            getTitlesWidget: (value, meta) {
              final index = value.toInt();
              if (index < 0 || index >= ordered.length) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  DateFormat('HH:mm').format(ordered[index].timestamp),
                  style:
                      const TextStyle(fontSize: 10, color: Color(0xFF667085)),
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
          barWidth: 3,
          color: const Color(0xFFD14343),
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(
            show: true,
            color: const Color(0xFFD14343).withValues(alpha: 0.15),
          ),
        ),
      ],
    );
  }
}
