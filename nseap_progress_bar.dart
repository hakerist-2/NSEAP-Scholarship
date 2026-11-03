import 'package:flutter/material.dart';
import 'package:nseapscholarship/theme/nseap_theme.dart';

/// Single progress row used inside analytics cards.
class NseapProgressBarItem extends StatelessWidget {
  const NseapProgressBarItem({
    required this.label,
    required this.value,
    required this.fraction,
    this.valueLabel,
    this.showPercentage = true,
    super.key,
  });

  final String label;
  final int value;
  final double fraction; // 0..1
  final String? valueLabel;
  final bool showPercentage;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF334155),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              valueLabel ?? '$value',
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (showPercentage) ...[
              const SizedBox(width: 6),
              Text(
                '${(fraction * 100).round()}%',
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: fraction.clamp(0, 1),
            minHeight: 7,
            backgroundColor: const Color(0xFFE2E8F0),
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
      ],
    );
  }
}

/// Card wrapping a list of progress bars (Top Schools / Programs / Barangay).
class NseapAnalyticsCard extends StatelessWidget {
  const NseapAnalyticsCard({
    required this.title,
    required this.subtitle,
    required this.items,
    this.icon,
    this.trailing,
    super.key,
  });

  final String title;
  final String subtitle;
  final List<NseapProgressBarItem> items;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null)
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: const Color(0xFFDBEAFE)),
                  ),
                  child: Icon(icon, size: 18, color: AppColors.primary),
                ),
              if (icon != null) const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 16),
          ...items.map(
            (w) =>
                Padding(padding: const EdgeInsets.only(bottom: 14), child: w),
          ),
          if (items.isEmpty)
            const Text(
              'No record yet',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
        ],
      ),
    );
  }
}
