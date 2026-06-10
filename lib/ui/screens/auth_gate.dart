import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/session_state.dart';
import '../../state/session_controller.dart';
import 'caregiver_dashboard_screen.dart';
import 'home_shell.dart';
import 'login_screen.dart';
import 'onboarding_flow_screen.dart';

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);

    return switch (session.status) {
      SessionStatus.loading => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      SessionStatus.unauthenticated => const LoginScreen(),
      SessionStatus.authenticated => session.role == SessionRole.caregiver
          ? const CaregiverDashboardScreen()
          : session.onboardingCompleted
              ? const HomeShell()
              : const OnboardingFlowScreen(),
    };
  }
}
