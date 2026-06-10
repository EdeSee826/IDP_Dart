import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/session_state.dart';
import '../services/backend_service.dart';
import 'patient_controller.dart';

final sessionControllerProvider =
    StateNotifierProvider<SessionController, SessionState>((ref) {
  return SessionController(ref);
});

class SessionController extends StateNotifier<SessionState> {
  SessionController(this._ref) : super(const SessionState.loading()) {
    loadSession();
  }

  static const _loggedInKey = 'session.loggedIn';
  static const _nameKey = 'session.name';
  static const _emailKey = 'session.email';
  static const _onboardingDoneKey = 'session.onboardingDone';
  static const _isNewUserKey = 'session.isNewUser';
  static const _sensorBaselineDoneKey = 'session.sensorBaselineDone';
  static const _roleKey = 'session.role';
  static const _caregiverTokenKey = 'session.caregiverToken';

  final Ref _ref;

  Future<void> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool(_loggedInKey) ?? false;
    final name = prefs.getString(_nameKey);
    final email = prefs.getString(_emailKey);
    final onboardingDone = prefs.getBool(_onboardingDoneKey) ?? false;
    final isNewUser = prefs.getBool(_isNewUserKey) ?? false;
    final sensorBaselineDone = prefs.getBool(_sensorBaselineDoneKey) ?? false;
    final role = prefs.getString(_roleKey) == SessionRole.caregiver.name
        ? SessionRole.caregiver
        : SessionRole.patient;
    final caregiverToken = prefs.getString(_caregiverTokenKey);

    if (isLoggedIn &&
        name != null &&
        email != null &&
        (role != SessionRole.caregiver || caregiverToken != null)) {
      state = SessionState.authenticated(
        name: name,
        email: email,
        role: role,
        caregiverAccessToken: caregiverToken,
        onboardingCompleted: onboardingDone,
        isNewUser: isNewUser,
        sensorBaselineCompleted: sensorBaselineDone,
      );
      _ref.read(patientControllerProvider.notifier).switchPatient(name);
      return;
    }

