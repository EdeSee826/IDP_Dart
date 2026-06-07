import '../../models/risk_event.dart';

enum AiTrendDirection {
  decreased,
  increased,
  stable,
  monitoring,
}

enum RiskTimeWindow {
  morning,
  afternoon,
  evening,
  night,
  unknown,
}

class AiTrendData {
  const AiTrendData({
    required this.direction,
    required this.changePercent,
    required this.lastWeekRiskEvents,
    required this.thisWeekRiskEvents,
    required this.peakRiskTimeText,
    required this.commonRiskMovementText,
    required this.stabilityText,
    required this.encouragementMessage,
    required this.careSuggestion,
    required this.weeklySummary,
  });

  final AiTrendDirection direction;
  final double changePercent;
  final int lastWeekRiskEvents;
  final int thisWeekRiskEvents;
  final String peakRiskTimeText;
  final String commonRiskMovementText;
  final String stabilityText;
  final String encouragementMessage;
  final String careSuggestion;
  final String weeklySummary;

  bool get showsPercentageBadge => direction != AiTrendDirection.monitoring;

  String get percentageBadgeText {
    final sign = changePercent > 0 ? '+' : '';
    return '$sign${changePercent.toStringAsFixed(0)}%';
  }

  static AiTrendData demo() {
    const lastWeekRiskEvents = 20;
    const thisWeekRiskEvents = 14;
    const changePercent =
        ((thisWeekRiskEvents - lastWeekRiskEvents) / lastWeekRiskEvents) * 100;

    return const AiTrendData(
      direction: AiTrendDirection.decreased,
      changePercent: changePercent,
      lastWeekRiskEvents: lastWeekRiskEvents,
      thisWeekRiskEvents: thisWeekRiskEvents,
      peakRiskTimeText: 'Morning activities (8AM-11AM)',
      commonRiskMovementText:
          'Elbow flexion was the most frequent risky movement this week.',
      stabilityText: '4 stable movement days this week',
      encouragementMessage:
          'Risky movements reduced by 30% compared with last week. Keep going!',
      careSuggestion:
          'Continue keeping your PICC arm movements smooth and relaxed.',
      weeklySummary: 'Weekly movement review',
    );
  }
}

class AiTrendAnalyzer {
  const AiTrendAnalyzer._();

  static AiTrendData fromEvents(
    List<RiskEvent> allEvents, {
    DateTime? now,
  }) {
    final baseNow = now ?? DateTime.now();
    final thisWeekStart = _startOfWeekMonday(baseNow);
    final lastWeekStart = thisWeekStart.subtract(const Duration(days: 7));
    final nextWeekStart = thisWeekStart.add(const Duration(days: 7));

    // TODO: Replace this filter when backend adds a dedicated flag like
    // event.isRisky == true to avoid relying on labels.
    final riskyEvents = allEvents.where(_isRiskyMovementEvent).toList();

    final thisWeekEvents = riskyEvents
        .where((event) =>
            !event.timestamp.isBefore(thisWeekStart) &&
            event.timestamp.isBefore(nextWeekStart))
        .toList();

    final lastWeekEvents = riskyEvents
        .where((event) =>
            !event.timestamp.isBefore(lastWeekStart) &&
            event.timestamp.isBefore(thisWeekStart))
        .toList();

    final thisWeekCount = thisWeekEvents.length;
    final lastWeekCount = lastWeekEvents.length;

    if (lastWeekCount == 0) {
      return AiTrendData(
        direction: AiTrendDirection.monitoring,
        changePercent: 0,
        lastWeekRiskEvents: lastWeekCount,
        thisWeekRiskEvents: thisWeekCount,
        peakRiskTimeText: _peakRiskTimeText(thisWeekEvents),
        commonRiskMovementText: _mostCommonMovementText(thisWeekEvents),
        stabilityText: _stabilityText(thisWeekEvents, thisWeekStart),
        encouragementMessage:
            'This week\'s movement pattern is being monitored.',
        careSuggestion:
            'Continue gentle, smooth arm movements during daily activities.',
        weeklySummary: 'Weekly movement review',
      );
    }

    final changePercent = _calculateChangePercent(
      lastWeek: lastWeekCount,
      thisWeek: thisWeekCount,
    );
    final direction = _trendDirection(changePercent);

    return AiTrendData(
      direction: direction,
      changePercent: changePercent,
      lastWeekRiskEvents: lastWeekCount,
      thisWeekRiskEvents: thisWeekCount,
      peakRiskTimeText: _peakRiskTimeText(thisWeekEvents),
      commonRiskMovementText: _mostCommonMovementText(thisWeekEvents),
      stabilityText: _stabilityText(thisWeekEvents, thisWeekStart),
      encouragementMessage: _encouragement(direction, changePercent),
      careSuggestion:
          'Try to avoid repetitive arm lifting during long daily activities.',
      weeklySummary: 'Weekly movement review',
    );
  }

