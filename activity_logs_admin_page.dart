import 'package:flutter/material.dart';
import 'package:nseapscholarship/services/realtime_sync.dart';
import 'package:nseapscholarship/theme/nseap_theme.dart';

import '../../data/admin_repository.dart';
import '../../models/admin_models.dart';
import '../../widgets/admin_widgets.dart';
import '../shared/admin_page_support.dart';

String _normalizeActivityType(String raw) =>
    raw == 'semester_submission' ? 'application' : raw;

/// Target types kept out of the category filter (QR sessions, payout
/// sessions and account-restored events) per earlier request.
const _hiddenActivityCategories = {
  'admin_qr_session',
  'payout_session',
  'user_account',
};

/// Preferred display order for the main activity categories.
const _preferredActivityCategories = [
  'admin',
  'applicants',
  'interview',
  'scholars',
];

/// Derives the displayed category from the admin's activity (action +
/// target), not just the raw target type:
/// - **admin** — login, logout, change password / email / username.
/// - **applicants** — approved / rejected (and other) application decisions.
/// - **interview** — applicants interviewed / interview started or scheduled.
/// - **scholars** — approved, needs revision, terminated, graduated scholar
///   updates (including semester submission reviews).
/// Falls back to the normalized target type (document, payout, …).
String _activityCategory(ActivityLog item) {
  final action = item.action.toLowerCase().trim();
  final target = item.targetType.toLowerCase().trim();

  // Hidden targets keep their raw type so they stay out of the filter.
  if (_hiddenActivityCategories.contains(target)) return target;

  // Admin account activity: login, logout, change password/email/username.
  if (target == 'admin_auth' ||
      target == 'admin_account' ||
      action.startsWith('admin_')) {
    return 'admin';
  }

  // Interview activity: applicant interviewed / check-in / interview flow.
  if (action.contains('interview') ||
      action.contains('check_in') ||
      action == 'scan_applicant_qr') {
    return 'interview';
  }

  // Scholar lifecycle: approve, needs revision, terminate, graduate —
  // includes semester submission reviews on the Scholars page.
  if (target == 'scholar' ||
      target == 'scholar_activation' ||
      target == 'semester_submission' ||
      action.startsWith('scholar_') ||
      action.startsWith('walkin_scholar')) {
    return 'scholars';
  }

  // Application decisions: approved / rejected / other applicant activity.
  if (target == 'application' || target == 'scholarship_application') {
    return 'applicants';
  }

  return _normalizeActivityType(target);
}

/// Displays administrative activity history (formerly Audit Logs) with archive
/// support — mirrors Notifications archive: Recent (<30d) vs Archive (manual or auto).
/// Logic is preserved verbatim; only the presentation is modernized.
class ActivityLogsAdminPage extends StatefulWidget {
  const ActivityLogsAdminPage({required this.repository, super.key});

  final AdminRepository repository;

  @override
  State<ActivityLogsAdminPage> createState() => _ActivityLogsAdminPageState();
}

