import 'package:flutter/material.dart';
import 'package:nseapscholarship/theme/nseap_theme.dart';

/// Top app bar per spec: search field, notification icon, help icon, avatar.
class NseapTopBar extends StatelessWidget {
  const NseapTopBar({
    this.hint = 'Search applicants, scholars...',
    this.onSearchChanged,
    this.onNotificationTap,
    this.onHelpTap,
    this.onProfileTap,
    this.adminName = 'Admin',
    this.adminInitial = 'A',
    this.notificationCount = 0,
    this.showMenuButton = false,
    this.onMenuTap,
    super.key,
  });

  final String hint;
  final ValueChanged<String>? onSearchChanged;
  final VoidCallback? onNotificationTap;
  final VoidCallback? onHelpTap;
  final VoidCallback? onProfileTap;
  final String adminName;
  final String adminInitial;
  final int notificationCount;
  final bool showMenuButton;
  final VoidCallback? onMenuTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (showMenuButton) ...[
            IconButton(
              onPressed: onMenuTap,
              icon: const Icon(Icons.menu_rounded),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFF8FAFC),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          // Search removed per admin_shell requirement — keep layout balanced with spacer
          const Spacer(),
          // Help — hidden when no handler (Help & Support removed)
          if (onHelpTap != null) ...[
            _IconBtn(
              icon: Icons.help_outline_rounded,
              tooltip: 'Help',
              onTap: onHelpTap,
            ),
            const SizedBox(width: 8),
          ],
          // Notifications
          Badge(
            isLabelVisible: notificationCount > 0,
            label: Text(
              '$notificationCount',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
            ),
            backgroundColor: const Color(0xFFEF4444),
            offset: const Offset(-2, 2),
            child: _IconBtn(
              icon: Icons.notifications_none_rounded,
              tooltip: 'Notifications',
              onTap: onNotificationTap,
            ),
          ),
          const SizedBox(width: 12),
          Container(width: 1, height: 28, color: const Color(0xFFE2E8F0)),
          const SizedBox(width: 12),
          // Avatar — logo A only
          InkWell(
            onTap: onProfileTap,
            borderRadius: BorderRadius.circular(20),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.primary,
              child: Text(
                adminInitial.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, this.onTap, this.tooltip});
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: const Color(0xFFF8FAFC),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 19, color: const Color(0xFF475569)),
          ),
        ),
      ),
    );
  }
}
