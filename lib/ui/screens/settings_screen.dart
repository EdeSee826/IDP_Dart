import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/backend_service.dart';
import '../../state/language_controller.dart';
import '../../state/session_controller.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const _supportEmail = 'picc-support@developer-team.com';

  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _familyEmailController;
  bool _familyAccessEnabled = false;
  bool _savingFamilyAccess = false;
  String? _familyAccessError;
  String? _familyInvitationToken;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final session = ref.read(sessionControllerProvider);
    _nameController = TextEditingController(text: session.name ?? '');
    _emailController = TextEditingController(text: session.email ?? '');
    _familyEmailController = TextEditingController();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final email = ref.read(sessionControllerProvider).email;
    final result = email == null
        ? const FamilyPrivacyResult(success: false)
        : await BackendService.fetchFamilyPrivacy(email);
    if (!mounted) return;
    setState(() {
      _familyAccessEnabled = result.enabled;
      _familyEmailController.text = result.familyEmail ?? '';
      _familyInvitationToken = null;
      _familyAccessError = result.success ? null : result.message;
      _loading = false;
    });
  }

  Future<void> _setLanguage(String? value) async {
    if (value == null) return;
    await ref.read(languageControllerProvider.notifier).setLanguage(value);
  }

  Future<void> _setFamilyAccess(bool value) async {
    if (value) {
      setState(() {
        _familyAccessEnabled = true;
        _familyAccessError = null;
      });
      return;
    }

    final email = ref.read(sessionControllerProvider).email;
    if (email == null) return;
    setState(() => _savingFamilyAccess = true);
    final result = await BackendService.updateFamilyPrivacy(
      email: email,
      enabled: false,
    );
    if (!mounted) return;
    setState(() {
      _savingFamilyAccess = false;
      _familyAccessEnabled = result.success ? false : true;
      _familyAccessError = result.success ? null : result.message;
      if (result.success) _familyEmailController.clear();
      if (result.success) _familyInvitationToken = null;
    });
  }

  Future<void> _saveFamilyAccess() async {
    final strings = ref.read(appStringsProvider);
    final email = ref.read(sessionControllerProvider).email;
    final familyEmail = _familyEmailController.text.trim();
    if (email == null) return;
    if (!familyEmail.contains('@')) {
      setState(() {
        _familyAccessError =
            strings.text('Enter a valid family email address.');
      });
      return;
    }

    setState(() {
      _savingFamilyAccess = true;
      _familyAccessError = null;
    });
    final result = await BackendService.updateFamilyPrivacy(
      email: email,
      enabled: true,
      familyEmail: familyEmail,
    );
    if (!mounted) return;
    setState(() {
      _savingFamilyAccess = false;
      _familyAccessEnabled = result.enabled;
      _familyInvitationToken = result.invitationToken;
      _familyAccessError = result.success ? null : result.message;
    });
    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(strings.text('Family visibility access saved.')),
        ),
      );
    }
  }

  Future<void> _saveProfile() async {
    await ref.read(sessionControllerProvider.notifier).updateProfile(
          name: _nameController.text,
          email: _emailController.text,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ref.read(appStringsProvider).text('Personal information saved.'),
        ),
      ),
    );
  }

  Future<void> _overwriteBaseline() async {
    final strings = ref.read(appStringsProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.text('Overwrite baseline calibration?')),
        content: Text(
          strings.text(
            'Your next sensor connection will perform static neutral calibration and save the result as the new baseline.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings.text('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings.text('Overwrite baseline')),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await ref.read(sessionControllerProvider.notifier).resetSensorBaseline();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          strings.text(
            'Ready. Connect the sensors to record the new baseline calibration.',
          ),
        ),
      ),
    );
  }

  Future<void> _copySupportEmail() async {
    await Clipboard.setData(const ClipboardData(text: _supportEmail));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ref.read(appStringsProvider).text('Developer support email copied.'),
        ),
      ),
    );
  }

  Future<void> _copyFamilyInvitationToken() async {
    final token = _familyInvitationToken;
    if (token == null) return;
    await Clipboard.setData(ClipboardData(text: token));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ref.read(appStringsProvider).text('Caregiver access token copied.'),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _familyEmailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final language = ref.watch(languageControllerProvider);
    final strings = ref.watch(appStringsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      appBar: AppBar(title: Text(strings.text('Settings'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _SettingsSection(
                  icon: Icons.language_rounded,
                  title: strings.text('Language'),
                  subtitle: strings
                      .text('Choose the language used by the application.'),
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(language),
                    initialValue: language,
                    decoration: InputDecoration(
                      labelText: strings.text('Application language'),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'English',
                        child: Text(strings.text('English')),
                      ),
                      DropdownMenuItem(
                        value: 'Malay',
                        child: Text(strings.text('Malay')),
                      ),
                      DropdownMenuItem(
                        value: 'Chinese',
                        child: Text(strings.text('Chinese')),
                      ),
                    ],
                    onChanged: _setLanguage,
                  ),
                ),
                const SizedBox(height: 14),
                _SettingsSection(
                  icon: Icons.tune_rounded,
                  title: strings.text('Calibration'),
                  subtitle: strings.text(
                    'Replace your original static neutral calibration reading.',
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: _overwriteBaseline,
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: Text(
                          strings.text('Perform new baseline calibration')),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _SettingsSection(
                  icon: Icons.shield_outlined,
                  title: strings.text('Data privacy'),
                  subtitle: strings.text(
                    'Control whether approved family members can track your PICC status.',
                  ),
                  child: Column(
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(strings.text('Allow family access')),
                        subtitle: Text(
                          _familyAccessEnabled
                              ? strings
                                  .text('Family tracking access is enabled.')
                              : strings.text('Only you can view your status.'),
                        ),
                        value: _familyAccessEnabled,
                        onChanged:
                            _savingFamilyAccess ? null : _setFamilyAccess,
                      ),
                      if (_familyAccessEnabled) ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: _familyEmailController,
                          enabled: !_savingFamilyAccess,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText: strings.text('Family email address'),
                            helperText: strings.text(
                              'This email will be allowed to view your PICC status.',
                            ),
                            prefixIcon:
                                const Icon(Icons.family_restroom_rounded),
                            border: const OutlineInputBorder(),
                            errorText: _familyAccessError,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed:
                                _savingFamilyAccess ? null : _saveFamilyAccess,
                            icon: _savingFamilyAccess
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.visibility_outlined),
                            label: Text(strings.text('Save family access')),
                          ),
                        ),
                        if (_familyInvitationToken != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF4FF),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFC9DFF7),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  strings.text('Caregiver access token'),
                                  style: const TextStyle(
                                    color: Color(0xFF1849A9),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                SelectableText(
                                  _familyInvitationToken!,
                                  style: const TextStyle(
                                    color: Color(0xFF101828),
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  strings.text(
                                    'Share this token securely with the family member. It is shown only once.',
                                  ),
                                  style: const TextStyle(
                                    color: Color(0xFF475467),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                OutlinedButton.icon(
                                  onPressed: _copyFamilyInvitationToken,
                                  icon: const Icon(Icons.copy_rounded),
                                  label: Text(strings.text('Copy token')),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ] else if (_familyAccessError != null) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _familyAccessError!,
                            style: const TextStyle(color: Color(0xFFB42318)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _SettingsSection(
                  icon: Icons.person_outline_rounded,
                  title: strings.text('Personal information'),
                  subtitle: strings.text(
                    'Update the name and email stored for this account.',
                  ),
                  child: Column(
                    children: [
                      TextField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: strings.text('Name'),
                          prefixIcon: const Icon(Icons.badge_outlined),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _emailController,
                        readOnly: true,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: strings.text('Email'),
                          helperText: strings.text(
                            'Email identifies your calibration and event records.',
                          ),
                          prefixIcon: const Icon(Icons.email_outlined),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: _saveProfile,
                          icon: const Icon(Icons.save_outlined),
                          label: Text(strings.text('Save')),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _SettingsSection(
                  icon: Icons.support_agent_rounded,
                  title: strings.text('Report a problem'),
                  subtitle: strings.text(
                    'Contact the developer team if something is not working.',
                  ),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.mail_outline_rounded,
                      color: theme.colorScheme.primary,
                    ),
                    title: const Text(_supportEmail),
                    trailing: IconButton(
                      tooltip: strings.text('Copy support email'),
                      onPressed: _copySupportEmail,
                      icon: const Icon(Icons.copy_rounded),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(subtitle, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}