class _ActivityLogsAdminPageState extends State<ActivityLogsAdminPage>
    with RealtimeSyncMixin {
  @override
  Set<String> get realtimeTables => const {'audit_logs'};
  @override
  Future<void> refreshRealtime() async {
    _reload();
    await _future;
  }

  late Future<List<ActivityLog>> _future = widget.repository.getActivityLogs();
  String _search = '';
  String _type = 'all';
  String _status = 'all';

  void _reload() => setState(() {
    _future = widget.repository.getActivityLogs();
  });

  List<ActivityLog> _filtered(List<ActivityLog> items) => items.where((item) {
    final category = _activityCategory(item);
    final text = '${item.action} ${item.targetType} $category'.toLowerCase();
    final matchesSearch = text.contains(_search);
    if (!matchesSearch) return false;
    final matchesType = _type == 'all' || category == _type;
    if (!matchesType) return false;
    return switch (_status) {
      'recent' => item.isRecent,
      'archive' => item.isArchived,
      _ => true,
    };
  }).toList();

  Future<void> _archive(ActivityLog item) async {
    await runAdminAction(
      context,
      () => widget.repository.archiveActivityLog(item.id),
      'Activity archived.',
      _reload,
    );
  }

  Future<void> _unarchive(ActivityLog item) async {
    await runAdminAction(
      context,
      () => widget.repository.unarchiveActivityLog(item.id),
      'Activity restored from archive.',
      _reload,
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<ActivityLog>>(
    future: _future,
    builder: (context, snapshot) {
      // Build category filter from each activity's admin action:
      // admin / applicants / interview / scholars, with a normalized
      // target-type fallback (document, payout, …). QR sessions, payout
      // sessions and account-restored events stay excluded.
      final allTypes =
          <String>{
                if (snapshot.hasData)
                  for (final i in snapshot.data!) _activityCategory(i),
              }
              .where(
                (t) => t.isNotEmpty && !_hiddenActivityCategories.contains(t),
              )
              .toList()
            ..sort((a, b) {
              final ia = _preferredActivityCategories.indexOf(a);
              final ib = _preferredActivityCategories.indexOf(b);
              if (ia != -1 && ib != -1) return ia.compareTo(ib);
              if (ia != -1) return -1;
              if (ib != -1) return 1;
              return a.compareTo(b);
            });
      final typeOptions = ['all', ...allTypes];
      // Keep selected type valid when data loads.
      if (!typeOptions.contains(_type)) {
        // Defer to next frame to avoid setState during build.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !typeOptions.contains(_type)) {
            setState(() => _type = 'all');
          }
        });
      }
      return AdminPageFrame(
        header: AdminPageHeader(
          title: 'Activity Logs',
          subtitle: 'Administrative history',
          action: FutureBuilder<List<ActivityLog>>(
            future: _future,
            builder: (context, snap) {
              final total = snap.data?.length ?? 0;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
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
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    tooltip: 'Refresh',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.textSecondary,
                      side: const BorderSide(color: AppColors.borderLight),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        toolbar: _ActivityToolbar(
          hint: 'Search action or category',
          onSearch: (value) => setState(() => _search = value.toLowerCase()),
          type: _type,
          typeOptions: typeOptions,
          status: _status,
          onTypeChanged: (value) => setState(() => _type = value),
          onStatusChanged: (value) => setState(() => _status = value),
        ),
        body: AdminAsyncView<List<ActivityLog>>(
          future: _future,
          isEmpty: (items) => items.isEmpty,
          onRetry: _reload,
          builder: (context, items) {
            final visible = _filtered(items);
            if (visible.isEmpty) {
              final label = switch (_status) {
                'recent' => 'No recent activity',
                'archive' => 'No archived activity',
                _ => 'No activity logs',
              };
              final msg = switch (_status) {
                'recent' =>
                  'Recent administrative actions from the last 30 days will appear here.',
                'archive' =>
                  'Manually archived or activity older than 30 days appears here.',
                _ =>
                  _search.isNotEmpty || _type != 'all'
                      ? 'Try changing your search or filters.'
                      : 'Activity will appear here when administrative actions are recorded.',
              };
              return AdminStatePanel.empty(title: label, message: msg);
            }

            // Counts for header badges
            final recentCount = items.where((e) => e.isRecent).length;
            final archiveCount = items.where((e) => e.isArchived).length;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SummaryStrip(
                  all: items.length,
                  recent: recentCount,
                  archived: archiveCount,
                  active: _status,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, index) {
                      final item = visible[index];
                      final isAuto =
                          item.isAutoArchived && item.archivedAt == null;
                      return _ActivityLogCard(
                        item: item,
                        isAutoArchived: isAuto,
                        onArchive: item.isArchived
                            ? null
                            : () => _archive(item),
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
    },
  );
}

class _ActivityToolbar extends StatelessWidget {
  const _ActivityToolbar({
    required this.hint,
    required this.onSearch,
    required this.type,
    required this.typeOptions,
    required this.status,
    required this.onTypeChanged,
    required this.onStatusChanged,
  });

  final String hint;
  final ValueChanged<String> onSearch;
  final String type;
  final List<String> typeOptions;
  final String status;
  final ValueChanged<String> onTypeChanged;
  final ValueChanged<String> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 720;
        final search = AdminSearchField(hint: hint, onChanged: onSearch);
        final typeFilter = SizedBox(
          width: narrow ? double.infinity : 190,
          child: adminStatusFilter(
            type,
            typeOptions,
            onTypeChanged,
            labels: const {'all': 'All categories'},
          ),
        );
        final statusPills = _StatusPills(
          value: status,
          onChanged: onStatusChanged,
        );
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              search,
              const SizedBox(height: 10),
              typeFilter,
              const SizedBox(height: 10),
              statusPills,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: search),
            const SizedBox(width: 12),
            typeFilter,
            const SizedBox(width: 12),
            statusPills,
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
      ('recent', 'Recent', Icons.history_rounded),
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
    required this.archived,
    required this.active,
  });
  final int all;
  final int recent;
  final int archived;
  final String active;

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, int count, String key) {
      final isActive = active == key;
      final isShowing = key == 'all' && active == 'all';
      final highlight = isActive || isShowing;
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: highlight ? AppColors.primaryLight : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: highlight
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
                  color: highlight ? AppColors.primary : AppColors.textTertiary,
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
                  color: highlight
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
        cell('TOTAL', all, 'all'),
        const SizedBox(width: 8),
        cell('RECENT', recent, 'recent'),
        const SizedBox(width: 8),
        cell('ARCHIVED', archived, 'archive'),
      ],
    );
  }
}

class _ActivityLogCard extends StatefulWidget {
  const _ActivityLogCard({
    required this.item,
    required this.isAutoArchived,
    this.onArchive,
    this.onUnarchive,
  });

  final ActivityLog item;
  final bool isAutoArchived;
  final VoidCallback? onArchive;
  final VoidCallback? onUnarchive;

  @override
  State<_ActivityLogCard> createState() => _ActivityLogCardState();
}

class _ActivityLogCardState extends State<_ActivityLogCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isArchivedState = item.isArchived;
    final isRecent = item.isRecent;

    final bg = isArchivedState ? const Color(0xFFF8FAFC) : Colors.white;
    final border = isArchivedState
        ? AppColors.borderLight
        : (isRecent
              ? AppColors.primary.withValues(alpha: 0.14)
              : AppColors.borderLight);
    final iconBg = isArchivedState
        ? AppColors.grey100
        : isRecent
        ? AppColors.primaryLight
        : AppColors.surfaceContainer;
    final iconColor = isArchivedState
        ? AppColors.textTertiary
        : (isRecent ? AppColors.primary : AppColors.textSecondary);

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
              : isRecent
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.06),
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
            if (isRecent && !isArchivedState)
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
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: iconBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isRecent && !isArchivedState
                                ? AppColors.primary.withValues(alpha: 0.10)
                                : Colors.transparent,
                          ),
                        ),
                        child: Icon(
                          _iconForAction(item.action),
                          size: 20,
                          color: iconColor,
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
                                    adminLabel(item.action),
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
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
                                  archived: isArchivedState,
                                  recent: isRecent,
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              adminLabel(_activityCategory(item)),
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 12.5,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              adminDateLabel(item.createdAt, withTime: true),
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 11.5,
                                color: AppColors.textTertiary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      _ActivityMenu(
                        isAutoArchived: widget.isAutoArchived,
                        onArchive: widget.onArchive,
                        onUnarchive: widget.onUnarchive,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _MetaChip(
                        icon: Icons.bolt_outlined,
                        label: adminLabel(item.action),
                      ),
                      _MetaChip(
                        icon: Icons.flag_outlined,
                        label: adminLabel(_activityCategory(item)),
                      ),
                      _MetaChip(
                        icon: Icons.schedule_rounded,
                        label: adminDateLabel(item.createdAt, withTime: true),
                      ),
                      if (item.archivedAt != null)
                        _MetaChip(
                          icon: Icons.archive_outlined,
                          label:
                              'Archived ${adminDateLabel(item.archivedAt, withTime: true)}',
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconForAction(String action) {
    final a = action.toLowerCase();
    if (a.contains('scholar')) return Icons.school_rounded;
    if (a.contains('document')) return Icons.description_rounded;
    if (a.contains('payout')) return Icons.payments_rounded;
    if (a.contains('interview')) return Icons.event_rounded;
    if (a.contains('application')) return Icons.people_alt_rounded;
    if (a.contains('admin')) return Icons.admin_panel_settings_rounded;
    if (a.contains('account') || a.contains('user')) {
      return Icons.person_rounded;
    }
    if (a.contains('semester')) return Icons.fact_check_rounded;
    if (a.contains('login') || a.contains('auth')) return Icons.login_rounded;
    return Icons.history_rounded;
  }
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.archived, required this.recent});
  final bool archived;
  final bool recent;
  @override
  Widget build(BuildContext context) {
    final (label, bg, fg, border) = switch ((archived, recent)) {
      (true, _) => (
        'Archived',
        AppColors.grey100,
        AppColors.textSecondary,
        AppColors.borderLight,
      ),
      (false, true) => (
        'Recent',
        AppColors.primaryLight,
        AppColors.primary,
        AppColors.primary.withValues(alpha: 0.18),
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

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 11.8,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityMenu extends StatelessWidget {
  const _ActivityMenu({
    required this.isAutoArchived,
    this.onArchive,
    this.onUnarchive,
  });
  final bool isAutoArchived;
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
        if (onArchive == null && onUnarchive == null)
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

/// Deprecated alias — use ActivityLogsAdminPage.
@Deprecated('Use ActivityLogsAdminPage')
typedef AuditLogsAdminPage = ActivityLogsAdminPage;
