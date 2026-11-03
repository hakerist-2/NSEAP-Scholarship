import 'package:flutter/material.dart';
import 'package:nseapscholarship/services/realtime_sync.dart';

import '../../../theme/nseap_theme.dart';
import '../../data/admin_repository.dart';
import '../../models/admin_models.dart';
import '../../widgets/admin_widgets.dart';
import '../shared/admin_page_support.dart';

/// Reviews notification history, marks as read, archives, and auto-archives
/// notifications older than 30 days into the Archive filter.
///
/// Design is intentionally modern / minimal while LOGIC is preserved
/// verbatim from the previous implementation.
class NotificationsAdminPage extends StatefulWidget {
  const NotificationsAdminPage({
    required this.repository,
    this.onCountChanged,
    super.key,
  });
  final AdminRepository repository;
  final VoidCallback? onCountChanged;

  @override
  State<NotificationsAdminPage> createState() => _NotificationsAdminPageState();
}

class _NotificationsAdminPageState extends State<NotificationsAdminPage>
    with RealtimeSyncMixin {
  @override
  Set<String> get realtimeTables => const {'notifications'};
  @override
  Future<void> refreshRealtime() async {
    _reload();
    await _future;
  }

  late Future<List<AdminNotification>> _future = widget.repository
      .getNotifications();
  String _search = '';
  String _status = 'all';

  void _reload() => setState(() {
    _future = widget.repository.getNotifications();
  });

  Future<void> _markAsRead(AdminNotification item) async {
    await runAdminAction(
      context,
      () => widget.repository.markNotificationRead(item.id),
      'Marked as opened.',
      () {
        _reload();
        widget.onCountChanged?.call();
      },
    );
  }

  Future<void> _archive(AdminNotification item) async {
    await runAdminAction(
      context,
      () => widget.repository.archiveNotification(item.id),
      'Notification archived.',
      () {
        _reload();
        widget.onCountChanged?.call();
      },
    );
  }

  Future<void> _unarchive(AdminNotification item) async {
    await runAdminAction(
      context,
      () => widget.repository.unarchiveNotification(item.id),
      'Notification restored from archive.',
      () {
        _reload();
        widget.onCountChanged?.call();
      },
    );
  }

  @override
  Widget build(BuildContext context) => AdminPageFrame(
    header: AdminPageHeader(
      title: 'Notifications',
      subtitle: 'Application and interview updates delivered to scholars',
      action: FutureBuilder<List<AdminNotification>>(
        future: _future,
        builder: (context, snap) {
          final total = snap.data?.length ?? 0;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.12),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  total == 0 ? 'No records' : '$total total',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
    toolbar: _NotificationsToolbar(
      onSearch: (value) => setState(() => _search = value.toLowerCase()),
      status: _status,
      onStatus: (value) => setState(() => _status = value),
    ),
    body: AdminAsyncView<List<AdminNotification>>(
      future: _future,
      isEmpty: (items) => items.isEmpty,
      onRetry: _reload,
      builder: (context, items) {
        // Only show Application submitted + Interview scheduled in admin panel.
        const allowedTitles = {'application submitted', 'interview scheduled'};
        // Derive filtered list with 30-day auto-archive.
        final visible = items.where((item) {
          if (!allowedTitles.contains(item.title.trim().toLowerCase())) {
            return false;
          }
          final text =
              '${item.title} ${item.body} ${item.userId} ${item.recipientName} ${item.displayRecipient} ${item.category}'
                  .toLowerCase();
          final matchesSearch = text.contains(_search);
          if (!matchesSearch) return false;
          return switch (_status) {
            'all' => true,
            'recent' => item.isRecent,
            'opened' => item.isOpened,
            'archive' => item.isArchived,
            _ => true,
          };
        }).toList();

        if (visible.isEmpty) {
          final label = switch (_status) {
            'all' => 'No notifications',
            'recent' => 'No recent notifications',
            'opened' => 'No opened notifications',
            'archive' => 'No archived notifications',
            _ => 'No notifications',
          };
          final msg = switch (_status) {
            'all' =>
              'No notifications yet. Try changing your search or filter.',
            'recent' =>
              'Unread notifications from the last 30 days will appear here.',
            'opened' =>
              'Notifications marked as opened will appear here (excluding archived).',
            'archive' =>
              'Manually archived or notifications older than 30 days appear here.',
            _ => 'Try changing your search or filter.',
          };
          return AdminStatePanel.empty(title: label, message: msg);
        }

        // Subtle count strip above list (derived, not mutating logic)
        final unreadCount = items
            .where(
              (e) =>
                  allowedTitles.contains(e.title.trim().toLowerCase()) &&
                  e.isRecent,
            )
            .length;
        final openedCount = items
            .where(
              (e) =>
                  allowedTitles.contains(e.title.trim().toLowerCase()) &&
                  e.isOpened,
            )
            .length;
        final archivedCount = items
            .where(
              (e) =>
                  allowedTitles.contains(e.title.trim().toLowerCase()) &&
                  e.isArchived,
            )
            .length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SummaryStrip(
              all: visible.length,
              recent: unreadCount,
              opened: openedCount,
              archived: archivedCount,
              active: _status,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: visible.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, index) {
                  final item = visible[index];
                  final isAuto = item.isAutoArchived && item.archivedAt == null;
                  return _NotificationCard(
                    item: item,
                    isAutoArchived: isAuto,
                    onMarkAsRead: item.readAt == null && !item.isArchived
                        ? () => _markAsRead(item)
                        : null,
                    onArchive: item.isArchived ? null : () => _archive(item),
                    onUnarchive: item.archivedAt != null
                        ? () => _unarchive(item)
                        : null,
                  );
                },
              ),
            ),
          ],
        );
      },
    ),
  );
}

