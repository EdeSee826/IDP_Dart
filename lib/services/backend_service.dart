import 'dart:convert';

import 'package:http/http.dart' as http;

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

class BackendBatteryStatus {
  final double? voltage;
  final int? batteryPercent;
  final DateTime? lastUpdated;
  final bool connected;
  final int? rawADC;
  final Map<String, dynamic>? sensor1;

  BackendBatteryStatus({
    required this.voltage,
    required this.batteryPercent,
    required this.lastUpdated,
    required this.connected,
    required this.rawADC,
    required this.sensor1,
  });

  factory BackendBatteryStatus.fromJson(Map<String, dynamic> json) {
    final sensor1 = json['sensor1'] as Map<String, dynamic>?;
    final primary = sensor1 ?? const <String, dynamic>{};

    return BackendBatteryStatus(
      voltage: (primary['voltage'] as num?)?.toDouble(),
      batteryPercent: primary['battery_percent'] as int?,
      lastUpdated: DateTime.tryParse(primary['last_updated'] as String? ?? ''),
      connected: primary['connected'] as bool? ?? false,
      rawADC: primary['raw_adc'] as int?,
      sensor1: sensor1,
    );
  }

  int? get sensor1BatteryPercent =>
      (sensor1?['battery_percent'] as num?)?.toInt();
}

class BackendRuntimeStatus {
  final bool backendReady;
  final bool streamingActive;
  final int connectedCount;
  final double? batteryVoltage;
  final int? batteryPercent;
  final DateTime? batteryLastUpdated;
  final bool batteryConnected;
  final BackendBatteryStatus? battery;
  final String? errorMessage;
  final List<BackendDeviceStatus> devices;
  final Map<String, dynamic>? staticPlacement;
  final String? calibrationPhase;
  final String? calibrationMessage;
  final int? calibrationRemainingSeconds;
  final bool? staticCalibrationPassed;

  BackendRuntimeStatus({
    required this.backendReady,
    required this.streamingActive,
    required this.connectedCount,
    required this.batteryVoltage,
    required this.batteryPercent,
    required this.batteryLastUpdated,
    required this.batteryConnected,
    this.battery,
    required this.errorMessage,
    required this.devices,
    this.staticPlacement,
    this.calibrationPhase,
    this.calibrationMessage,
    this.calibrationRemainingSeconds,
    this.staticCalibrationPassed,
  });

  factory BackendRuntimeStatus.fromJson(Map<String, dynamic> json) {
    final devices = (json['devices'] as List<dynamic>? ?? const [])
        .map((item) =>
            BackendDeviceStatus.fromJson(item as Map<String, dynamic>))
        .toList();
    final batteryJson = json['battery'] as Map<String, dynamic>?;
    final battery =
        batteryJson == null ? null : BackendBatteryStatus.fromJson(batteryJson);
    final calibrationValidation =
        json['calibration_validation'] as Map<String, dynamic>?;

    return BackendRuntimeStatus(
      backendReady: json['backend_ready'] as bool? ?? false,
      streamingActive: json['streaming_active'] as bool? ?? false,
      connectedCount: json['connected_count'] as int? ?? 0,
      battery: battery,
      batteryVoltage:
          battery?.voltage ?? (json['battery_voltage'] as num?)?.toDouble(),
      batteryPercent:
          battery?.batteryPercent ?? json['battery_percent'] as int?,
      batteryLastUpdated: battery?.lastUpdated ??
          DateTime.tryParse(json['battery_last_updated'] as String? ?? ''),
      batteryConnected:
          battery?.connected ?? json['battery_connected'] as bool? ?? false,
      errorMessage: json['error_message'] as String?,
      devices: devices,
      staticPlacement: json['static_placement'] as Map<String, dynamic>?,
      calibrationPhase: json['calibration_phase'] as String?,
      calibrationMessage: json['calibration_message'] as String?,
      calibrationRemainingSeconds:
          (json['calibration_remaining_seconds'] as num?)?.toInt(),
      staticCalibrationPassed: calibrationValidation?['static_passed'] as bool?,
    );
  }

  bool get device1Connected {
    return devices.isNotEmpty && devices.first.connected;
  }

  bool get device2Connected {
    return false;
  }

  /// Static placement result for device 1 (first device in `devices`).
  /// Returns `true` for pass, `false` for fail, `null` if unknown/not provided.
  bool? get device1StaticPassed {
    if (staticPlacement == null || devices.isEmpty) return null;
    final key = devices.first.name;
    final entry = staticPlacement![key];
    if (entry == null) return null;
    return entry['passed'] as bool?;
  }

  bool? get device2StaticPassed {
    return null;
  }
}

class BackendActionResult {
  final bool success;
  final String? message;

  const BackendActionResult({required this.success, this.message});
}

class AccountAuthResult {
  const AccountAuthResult({
    required this.success,
    this.name,
    this.email,
    this.onboardingCompleted = false,
    this.baselineCompleted = false,
    this.message,
  });

  final bool success;
  final String? name;
  final String? email;
  final bool onboardingCompleted;
  final bool baselineCompleted;
  final String? message;

