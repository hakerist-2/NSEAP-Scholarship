import 'package:flutter/material.dart';
import 'package:nseapscholarship/theme/nseap_theme.dart';

/// Status badge used across tables and cards.
///
/// Variants: Under Review (amber), Pending (slate), Approved (green),
/// Rejected (red). Colors tuned to government/education style.
enum NseapBadgeVariant {
  underReview,
  pending,
  approved,
  rejected,
  interview,
  active,
}

class NseapStatusBadge extends StatelessWidget {
  const NseapStatusBadge({required this.label, this.variant, super.key});

  /// Convenience ctor mapping raw status string to variant.
  factory NseapStatusBadge.fromStatus(String status, {Key? key}) {
    final normalized = status.toLowerCase().trim();
    final variant = switch (normalized) {
      'approved' ||
      'scholar' ||
      'verified' ||
      'active' => NseapBadgeVariant.approved,
      'rejected' ||
      'withdrawn' ||
      'cancelled' ||
      'terminated' => NseapBadgeVariant.rejected,
      'under_review' || 'under review' => NseapBadgeVariant.underReview,
      'interview_scheduled' ||
      'interview' ||
      'scheduled' ||
      'interview_completed' => NseapBadgeVariant.interview,
      _ => NseapBadgeVariant.pending,
    };
    final label = switch (normalized) {
      'under_review' => 'Under Review',
      'interview_scheduled' => 'Scheduled',
      'interview_completed' => 'Interviewed',
      'scholar' => 'Approved',
      _ =>
        status
            .split('_')
            .map(
              (p) => p.isEmpty ? '' : '${p[0].toUpperCase()}${p.substring(1)}',
            )
            .join(' '),
    };
    return NseapStatusBadge(label: label, variant: variant, key: key);
  }

  final String label;
  final NseapBadgeVariant? variant;

  @override
  Widget build(BuildContext context) {
    final v = variant ?? _infer(label);
    final (bg, fg, dot) = switch (v) {
      NseapBadgeVariant.underReview => (
        const Color(0xFFFFF7ED),
        const Color(0xFF9A3412),
        const Color(0xFFF59E0B),
      ),
      NseapBadgeVariant.pending => (
        const Color(0xFFF1F5F9),
        const Color(0xFF475569),
        const Color(0xFF94A3B8),
      ),
      NseapBadgeVariant.approved => (
        const Color(0xFFECFDF5),
        const Color(0xFF065F46),
        const Color(0xFF10B981),
      ),
      NseapBadgeVariant.rejected => (
        const Color(0xFFFEF2F2),
        const Color(0xFF991B1B),
        const Color(0xFFEF4444),
      ),
      NseapBadgeVariant.interview => (
        const Color(0xFFEFF6FF),
        AppColors.primary,
        const Color(0xFF3B82F6),
      ),
      NseapBadgeVariant.active => (
        const Color(0xFFECFDF5),
        const Color(0xFF065F46),
        const Color(0xFF10B981),
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }

  NseapBadgeVariant _infer(String label) {
    final l = label.toLowerCase();
    if (l.contains('approved') || l.contains('scholar')) {
      return NseapBadgeVariant.approved;
    }
    if (l.contains('reject')) return NseapBadgeVariant.rejected;
    if (l.contains('review')) return NseapBadgeVariant.underReview;
    if (l.contains('interview') || l.contains('scheduled')) {
      return NseapBadgeVariant.interview;
    }
    return NseapBadgeVariant.pending;
  }
}