// ── Toolbar with segmented pill filter ─────────────────────────────────────

class _NotificationsToolbar extends StatelessWidget {
  const _NotificationsToolbar({
    required this.onSearch,
    required this.status,
    required this.onStatus,
  });

  final ValueChanged<String> onSearch;
  final String status;
  final ValueChanged<String> onStatus;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final search = AdminSearchField(
          hint: 'Search title, body, or recipient',
          onChanged: onSearch,
        );
        final pills = _StatusPills(value: status, onChanged: onStatus);
        if (constraints.maxWidth < 640) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [search, const SizedBox(height: 10), pills],
          );
        }
        return Row(
          children: [
            Expanded(child: search),
            const SizedBox(width: 12),
            pills,
          ],
        );
      },
    );
  }
}

class _StatusPills extends StatelessWidget {
  const _StatusPills({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    const options = [
      ('all', 'All', Icons.inbox_rounded),
      ('recent', 'Recent', Icons.mark_email_unread_rounded),
      ('opened', 'Opened', Icons.mark_email_read_rounded),
      ('archive', 'Archive', Icons.archive_rounded),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((o) {
          final selected = value == o.$1;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: ChoiceChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    o.$3,
                    size: 14,
                    color: selected ? Colors.white : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(o.$2),
                ],
              ),
              selected: selected,
              onSelected: (_) => onChanged(o.$1),
              showCheckmark: false,
              labelStyle: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppColors.textSecondary,
                letterSpacing: 0.1,
              ),
              backgroundColor: Colors.transparent,
              selectedColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              side: BorderSide.none,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({
    required this.all,
    required this.recent,
    required this.opened,
    required this.archived,
    required this.active,
  });
  final int all;
  final int recent;
  final int opened;
  final int archived;
  final String active;

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, int count, String key) {
      final isActive = active == key || (key == 'all' && active == 'all');
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? AppColors.primaryLight : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive
                  ? AppColors.primary.withValues(alpha: 0.18)
                  : AppColors.borderLight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: isActive ? AppColors.primary : AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$count',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: isActive
                      ? AppColors.primaryDark
                      : const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        cell('All', all, 'all'),
        const SizedBox(width: 8),
        cell('RECENT', recent, 'recent'),
        const SizedBox(width: 8),
        cell('OPENED', opened, 'opened'),
        const SizedBox(width: 8),
        cell('ARCHIVED', archived, 'archive'),
      ],
    );
  }
}

