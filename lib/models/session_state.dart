enum SessionStatus { loading, authenticated, unauthenticated }

class SessionState {
  const SessionState({
    required this.status,
    this.name,
    this.email,
    this.onboardingCompleted = false,
    this.isNewUser = false,
  });

  final SessionStatus status;
  final String? name;
  final String? email;
  final bool onboardingCompleted;
  final bool isNewUser;

  const SessionState.loading()
      : status = SessionStatus.loading,
        name = null,
        email = null,
        onboardingCompleted = false,
        isNewUser = false;

  const SessionState.unauthenticated()
      : status = SessionStatus.unauthenticated,
        name = null,
        email = null,
        onboardingCompleted = false,
        isNewUser = false;

  const SessionState.authenticated({
    required this.name,
    required this.email,
    this.onboardingCompleted = false,
    this.isNewUser = false,
  }) : status = SessionStatus.authenticated;
}
