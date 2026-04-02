class RiskEvent {
  const RiskEvent({
    required this.eventNumber,
    required this.timestamp,
    required this.sourceDevice,
  });

  final int eventNumber;
  final DateTime timestamp;
  final String sourceDevice;
}
