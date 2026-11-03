import 'package:flutter/material.dart';
import 'package:nseapscholarship/repositories/support_repository.dart';
import 'package:nseapscholarship/services/realtime_sync.dart';
import 'package:nseapscholarship/theme/nseap_theme.dart';

import 'admin_navigation.dart';
import 'data/admin_repository.dart';
import 'models/admin_models.dart';
import 'pages/admin_pages.dart';
import 'pages/support/help_support_admin_page.dart';
import 'widgets/admin_widgets.dart';
import 'widgets/dashboard/nseap_sidebar.dart';

/// Hosts authenticated admin pages and their responsive navigation chrome.
class AdminShell extends StatefulWidget {
  const AdminShell({
    required this.repository,
    required this.profile,
    required this.onProfileChanged,
    required this.onSignedOut,
    super.key,
  });

  final AdminRepository repository;
  final AdminProfile profile;
  final ValueChanged<AdminProfile> onProfileChanged;
  final VoidCallback onSignedOut;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> with RealtimeSyncMixin {
  @override
  Set<String> get realtimeTables => const {
    'notifications',
    'admin_users',
    'users',
    'support_conversations',
    'support_messages',
    'support_reads',
  };
  @override
  Future<void> refreshRealtime() async {
    _refreshUnreadCount();
    _refreshSupportUnread();
    final profile = await widget.repository.getCurrentAdmin();
    if (!mounted || profile == null) return;
    if (profile.name != _profile.name ||
        profile.email != _profile.email ||
        profile.username != _profile.username ||
        profile.role != _profile.role ||
        profile.accountStatus != _profile.accountStatus ||
        profile.mustChangePassword != _profile.mustChangePassword) {
      _profileChanged(profile);
    }
  }

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _supportRepo = SupportRepository();
  AdminSection _selected = AdminSection.overview;
  late AdminProfile _profile = widget.profile;
  late Future<int> _unreadNotifications = _loadUnreadNotifications();
  int _unreadSupport = 0;
  // Retain initialized pages so filters and in-page state survive navigation.
  late final Map<AdminSection, Widget> _pageCache = {
    AdminSection.overview: DashboardAdminPage(
      repository: widget.repository,
      onNavigate: _select,
    ),
  };

  Widget _pageFor(AdminSection section) => switch (section) {
    AdminSection.overview => DashboardAdminPage(
      repository: widget.repository,
      onNavigate: _select,
    ),
    AdminSection.applicants => ApplicantsAdminPage(
      repository: widget.repository,
    ),
    AdminSection.interviews => InterviewsAdminPage(
      repository: widget.repository,
    ),
    AdminSection.scholars => ScholarsAdminPage(repository: widget.repository),
    AdminSection.requirements => SemesterRequirementsAdminPage(
      repository: widget.repository,
    ),
    AdminSection.announcements => AnnouncementsAdminPage(
      repository: widget.repository,
    ),
    AdminSection.reports => ReportsAdminPage(repository: widget.repository),
    AdminSection.settings => _settingsPage(_profile),
    AdminSection.helpSupport => const HelpSupportAdminPage(active: true),
    AdminSection.notifications => NotificationsAdminPage(
      repository: widget.repository,
      onCountChanged: _refreshUnreadCount,
    ),
    AdminSection.activityLogs => ActivityLogsAdminPage(
      repository: widget.repository,
    ),
  };

  Widget _settingsPage(AdminProfile profile) => SettingsAdminPage(
    repository: widget.repository,
    profile: profile,
    onProfileChanged: _profileChanged,
    onSignedOut: widget.onSignedOut,
  );

  Future<int> _loadUnreadNotifications() async {
    final items = await widget.repository.getNotifications();
    // Sync with notification page logic: Recent = unread & not auto-archived (30d)
    return items.where((item) => item.isRecent).length;
  }

  Future<void> _loadSupportUnread() async {
    try {
      final count = await _supportRepo.unreadTotal(admin: true);
      if (mounted && count != _unreadSupport) {
        setState(() => _unreadSupport = count);
      }
    } catch (_) {
      // Keep last known badge; the Help and Support page surfaces errors.
    }
  }

  void _refreshUnreadCount() {
    if (!mounted) return;
    setState(() {
      _unreadNotifications = _loadUnreadNotifications();
    });
  }

  void _refreshSupportUnread() {
    if (!mounted) return;
    _loadSupportUnread();
  }

  @override
  void initState() {
    super.initState();
    _loadSupportUnread();
  }

  void _profileChanged(AdminProfile profile) {
    setState(() {
      _profile = profile;
      _pageCache[AdminSection.settings] = _settingsPage(profile);
    });
    widget.onProfileChanged(profile);
  }

  void _select(AdminSection section, {bool closeDrawer = false}) {
    if (section == _selected) {
      if (closeDrawer) Navigator.pop(context);
      return;
    }
    setState(() {
      _selected = section;
      if (section != AdminSection.helpSupport) {
        _pageCache.putIfAbsent(section, () => _pageFor(section));
      }
      // Re-query the badge after the notification page may have changed reads.
      if (section == AdminSection.notifications) {
        _unreadNotifications = _loadUnreadNotifications();
      }
      if (section == AdminSection.helpSupport) {
        _loadSupportUnread();
      }
    });
    if (closeDrawer) Navigator.pop(context);
  }

  Future<void> _signOut() async {
    await widget.repository.signOut();
    if (mounted) widget.onSignedOut();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 1050;
        final navigation = NseapSidebar(
          selected: _selected,
          onSelect: (section) => _select(section, closeDrawer: !desktop),
          onSignOut: _signOut,
          adminName: _profile.name.isEmpty ? 'Admin User' : _profile.name,
          adminEmail: _profile.email,
          adminRole: _profile.role.isEmpty
              ? 'Super Admin'
              : adminLabel(_profile.role),
          badges: {
            if (_unreadSupport > 0) AdminSection.helpSupport: _unreadSupport,
          },
        );
        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: const Color(0xFFF5F6FA),
          drawer: desktop
              ? null
              : Drawer(
                  width: 260,
                  backgroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.horizontal(
                      right: Radius.circular(16),
                    ),
                  ),
                  child: SafeArea(child: navigation),
                ),
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (desktop) navigation,
              Expanded(
                child: Stack(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        desktop ? 16 : 12,
                        16,
                        16,
                        16,
                      ),
                      child: IndexedStack(
                        index: _selected.index,
                        children: AdminSection.values.map((section) {
                          // Keep Help and Support state alive while updating its
                          // visibility flag so read receipts only fire on view.
                          if (section == AdminSection.helpSupport) {
                            return HelpSupportAdminPage(
                              active: _selected == section,
                            );
                          }
                          return _pageCache[section] ?? const SizedBox.shrink();
                        }).toList(),
                      ),
                    ),
                    if (!desktop)
                      Positioned(
                        left: 12,
                        top: 12,
                        child: SafeArea(
                          child: Material(
                            color: Colors.white,
                            elevation: 2,
                            shadowColor: Colors.black.withValues(alpha: 0.08),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            child: IconButton(
                              onPressed: () =>
                                  _scaffoldKey.currentState?.openDrawer(),
                              icon: const Icon(
                                Icons.menu_rounded,
                                size: 20,
                                color: Color(0xFF475569),
                              ),
                              tooltip: 'Open menu',
                              style: IconButton.styleFrom(
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
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
      },
    );
  }
}

class AdminSidebar extends StatelessWidget {
  const AdminSidebar({
    required this.sections,
    required this.selected,
    required this.collapsed,
    required this.onSelect,
    required this.onSignOut,
    super.key,
  });

  final List<AdminSection> sections;
  final AdminSection selected;
  final bool collapsed;
  final ValueChanged<AdminSection> onSelect;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final mainSections = sections
        .where(
          (section) =>
              section != AdminSection.settings &&
              section != AdminSection.notifications &&
              section != AdminSection.activityLogs,
        )
        .toList();
    final secondarySections = sections
        .where(
          (s) =>
              s == AdminSection.notifications || s == AdminSection.activityLogs,
        )
        .toList();
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0F3DAA), Color(0xFF104BC4), Color(0xFF165EF0)],
        ),
      ),
      child: Column(
        children: [
          _SidebarHeader(collapsed: collapsed),
          const SizedBox(height: 8),
          if (!collapsed)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'MENU',
                  style: TextStyle(
                    color: Color(0xFF8FB0FF),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
          Expanded(
            child: ClipRect(
              child: ListView(
                clipBehavior: Clip.hardEdge,
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                children: [
                  for (final section in mainSections)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: _SidebarMenuItem(
                        icon: section.icon,
                        label: section.label,
                        selected: section == selected,
                        collapsed: collapsed,
                        onTap: () => onSelect(section),
                      ),
                    ),
                  if (secondarySections.isNotEmpty && !collapsed) ...[
                    for (final section in secondarySections)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: _SidebarMenuItem(
                          icon: section.icon,
                          label: section.label,
                          selected: section == selected,
                          collapsed: collapsed,
                          onTap: () => onSelect(section),
                        ),
                      ),
                  ],
                  if (secondarySections.isNotEmpty && collapsed)
                    for (final section in secondarySections)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3, top: 3),
                        child: _SidebarMenuItem(
                          icon: section.icon,
                          label: section.label,
                          selected: section == selected,
                          collapsed: collapsed,
                          onTap: () => onSelect(section),
                        ),
                      ),
                ],
              ),
            ),
          ),
          _SidebarUtilities(
            selected: selected,
            collapsed: collapsed,
            onSelect: onSelect,
            onSignOut: onSignOut,
          ),
        ],
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xFF2D5BD0), width: 1)),
    ),
    child: Row(
      mainAxisAlignment: collapsed
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.asset(
            'assets/icon/app_icon.png',
            width: 38,
            height: 38,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                const Icon(Icons.school_rounded, color: Colors.white, size: 28),
          ),
        ),
        if (!collapsed) ...[
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'NSEAP',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    height: 1,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Admin Portal',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xFFC9D6F4),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}

class _SidebarMenuItem extends StatefulWidget {
  const _SidebarMenuItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.collapsed,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  /// Renders destructive entries such as sign-out with error tones.
  final bool danger;

  @override
  State<_SidebarMenuItem> createState() => _SidebarMenuItemState();
}

class _SidebarMenuItemState extends State<_SidebarMenuItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    const idleForeground = Color(0xFFC9D6F4);
    const selectedBg = Color(0xFF3A5BC7);
    const hoverBg = Color(0xFF2D4791);
    final foreground = widget.selected
        ? Colors.white
        : widget.danger
        ? const Color(0xFFFCA5A5)
        : _hovered
        ? Colors.white
        : idleForeground;
    final background = widget.selected
        ? selectedBg
        : widget.danger && _hovered
        ? hoverBg
        : _hovered
        ? hoverBg
        : Colors.transparent;
    final item = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: AppDurations.hover,
        curve: Curves.easeOutCubic,
        height: 38,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(10),
          border: widget.selected
              ? Border.all(
                  color: Colors.white.withValues(alpha: 0.14),
                  width: 1,
                )
              : null,
          boxShadow: widget.selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
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
            borderRadius: BorderRadius.circular(10),
            hoverColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            splashFactory: NoSplash.splashFactory,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: widget.collapsed ? 0 : 12,
              ),
              child: Row(
                mainAxisAlignment: widget.collapsed
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  Icon(widget.icon, size: 18, color: foreground),
                  if (!widget.collapsed) ...[
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: foreground,
                          fontSize: 12.5,
                          fontWeight: widget.selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return Tooltip(message: widget.label, child: item);
  }
}

class _SidebarUtilities extends StatelessWidget {
  const _SidebarUtilities({
    required this.selected,
    required this.collapsed,
    required this.onSelect,
    required this.onSignOut,
  });

  final AdminSection selected;
  final bool collapsed;
  final ValueChanged<AdminSection> onSelect;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF2D5BD0), width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SidebarMenuItem(
            icon: AdminSection.settings.icon,
            label: AdminSection.settings.label,
            selected: AdminSection.settings == selected,
            collapsed: collapsed,
            onTap: () => onSelect(AdminSection.settings),
          ),
          const SizedBox(height: 3),
          const SizedBox(height: 6),
          Container(height: 1, color: const Color(0xFF2D5BD0)),
          const SizedBox(height: 10),
          _SidebarMenuItem(
            icon: Icons.logout_rounded,
            label: 'Sign out',
            selected: false,
            collapsed: collapsed,
            danger: true,
            onTap: onSignOut,
          ),
        ],
      ),
    );
  }
}
