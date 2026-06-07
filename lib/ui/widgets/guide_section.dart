import 'package:flutter/material.dart';

import '../models/guide_item.dart';
import 'guide_card.dart';

class GuideSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final Color backgroundColor;
  final List<GuideItem> cards;
  final IconData statusIcon;
  final String? detectedRiskTitle;

  const GuideSection({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.backgroundColor,
    required this.cards,
    required this.statusIcon,
    this.detectedRiskTitle,
  });

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 560;
        const cardHeight = 330.0;

        Widget buildCard(GuideItem item) {
          final isDetected = detectedRiskTitle == item.title;

          return SizedBox(
            width: isCompact ? double.infinity : 230,
            height: cardHeight,
            child: GuideCard(
              item: item,
              accentColor: isDetected ? Colors.red : color,
              statusIcon: statusIcon,
              isDetected: isDetected,
            ),
          );
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: color.withValues(alpha: 0.18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: color, size: 30),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: TextStyle(
                      color: color,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Center(
                child: isCompact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          for (var index = 0;
                              index < cards.length;
                              index++) ...[
                            buildCard(cards[index]),
                            if (index != cards.length - 1)
                              const SizedBox(height: 16),
                          ],
                        ],
                      )
                    : Wrap(
                        alignment: WrapAlignment.center,
                        runAlignment: WrapAlignment.center,
                        spacing: 16,
                        runSpacing: 16,
                        children: cards.map(buildCard).toList(),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