    state = const SessionState.unauthenticated();
  }

  Future<String?> register({
    required String name,
    required String email,
    required String password,
  }) async {
    if (name.trim().isEmpty || email.trim().isEmpty || password.isEmpty) {
      return 'Valid name, email, and password are required.';
    }

    final result = await BackendService.registerAccount(
      name: name.trim(),
      email: email.trim(),
      password: password,
    );
    if (!result.success) return result.message;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loggedInKey, true);
    await prefs.setString(_nameKey, name.trim());
    await prefs.setString(_emailKey, email.trim());
    await prefs.setBool(_onboardingDoneKey, false);
    await prefs.setBool(_isNewUserKey, true);
    await prefs.setBool(_sensorBaselineDoneKey, false);
    await prefs.setString(_roleKey, SessionRole.patient.name);
    await prefs.remove(_caregiverTokenKey);

    state = SessionState.authenticated(
      name: name.trim(),
      email: email.trim(),
      role: SessionRole.patient,
      onboardingCompleted: false,
      isNewUser: true,
      sensorBaselineCompleted: false,
    );
    _ref.read(patientControllerProvider.notifier).switchPatient(name.trim());
    return null;
  }

  Future<String?> login({
    required String email,
    required String password,
  }) async {
    if (email.trim().isEmpty || password.isEmpty) {
      return 'Email and password are required.';
    }

    final result = await BackendService.loginAccount(
      email: email.trim(),
      password: password,
    );
    if (!result.success) return result.message;
    final accountName = result.name!;
    final accountEmail = result.email!;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loggedInKey, true);
    await prefs.setString(_nameKey, accountName);
    await prefs.setString(_emailKey, accountEmail);
    await prefs.setBool(_onboardingDoneKey, result.onboardingCompleted);
    await prefs.setBool(_isNewUserKey, false);
    await prefs.setBool(_sensorBaselineDoneKey, result.baselineCompleted);
    await prefs.setString(_roleKey, SessionRole.patient.name);
    await prefs.remove(_caregiverTokenKey);

    state = SessionState.authenticated(
      name: accountName,
      email: accountEmail,
      role: SessionRole.patient,
      onboardingCompleted: result.onboardingCompleted,
      isNewUser: false,
      sensorBaselineCompleted: result.baselineCompleted,
    );
    _ref.read(patientControllerProvider.notifier).switchPatient(accountName);
    return null;
  }

  Future<String?> loginCaregiver({
    required String email,
    required String token,
  }) async {
    if (email.trim().isEmpty || token.trim().isEmpty) {
      return 'Email and access token are required.';
    }

    final result = await BackendService.loginCaregiver(
      email: email.trim(),
      token: token.trim(),
    );
    if (!result.success) return result.message;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loggedInKey, true);
    await prefs.setString(_nameKey, result.name!);
    await prefs.setString(_emailKey, result.email!);
    await prefs.setString(_roleKey, SessionRole.caregiver.name);
    await prefs.setString(_caregiverTokenKey, result.accessToken!);
    await prefs.setBool(_onboardingDoneKey, true);
    await prefs.setBool(_isNewUserKey, false);
    await prefs.setBool(_sensorBaselineDoneKey, false);

    state = SessionState.authenticated(
      name: result.name!,
      email: result.email!,
      role: SessionRole.caregiver,
      caregiverAccessToken: result.accessToken,
      onboardingCompleted: true,
    );
    _ref.read(patientControllerProvider.notifier).clearPatient();
    return null;
  }

  Future<void> completeOnboarding() async {
    if (state.status != SessionStatus.authenticated) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final result = await BackendService.updateAccountState(
      email: state.email!,
      onboardingCompleted: true,
    );
    if (!result.success) return;
    await prefs.setBool(_onboardingDoneKey, true);

    state = SessionState.authenticated(
      name: state.name!,
      email: state.email!,
      role: state.role,
      caregiverAccessToken: state.caregiverAccessToken,
      onboardingCompleted: true,
      isNewUser: state.isNewUser,
      sensorBaselineCompleted: state.sensorBaselineCompleted,
    );
  }

  Future<void> completeSensorBaseline() async {
    if (state.status != SessionStatus.authenticated) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final result = await BackendService.updateAccountState(
      email: state.email!,
      baselineCompleted: true,
    );
    if (!result.success) return;
    await prefs.setBool(_sensorBaselineDoneKey, true);

    state = SessionState.authenticated(
      name: state.name!,
      email: state.email!,
      role: state.role,
      caregiverAccessToken: state.caregiverAccessToken,
      onboardingCompleted: state.onboardingCompleted,
      isNewUser: false,
      sensorBaselineCompleted: true,
    );
  }

  Future<void> resetSensorBaseline() async {
    if (state.status != SessionStatus.authenticated) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final result = await BackendService.updateAccountState(
      email: state.email!,
      baselineCompleted: false,
    );
    if (!result.success) return;
    await prefs.setBool(_sensorBaselineDoneKey, false);

    state = SessionState.authenticated(
      name: state.name!,
      email: state.email!,
      role: state.role,
      caregiverAccessToken: state.caregiverAccessToken,
      onboardingCompleted: state.onboardingCompleted,
      isNewUser: state.isNewUser,
      sensorBaselineCompleted: false,
    );
  }

  Future<void> updateProfile({
    required String name,
    required String email,
  }) async {
    if (state.status != SessionStatus.authenticated ||
        name.trim().isEmpty ||
        email.trim().isEmpty) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final result = await BackendService.updateAccountState(
      email: state.email!,
      name: name.trim(),
    );
    if (!result.success) return;
    await prefs.setString(_nameKey, name.trim());
    await prefs.setString(_emailKey, email.trim());

    state = SessionState.authenticated(
      name: name.trim(),
      email: email.trim(),
      role: state.role,
      caregiverAccessToken: state.caregiverAccessToken,
      onboardingCompleted: state.onboardingCompleted,
      isNewUser: state.isNewUser,
      sensorBaselineCompleted: state.sensorBaselineCompleted,
    );
    _ref.read(patientControllerProvider.notifier).setPatientName(name.trim());
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loggedInKey, false);
    await prefs.remove(_nameKey);
    await prefs.remove(_emailKey);
    await prefs.remove(_onboardingDoneKey);
    await prefs.remove(_isNewUserKey);
    await prefs.remove(_sensorBaselineDoneKey);
    await prefs.remove(_roleKey);
    await prefs.remove(_caregiverTokenKey);

    state = const SessionState.unauthenticated();
    _ref.read(patientControllerProvider.notifier).clearPatient();
  }
}
