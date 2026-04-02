import 'dart:convert';
import 'dart:math';

enum DeviceSlot { device1, device2 }

class SensorPacket {
  const SensorPacket({
    required this.slot,
    required this.deviceLabel,
    required this.timestamp,
    required this.accX,
    required this.accY,
    required this.accZ,
    required this.gyroX,
    required this.gyroY,
    required this.gyroZ,
    required this.riskFlag,
  });

  final DeviceSlot slot;
  final String deviceLabel;
  final DateTime timestamp;
  final double accX;
  final double accY;
  final double accZ;
  final double gyroX;
  final double gyroY;
  final double gyroZ;
  final bool riskFlag;

  factory SensorPacket.fromBlePayload({
    required DeviceSlot slot,
    required String deviceLabel,
    required List<int> payload,
  }) {
    final now = DateTime.now();
    if (payload.isEmpty) {
      return SensorPacket(
        slot: slot,
        deviceLabel: deviceLabel,
        timestamp: now,
        accX: 0,
        accY: 0,
        accZ: 0,
        gyroX: 0,
        gyroY: 0,
        gyroZ: 0,
        riskFlag: false,
      );
    }

    final parsedAsText = _tryParseTextPayload(
      slot: slot,
      deviceLabel: deviceLabel,
      payload: payload,
      timestamp: now,
    );
    if (parsedAsText != null) {
      return parsedAsText;
    }

    if (payload.length >= 6) {
      final accX = (payload[0] - 128) / 32;
      final accY = (payload[1] - 128) / 32;
      final accZ = (payload[2] - 128) / 32;
      final gyroX = (payload[3] - 128) / 6;
      final gyroY = (payload[4] - 128) / 6;
      final gyroZ = (payload[5] - 128) / 6;
      return SensorPacket(
        slot: slot,
        deviceLabel: deviceLabel,
        timestamp: now,
        accX: accX,
        accY: accY,
        accZ: accZ,
        gyroX: gyroX,
        gyroY: gyroY,
        gyroZ: gyroZ,
        riskFlag: false,
      );
    }

    final random = Random();
    return SensorPacket(
      slot: slot,
      deviceLabel: deviceLabel,
      timestamp: now,
      accX: random.nextDouble() * 2 - 1,
      accY: random.nextDouble() * 2 - 1,
      accZ: 1 + random.nextDouble(),
      gyroX: random.nextDouble() * 30,
      gyroY: random.nextDouble() * 30,
      gyroZ: random.nextDouble() * 30,
      riskFlag: false,
    );
  }

  static SensorPacket? _tryParseTextPayload({
    required DeviceSlot slot,
    required String deviceLabel,
    required List<int> payload,
    required DateTime timestamp,
  }) {
    final text = utf8.decode(payload, allowMalformed: true).trim();
    if (text.isEmpty) {
      return null;
    }

    if (text.startsWith('{') && text.endsWith('}')) {
      try {
        final json = jsonDecode(text) as Map<String, dynamic>;
        return SensorPacket(
          slot: slot,
          deviceLabel: deviceLabel,
          timestamp: timestamp,
          accX: (json['ax'] as num?)?.toDouble() ?? 0,
          accY: (json['ay'] as num?)?.toDouble() ?? 0,
          accZ: (json['az'] as num?)?.toDouble() ?? 0,
          gyroX: (json['gx'] as num?)?.toDouble() ?? 0,
          gyroY: (json['gy'] as num?)?.toDouble() ?? 0,
          gyroZ: (json['gz'] as num?)?.toDouble() ?? 0,
          riskFlag: json['risk'] == true,
        );
      } catch (_) {
        return null;
      }
    }

    final parts = text.split(',').map((e) => e.trim()).toList();
    if (parts.length >= 6) {
      final values = parts.take(6).map(double.tryParse).toList();
      if (values.every((value) => value != null)) {
        final hasRisk = parts.length > 6 && parts[6].toUpperCase().contains('RISK');
        return SensorPacket(
          slot: slot,
          deviceLabel: deviceLabel,
          timestamp: timestamp,
          accX: values[0]!,
          accY: values[1]!,
          accZ: values[2]!,
          gyroX: values[3]!,
          gyroY: values[4]!,
          gyroZ: values[5]!,
          riskFlag: hasRisk,
        );
      }
    }

    final hasRisk = text.toUpperCase().contains('RISK');
    return SensorPacket(
      slot: slot,
      deviceLabel: deviceLabel,
      timestamp: timestamp,
      accX: 0,
      accY: 0,
      accZ: 0,
      gyroX: 0,
      gyroY: 0,
      gyroZ: 0,
      riskFlag: hasRisk,
    );
  }
}
