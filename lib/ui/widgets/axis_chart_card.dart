import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/patient_state.dart';

class AxisChartCard extends StatelessWidget {
  const AxisChartCard({
    super.key,
    required this.title,
    required this.samples,
  });

  final String title;
  final List<SensorSample> samples;

  @override
  Widget build(BuildContext context) {
    final xSpots = <FlSpot>[];
    final ySpots = <FlSpot>[];
    final zSpots = <FlSpot>[];

    for (var i = 0; i < samples.length; i++) {
      xSpots.add(FlSpot(i.toDouble(), samples[i].x));
      ySpots.add(FlSpot(i.toDouble(), samples[i].y));
      zSpots.add(FlSpot(i.toDouble(), samples[i].z));
    }

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
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1F2D),
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 180,
            child: samples.isEmpty
                ? const Center(child: Text('Waiting for sensor stream...'))
                : LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: (samples.length - 1).toDouble(),
                      minY: -6,
                      maxY: 6,
                      gridData: FlGridData(
                        show: true,
                        horizontalInterval: 2,
                        getDrawingHorizontalLine: (_) => const FlLine(
                            color: Color(0xFFF0F3F9), strokeWidth: 1),
                        drawVerticalLine: false,
                      ),
                      borderData: FlBorderData(
                        show: true,
                        border: Border.all(color: const Color(0xFFE3E8F0)),
                      ),
                      titlesData: const FlTitlesData(
                        topTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                      ),
                      lineBarsData: [
                        _line(xSpots, const Color(0xFF2563EB)),
                        _line(ySpots, const Color(0xFF10B981)),
                        _line(zSpots, const Color(0xFFF97316)),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 10),
          const Wrap(
            spacing: 12,
            children: [
              _LegendDot(label: 'X', color: Color(0xFF2563EB)),
              _LegendDot(label: 'Y', color: Color(0xFF10B981)),
              _LegendDot(label: 'Z', color: Color(0xFFF97316)),
            ],
          ),
        ],
      ),
    );
  }

  LineChartBarData _line(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      barWidth: 2,
      color: color,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(show: false),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}
