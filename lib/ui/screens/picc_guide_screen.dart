import 'package:flutter/material.dart';

import '../data/picc_guide_data.dart';
import '../models/guide_item.dart';
import '../widgets/guide_section.dart';

class PiccGuideScreen extends StatefulWidget {
  const PiccGuideScreen({super.key});

  @override
  State<PiccGuideScreen> createState() => _PiccGuideScreenState();
}

class _PiccGuideScreenState extends State<PiccGuideScreen> {
  String searchQuery = '';

  // Connect this variable with your real ML result later.
  // Example:
  // if ML predicts "Elbow Flexion Risk", set detectedRiskTitle = 'Elbow Flexion';
  String? detectedRiskTitle = 'Elbow Flexion';

  List<GuideItem> _filterCards(List<GuideItem> cards) {
    final query = searchQuery.trim().toLowerCase();

    if (query.isEmpty) {
      return cards;
    }

    return cards.where((item) {
      return item.title.toLowerCase().contains(query) ||
          item.description.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filteredAvoidCards = _filterCards(avoidCards);
    final filteredSafeCards = _filterCards(safeCards);
    final filteredCareCards = _filterCards(careCards);

    return Scaffold(
      backgroundColor: const Color(0xFFF6FAFF),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: _HeaderSection()),
            const SizedBox(height: 24),
            const Center(child: _WhyCareCard()),
            const SizedBox(height: 20),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: _SearchBar(
                  onChanged: (value) {
                    setState(() {
                      searchQuery = value;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (detectedRiskTitle != null)
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: _DetectedRiskBanner(
                    riskTitle: detectedRiskTitle!,
                    onClear: () {
                      setState(() {
                        detectedRiskTitle = null;
                      });
                    },
                  ),
                ),
              ),
            const SizedBox(height: 24),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: GuideSection(
                  title: 'MOVEMENTS TO AVOID',
                  icon: Icons.warning_rounded,
                  color: Colors.red,
                  backgroundColor: const Color(0xFFFFF1F1),
                  cards: filteredAvoidCards,
                  statusIcon: Icons.cancel_rounded,
                  detectedRiskTitle: detectedRiskTitle,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: GuideSection(
                  title: 'SAFE MOVEMENTS',
                  icon: Icons.check_circle,
                  color: Colors.green,
                  backgroundColor: const Color(0xFFEFFFF5),
                  cards: filteredSafeCards,
                  statusIcon: Icons.check_circle_rounded,
                  detectedRiskTitle: detectedRiskTitle,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: GuideSection(
                  title: 'DAILY PICC CARE',
                  icon: Icons.medical_services_rounded,
                  color: Colors.blue,
                  backgroundColor: const Color(0xFFEFF7FF),
                  cards: filteredCareCards,
                  statusIcon: Icons.health_and_safety_rounded,
                  detectedRiskTitle: detectedRiskTitle,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: const _WarningSignsSection(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderSection extends StatelessWidget {
  const _HeaderSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFEAF4FF),
            Color(0xFFF8FBFF),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 750;

          const textSection = Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PICC Movement & Care Guide',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF10213D),
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  'Safe movements and proper daily care help protect your PICC line and reduce the risk of complications.',
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.4,
                    color: Color(0xFF334766),
                  ),
                ),
              ],
            ),
          );

          final imageSection = SizedBox(
            height: 250,
            width: 340,
            child: Image.asset(
              'header_patient.png',
              fit: BoxFit.cover,
            ),
          );

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PICC Movement & Care Guide',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF10213D),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Safe movements and proper daily care help protect your PICC line and reduce the risk of complications.',
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: Color(0xFF334766),
                  ),
                ),
                const SizedBox(height: 16),
                Center(child: imageSection),
              ],
            );
          }

          return Row(
            children: [
              textSection,
              const SizedBox(width: 20),
              imageSection,
            ],
          );
        },
      ),
    );
  }
}

class _WhyCareCard extends StatelessWidget {
  const _WhyCareCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF7FF),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFC9DFFF)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.shield_rounded,
            size: 58,
            color: Color(0xFF2F80ED),
          ),
          SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Why PICC Care Matters',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0E3A7A),
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'A PICC (Peripherally Inserted Central Catheter) is a long, flexible tube placed into a vein in the arm to deliver medicines, fluids, or nutrition. Proper care and safe movement habits help prevent infection, irritation, blockage, and accidental dislodgement.',
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.4,
                    color: Color(0xFF1E2A3A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final ValueChanged<String> onChanged;

  const _SearchBar({
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Search PICC care tips...',
        prefixIcon: const Icon(Icons.search_rounded),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _DetectedRiskBanner extends StatelessWidget {
  final String riskTitle;
  final VoidCallback onClear;

  const _DetectedRiskBanner({
    required this.riskTitle,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE8E8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Colors.red,
            size: 32,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Detected risk movement: $riskTitle. Please reduce this movement and keep your PICC arm relaxed.',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF8A1F1F),
              ),
            ),
          ),
          TextButton(
            onPressed: onClear,
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

class _WarningSignsSection extends StatelessWidget {
  const _WarningSignsSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1ED),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: const Color(0xFFFFC8BD),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.emergency_rounded,
                color: Colors.red,
                size: 30,
              ),
              SizedBox(width: 10),
              Text(
                'WARNING SIGNS',
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Contact your healthcare provider if you notice:',
            style: TextStyle(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              runAlignment: WrapAlignment.center,
              spacing: 14,
              runSpacing: 14,
              children: warningSigns.map((item) {
                return SizedBox(
                  width: 146,
                  height: 182,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        height: 182,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.red.withValues(alpha: 0.15),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            const Align(
                              alignment: Alignment.topLeft,
                              child: Icon(
                                Icons.medical_services_rounded,
                                color: Colors.red,
                                size: 22,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: Center(
                                child: SizedBox(
                                  height: 80,
                                  width: 80,
                                  child: Image.asset(
                                    item.imagePath,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              item.title,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              softWrap: true,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                                height: 1.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
