import 'package:flutter/material.dart';

/// Reusable statistic card per spec: icon container, value, trend, border/shadow.
class NseapStatisticCard extends StatelessWidget {
  const NseapStatisticCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    this.trendLabel,
    this.trendUp,
    this.trendColor,
    this.trendTooltip,
    this.onTrendTap,
    this.onTap,
    this.cardWidth,
    super.key,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String? trendLabel;
  final bool? trendUp;
  final Color? trendColor;
  final String? trendTooltip;
  final VoidCallback? onTrendTap;
  final VoidCallback? onTap;

  /// Explicit per-card width. When provided, the card avoids LayoutBuilder
  /// so it can be placed inside IntrinsicHeight without
  /// "LayoutBuilder does not support returning intrinsic dimensions".
  final double? cardWidth;

  Widget _trendBadge(BuildContext context, Widget badge) {
    if (trendTooltip == null && onTrendTap == null) return badge;
    final withTooltip = trendTooltip != null
        ? Tooltip(
            message: trendTooltip!,
            triggerMode: TooltipTriggerMode.tap,
            showDuration: const Duration(seconds: 3),
            child: badge,
          )
        : badge;
    if (onTrendTap == null) return withTooltip;
    return InkWell(
      onTap: onTrendTap,
      borderRadius: BorderRadius.circular(20),
      child: withTooltip,
    );
  }

  @override
  Widget build(BuildContext context) {
    // If cardWidth is provided (dashboard grid passes (availableWidth-gap*4)/5),
    // build directly without LayoutBuilder to remain compatible with
    // IntrinsicHeight. Otherwise fall back to LayoutBuilder for standalone use.
    if (cardWidth != null) {
      return _buildCard(context, cardWidth!);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final cw = constraints.maxWidth;
        return _buildCard(context, cw);
      },
    );
  }

  Widget _buildCard(BuildContext context, double cardWidth) {
    final isNarrow = cardWidth < 180;
    final isVeryNarrow = cardWidth < 120;
    final padding = isVeryNarrow
        ? 8.0
        : isNarrow
        ? 10.0
        : 16.0;
    final iconSize = isVeryNarrow
        ? 30.0
        : isNarrow
        ? 34.0
        : 42.0;
    final iconIconSize = isVeryNarrow
        ? 16.0
        : isNarrow
        ? 17.0
        : 20.0;
    final titleFont = isVeryNarrow
        ? 10.0
        : isNarrow
        ? 10.5
        : 12.0;
    final valueFont = isVeryNarrow
        ? 16.0
        : isNarrow
        ? 18.0
        : 26.0;
    final vsFont = isVeryNarrow
        ? 9.0
        : isNarrow
        ? 10.0
        : 11.0;
    final gapTop = isNarrow ? 10.0 : 18.0;

    final card = Container(
      constraints: BoxConstraints(minHeight: isNarrow ? 132 : 164),
      padding: EdgeInsets.all(padding),
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
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // On narrow cards stack icon above trend to save width
          if (isNarrow)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: iconSize,
                  height: iconSize,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: iconColor, size: iconIconSize),
                ),
                if (trendLabel != null) ...[
                  const SizedBox(height: 6),
                  _trendBadge(
                    context,
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isVeryNarrow ? 6 : 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: (trendColor ?? const Color(0xFF10B981))
                            .withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            (trendUp ?? true)
                                ? Icons.trending_up_rounded
                                : Icons.trending_down_rounded,
                            size: 11,
                            color: trendColor ?? const Color(0xFF059669),
                          ),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              trendLabel!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: trendColor ?? const Color(0xFF059669),
                                fontSize: isVeryNarrow ? 9 : 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: iconSize,
                  height: iconSize,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: iconIconSize),
                ),
                const SizedBox(width: 8),
                if (trendLabel != null)
                  Flexible(
                    child: _trendBadge(
                      context,
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: (trendColor ?? const Color(0xFF10B981))
                              .withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              (trendUp ?? true)
                                  ? Icons.trending_up_rounded
                                  : Icons.trending_down_rounded,
                              size: 13,
                              color: trendColor ?? const Color(0xFF059669),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                trendLabel!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: trendColor ?? const Color(0xFF059669),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          SizedBox(height: gapTop),
          Text(
            title,
            maxLines: isNarrow ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: const Color(0xFF64748B),
              fontSize: titleFont,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                color: const Color(0xFF0F172A),
                fontSize: valueFont,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'vs last cycle',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: const Color(0xFF94A3B8),
              fontSize: vsFont,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: card,
      ),
    );
  }
}
