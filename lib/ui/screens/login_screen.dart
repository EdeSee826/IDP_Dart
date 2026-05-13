import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/session_state.dart';
import '../../state/session_controller.dart';

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
  bool _isRegisterMode = false;

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
                        _isRegisterMode ? 'Create Account' : 'Sign In',
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _isRegisterMode
                            ? 'Create a new account to get started with PICC monitoring.'
                            : 'Log in to continue to your patient dashboard.',
                        style: const TextStyle(color: Color(0xFF667085)),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F6FB),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed: _submitting
                                    ? null
                                    : () {
                                        setState(() {
                                          _isRegisterMode = false;
                                        });
                                      },
                                style: FilledButton.styleFrom(
                                  backgroundColor: _isRegisterMode
                                      ? Colors.transparent
                                      : null,
                                  foregroundColor: _isRegisterMode
                                      ? const Color(0xFF667085)
                                      : null,
                                ),
                                child: const Text('Sign In'),
                              ),
                            ),
                            Expanded(
                              child: FilledButton(
                                onPressed: _submitting
                                    ? null
                                    : () {
                                        setState(() {
                                          _isRegisterMode = true;
                                        });
                                      },
                                style: FilledButton.styleFrom(
                                  backgroundColor: _isRegisterMode
                                      ? null
                                      : Colors.transparent,
                                  foregroundColor: _isRegisterMode
                                      ? null
                                      : const Color(0xFF667085),
                                ),
                                child: const Text('Create Account'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Full Name',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Name is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Email is required';
                          }
                          if (!value.contains('@')) {
                            return 'Enter a valid email';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.length < 6) {
                            return 'Minimum 6 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _submitting
                            ? null
                            : () async {
                                if (!_formKey.currentState!.validate()) {
                                  return;
                                }
                                setState(() {
                                  _submitting = true;
                                });
                                if (_isRegisterMode) {
                                  await ref
                                      .read(sessionControllerProvider.notifier)
                                      .register(
                                        name: _nameController.text,
                                        email: _emailController.text,
                                        password: _passwordController.text,
                                      );
                                } else {
                                  await ref
                                      .read(sessionControllerProvider.notifier)
                                      .login(
                                        name: _nameController.text,
                                        email: _emailController.text,
                                        password: _passwordController.text,
                                      );
                                }
                                if (mounted) {
                                  setState(() {
                                    _submitting = false;
                                  });
                                }
                              },
                        child: Text(_submitting
                            ? (_isRegisterMode ? 'Creating...' : 'Signing in...')
                            : (_isRegisterMode ? 'Create Account' : 'Sign In')),
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