// ── Modern notification card ───────────────────────────────────────────────

class _NotificationCard extends StatefulWidget {
  const _NotificationCard({
    required this.item,
    required this.isAutoArchived,
    this.onMarkAsRead,
    this.onArchive,
    this.onUnarchive,
  });

  final AdminNotification item;
  final bool isAutoArchived;
  final VoidCallback? onMarkAsRead;
  final VoidCallback? onArchive;
  final VoidCallback? onUnarchive;

  @override
  State<_NotificationCard> createState() => _NotificationCardState();
}

class _NotificationCardState extends State<_NotificationCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final bool isUnread = widget.onMarkAsRead != null;
    final bool isArchivedState = item.isArchived;
    final bool isInterview = item.title.toLowerCase().contains('interview');

    // Semantic tokens
    final Color bg = isArchivedState ? const Color(0xFFF8FAFC) : Colors.white;
    final Color border = isUnread
        ? AppColors.primary.withValues(alpha: 0.18)
        : AppColors.borderLight;
    final Color iconBg = isArchivedState
        ? AppColors.grey100
        : isUnread
        ? AppColors.primaryLight
        : AppColors.surfaceContainer;
    final Color iconColor = isArchivedState
        ? AppColors.textTertiary
        : isUnread
        ? AppColors.primary
        : AppColors.textSecondary;
    final IconData leadingIcon = isArchivedState
        ? Icons.archive_rounded
        : isInterview
        ? Icons.event_rounded
        : Icons.description_rounded;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: AppDurations.hover,
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _hovered ? -1 : 0, 0),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _hovered && !isArchivedState
                ? AppColors.primary.withValues(alpha: 0.14)
                : border,
          ),
          boxShadow: _hovered
              ? AppElevation.shadowMd
              : isUnread
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.07),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ]
              : AppElevation.shadowXs,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Left accent for unread
            if (isUnread)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(width: 3.5, color: AppColors.primary),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Leading icon
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: iconBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isUnread
                                ? AppColors.primary.withValues(alpha: 0.12)
                                : Colors.transparent,
                          ),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(leadingIcon, size: 20, color: iconColor),
                            if (isUnread)
                              Positioned(
                                top: 6,
                                right: 7,
                                child: Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 1.2,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    item.title,
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 14,
                                      fontWeight: isUnread
                                          ? FontWeight.w800
                                          : FontWeight.w700,
                                      color: isArchivedState
                                          ? AppColors.grey700
                                          : const Color(0xFF0F172A),
                                      letterSpacing: -0.2,
                                      height: 1.2,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _StateBadge(
                                  unread: isUnread,
                                  archived: isArchivedState,
                                  opened:
                                      item.readAt != null && !isArchivedState,
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              item.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 12.8,
                                color: isArchivedState
                                    ? AppColors.textTertiary
                                    : AppColors.textSecondary,
                                height: 1.45,
                                fontWeight: isUnread
                                    ? FontWeight.w500
                                    : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      _NotificationMenu(
                        isAutoArchived: widget.isAutoArchived,
                        onMarkAsRead: widget.onMarkAsRead,
                        onArchive: widget.onArchive,
                        onUnarchive: widget.onUnarchive,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Meta chips row
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _MetaChip(
                        icon: Icons.person_outline_rounded,
                        label: item.displayRecipient,
                      ),
                      _MetaChip(
                        icon: Icons.schedule_rounded,
                        label: adminDateLabel(item.createdAt, withTime: true),
                      ),
                      if (item.readAt != null)
                        _MetaChip(
                          icon: Icons.visibility_outlined,
                          label:
                              'Opened ${adminDateLabel(item.readAt, withTime: true)}',
                          tone: _ChipTone.success,
                        ),
                      if (item.archivedAt != null)
                        _MetaChip(
                          icon: Icons.archive_outlined,
                          label:
                              'Archived ${adminDateLabel(item.archivedAt, withTime: true)}',
                          tone: _ChipTone.neutral,
                        ),
                      if (item.category.isNotEmpty)
                        _MetaChip(
                          icon: Icons.label_outline_rounded,
                          label: adminLabel(item.category),
                        ),
                    ],
                  ),
                  if (widget.isAutoArchived) ...[],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({
    required this.unread,
    required this.archived,
    required this.opened,
  });
  final bool unread;
  final bool archived;
  final bool opened;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg, border) = switch ((unread, archived, opened)) {
      (true, _, _) => (
        'New',
        AppColors.primary,
        Colors.white,
        AppColors.primary,
      ),
      (_, true, _) => (
        'Archived',
        AppColors.grey100,
        AppColors.textSecondary,
        AppColors.borderLight,
      ),
      (_, _, true) => (
        'Opened',
        AppColors.successLight,
        AppColors.success,
        AppColors.success.withValues(alpha: 0.18),
      ),
      _ => ('', Colors.transparent, Colors.transparent, Colors.transparent),
    };
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: fg,
        ),
      ),
    );
  }
}

