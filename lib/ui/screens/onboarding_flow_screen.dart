import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/backend_status_provider.dart';
import '../../state/session_controller.dart';
import '../widgets/sensor_connection_panel.dart';

class OnboardingFlowScreen extends ConsumerStatefulWidget {
  const OnboardingFlowScreen({super.key});

  @override
  ConsumerState<OnboardingFlowScreen> createState() =>
      _OnboardingFlowScreenState();
}

class _OnboardingFlowScreenState extends ConsumerState<OnboardingFlowScreen> {
  final PageController _pageController = PageController();
  int _pageIndex = 0;

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
                color:
                    active ? const Color(0xFF2D8E90) : const Color(0xFFD2E3EE),
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
    Widget? primaryAction,
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
                if (primaryAction != null) ...[
                  SizedBox(width: double.infinity, child: primaryAction),
                ],
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: const Text('Get Started'),
      ),
    );
  }

  Widget _sensorPlacementPage() {
    return _pageCard(
      title: 'Sensor Placement',
      subtitle:
          'Place both wearable sensors comfortably for reliable daily monitoring.',
      content: Column(
        children: [
          // MAIN IMAGE SECTION
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 320,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'images/image_2.png',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFEEF4F6), Color(0xFFDDEBE8)],
                        ),
                      ),
                      child: const Center(
                        child: Icon(Icons.accessibility_new_rounded,
                            size: 66, color: Color(0xFF7A8698)),
                      ),
                    ),
                  ),

                  // Add interactive markers aligned to image positions
                  Align(
                    alignment: const FractionalOffset(0.24, 0.30),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: GestureDetector(
                        onTap: () => _showSensorSheet(
                          title: 'Sensor 1: Upper Arm Sensor',
                          connected:
                              ref.read(backendStatusProvider).device1Connected,
                          batteryLevel: ref
                              .read(backendStatusProvider)
                              .device1BatteryPercent,
                        ),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color:
                                ref.read(backendStatusProvider).device1Connected
                                    ? const Color(0xFF20B26C)
                                    : const Color(0xFFE5484D),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x22000000),
                                blurRadius: 6,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Text('1',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ),
                    ),
                  ),

                  Align(
                    alignment: const FractionalOffset(0.18, 0.80),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: GestureDetector(
                        onTap: () => _showSensorSheet(
                          title: 'Sensor 2: Wrist Sensor',
                          connected:
                              ref.read(backendStatusProvider).device2Connected,
                          batteryLevel: ref
                              .read(backendStatusProvider)
                              .device2BatteryPercent,
                        ),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color:
                                ref.read(backendStatusProvider).device2Connected
                                    ? const Color(0xFF20B26C)
                                    : const Color(0xFFE5484D),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x22000000),
                                blurRadius: 6,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Text('2',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // SENSOR CLOSE-UP SECTION
          LayoutBuilder(builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 500;
            return isNarrow
                ? Column(
                    children: [
                      _instructionCard(
                        asset: 'images/image_3.png',
                        title: 'Sensor 1: Upper Arm Sensor',
                        description:
                            'Placed above the elbow region on the upper arm.',
                      ),
                      const SizedBox(height: 10),
                      _instructionCard(
                        asset: 'images/image_4.png',
                        title: 'Sensor 2: Wrist Sensor',
                        description:
                            'Placed comfortably near the wrist/forearm region.',
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: _instructionCard(
                          asset: 'images/image_3.png',
                          title: 'Sensor 1: Upper Arm Sensor',
                          description:
                              'Placed above the elbow region on the upper arm.',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _instructionCard(
                          asset: 'images/image_4.png',
                          title: 'Sensor 2: Wrist Sensor',
                          description:
                              'Placed comfortably near the wrist/forearm region.',
                        ),
                      ),
                    ],
                  );
          }),

          const SizedBox(height: 14),

          // PLACEMENT TIPS (kept)
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
                Text(
                    '• Avoid placing sensors directly on elbow or wrist joints'),
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: const Text('Continue'),
      ),
    );
  }

  Widget _instructionCard({
    required String asset,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD6ECE4)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F5BA8),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              asset,
              height: 110,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                height: 110,
                color: const Color(0xFFF6F9F8),
                child: const Center(
                  child: Icon(Icons.photo, color: Color(0xFF9AA5AE)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
                fontWeight: FontWeight.w800, color: Color(0xFF1D3E53)),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: const TextStyle(color: Color(0xFF526676)),
          ),
        ],
      ),
    );
  }

  Widget _connectSensorsPage() {
    return _pageCard(
      title: 'Connect Sensors',
      subtitle:
          'Connect both wearable sensors to record your first static and functional baseline before monitoring.',
      content: SensorConnectionPanel(
        showContinueButton: true,
        showImage: false,
        continueLabel: 'Continue',
        onContinue: _enterDashboard,
      ),
      primaryAction: null,
    );
  }

  Future<void> _showSensorSheet({
    required String title,
    required bool connected,
    required int? batteryLevel,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final backendStatus = ref.watch(backendStatusProvider);
        final bool isDevice1 = title.contains('Sensor 1');
        final bool? staticPassed = isDevice1
            ? backendStatus.device1StaticPassed
            : backendStatus.device2StaticPassed;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Status:',
                      style: TextStyle(color: Color(0xFF667085))),
                  const SizedBox(width: 8),
                  Text(
                    connected ? 'Connected' : 'Disconnected',
                    style: TextStyle(
                      color: connected
                          ? const Color(0xFF20B26C)
                          : const Color(0xFFE5484D),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Battery:',
                      style: TextStyle(color: Color(0xFF667085))),
                  const SizedBox(width: 8),
                  Text(
                    batteryLevel != null ? '$batteryLevel%' : 'Not exposed',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Orientation check:',
                      style: TextStyle(color: Color(0xFF667085))),
                  const SizedBox(width: 8),
                  if (staticPassed == null) ...[
                    const Text('Not checked',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ] else if (staticPassed == true) ...[
                    const Text('PASS',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1FAD66))),
                  ] else ...[
                    const Text('FAIL',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFE23F3F))),
                  ]
                ],
              ),
              if (staticPassed == false) ...[
                const SizedBox(height: 8),
                const Text(
                  'Check orientation: is the device marker pointing downwards?',
                  style: TextStyle(color: Color(0xFF667085)),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'Connection status is managed by the backend.',
                style: TextStyle(color: Color(0xFF667085)),
              ),
            ],
          ),
        );
      },
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: const Text('Enter Dashboard'),
      ),
    );
  }
}