  static DateTime _startOfWeekMonday(DateTime value) {
    final normalized = DateTime(value.year, value.month, value.day);
    final daysFromMonday = normalized.weekday - DateTime.monday;
    return normalized.subtract(Duration(days: daysFromMonday));
  }

  static bool _isRiskyMovementEvent(RiskEvent event) {
    final riskLevel = event.riskLevel.toLowerCase();
    final type = event.eventType.toLowerCase();

    const riskyLabels = {
      'elbow flexion',
      'shoulder abduction',
      'shoulder adduction',
    };
    const safeLabels = {
      'standing',
      'walking',
      'neutral posture',
    };

    if (safeLabels.contains(type)) {
      return false;
    }

    return riskLevel == 'risky' || riskyLabels.contains(type);
  }

  static double _calculateChangePercent({
    required int lastWeek,
    required int thisWeek,
  }) {
    if (lastWeek == 0) {
      return 0;
    }

    return ((thisWeek - lastWeek) / lastWeek) * 100;
  }

  static AiTrendDirection _trendDirection(double changePercent) {
    const stableThreshold = 5.0;
    if (changePercent <= -stableThreshold) {
      return AiTrendDirection.decreased;
    }
    if (changePercent >= stableThreshold) {
      return AiTrendDirection.increased;
    }
    return AiTrendDirection.stable;
  }

  static String _encouragement(
    AiTrendDirection direction,
    double changePercent,
  ) {
    if (direction == AiTrendDirection.decreased) {
      return 'Risky movements reduced by ${changePercent.abs().toStringAsFixed(0)}% compared with last week. Keep going!';
    }
    if (direction == AiTrendDirection.increased) {
      return 'Risky movements increased slightly this week. Try to keep your PICC arm relaxed during repetitive activities.';
    }
    return 'Your movement pattern remained stable compared with last week.';
  }

  static String _peakRiskTimeText(List<RiskEvent> events) {
    if (events.isEmpty) {
      return 'No clear peak time yet this week';
    }

    final counts = <RiskTimeWindow, int>{
      RiskTimeWindow.morning: 0,
      RiskTimeWindow.afternoon: 0,
      RiskTimeWindow.evening: 0,
      RiskTimeWindow.night: 0,
    };

    for (final event in events) {
      counts[_toTimeWindow(event.timestamp)] =
          (counts[_toTimeWindow(event.timestamp)] ?? 0) + 1;
    }

    final top = counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    switch (top) {
      case RiskTimeWindow.morning:
        return 'Most risky events occurred during morning activities';
      case RiskTimeWindow.afternoon:
        return 'Most risky events occurred during afternoon activities';
      case RiskTimeWindow.evening:
        return 'Most risky events occurred during evening activities';
      case RiskTimeWindow.night:
        return 'Most risky events occurred during night activities';
      case RiskTimeWindow.unknown:
        return 'No clear peak time yet this week';
    }
  }

  static RiskTimeWindow _toTimeWindow(DateTime time) {
    final hour = time.hour;
    if (hour >= 6 && hour < 12) {
      return RiskTimeWindow.morning;
    }
    if (hour >= 12 && hour < 18) {
      return RiskTimeWindow.afternoon;
    }
    if (hour >= 18 && hour < 24) {
      return RiskTimeWindow.evening;
    }
    return RiskTimeWindow.night;
  }

  static String _mostCommonMovementText(List<RiskEvent> events) {
    if (events.isEmpty) {
      return 'No frequent risky movement pattern detected yet';
    }

    final counts = <String, int>{};
    for (final event in events) {
      counts[event.eventType] = (counts[event.eventType] ?? 0) + 1;
    }

    final top = counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    return '$top was the most frequent risky movement this week.';
  }

  static String _stabilityText(List<RiskEvent> events, DateTime thisWeekStart) {
    final dayCounts = <DateTime, int>{};
    for (var i = 0; i < 7; i++) {
      final day = thisWeekStart.add(Duration(days: i));
      dayCounts[DateTime(day.year, day.month, day.day)] = 0;
    }

    for (final event in events) {
      final day = DateTime(
        event.timestamp.year,
        event.timestamp.month,
        event.timestamp.day,
      );
      if (dayCounts.containsKey(day)) {
        dayCounts[day] = (dayCounts[day] ?? 0) + 1;
      }
    }

    var stableDays = 0;
    for (final count in dayCounts.values) {
      if (count <= 1) {
        stableDays++;
      }
    }

    return '$stableDays stable movement day(s) this week';
  }
}
