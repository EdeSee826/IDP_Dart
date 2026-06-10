import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/risk_event.dart';
import '../../state/language_controller.dart';
import '../models/ai_trend_data.dart';
import 'ai_trend_insight_card.dart';

class AiRiskTrendSection extends ConsumerWidget {
  const AiRiskTrendSection({
    super.key,
    required this.events,
    this.useDemoRiskTrendData = true,
  });

  final List<RiskEvent> events;
  final bool useDemoRiskTrendData;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    // TODO: Switch useDemoRiskTrendData to false when live ML-labeled event
    // stream is ready and RiskEvent contains reliable risk classification.
    final data = useDemoRiskTrendData
        ? AiTrendData.demo()
        : AiTrendAnalyzer.fromEvents(events);

    final trendMeta = _trendVisuals(data.direction);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFF3F8FF),
            Color(0xFFEAF4FF),
            Color(0xFFDCEEFF),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD4E5FB)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF94A3B8).withValues(alpha: 0.15),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.psychology_rounded,
                  size: 24,
                  color: Color(0xFF4C6EF5),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  strings.text('AI Risk Trend Analysis'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.76),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.auto_awesome_rounded,
                      size: 14,
                      color: Color(0xFF1D4ED8),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      strings.text('Weekly Movement Review'),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1D4ED8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            strings.text(data.encouragementMessage),
            style: const TextStyle(
              color: Color(0xFF334155),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            runAlignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              AiTrendInsightCard(
                title: strings.text('Weekly Trend'),
                value:
                    '${data.thisWeekRiskEvents} ${strings.text('this week vs')} ${data.lastWeekRiskEvents} ${strings.text('last week')}',
                subtitle: strings.text(data.weeklySummary),
                icon: trendMeta.icon,
                iconColor: trendMeta.color,
                badgeText:
                    data.showsPercentageBadge ? data.percentageBadgeText : null,
                badgeColor: trendMeta.badge,
              ),
              AiTrendInsightCard(
                title: strings.text('Peak Risk Time'),
                value: strings.text(data.peakRiskTimeText),
                subtitle:
                    strings.text('Time-of-day pattern from weekly events'),
                icon: Icons.schedule_rounded,
                iconColor: const Color(0xFF2563EB),
              ),
              AiTrendInsightCard(
                title: strings.text('Common Risk'),
                value: strings.text(data.commonRiskMovementText),
                subtitle: strings.text(
                  'Most frequent movement needing extra awareness',
                ),
                icon: Icons.fitness_center_rounded,
                iconColor: const Color(0xFF8B5CF6),
              ),
              AiTrendInsightCard(
                title: strings.text('Stability'),
                value: strings.text(data.stabilityText),
                subtitle: strings.text('Consistent movement awareness days'),
                icon: Icons.verified_rounded,
                iconColor: const Color(0xFF0F766E),
              ),
              AiTrendInsightCard(
                title: strings.text('Care Suggestion'),
                value: strings.text(data.careSuggestion),
                subtitle: strings.text(
                  'Gentle reminder tailored to this week\'s pattern',
                ),
                icon: Icons.lightbulb_rounded,
                iconColor: const Color(0xFFD97706),
              ),
            ],
          ),
        ],
      ),
    );
  }

  _TrendMeta _trendVisuals(AiTrendDirection direction) {
    switch (direction) {
      case AiTrendDirection.decreased:
        return const _TrendMeta(
          icon: Icons.trending_down_rounded,
          color: Color(0xFF15803D),
          badge: Color(0xFFD1FAE5),
        );
      case AiTrendDirection.increased:
        return const _TrendMeta(
          icon: Icons.trending_up_rounded,
          color: Color(0xFFD14343),
          badge: Color(0xFFFEE2E2),
        );
      case AiTrendDirection.stable:
        return const _TrendMeta(
          icon: Icons.trending_flat_rounded,
          color: Color(0xFF0369A1),
          badge: Color(0xFFE0F2FE),
        );
      case AiTrendDirection.monitoring:
        return const _TrendMeta(
          icon: Icons.query_stats_rounded,
          color: Color(0xFF475569),
          badge: Color(0xFFE2E8F0),
        );
    }
  }
}

class _TrendMeta {
  const _TrendMeta({
    required this.icon,
    required this.color,
    required this.badge,
  });

  final IconData icon;
  final Color color;
  final Color badge;
}
