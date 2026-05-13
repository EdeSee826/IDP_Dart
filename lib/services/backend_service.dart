import 'package:http/http.dart' as http;
import 'dart:convert';

class RiskyEvent {
  final int id;
  final String eventType;
  final String timestamp; // Format: YYYY-MM-DD HH:MM:SS
  final String riskLevel;

  RiskyEvent({
    required this.id,
    required this.eventType,
    required this.timestamp,
    required this.riskLevel,
  });

  factory RiskyEvent.fromJson(Map<String, dynamic> json) {
    return RiskyEvent(
      id: json['id'],
      eventType: json['event_type'],
      timestamp: json['timestamp'],
      riskLevel: json['risk_level'],
    );
  }
}

class BackendDeviceStatus {
  final String name;
  final bool connected;

  BackendDeviceStatus({
    required this.name,
    required this.connected,
  });

  factory BackendDeviceStatus.fromJson(Map<String, dynamic> json) {
    return BackendDeviceStatus(
      name: json['name'] as String? ?? 'Unknown',
      connected: json['connected'] as bool? ?? false,
    );
  }
}

class BackendRuntimeStatus {
  final bool backendReady;
  final bool streamingActive;
  final int connectedCount;
  final String? errorMessage;
  final List<BackendDeviceStatus> devices;

  BackendRuntimeStatus({
    required this.backendReady,
    required this.streamingActive,
    required this.connectedCount,
    required this.errorMessage,
    required this.devices,
  });

  factory BackendRuntimeStatus.fromJson(Map<String, dynamic> json) {
    final devices = (json['devices'] as List<dynamic>? ?? const [])
        .map((item) =>
            BackendDeviceStatus.fromJson(item as Map<String, dynamic>))
        .toList();

    return BackendRuntimeStatus(
      backendReady: json['backend_ready'] as bool? ?? false,
      streamingActive: json['streaming_active'] as bool? ?? false,
      connectedCount: json['connected_count'] as int? ?? 0,
      errorMessage: json['error_message'] as String?,
      devices: devices,
    );
  }

  bool get device1Connected {
    return devices.isNotEmpty && devices.first.connected;
  }

  bool get device2Connected {
    return devices.length > 1 && devices[1].connected;
  }
}

class BackendActionResult {
  final bool success;
  final String? message;

  const BackendActionResult({required this.success, this.message});
}

class BackendService {
  static const String baseUrl = 'http://localhost:5000/api';
  static const Duration timeout = Duration(seconds: 30);

  // Health check
  static Future<bool> healthCheck() async {
    try {
      final response =
          await http.get(Uri.parse('$baseUrl/health')).timeout(timeout);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<BackendRuntimeStatus> fetchRuntimeStatus() async {
    try {
      final response =
          await http.get(Uri.parse('$baseUrl/status')).timeout(timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return BackendRuntimeStatus.fromJson(data);
      }
    } catch (e) {
      // Fall through to default offline status.
    }

    return BackendRuntimeStatus(
      backendReady: false,
      streamingActive: false,
      connectedCount: 0,
      errorMessage: null,
      devices: [
        BackendDeviceStatus(name: 'XIAO_MG24_Sensor_01', connected: false),
        BackendDeviceStatus(name: 'XIAO_MG24_Sensor_02', connected: false),
      ],
    );
  }

  // Start streaming
  static Future<BackendActionResult> startStreaming() async {
    try {
      final response =
          await http.post(Uri.parse('$baseUrl/start')).timeout(timeout);
      if (response.statusCode == 200) {
        return const BackendActionResult(success: true);
      }

      final body = response.body.isNotEmpty ? json.decode(response.body) : null;
      return BackendActionResult(
        success: false,
        message: body is Map<String, dynamic>
            ? body['error'] as String? ?? 'Failed to start streaming'
            : 'Failed to start streaming',
      );
    } catch (e) {
      return BackendActionResult(success: false, message: 'Error: $e');
    }
  }

  // Stop streaming
  static Future<BackendActionResult> stopStreaming() async {
    try {
      final response =
          await http.post(Uri.parse('$baseUrl/stop')).timeout(timeout);
      if (response.statusCode == 200) {
        return const BackendActionResult(success: true);
      }

      final body = response.body.isNotEmpty ? json.decode(response.body) : null;
      return BackendActionResult(
        success: false,
        message: body is Map<String, dynamic>
            ? body['error'] as String? ?? 'Failed to stop streaming'
            : 'Failed to stop streaming',
      );
    } catch (e) {
      return BackendActionResult(success: false, message: 'Error: $e');
    }
  }

  // Fetch today's risky events
  static Future<List<RiskyEvent>> fetchTodayEvents() async {
    try {
      final response =
          await http.get(Uri.parse('$baseUrl/events/today')).timeout(timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final events = (data['events'] as List)
            .map((e) => RiskyEvent.fromJson(e))
            .toList();
        return events;
      } else {
        return [];
      }
    } catch (e) {
      return [];
    }
  }

  // Fetch all risky events
  static Future<List<RiskyEvent>> fetchAllEvents() async {
    try {
      final response =
          await http.get(Uri.parse('$baseUrl/events/all')).timeout(timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final events = (data['events'] as List)
            .map((e) => RiskyEvent.fromJson(e))
            .toList();
        return events;
      } else {
        return [];
      }
    } catch (e) {
      return [];
    }
  }

  // Fetch grouped events (by day) from the backend
  static Future<List<Map<String, dynamic>>> fetchGroupedEvents() async {
    try {
      final response =
          await http.get(Uri.parse('$baseUrl/events/all')).timeout(timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final grouped = (data['grouped_events'] as List<dynamic>?) ?? [];
        return grouped.map((g) => g as Map<String, dynamic>).toList();
      } else {
        return [];
      }
    } catch (e) {
      return [];
    }
  }

  // Clear all events
  static Future<bool> clearAllEvents() async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/events/clear'))
          .timeout(timeout);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Sync appointment to Teams calendar
  static Future<BackendActionResult> syncAppointmentToTeams({
    required String title,
    required DateTime startTime,
    required String location,
  }) async {
    try {
      final body = {
        'title': title,
        'start_time': startTime.toIso8601String(),
        'location': location,
      };

      final response = await http
          .post(
            Uri.parse('$baseUrl/appointment/sync-teams'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(body),
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        return const BackendActionResult(
            success: true, message: 'Synced to Teams calendar');
      }

      final responseBody =
          response.body.isNotEmpty ? json.decode(response.body) : null;
      return BackendActionResult(
        success: false,
        message: responseBody is Map<String, dynamic>
            ? responseBody['error'] as String? ?? 'Failed to sync to Teams'
            : 'Failed to sync to Teams',
      );
    } catch (e) {
      return BackendActionResult(
          success: false, message: 'Error syncing to Teams: $e');
    }
  }
}