  factory AccountAuthResult.fromResponse(http.Response response) {
    final body = response.body.isEmpty
        ? const <String, dynamic>{}
        : json.decode(response.body) as Map<String, dynamic>;
    final account = body['account'] as Map<String, dynamic>?;
    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        account != null) {
      return AccountAuthResult(
        success: true,
        name: account['name'] as String?,
        email: account['email'] as String?,
        onboardingCompleted: account['onboarding_completed'] as bool? ?? false,
        baselineCompleted: account['baseline_completed'] as bool? ?? false,
      );
    }
    return AccountAuthResult(
      success: false,
      message: body['error'] as String? ?? 'Account request failed',
    );
  }
}

class FamilyPrivacyResult {
  const FamilyPrivacyResult({
    required this.success,
    this.enabled = false,
    this.familyEmail,
    this.invitationToken,
    this.message,
  });

  final bool success;
  final bool enabled;
  final String? familyEmail;
  final String? invitationToken;
  final String? message;

  factory FamilyPrivacyResult.fromResponse(http.Response response) {
    final body = response.body.isEmpty
        ? const <String, dynamic>{}
        : json.decode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return FamilyPrivacyResult(
        success: true,
        enabled: body['family_access_enabled'] as bool? ?? false,
        familyEmail: body['family_email'] as String?,
        invitationToken: body['invitation_token'] as String?,
      );
    }
    return FamilyPrivacyResult(
      success: false,
      message: body['error'] as String? ?? 'Privacy request failed',
    );
  }
}

class CaregiverPatientSummary {
  const CaregiverPatientSummary({
    required this.email,
    required this.name,
    required this.todayEventCount,
    required this.weeklyEventCount,
    required this.riskLevel,
    required this.events,
    this.latestEvent,
  });

  final String email;
  final String name;
  final int todayEventCount;
  final int weeklyEventCount;
  final String riskLevel;
  final RiskyEvent? latestEvent;
  final List<RiskyEvent> events;

  factory CaregiverPatientSummary.fromJson(Map<String, dynamic> json) {
    final latest = json['latest_event'] as Map<String, dynamic>?;
    return CaregiverPatientSummary(
      email: json['email'] as String,
      name: json['name'] as String,
      todayEventCount: (json['today_event_count'] as num?)?.toInt() ?? 0,
      weeklyEventCount: (json['weekly_event_count'] as num?)?.toInt() ?? 0,
      riskLevel: json['risk_level'] as String? ?? 'low',
      latestEvent: latest == null ? null : RiskyEvent.fromJson(latest),
      events: (json['events'] as List<dynamic>? ?? const [])
          .map((item) => RiskyEvent.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class CaregiverLoginResult {
  const CaregiverLoginResult({
    required this.success,
    this.name,
    this.email,
    this.accessToken,
    this.patients = const [],
    this.message,
  });

  final bool success;
  final String? name;
  final String? email;
  final String? accessToken;
  final List<CaregiverPatientSummary> patients;
  final String? message;

  factory CaregiverLoginResult.fromResponse(http.Response response) {
    final body = response.body.isEmpty
        ? const <String, dynamic>{}
        : json.decode(response.body) as Map<String, dynamic>;
    final account = body['account'] as Map<String, dynamic>?;
    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        account != null) {
      return CaregiverLoginResult(
        success: true,
        name: account['name'] as String?,
        email: account['email'] as String?,
        accessToken: body['access_token'] as String?,
        patients: _caregiverPatientsFromBody(body),
      );
    }
    return CaregiverLoginResult(
      success: false,
      message: body['error'] as String? ?? 'Caregiver sign in failed',
    );
  }
}

List<CaregiverPatientSummary> _caregiverPatientsFromBody(
  Map<String, dynamic> body,
) {
  return (body['patients'] as List<dynamic>? ?? const [])
      .map(
        (item) =>
            CaregiverPatientSummary.fromJson(item as Map<String, dynamic>),
      )
      .toList();
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

  static Future<AccountAuthResult> registerAccount({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/accounts/register'),
            headers: const {'Content-Type': 'application/json'},
            body: json.encode({
              'name': name,
              'email': email,
              'password': password,
            }),
          )
          .timeout(timeout);
      return AccountAuthResult.fromResponse(response);
    } catch (_) {
      return const AccountAuthResult(
        success: false,
        message: 'Unable to contact the account server.',
      );
    }
  }

  static Future<AccountAuthResult> loginAccount({
    required String email,
    required String password,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/accounts/login'),
            headers: const {'Content-Type': 'application/json'},
            body: json.encode({'email': email, 'password': password}),
          )
          .timeout(timeout);
      return AccountAuthResult.fromResponse(response);
    } catch (_) {
      return const AccountAuthResult(
        success: false,
        message: 'Unable to contact the account server.',
      );
    }
  }

  static Future<CaregiverLoginResult> loginCaregiver({
    required String email,
    required String token,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/family/login'),
            headers: const {'Content-Type': 'application/json'},
            body: json.encode({'email': email, 'token': token}),
          )
          .timeout(timeout);
      return CaregiverLoginResult.fromResponse(response);
    } catch (_) {
      return const CaregiverLoginResult(
        success: false,
        message: 'Unsucessful Login.',
      );
    }
  }

