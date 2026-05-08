import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/session_state.dart';
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

  final Ref _ref;

  Future<void> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool(_loggedInKey) ?? false;
    final name = prefs.getString(_nameKey);
    final email = prefs.getString(_emailKey);
    final onboardingDone = prefs.getBool(_onboardingDoneKey) ?? false;

    if (isLoggedIn && name != null && email != null) {
      state = SessionState.authenticated(
        name: name,
        email: email,
        onboardingCompleted: onboardingDone,
      );
      _ref.read(patientControllerProvider.notifier).setPatientName(name);
      return;
    }

    state = const SessionState.unauthenticated();
  }

  Future<void> login({
    required String name,
    required String email,
    required String password,
  }) async {
    if (name.trim().isEmpty || email.trim().isEmpty || password.isEmpty) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loggedInKey, true);
    await prefs.setString(_nameKey, name.trim());
    await prefs.setString(_emailKey, email.trim());
    await prefs.setBool(_onboardingDoneKey, false);

    state = SessionState.authenticated(
      name: name.trim(),
      email: email.trim(),
      onboardingCompleted: false,
    );
    _ref.read(patientControllerProvider.notifier).setPatientName(name.trim());
  }

  Future<void> completeOnboarding() async {
    if (state.status != SessionStatus.authenticated) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingDoneKey, true);

    state = SessionState.authenticated(
      name: state.name!,
      email: state.email!,
      onboardingCompleted: true,
    );
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loggedInKey, false);
    await prefs.remove(_nameKey);
    await prefs.remove(_emailKey);
    await prefs.remove(_onboardingDoneKey);

    state = const SessionState.unauthenticated();
  }
}
