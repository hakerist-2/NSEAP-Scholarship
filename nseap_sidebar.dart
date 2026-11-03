import 'package:flutter/material.dart';
import 'package:nseapscholarship/theme/nseap_theme.dart';

import '../../admin_navigation.dart';

/// Modern, clean sidebar — white surface with soft hierarchy,
/// grouped navigation and subtle selected treatment.
class NseapSidebar extends StatelessWidget {
  const NseapSidebar({
    required this.selected,
    required this.onSelect,
    required this.onSignOut,
    this.adminName = 'Admin User',
    this.adminEmail = 'admin@nseap.gov.ph',
    this.adminRole = 'Super Admin',
    this.badges = const {},
    super.key,
  });

  final AdminSection selected;
  final ValueChanged<AdminSection> onSelect;
  final VoidCallback onSignOut;
  final String adminName;
  final String adminEmail;
  final String adminRole;
  final Map<AdminSection, int> badges;

  @override
  Widget build(BuildContext context) {
    const main = [
      AdminSection.overview,
      AdminSection.applicants,
      AdminSection.interviews,
      AdminSection.scholars,
      AdminSection.requirements,
      AdminSection.announcements,
      AdminSection.reports,
    ];
    const system = [
      AdminSection.notifications,
      AdminSection.helpSupport,
      AdminSection.activityLogs,
      AdminSection.settings,
    ];

    return Container(
      width: 260,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: AppColors.borderLight)),
      ),
      child: Column(
        children: [
          // ── Brand header ──
          Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: AppColors.borderLight)),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.18),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.school_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NSEAP',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: Color(0xFF0F172A),
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                          height: 1,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'LGU Lal-lo · Scholarship',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.1,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Navigation ──
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
              children: [
                _SectionLabel('Menu'),
                const SizedBox(height: 6),
                for (final s in main)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _SidebarItem(
                      icon: s.icon,
                      label: s.label,
                      selected: s == selected,
                      badgeCount: badges[s] ?? 0,
                      onTap: () => onSelect(s),
                    ),
                  ),
                const SizedBox(height: 16),
                _SectionLabel('System'),
                const SizedBox(height: 6),
                for (final s in system)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _SidebarItem(
                      icon: s.icon,
                      label: s.label,
                      selected: s == selected,
                      badgeCount: badges[s] ?? 0,
                      onTap: () => onSelect(s),
                    ),
                  ),
              ],
            ),
          ),

          // ── Admin footer ──
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      adminName.isEmpty
                          ? 'A'
                          : adminName.trim()[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        adminName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                          height: 1.1,
                        ),
                      ),
                      Text(
                        adminRole,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Tooltip(
                  message: 'Sign out',
                  child: InkWell(
                    onTap: onSignOut,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.borderLight),
                      ),
                      child: const Icon(
                        Icons.logout_rounded,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                    ),
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontFamily: 'Inter',
          color: AppColors.textTertiary,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          height: 1,
        ),
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.danger = false,
    this.badgeCount = 0,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool danger;
  final int badgeCount;
  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final danger = widget.danger;

    final bg = selected
        ? AppColors.primary
        : danger && _hovered
        ? AppColors.errorLight
        : _hovered
        ? AppColors.surfaceContainerHigh
        : Colors.transparent;

    final fg = selected
        ? Colors.white
        : danger
        ? AppColors.error
        : _hovered
        ? const Color(0xFF0F172A)
        : const Color(0xFF475569);

    final iconBg = selected
        ? Colors.white.withValues(alpha: 0.18)
        : danger
        ? AppColors.errorLight
        : _hovered
        ? Colors.white
        : AppColors.surfaceContainer;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: AppDurations.hover,
        curve: Curves.easeOutCubic,
        height: 40,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: selected
              ? Border.all(color: Colors.white.withValues(alpha: 0.12))
              : danger && _hovered
              ? Border.all(color: AppColors.error.withValues(alpha: 0.14))
              : _hovered
              ? Border.all(color: AppColors.borderLight)
              : null,
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.22),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(12),
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: iconBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected
                            ? Colors.white.withValues(alpha: 0.22)
                            : danger
                            ? AppColors.error.withValues(alpha: 0.12)
                            : Colors.transparent,
                      ),
                    ),
                    child: Icon(
                      widget.icon,
                      size: 16,
                      color: selected ? Colors.white : fg,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: fg,
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        letterSpacing: 0.1,
                        height: 1,
                      ),
                    ),
                  ),
                  if (widget.badgeCount > 0)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: selected ? Colors.white : AppColors.error,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        widget.badgeCount > 99 ? '99+' : '${widget.badgeCount}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: selected ? AppColors.primary : Colors.white,
                          height: 1,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
