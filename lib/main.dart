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
      ),
      home: const AuthGate(),
    );
  }
}
