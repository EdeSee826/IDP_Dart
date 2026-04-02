enum SessionStatus { loading, authenticated, unauthenticated }

class SessionState {
  const SessionState({
    required this.status,
    this.name,
    this.email,
  });

  final SessionStatus status;
  final String? name;
  final String? email;

  const SessionState.loading()
      : status = SessionStatus.loading,
        name = null,
        email = null;

  const SessionState.unauthenticated()
      : status = SessionStatus.unauthenticated,
        name = null,
        email = null;

  const SessionState.authenticated({
    required this.name,
    required this.email,
  }) : status = SessionStatus.authenticated;
}