enum _ChipTone { neutral, success }

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    this.tone = _ChipTone.neutral,
  });
  final IconData icon;
  final String label;
  final _ChipTone tone;

  @override
  Widget build(BuildContext context) {
    final bg = tone == _ChipTone.success
        ? AppColors.successLight
        : Colors.white;
    final fg = tone == _ChipTone.success
        ? AppColors.success
        : AppColors.textSecondary;
    final border = tone == _ChipTone.success
        ? AppColors.success.withValues(alpha: 0.14)
        : AppColors.borderLight;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11.8,
              fontWeight: FontWeight.w600,
              color: fg,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationMenu extends StatelessWidget {
  const _NotificationMenu({
    required this.isAutoArchived,
    this.onMarkAsRead,
    this.onArchive,
    this.onUnarchive,
  });

  final bool isAutoArchived;
  final VoidCallback? onMarkAsRead;
  final VoidCallback? onArchive;
  final VoidCallback? onUnarchive;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStateProperty.all(Colors.white),
        elevation: WidgetStateProperty.all(10),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(vertical: 6),
        ),
      ),
      menuChildren: [
        if (onMarkAsRead != null)
          MenuItemButton(
            onPressed: onMarkAsRead,
            leadingIcon: const Icon(Icons.visibility_outlined, size: 18),
            child: const Text(
              'Mark as read',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ),
        if (onArchive != null)
          MenuItemButton(
            onPressed: onArchive,
            leadingIcon: const Icon(Icons.archive_outlined, size: 18),
            child: const Text('Archive', style: TextStyle(fontSize: 13.5)),
          ),
        if (onUnarchive != null)
          MenuItemButton(
            onPressed: onUnarchive,
            leadingIcon: const Icon(Icons.unarchive_outlined, size: 18),
            child: const Text('Unarchive', style: TextStyle(fontSize: 13.5)),
          ),
        if (onMarkAsRead == null && onArchive == null && onUnarchive == null)
          MenuItemButton(
            onPressed: null,
            child: Text(
              isAutoArchived
                  ? 'Auto-archived after 30 days'
                  : 'No actions available',
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
      ],
      builder: (context, controller, child) => IconButton(
        tooltip: 'More actions',
        style: IconButton.styleFrom(
          backgroundColor: Colors.white,
          side: const BorderSide(color: AppColors.borderLight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.all(8),
          minimumSize: const Size(36, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: const Icon(
          Icons.more_horiz_rounded,
          size: 18,
          color: AppColors.textSecondary,
        ),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}