  static Future<List<CaregiverPatientSummary>> fetchCaregiverDashboard(
    String email,
    String accessToken,
  ) async {
    final uri = Uri.parse('$baseUrl/family/dashboard').replace(
      queryParameters: {'email': email},
    );
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $accessToken'},
    ).timeout(timeout);
    final body = response.body.isEmpty
        ? const <String, dynamic>{}
        : json.decode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(body['error'] as String? ?? 'Unable to load patients');
    }
    return _caregiverPatientsFromBody(body);
  }

  static Future<AccountAuthResult> updateAccountState({
    required String email,
    String? name,
    bool? onboardingCompleted,
    bool? baselineCompleted,
  }) async {
    try {
      final body = <String, dynamic>{'email': email};
      if (name != null) body['name'] = name;
      if (onboardingCompleted != null) {
        body['onboarding_completed'] = onboardingCompleted;
      }
      if (baselineCompleted != null) {
        body['baseline_completed'] = baselineCompleted;
      }
      final response = await http
          .patch(
            Uri.parse('$baseUrl/accounts/state'),
            headers: const {'Content-Type': 'application/json'},
            body: json.encode(body),
          )
          .timeout(timeout);
      return AccountAuthResult.fromResponse(response);
    } catch (_) {
      return const AccountAuthResult(
        success: false,
        message: 'Unable to update the account.',
      );
    }
  }

  static Future<FamilyPrivacyResult> fetchFamilyPrivacy(String email) async {
    try {
      final uri = Uri.parse('$baseUrl/accounts/privacy').replace(
        queryParameters: {'email': email},
      );
      final response = await http.get(uri).timeout(timeout);
      return FamilyPrivacyResult.fromResponse(response);
    } catch (_) {
      return const FamilyPrivacyResult(
        success: false,
        message: 'Unable to load family access settings.',
      );
    }
  }

  static Future<FamilyPrivacyResult> updateFamilyPrivacy({
    required String email,
    required bool enabled,
    String? familyEmail,
  }) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/accounts/privacy'),
            headers: const {'Content-Type': 'application/json'},
            body: json.encode({
              'email': email,
              'family_access_enabled': enabled,
              'family_email': familyEmail,
            }),
          )
          .timeout(timeout);
      return FamilyPrivacyResult.fromResponse(response);
    } catch (_) {
      return const FamilyPrivacyResult(
        success: false,
        message: 'Unable to update family access settings.',
      );
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
      batteryVoltage: null,
      batteryPercent: null,
      batteryLastUpdated: null,
      batteryConnected: false,
      battery: null,
      errorMessage: null,
      devices: [
        BackendDeviceStatus(name: 'XIAO_MG24_Sensor_02', connected: false),
      ],
      calibrationPhase: null,
      calibrationMessage: null,
      calibrationRemainingSeconds: null,
      staticCalibrationPassed: null,
    );
  }

  // Start streaming
  static Future<BackendActionResult> startStreaming({
    bool enrollBaseline = false,
    String accountId = 'default',
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/start'),
            headers: const {'Content-Type': 'application/json'},
            body: json.encode({
              'enroll_baseline': enrollBaseline,
              'account_id': accountId,
            }),
          )
          .timeout(timeout);
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

  static Future<BackendActionResult> retryCalibration() async {
    try {
      final response = await http
          .post(Uri.parse('$baseUrl/calibration/retry'))
          .timeout(timeout);
      if (response.statusCode == 200) {
        return const BackendActionResult(success: true);
      }

      final body = response.body.isNotEmpty ? json.decode(response.body) : null;
      return BackendActionResult(
        success: false,
        message: body is Map<String, dynamic>
            ? body['error'] as String? ?? 'Failed to retry calibration'
            : 'Failed to retry calibration',
      );
    } catch (e) {
      return BackendActionResult(success: false, message: 'Error: $e');
    }
  }

  // Fetch today's risky events
  static Future<List<RiskyEvent>> fetchTodayEvents(String accountId) async {
    try {
      final uri = Uri.parse('$baseUrl/events/today').replace(
        queryParameters: {'account_id': accountId},
      );
      final response = await http.get(uri).timeout(timeout);

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
  static Future<List<RiskyEvent>> fetchAllEvents(String accountId) async {
    try {
      final uri = Uri.parse('$baseUrl/events/all').replace(
        queryParameters: {'account_id': accountId},
      );
      final response = await http.get(uri).timeout(timeout);

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
  static Future<List<Map<String, dynamic>>> fetchGroupedEvents(
    String accountId,
  ) async {
    try {
      final uri = Uri.parse('$baseUrl/events/all').replace(
        queryParameters: {'account_id': accountId},
      );
      final response = await http.get(uri).timeout(timeout);

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
  static Future<bool> clearAllEvents(String accountId) async {
    try {
      final uri = Uri.parse('$baseUrl/events/clear').replace(
        queryParameters: {'account_id': accountId},
      );
      final response = await http.delete(uri).timeout(timeout);
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
