enum SessionStatus { loading, authenticated, unauthenticated }

class SessionState {
  const SessionState({
    required this.status,
    this.name,
    this.email,
    this.onboardingCompleted = false,
  });

  final SessionStatus status;
  final String? name;
  final String? email;
  final bool onboardingCompleted;

  const SessionState.loading()
      : status = SessionStatus.loading,
        name = null,
        email = null,
        onboardingCompleted = false;

  const SessionState.unauthenticated()
      : status = SessionStatus.unauthenticated,
        name = null,
        email = null,
        onboardingCompleted = false;

  const SessionState.authenticated({
    required this.name,
    required this.email,
    this.onboardingCompleted = false,
  }) : status = SessionStatus.authenticated;
}
