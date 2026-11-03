import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:nseapscholarship/theme/nseap_theme.dart';

/// Modern bar chart for growth analytics.
class NseapBarChart extends StatelessWidget {
  const NseapBarChart({
    required this.values,
    required this.labels,
    this.color = AppColors.primary,
    this.height = 200,
    super.key,
  }) : assert(values.length == labels.length);

  final List<int> values;
  final List<String> labels;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, c) {
          final maxV = values.isEmpty ? 1 : values.reduce(math.max);
          final safeMax = maxV == 0 ? 1 : maxV;
          // Nice rounded max for grid
          final gridMax = _niceMax(safeMax);
          return CustomPaint(
            size: Size(c.maxWidth, height),
            painter: _BarPainter(
              values: values,
              labels: labels,
              maxValue: gridMax,
              barColor: color,
            ),
          );
        },
      ),
    );
  }

  static int _niceMax(int v) {
    if (v <= 10) return 10;
    if (v <= 50) return ((v + 9) ~/ 10) * 10;
    if (v <= 100) return ((v + 19) ~/ 20) * 20;
    if (v <= 500) return ((v + 49) ~/ 50) * 50;
    return ((v + 99) ~/ 100) * 100;
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.values,
    required this.labels,
    required this.maxValue,
    required this.barColor,
  });
  final List<int> values;
  final List<String> labels;
  final int maxValue;
  final Color barColor;

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 36.0;
    const bottomPad = 28.0;
    const topPad = 18.0;
    const rightPad = 8.0;

    final chartW = size.width - leftPad - rightPad;
    final chartH = size.height - topPad - bottomPad;
    if (chartW <= 0 || chartH <= 0 || values.isEmpty) return;

    // Grid lines + Y labels
    final gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1;
    final yStyle = const TextStyle(
      color: Color(0xFF94A3B8),
      fontSize: 10,
      fontWeight: FontWeight.w600,
    );
    for (var i = 0; i <= 3; i++) {
      final y = topPad + chartH * i / 3;
      final isEdge = i == 0 || i == 3;
      canvas.drawLine(
        Offset(leftPad, y),
        Offset(size.width - rightPad, y),
        gridPaint
          ..color = isEdge
              ? const Color(0xFFE2E8F0).withValues(alpha: 0.9)
              : const Color(0xFFF1F5F9),
      );
      // dashed for middle
      if (!isEdge) {
        // already solid light, keep as is for modern clean
      }
      final v = (maxValue * (3 - i) / 3).round();
      final tp = TextPainter(
        text: TextSpan(text: '$v', style: yStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftPad - tp.width - 8, y - 6));
    }

    // Bars
    final n = values.length;
    final gap = chartW * 0.12 / (n > 1 ? n : 1);
    final barW = (chartW - gap * (n + 1)) / n;
    final barWClamped = barW.clamp(18.0, 44.0);
    // Recalc gap to center
    final totalBarW = barWClamped * n + gap * (n + 1);
    final startX = leftPad + (chartW - totalBarW) / 2 + gap;

    final xStyle = const TextStyle(
      color: Color(0xFF64748B),
      fontSize: 11,
      fontWeight: FontWeight.w600,
    );
    final valueStyle = TextStyle(
      color: barColor,
      fontSize: 10,
      fontWeight: FontWeight.w800,
    );

    for (var i = 0; i < n; i++) {
      final v = values[i];
      final h = chartH * (v / maxValue);
      final x = startX + i * (barWClamped + gap);
      final y = topPad + chartH - h;
      final rect = Rect.fromLTWH(x, y, barWClamped, h);
      // Gradient fill — no borderRadius as requested
      final shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [barColor, barColor.withValues(alpha: 0.72)],
      ).createShader(Rect.fromLTWH(x, y, barWClamped, h));
      canvas.drawRect(rect, Paint()..shader = shader);
      // Subtle top highlight — no radius
      canvas.drawRect(
        Rect.fromLTWH(x, y, barWClamped, 4),
        Paint()..color = Colors.white.withValues(alpha: 0.18),
      );

      // Value pill above bar
      if (v > 0) {
        final label = '$v';
        final tp = TextPainter(
          text: TextSpan(text: label, style: valueStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        final pillW = tp.width + 10;
        final pillH = tp.height + 6;
        final pillX = x + barWClamped / 2 - pillW / 2;
        final pillY = y - pillH - 6;
        if (pillY > topPad - 6) {
          final pillRect = RRect.fromRectAndRadius(
            Rect.fromLTWH(pillX, pillY, pillW, pillH),
            const Radius.circular(20),
          );
          canvas.drawRRect(
            pillRect,
            Paint()..color = barColor.withValues(alpha: 0.10),
          );
          tp.paint(canvas, Offset(pillX + 5, pillY + 3));
        }
      }

      // X label
      final tpX = TextPainter(
        text: TextSpan(text: labels[i], style: xStyle),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: barWClamped + 16);
      tpX.paint(
        canvas,
        Offset(
          x + barWClamped / 2 - tpX.width / 2,
          size.height - bottomPad + 8,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) =>
      old.values != values || old.maxValue != maxValue || old.labels != labels;
}

/// One growth card: left bar chart, right stats column (approved/rejected or submitted/notSubmitted).
class NseapBarGrowthCard extends StatelessWidget {
  const NseapBarGrowthCard({
    required this.title,
    required this.subtitle,
    required this.values,
    required this.labels,
    required this.rightStats,
    this.barColor = AppColors.primary,
    this.height = 200,
    super.key,
  });

  final String title;
  final String subtitle;
  final List<int> values;
  final List<String> labels;
  final List<RightStat> rightStats;
  final Color barColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title.isNotEmpty) ...[
            // Header
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: barColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    title.toLowerCase().contains('scholar')
                        ? Icons.school_outlined
                        : Icons.trending_up_rounded,
                    size: 18,
                    color: barColor,
                  ),
                ),
                const SizedBox(width: 10),
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
                          letterSpacing: -0.3,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          if (rightStats.isNotEmpty) ...[
            _TopStatsRow(stats: rightStats),
            const SizedBox(height: 14),
            Container(height: 1, color: const Color(0xFFF1F5F9)),
            const SizedBox(height: 14),
          ],
          RepaintBoundary(
            child: NseapBarChart(
              values: values,
              labels: labels,
              color: barColor,
              height: height,
            ),
          ),
        ],
      ),
    );
  }
}

