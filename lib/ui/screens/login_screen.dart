import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/session_state.dart';
import '../../state/language_controller.dart';
import '../../state/session_controller.dart';

enum _LoginMode { patient, register, caregiver }

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _submitting = false;
  _LoginMode _mode = _LoginMode.patient;
  String? _errorMessage;

  bool get _isRegisterMode => _mode == _LoginMode.register;
  bool get _isCaregiverMode => _mode == _LoginMode.caregiver;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    final strings = ref.watch(appStringsProvider);

    if (session.status == SessionStatus.authenticated) {
      return const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE6EBF2)),
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _isRegisterMode
                            ? strings.text('Create Account')
                            : _isCaregiverMode
                                ? strings.text('Caregiver Access')
                                : strings.text('Patient Sign In'),
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _isRegisterMode
                            ? strings.text(
                                'Create a new account to get started with PICC monitoring.',
                              )
                            : _isCaregiverMode
                                ? strings.text(
                                    'View summaries and trends for patients who shared access with you.',
                                  )
                                : strings.text(
                                    'Log in to continue to your patient dashboard.',
                                  ),
                        style: const TextStyle(color: Color(0xFF667085)),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F6FB),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SegmentedButton<_LoginMode>(
                          segments: [
                            ButtonSegment(
                              value: _LoginMode.patient,
                              label: Text(strings.text('Patient')),
                            ),
                            ButtonSegment(
                              value: _LoginMode.register,
                              label: Text(strings.text('Create')),
                            ),
                            ButtonSegment(
                              value: _LoginMode.caregiver,
                              label: Text(strings.text('Family')),
                            ),
                          ],
                          selected: {_mode},
                          showSelectedIcon: false,
                          onSelectionChanged: _submitting
                              ? null
                              : (selection) {
                                  setState(() {
                                    _mode = selection.first;
                                    _errorMessage = null;
                                  });
                                },
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (_isRegisterMode) ...[
                        TextFormField(
                          controller: _nameController,
                          decoration: InputDecoration(
                            labelText: strings.text('Username'),
                            border: const OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (_isRegisterMode &&
                                (value == null || value.trim().isEmpty)) {
                              return strings.text('Name is required');
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: strings.text('Email'),
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return strings.text('Email is required');
                          }
                          if (!value.contains('@')) {
                            return strings.text('Enter a valid email');
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: !_isCaregiverMode,
                        decoration: InputDecoration(
                          labelText: _isCaregiverMode
                              ? strings.text('Access token')
                              : strings.text('Password'),
                          prefixIcon: _isCaregiverMode
                              ? const Icon(Icons.key_outlined)
                              : null,
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (_isCaregiverMode &&
                              (value == null || value.trim().isEmpty)) {
                            return strings.text('Access token is required');
                          }
                          if (value == null || value.length < 6) {
                            return strings.text('Minimum 6 characters');
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      if (_errorMessage != null) ...[
                        Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: Color(0xFFB42318),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      FilledButton(
                        onPressed: _submitting
                            ? null
                            : () async {
                                if (!_formKey.currentState!.validate()) {
                                  return;
                                }
                                setState(() {
                                  _submitting = true;
                                  _errorMessage = null;
                                });
                                String? error;
                                if (_isRegisterMode) {
                                  error = await ref
                                      .read(sessionControllerProvider.notifier)
                                      .register(
                                        name: _nameController.text,
                                        email: _emailController.text,
                                        password: _passwordController.text,
                                      );
                                } else if (_isCaregiverMode) {
                                  error = await ref
                                      .read(sessionControllerProvider.notifier)
                                      .loginCaregiver(
                                        email: _emailController.text,
                                        token: _passwordController.text,
                                      );
                                } else {
                                  error = await ref
                                      .read(sessionControllerProvider.notifier)
                                      .login(
                                        email: _emailController.text,
                                        password: _passwordController.text,
                                      );
                                }
                                if (mounted) {
                                  setState(() {
                                    _submitting = false;
                                    _errorMessage = error;
                                  });
                                }
                              },
                        child: Text(_submitting
                            ? (_isRegisterMode
                                ? strings.text('Creating...')
                                : strings.text('Signing in...'))
                            : (_isRegisterMode
                                ? strings.text('Create Account')
                                : _isCaregiverMode
                                    ? strings.text('Open Caregiver Dashboard')
                                    : strings.text('Patient Sign In'))),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
