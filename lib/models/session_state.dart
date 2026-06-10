enum SessionStatus { loading, authenticated, unauthenticated }

enum SessionRole { patient, caregiver }

class SessionState {
  const SessionState({
    required this.status,
    this.role = SessionRole.patient,
    this.caregiverAccessToken,
    this.name,
    this.email,
    this.onboardingCompleted = false,
    this.isNewUser = false,
    this.sensorBaselineCompleted = false,
  });

  final SessionStatus status;
  final SessionRole role;
  final String? caregiverAccessToken;
  final String? name;
  final String? email;
  final bool onboardingCompleted;
  final bool isNewUser;
  final bool sensorBaselineCompleted;

  const SessionState.loading()
      : status = SessionStatus.loading,
        role = SessionRole.patient,
        caregiverAccessToken = null,
        name = null,
        email = null,
        onboardingCompleted = false,
        isNewUser = false,
        sensorBaselineCompleted = false;

  const SessionState.unauthenticated()
      : status = SessionStatus.unauthenticated,
        role = SessionRole.patient,
        caregiverAccessToken = null,
        name = null,
        email = null,
        onboardingCompleted = false,
        isNewUser = false,
        sensorBaselineCompleted = false;

  const SessionState.authenticated({
    required this.name,
    required this.email,
    this.role = SessionRole.patient,
    this.caregiverAccessToken,
    this.onboardingCompleted = false,
    this.isNewUser = false,
    this.sensorBaselineCompleted = false,
  }) : status = SessionStatus.authenticated;
}
