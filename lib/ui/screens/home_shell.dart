import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/session_controller.dart';
import 'event_log_screen.dart';
import 'patient_dashboard_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _selectedIndex = 0;
  bool _reminderShown = false;

  static const _pages = [
    PatientDashboardScreen(),
    EventLogScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _reminderShown) {
        return;
      }
      _reminderShown = true;
      _showCareReminderDialog();
    });
  }

  Future<void> _showCareReminderDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Daily Care Reminder'),
          content: const SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Keep line dressing clean, dry, and intact.'),
                  SizedBox(height: 8),
                  Text('Use waterproof cover when showering.'),
                  SizedBox(height: 10),
                  Text('Check for:',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  SizedBox(height: 4),
                  Text('- Redness'),
                  Text('- Swelling'),
                  Text('- Leakage'),
                  SizedBox(height: 10),
                  Text(
                    'Flushing schedule reminder:',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 4),
                  Text('- Flush line at prescribed times (for example daily)'),
                  Text('- Use correct method (saline / heparin)'),
                  SizedBox(height: 10),
                  Text('Daily precautions:',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  SizedBox(height: 4),
                  Text('- Avoid heavy lifting'),
                  Text('- Avoid excessive bending'),
                  Text('- Do not pull or twist catheter'),
                  SizedBox(height: 10),
                  Text('Immediate alert if:',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  SizedBox(height: 4),
                  Text('- Fever'),
                  Text('- Pain at site'),
                  Text('- Swelling of arm'),
                  Text('- Pus or unusual discharge'),
                ],
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('I Understand'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      appBar: AppBar(
        title: const Text('Patient Monitoring Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Logout',
            onPressed: () async {
              await ref.read(sessionControllerProvider.notifier).logout();
            },
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: _pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt),
            label: 'Event Log',
          ),
        ],
      ),
    );
  }
}