class RightStat {
  const RightStat({
    required this.label,
    required this.value,
    required this.share,
    required this.icon,
    required this.color,
  });
  final String label;
  final int value;
  final double share; // 0-100
  final IconData icon;
  final Color color;
}

class _RightStatsColumn extends StatelessWidget {
  const _RightStatsColumn({required this.stats});
  final List<RightStat> stats;

  @override
  Widget build(BuildContext context) {
    String fmt(int n) => n.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < stats.length; i++) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: stats[i].color.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: stats[i].color.withValues(alpha: 0.12)),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: stats[i].color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(stats[i].icon, size: 16, color: stats[i].color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stats[i].label,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        fmt(stats[i].value),
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (i < stats.length - 1) const SizedBox(height: 10),
        ],
        const SizedBox(height: 10),
        // Total footnote
        Builder(
          builder: (context) {
            final total = stats.fold<int>(0, (a, b) => a + b.value);
            return Text(
              'Total ${stats.length == 2 ? (stats[0].label == 'Approved' ? 'in window' : 'scholars') : ''}: ${fmt(total)}',
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            );
          },
        ),
      ],
    );
  }
}

class _TopStatsRow extends StatelessWidget {
  const _TopStatsRow({required this.stats});
  final List<RightStat> stats;

  @override
  Widget build(BuildContext context) {
    String fmt(int n) => n.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
    return Row(
      children: [
        for (var i = 0; i < stats.length; i++) ...[
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: stats[i].color.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: stats[i].color.withValues(alpha: 0.12),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: stats[i].color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(stats[i].icon, size: 16, color: stats[i].color),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stats[i].label,
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          fmt(stats[i].value),
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (i < stats.length - 1) const SizedBox(width: 10),
        ],
      ],
    );
  }
}

// Public factory helpers so dashboard can build rightStats easily
List<RightStat> buildApplicantRightStats({
  required int approved,
  required int rejected,
}) {
  final total = approved + rejected;
  double share(int v) =>
      total == 0 ? 0 : (v / total * 100).clamp(0, 100).toDouble();
  return [
    RightStat(
      label: 'Approved',
      value: approved,
      share: share(approved),
      icon: Icons.verified_outlined,
      color: const Color(0xFF059669),
    ),
    RightStat(
      label: 'Rejected',
      value: rejected,
      share: share(rejected),
      icon: Icons.cancel_outlined,
      color: const Color(0xFFDC2626),
    ),
  ];
}

List<RightStat> buildScholarRightStats({
  required int submitted,
  required int notSubmitted,
}) {
  final total = submitted + notSubmitted;
  double share(int v) =>
      total == 0 ? 0 : (v / total * 100).clamp(0, 100).toDouble();
  return [
    RightStat(
      label: 'Submitted',
      value: submitted,
      share: share(submitted),
      icon: Icons.assignment_turned_in_outlined,
      color: AppColors.primary,
    ),
    RightStat(
      label: 'Not Submitted',
      value: notSubmitted,
      share: share(notSubmitted),
      icon: Icons.pending_outlined,
      color: const Color(0xFFEA580C),
    ),
  ];
}
