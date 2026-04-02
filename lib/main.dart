import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/screens/auth_gate.dart';

void main() {
  runApp(const ProviderScope(child: PatientMonitoringApp()));
}

class PatientMonitoringApp extends StatelessWidget {
  const PatientMonitoringApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Patient Monitor',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F5BA8)),
        useMaterial3: true,
        splashFactory: InkRipple.splashFactory,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: _SmoothPageTransitionBuilder(),
            TargetPlatform.iOS: _SmoothPageTransitionBuilder(),
            TargetPlatform.linux: _SmoothPageTransitionBuilder(),
            TargetPlatform.macOS: _SmoothPageTransitionBuilder(),
            TargetPlatform.windows: _SmoothPageTransitionBuilder(),
          },
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class _SmoothPageTransitionBuilder extends PageTransitionsBuilder {
  const _SmoothPageTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final eased = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return FadeTransition(
      opacity: Tween<double>(begin: 0.92, end: 1.0).animate(eased),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.02, 0.02),
          end: Offset.zero,
        ).animate(eased),
        child: child,
      ),
    );
  }
}
