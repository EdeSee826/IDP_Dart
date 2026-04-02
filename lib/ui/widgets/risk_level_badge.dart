import 'package:flutter/material.dart';

import '../../models/patient_state.dart';

class RiskLevelBadge extends StatelessWidget {
  const RiskLevelBadge({
    super.key,
    required this.level,
  });

  final RiskLevel level;

  @override
  Widget build(BuildContext context) {
    final (text, color) = switch (level) {
      RiskLevel.low => ('Low', const Color(0xFF1E9E58)),
      RiskLevel.medium => ('Medium', const Color(0xFFE9A111)),
      RiskLevel.high => ('High', const Color(0xFFD14343)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
