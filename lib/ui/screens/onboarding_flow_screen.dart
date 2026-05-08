import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/patient_controller.dart';
import '../../state/session_controller.dart';

class OnboardingFlowScreen extends ConsumerStatefulWidget {
  const OnboardingFlowScreen({super.key});

  @override
  ConsumerState<OnboardingFlowScreen> createState() =>
      _OnboardingFlowScreenState();
}

class _OnboardingFlowScreenState extends ConsumerState<OnboardingFlowScreen> {
  final PageController _pageController = PageController();
  int _pageIndex = 0;
  bool _connecting = false;
  bool _sensor1Connected = false;
  bool _sensor2Connected = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _nextPage() async {
    if (_pageIndex >= 3) {
      return;
    }
    await _pageController.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _connectSensors() async {
    if (_connecting) {
      return;
    }

    setState(() {
      _connecting = true;
    });

    await Future<void>.delayed(const Duration(milliseconds: 800));

    if (!mounted) {
      return;
    }

    ref.read(patientControllerProvider.notifier).setMockSensorsConnected();

    setState(() {
      _sensor1Connected = true;
      _sensor2Connected = true;
      _connecting = false;
    });
  }

  Future<void> _enterDashboard() async {
    await ref.read(sessionControllerProvider.notifier).completeOnboarding();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF0F9F7), Color(0xFFE7F2FB)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 12),
              _stepIndicator(),
              const SizedBox(height: 12),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (value) {
                    setState(() {
                      _pageIndex = value;
                    });
                  },
                  children: [
                    _welcomePage(),
                    _sensorPlacementPage(),
                    _connectSensorsPage(),
                    _gentleIntroPage(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: List.generate(4, (index) {
          final active = index == _pageIndex;
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              margin: EdgeInsets.only(right: index == 3 ? 0 : 8),
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: active
                    ? const Color(0xFF2D8E90)
                    : const Color(0xFFD2E3EE),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _pageCard({
    required String title,
    required String subtitle,
    required Widget content,
    required Widget primaryAction,
  }) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFFDCE9F1)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x140F5BA8),
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F2F47),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF496174),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 22),
                content,
                const SizedBox(height: 24),
                SizedBox(width: double.infinity, child: primaryAction),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _welcomePage() {
    return _pageCard(
      title: 'PICC Care Companion',
      subtitle:
          'Helping you monitor and protect your PICC arm with gentle guidance and daily support.',
      content: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFE9F7F3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFC9EBDD)),
        ),
        child: const Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Color(0xFF2D8E90),
              child: Icon(Icons.favorite_rounded, color: Colors.white),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'You are not alone in your care routine. We will guide each step calmly and clearly.',
                style: TextStyle(
                  color: Color(0xFF1F4D4F),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
      primaryAction: FilledButton(
        onPressed: _nextPage,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF2D8E90),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: const Text('Get Started'),
      ),
    );
  }

  Widget _sensorPlacementPage() {
    return _pageCard(
      title: 'Sensor Placement',
      subtitle:
          'Place both IMU sensors comfortably for reliable daily monitoring.',
      content: Column(
        children: [
          _placementCard(
            index: 1,
            title: 'Upper Arm Sensor',
            detail: 'Place above the elbow on the upper arm.',
          ),
          const SizedBox(height: 10),
          _placementCard(
            index: 2,
            title: 'Forearm Sensor',
            detail: 'Place above the wrist on the forearm.',
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F7FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFD5E6F7)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Placement Tips',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF21415A),
                  ),
                ),
                SizedBox(height: 8),
                Text('• Keep straps snug but comfortable'),
                Text('• Avoid placing sensors directly on elbow or wrist joints'),
                Text('• Make sure sensors do not shift during movement'),
              ],
            ),
          ),
        ],
      ),
      primaryAction: FilledButton(
        onPressed: _nextPage,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF2D8E90),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: const Text('Continue'),
      ),
    );
  }

  Widget _placementCard({
    required int index,
    required String title,
    required String detail,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FCFB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD6ECE4)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: const Color(0xFF2D8E90),
            child: Text(
              '$index',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sensor $index: $title',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1D3E53),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: const TextStyle(color: Color(0xFF526676)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _connectSensorsPage() {
    return _pageCard(
      title: 'Connect Sensors',
      subtitle: 'We will quickly check both sensors before monitoring begins.',
      content: Column(
        children: [
          _sensorConnectionCard(
            sensorName: 'Sensor 1: Upper Arm Sensor',
            connected: _sensor1Connected,
          ),
          const SizedBox(height: 10),
          _sensorConnectionCard(
            sensorName: 'Sensor 2: Forearm Sensor',
            connected: _sensor2Connected,
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _connecting ? null : _connectSensors,
              icon: Icon(_connecting
                  ? Icons.sync_rounded
                  : Icons.bluetooth_connected_rounded),
              label: Text(_connecting ? 'Connecting...' : 'Connect Sensors'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF2D8E90),
                side: const BorderSide(color: Color(0xFF2D8E90)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
      primaryAction: FilledButton(
        onPressed: (_sensor1Connected && _sensor2Connected) ? _nextPage : null,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF2D8E90),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: const Text('Continue'),
      ),
    );
  }

  Widget _sensorConnectionCard({
    required String sensorName,
    required bool connected,
  }) {
    final color = connected ? const Color(0xFF159C6E) : const Color(0xFF688096);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: connected ? const Color(0xFFEAF8F1) : const Color(0xFFF4F8FC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: connected ? const Color(0xFFBDE7D2) : const Color(0xFFDCE8F3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            connected ? Icons.check_circle_rounded : Icons.sensors_outlined,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              sensorName,
              style: const TextStyle(
                color: Color(0xFF244256),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            connected ? 'Connected' : 'Not connected',
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _gentleIntroPage() {
    return _pageCard(
      title: 'You are ready.',
      subtitle:
          'The app will quietly monitor your PICC arm and provide gentle guidance when additional care may be helpful.',
      content: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF2FF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFCBDBF5)),
        ),
        child: const Text(
          'You can view your PICC arm status, sensor readiness, movement count, reminders, and your daily care checklist in one place.',
          style: TextStyle(
            color: Color(0xFF29465E),
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
      ),
      primaryAction: FilledButton(
        onPressed: _enterDashboard,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF2D8E90),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: const Text('Enter Dashboard'),
      ),
    );
  }
}
