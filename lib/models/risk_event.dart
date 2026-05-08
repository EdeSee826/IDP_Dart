class RiskEvent {
  const RiskEvent({
    required this.eventNumber,
    required this.timestamp,
    required this.sourceDevice,
    this.eventType = 'Unknown',
    this.riskLevel = 'Risky',
  });

  final int eventNumber;
  final DateTime timestamp;
  final String sourceDevice;
  final String eventType;
  final String riskLevel;

  /// Factory constructor to create from backend response
  factory RiskEvent.fromBackend({
    required int id,
    required String eventType,
    required String timestamp, // Format: YYYY-MM-DD HH:MM:SS
    required String riskLevel,
  }) {
    // Parse the timestamp: YYYY-MM-DD HH:MM:SS
    final dateTime = DateTime.parse(timestamp.replaceFirst(' ', 'T'));

    return RiskEvent(
      eventNumber: id,
      timestamp: dateTime,
      sourceDevice: 'Backend',
      eventType: eventType,
      riskLevel: riskLevel,
    );
  }
}
