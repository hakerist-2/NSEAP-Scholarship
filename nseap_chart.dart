import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:nseapscholarship/theme/nseap_theme.dart';

/// Monthly Applicant Growth line chart (Jan–Jun) with subtle fill & dots.
class NseapGrowthChart extends StatelessWidget {
  const NseapGrowthChart({
    required this.values,
    required this.labels,
    this.height = 220,
    super.key,
  }) : assert(values.length == labels.length);

  final List<int> values;
  final List<String> labels;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, c) {
          final maxV = values.isEmpty ? 1 : values.reduce(math.max);
          final safeMax = maxV == 0 ? 1 : maxV;
          return CustomPaint(
            size: Size(c.maxWidth, height),
            painter: _GrowthPainter(
              values: values,
              labels: labels,
              maxValue: safeMax,
            ),
          );
        },
      ),
    );
  }
}

class _GrowthPainter extends CustomPainter {
  _GrowthPainter({
    required this.values,
    required this.labels,
    required this.maxValue,
  });
  final List<int> values;
  final List<String> labels;
  final int maxValue;

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 36.0;
    const bottomPad = 26.0;
    const topPad = 12.0;
    const rightPad = 12.0;

    final chartW = size.width - leftPad - rightPad;
    final chartH = size.height - topPad - bottomPad;
    if (chartW <= 0 || chartH <= 0 || values.isEmpty) return;

    final gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1;

    // 4 horizontal grid lines
    for (var i = 0; i <= 3; i++) {
      final y = topPad + chartH * i / 3;
      if (i == 0 || i == 3) {
        canvas.drawLine(
          Offset(leftPad, y),
          Offset(size.width - rightPad, y),
          gridPaint..color = const Color(0xFFE2E8F0).withValues(alpha: 0.9),
        );
      } else {
        // dashed
        _dashedLine(
          canvas,
          Offset(leftPad, y),
          Offset(size.width - rightPad, y),
          gridPaint..color = const Color(0xFFF1F5F9),
        );
      }
    }

    // Y labels
    final yStyle = const TextStyle(
      color: Color(0xFF94A3B8),
      fontSize: 10,
      fontWeight: FontWeight.w600,
    );
    for (var i = 0; i <= 3; i++) {
      final v = (maxValue * (3 - i) / 3).round();
      final tp = TextPainter(
        text: TextSpan(text: '$v', style: yStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(leftPad - tp.width - 8, topPad + chartH * i / 3 - 6),
      );
    }

    // points
    double xFor(int i) =>
        leftPad + chartW * i / (values.length - 1).clamp(1, 999);
    double yFor(int v) => topPad + chartH * (1 - v / maxValue);

    final points = [
      for (var i = 0; i < values.length; i++) Offset(xFor(i), yFor(values[i])),
    ];

    // area fill
    final fillPath = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final p0 = points[i - 1];
      final p1 = points[i];
      final mx = (p0.dx + p1.dx) / 2;
      fillPath.cubicTo(mx, p0.dy, mx, p1.dy, p1.dx, p1.dy);
    }
    fillPath.lineTo(points.last.dx, topPad + chartH);
    fillPath.lineTo(points.first.dx, topPad + chartH);
    fillPath.close();
    canvas.drawPath(
      fillPath,
      Paint()
          ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.primary.withValues(alpha: 0.20), AppColors.primary.withValues(alpha: 0.0)],
        ).createShader(Rect.fromLTWH(leftPad, topPad, chartW, chartH)),
    );

    // line
    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final p0 = points[i - 1];
      final p1 = points[i];
      final mx = (p0.dx + p1.dx) / 2;
      linePath.cubicTo(mx, p0.dy, mx, p1.dy, p1.dx, p1.dy);
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = AppColors.primary
        ..strokeWidth = 2.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // dots
    for (final p in points) {
      canvas.drawCircle(p, 4.5, Paint()..color = Colors.white);
      canvas.drawCircle(
        p,
        4.5,
        Paint()
          ..color = AppColors.primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2,
      );
      canvas.drawCircle(p, 2, Paint()..color = AppColors.primary);
    }

    // X labels
    final xStyle = const TextStyle(
      color: Color(0xFF64748B),
      fontSize: 11,
      fontWeight: FontWeight.w600,
    );
    for (var i = 0; i < labels.length; i++) {
      final tp = TextPainter(
        text: TextSpan(text: labels[i], style: xStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(xFor(i) - tp.width / 2, size.height - bottomPad + 8),
      );
    }
  }

  void _dashedLine(Canvas c, Offset a, Offset b, Paint p) {
    const dash = 5.0;
    const gap = 5.0;
    var cur = a.dx;
    while (cur < b.dx) {
      final next = (cur + dash).clamp(a.dx, b.dx);
      c.drawLine(Offset(cur, a.dy), Offset(next, a.dy), p);
      cur = next + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _GrowthPainter old) =>
      old.values != values || old.maxValue != maxValue || old.labels != labels;
}

/// Wrapper card for the growth chart with dropdown.
class NseapGrowthChartCard extends StatelessWidget {
  const NseapGrowthChartCard({
    required this.values,
    required this.labels,
    this.selectedRange = 'Last 6 Months',
    this.onRangeChanged,
    super.key,
  });

  final List<int> values;
  final List<String> labels;
  final String selectedRange;
  final ValueChanged<String?>? onRangeChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Expanded(
                child: Text(
                  'Monthly Applicant Growth',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedRange,
                    isDense: true,
                    style: const TextStyle(
                      color: Color(0xFF334155),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: Color(0xFF64748B),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'Last 6 Months',
                        child: Text('Last 6 Months'),
                      ),
                      DropdownMenuItem(
                        value: 'Last 3 Months',
                        child: Text('Last 3 Months'),
                      ),
                      DropdownMenuItem(
                        value: 'This Year',
                        child: Text('This Year'),
                      ),
                    ],
                    onChanged: onRangeChanged ?? (_) {},
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          NseapGrowthChart(values: values, labels: labels),
        ],
      ),
    );
  }
}
