import 'package:flutter/material.dart';
import 'package:nseapscholarship/services/realtime_sync.dart';
import 'package:flutter/services.dart';
import 'package:nseapscholarship/admin/widgets/dashboard/dashboard_export.dart';
import 'package:nseapscholarship/theme/nseap_theme.dart';
import 'package:printing/printing.dart';

import '../../admin_navigation.dart';
import '../../data/admin_repository.dart';
import '../../models/admin_models.dart';
import '../../widgets/admin_widgets.dart';
import '../../widgets/requirement_download_button.dart';
import '../shared/admin_page_support.dart';
import '../../../utils/academic_year.dart';

const _pageInk = Color(0xFF1B2530);
const _pageRed = AppColors.error;
const _pageOrange = AppColors.warningDark;
const _pageShadow = BoxShadow(
  color: Color(0x0A101828),
  blurRadius: 24,
  offset: Offset(0, 8),
);

/// Supports filtering, reviewing, exporting, and deciding applications.
class ApplicantsAdminPage extends StatefulWidget {
  const ApplicantsAdminPage({required this.repository, super.key});

  final AdminRepository repository;

  @override
  State<ApplicantsAdminPage> createState() => _ApplicantsAdminPageState();
}

class _ApplicantsAdminPageState extends State<ApplicantsAdminPage>
    with RealtimeSyncMixin {
  @override
  Set<String> get realtimeTables => const {
    'users',
    'scholarship_applications',
    'interview_schedules',
    'scholarship_documents',
    'applicant_education',
  };
  @override
  Future<void> refreshRealtime() async {
    _reload();
    await _future;
  }

  late Future<(List<AdminApplication>, List<ApplicantInterview>)> _future =
      _load();
  final Map<String, AdminApplication> _selected = {};
  final TextEditingController _searchController = TextEditingController();
  String _search = '';
  String _statusFilter = 'all';
  String _academicYear = 'all';
  // Dynamic academic year list — auto-generates next AY when current ends.
  // Example: after 2026-2027 (Jun 2026-Apr 2027) ends, 2027-2028 appears
  // without a code change.
  List<String> get _academicYears => AcademicYearUtils.generateAcademicYears();
  bool _inAcademicYear(DateTime? dt, String year) =>
      AcademicYearUtils.isInAcademicYear(dt, year);

  bool _exporting = false;
  bool _selectionMode = false;

  @override
  void initState() {
    super.initState();
    _searchController.text = adminApplicantSearchNotifier.value;
    _search = adminApplicantSearchNotifier.value.trim().toLowerCase();
    adminApplicantSearchNotifier.addListener(_applyGlobalSearch);
    adminApplicationsRefreshNotifier.addListener(_applyExternalRefresh);
  }

  void _applyExternalRefresh() {
    if (!mounted) return;
    _reload();
  }

  void _applyGlobalSearch() {
    final value = adminApplicantSearchNotifier.value;
    final normalized = value.trim().toLowerCase();
    if (normalized == _search) return;
    if (mounted) {
      setState(() {
        _search = normalized;
        if (_searchController.text != value) {
          _searchController.text = value;
          _searchController.selection = TextSelection.fromPosition(
            TextPosition(offset: _searchController.text.length),
          );
        }
      });
    }
  }

  void _onSearchChanged(String value) {
    final normalized = value.trim().toLowerCase();
    setState(() => _search = normalized);
    if (adminApplicantSearchNotifier.value != value) {
      adminApplicantSearchNotifier.value = value;
    }
  }

  bool _matchesSearch(AdminApplication item, String query) {
    if (query.isEmpty) return true;
    final terms = query
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .map((t) => t.toLowerCase())
        .toList();
    if (terms.isEmpty) return true;
    final searchable = [
      item.name,
      _barangayLabel(item),
      item.school,
      item.course,
      _statusLabel(item.status),
      adminLabel(item.status),
      item.status,
      item.address,
      item.number,
      item.email,
    ].join(' ').toLowerCase();
    return terms.every((term) => searchable.contains(term));
  }

  Future<(List<AdminApplication>, List<ApplicantInterview>)> _load() async {
    final values = await Future.wait<dynamic>([
      widget.repository.getApplications(),
      widget.repository.getApplicantInterviews(),
    ]);
    return (
      values[0] as List<AdminApplication>,
      values[1] as List<ApplicantInterview>,
    );
  }

  void _reload() => setState(() {
    _future = _load();
  });

  @override
  void dispose() {
    adminApplicantSearchNotifier.removeListener(_applyGlobalSearch);
    adminApplicationsRefreshNotifier.removeListener(_applyExternalRefresh);
    _searchController.dispose();
    super.dispose();
  }

  void _resetFilters() => setState(() {
    adminApplicantSearchNotifier.value = '';
    _searchController.clear();
    _search = '';
    _statusFilter = 'all';
    _academicYear = 'all';
    _selected.clear();
  });

  void _filterByStatus(String filter) => setState(() {
    _statusFilter = filter;
    _selected.clear();
  });

  void _toggleSelectionMode() => setState(() {
    _selectionMode = !_selectionMode;
    if (!_selectionMode) _selected.clear();
  });

  Future<void> _export(
    List<AdminApplication> visible,
    AdminExportFormat format,
  ) async {
    if (_exporting) return;
    final rows = _selected.isEmpty ? visible : _selected.values.toList();
    if (rows.isEmpty) {
      showAdminMessage(context, 'No applicants available to export.');
      return;
    }

    const headers = [
      'Application ID',
      'Applicant',
      'Email',
      'School',
      'Course',
      'Year Level',
      'Address',
      'Status',
      'Date Applied',
    ];
    final exportRows = rows
        .map(
          (item) => [
            item.number,
            item.name,
            item.email,
            item.school,
            item.course,
            item.yearLevel,
            item.address,
            _statusLabel(item.status),
            adminDateLabel(item.submittedAt),
          ],
        )
        .toList();

    setState(() => _exporting = true);
    try {
      if (format == AdminExportFormat.pdf) {
        // Reuses dashboard's PDF download (web file) — same button/logic
        await exportTablePdf(
          title: 'LGU Lal-lo Scholarship Applicants',
          headers: headers,
          rows: exportRows,
        );
        if (mounted) {
          showAdminMessage(
            context,
            'PDF downloaded (${exportRows.length} applicants).',
          );
        }
      } else {
        // Reuses dashboard's Excel-ready CSV (BOM + proper quoting + file download)
        await exportTableCsv(
          title: 'LGU Lal-lo Scholarship Applicants',
          headers: headers,
          rows: exportRows,
        );
        if (mounted) {
          showAdminMessage(
            context,
            'CSV downloaded — Excel-ready (${exportRows.length} applicants).',
          );
        }
      }
    } catch (error) {
      if (mounted) {
        showAdminMessage(context, readableAdminError(error), error: true);
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _changeStatus(
    AdminApplication item,
    String status, {
    bool requireRemarks = false,
  }) async {
    String? remarks;
    if (requireRemarks) {
      remarks = await showAdminTextDialog(
        context,
        title: 'Reject ${item.number}?',
        label: 'Rejection remarks (required)',
      );
      if (remarks == null || remarks.trim().isEmpty) {
        if (mounted && remarks != null) {
          showAdminMessage(
            context,
            'Rejection remarks are required.',
            error: true,
          );
        }
        return;
      }
    } else {
      final confirmed = await confirmAdminAction(
        context,
        title: '${_statusLabel(status)} application?',
        message:
            'Update ${item.name}\'s application to ${_statusLabel(status)}?',
        confirmLabel: _statusLabel(status),
      );
      if (!confirmed) return;
    }
    if (!mounted) return;
    await runAdminAction(
      context,
      () => widget.repository.transitionApplication(
        item.id,
        status,
        note: remarks,
      ),
      'Application updated.',
      _reload,
    );
  }

  Future<void> _openApplicant(AdminApplication item) async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close applicant details',
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, _, _) => Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: Colors.white,
          elevation: 16,
          child: SizedBox(
            width: MediaQuery.sizeOf(context).width.clamp(0, 720).toDouble(),
            height: double.infinity,
            child: _ApplicantDetailPanel(
              repository: widget.repository,
              application: item,
              onStatusChanged: _reload,
            ),
          ),
        ),
      ),
      transitionBuilder: (context, animation, _, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
        child: child,
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) => AdminAsyncView<(List<AdminApplication>, List<ApplicantInterview>)>(
    future: _future,
    isEmpty: (_) => false,
    onRetry: _reload,
    builder: (context, data) {
      final applications = data.$1;
      // Index schedules by application to avoid repeated list scans per row.
      final interviews = {
        for (final interview in data.$2) interview.applicationId: interview,
      };
      final kpiApplications = applications
          .where((a) => _inAcademicYear(a.submittedAt, _academicYear))
          .toList();
      final visible = applications.where((item) {
        return _matchesSearch(item, _search) &&
            _inAcademicYear(item.submittedAt, _academicYear) &&
            switch (_statusFilter) {
              'under_review' => {
                'under_review',
                'final_evaluation',
                'interview_completed',
              }.contains(item.status),
              'approved' => item.status == 'scholar',
              'rejected' => item.status == 'rejected',
              _ => true,
            };
      }).toList();

      return SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Academic Year filter — right side top of KPI cards
                LayoutBuilder(
                  builder: (context, c) {
                    final narrow = c.maxWidth < 520;
                    final filter = Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x0A101828),
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _academicYear,
                          isDense: true,
                          icon: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 18,
                            color: Color(0xFF64748B),
                          ),
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: 'all',
                              child: Text('All'),
                            ),
                            ..._academicYears.map(
                              (y) => DropdownMenuItem(value: y, child: Text(y)),
                            ),
                          ],
                          onChanged: (v) => setState(() {
                            _academicYear = v ?? 'all';
                            _selected.clear();
                          }),
                        ),
                      ),
                    );
                    final title = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Applicants Overview',
                          style: TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Review, verify and manage scholarship applications',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _academicYear == 'all'
                              ? 'All academic years · Updated just now'
                              : 'Academic Year $_academicYear',
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    );
                    if (narrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(child: title),
                              const SizedBox(width: 12),
                              filter,
                            ],
                          ),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: title),
                        const SizedBox(width: 12),
                        filter,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                _ApplicantStats(
                  applications: kpiApplications,
                  selectedFilter: _statusFilter,
                  onSelected: _filterByStatus,
                ),
                const SizedBox(height: 20),
                _FilterPanel(
                  controller: _searchController,
                  onSearchChanged: _onSearchChanged,
                  onReset: _resetFilters,
                  selectionMode: _selectionMode,
                  onToggleSelection: _toggleSelectionMode,
                  onExport: (format) => _export(visible, format),
                  exporting: _exporting,
                  canExport: _selected.isNotEmpty || visible.isNotEmpty,
                  exportCount: _selected.isNotEmpty
                      ? _selected.length
                      : visible.length,
                ),
                const SizedBox(height: 20),
                _ApplicantsTable(
                  items: visible,
                  hasApplications: applications.isNotEmpty,
                  interviews: interviews,
                  selectionMode: _selectionMode,
                  selected: _selected,
                  onSelectionChanged: (item, selected) => setState(() {
                    if (selected) {
                      _selected[item.id] = item;
                    } else {
                      _selected.remove(item.id);
                    }
                  }),
                  onSelectAll: (selected) => setState(() {
                    for (final item in visible) {
                      if (selected) {
                        _selected[item.id] = item;
                      } else {
                        _selected.remove(item.id);
                      }
                    }
                  }),
                  onView: _openApplicant,
                  onAction: (item, action) async {
                    switch (action) {
                      case 'view':
                        await _openApplicant(item);
                      case 'under_review':
                        await _changeStatus(item, 'under_review');
                      case 'approve':
                        await _changeStatus(item, 'scholar');
                      case 'reject':
                        await _changeStatus(
                          item,
                          'rejected',
                          requireRemarks: true,
                        );
                    }
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _ApplicantStats extends StatelessWidget {
  const _ApplicantStats({
    required this.applications,
    required this.selectedFilter,
    required this.onSelected,
  });

  final List<AdminApplication> applications;
  final String selectedFilter;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    int count(Set<String> statuses) =>
        applications.where((item) => statuses.contains(item.status)).length;
    final values = [
      (
        'Total Applicants',
        applications.length,
        Icons.groups_outlined,
        AppColors.primary,
        'all',
      ),
      (
        'Under Review',
        count({'under_review', 'final_evaluation', 'interview_completed'}),
        Icons.rate_review_outlined,
        AppColors.goldDark,
        'under_review',
      ),
      (
        'Approved Applicants',
        count({'scholar'}),
        Icons.task_alt_outlined,
        const Color(0xFF16835D),
        'approved',
      ),
      (
        'Rejected Applicants',
        count({'rejected'}),
        Icons.person_off_outlined,
        AppColors.error,
        'rejected',
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 850
            ? 4
            : constraints.maxWidth >= 520
            ? 2
            : 1;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final value in values)
              SizedBox(
                width: width,
                child: Semantics(
                  button: true,
                  selected: selectedFilter == value.$5,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selectedFilter == value.$5
                            ? value.$4.withValues(alpha: 0.55)
                            : NseapColors.border,
                      ),
                      boxShadow: const [_pageShadow],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => onSelected(value.$5),
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: value.$4.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: Icon(
                                  value.$3,
                                  color: value.$4,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${value.$2}',
                                      style: TextStyle(
                                        color: value.$4,
                                        fontSize: 23,
                                        height: 1,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      value.$1,
                                      maxLines: 2,
                                      style: const TextStyle(
                                        color: NseapColors.textSecondary,
                                        fontSize: 12,
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _FilterPanel extends StatelessWidget {
  const _FilterPanel({
    required this.controller,
    required this.onSearchChanged,
    required this.onReset,
    required this.selectionMode,
    required this.onToggleSelection,
    required this.onExport,
    required this.exporting,
    required this.canExport,
    this.exportCount,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onReset;
  final bool selectionMode;
  final VoidCallback onToggleSelection;
  final void Function(AdminExportFormat) onExport;
  final bool exporting;
  final bool canExport;
  final int? exportCount;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final isNarrow = constraints.maxWidth < 680;
      final searchField = AdminSearchField(
        controller: controller,
        hint: 'Search names, barangay, school, course, status…',
        onChanged: onSearchChanged,
      );
      final actions = Wrap(
        spacing: 9,
        runSpacing: 9,
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _ResetButton(onPressed: onReset),
          AdminSelectionButton(
            selectionMode: selectionMode,
            onPressed: onToggleSelection,
          ),
          AdminExportDropdown(
            enabled: canExport,
            exporting: exporting,
            count: exportCount,
            onExportPdf: () => onExport(AdminExportFormat.pdf),
            onExportCsv: () => onExport(AdminExportFormat.csv),
          ),
        ],
      );
      if (isNarrow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            searchField,
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerRight, child: actions),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: searchField),
          const SizedBox(width: 12),
          actions,
        ],
      );
    },
  );
}

/// Modern clean reset button — consistent with Applicants filter bar design.
/// Resets search, status, academic year and selection (via [onPressed]).
class _ResetButton extends StatelessWidget {
  const _ResetButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.restart_alt_rounded, size: 18),
        label: const Text(
          'Reset',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF334155),
          backgroundColor: Colors.white,
          side: const BorderSide(color: AppColors.borderLight, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          elevation: 0,
        ),
      ),
    );
  }
}

class _ApplicantsTable extends StatelessWidget {
  const _ApplicantsTable({
    required this.items,
    required this.hasApplications,
    required this.interviews,
    required this.selectionMode,
    required this.selected,
    required this.onSelectionChanged,
    required this.onSelectAll,
    required this.onView,
    required this.onAction,
  });

  final List<AdminApplication> items;
  final bool hasApplications;
  final Map<String, ApplicantInterview> interviews;
  final bool selectionMode;
  final Map<String, AdminApplication> selected;
  final void Function(AdminApplication item, bool selected) onSelectionChanged;
  final ValueChanged<bool> onSelectAll;
  final ValueChanged<AdminApplication> onView;
  final void Function(AdminApplication item, String action) onAction;

  @override
  Widget build(BuildContext context) => _WhiteCard(
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Applicants',
                  style: TextStyle(
                    color: NseapColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F3),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  selectionMode
                      ? '${selected.length} of ${items.length} selected'
                      : '${items.length} records',
                  style: const TextStyle(
                    color: NseapColors.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (items.isEmpty)
          SizedBox(
            height: 180,
            child: AdminStatePanel.empty(
              title: hasApplications
                  ? 'No matching applicants'
                  : 'No applicants yet',
              message: hasApplications
                  ? 'Reset filters or try another search.'
                  : 'Submitted scholarship applications will appear here.',
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 820) {
                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final interview = interviews[item.id];
                    return AdminRecordCard(
                      title: item.name,
                      subtitle: item.number,
                      status: item.status,
                      fields: {
                        'No.': '${index + 1}',
                        'Barangay': _barangayLabel(item),
                        'Applied': adminDateLabel(item.submittedAt),
                        'Interview': adminDateLabel(
                          interview?.scheduledAt,
                          withTime: true,
                        ),
                      },
                      actions: [
                        if (selectionMode)
                          Checkbox(
                            value: selected.containsKey(item.id),
                            onChanged: (value) =>
                                onSelectionChanged(item, value ?? false),
                          ),
                        FilledButton.tonalIcon(
                          onPressed: () => onView(item),
                          icon: const Icon(Icons.person_search_outlined),
                          label: const Text('View Application '),
                        ),
                        _ApplicantMenu(
                          item: item,
                          onSelected: (action) => onAction(item, action),
                        ),
                      ],
                    );
                  },
                );
              }
              final allSelected = items.every(
                (item) => selected.containsKey(item.id),
              );
              // Fit table to screen without horizontal scroll: scale down if needed
              // and use tighter spacing + constrained cells for narrow screens.
              return FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: DataTable(
                    showCheckboxColumn: selectionMode,
                    headingRowColor: WidgetStateProperty.all(
                      const Color(0xFFF8FAFC),
                    ),
                    headingRowHeight: 46,
                    dataRowMinHeight: 56,
                    dataRowMaxHeight: 56,
                    horizontalMargin: 12,
                    columnSpacing: 14,
                    headingTextStyle: const TextStyle(
                      color: NseapColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                    columns: const [
                      DataColumn(label: Text('#')),
                      DataColumn(label: Text('APPLICATION ID')),
                      DataColumn(label: Text('APPLICANT')),
                      DataColumn(label: Text('BARANGAY')),
                      DataColumn(label: Text('DATE APPLIED')),
                      DataColumn(label: Text('INTERVIEW SCHEDULE')),
                      DataColumn(label: Text('STATUS')),
                      DataColumn(label: Text('ACTIONS')),
                    ],
                    rows: items.asMap().entries.map((entry) {
                      final index = entry.key;
                      final item = entry.value;
                      final interview = interviews[item.id];
                      return DataRow(
                        selected:
                            selectionMode && selected.containsKey(item.id),
                        onSelectChanged: selectionMode
                            ? (value) =>
                                  onSelectionChanged(item, value ?? false)
                            : null,
                        cells: [
                          DataCell(
                            Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: NseapColors.textSecondary,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              item.number,
                              style: const TextStyle(
                                color: NseapColors.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircleAvatar(
                                  radius: 15,
                                  backgroundColor: NseapColors.primary
                                      .withValues(alpha: 0.12),
                                  foregroundColor: NseapColors.primary,
                                  child: Text(
                                    item.name.isEmpty
                                        ? 'A'
                                        : item.name[0].toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  item.name,
                                  style: const TextStyle(
                                    color: _pageInk,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          DataCell(Text(_barangayLabel(item))),
                          DataCell(Text(adminDateLabel(item.submittedAt))),
                          DataCell(
                            Text(
                              adminDateLabel(
                                interview?.scheduledAt,
                                withTime: true,
                              ),
                            ),
                          ),
                          DataCell(_ApplicationBadge(item.status)),
                          DataCell(
                            _ApplicantMenu(
                              item: item,
                              onSelected: (action) => onAction(item, action),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                    onSelectAll: selectionMode
                        ? (value) => onSelectAll(value ?? !allSelected)
                        : null,
                  ),
                ),
              );
            },
          ),
      ],
    ),
  );
}

class _ApplicantMenu extends StatelessWidget {
  const _ApplicantMenu({required this.item, required this.onSelected});
  final AdminApplication item;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Applicant actions',
    onSelected: onSelected,
    itemBuilder: (_) {
      final isDecided = item.status == 'scholar' || item.status == 'rejected';
      final isUnderReview = {
        'under_review',
        'final_evaluation',
        'interview_completed',
      }.contains(item.status);
      return [
        const PopupMenuItem(
          value: 'view',
          child: _MenuLabel(Icons.person_outline, 'View Application'),
        ),
        if (!isUnderReview)
          PopupMenuItem(
            value: 'under_review',
            child: _MenuLabel(
              Icons.rate_review_outlined,
              isDecided ? 'Move to Under Review' : 'Set to Under Review',
              color: const Color(0xFF9A6A00),
            ),
          ),
        if (!isDecided) ...const [
          PopupMenuItem(
            value: 'approve',
            child: _MenuLabel(
              Icons.task_alt_outlined,
              'Approve',
              color: Color(0xFF16835D),
            ),
          ),
          PopupMenuItem(
            value: 'reject',
            child: _MenuLabel(
              Icons.block_outlined,
              'Reject',
              color: AppColors.error,
            ),
          ),
        ],
      ];
    },
  );
}

class _MenuLabel extends StatelessWidget {
  const _MenuLabel(this.icon, this.label, {this.color});
  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 19, color: color ?? NseapColors.primary),
      const SizedBox(width: 10),
      Text(label),
    ],
  );
}

/// Opens the original approved application independently of semester submissions.
Future<void> showScholarApplicationRecord(
  BuildContext context, {
  required AdminRepository repository,
  required ScholarRecord scholar,
}) async {
  final applicationId = scholar.applicationId;
  if (applicationId == null) {
    showAdminMessage(
      context,
      'No application is linked to this scholar.',
      error: true,
    );
    return;
  }
  try {
    final application = await repository.getApplication(applicationId);
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _ApplicantDetailPanel(
          repository: repository,
          application: application,
          scholar: scholar,
          onStatusChanged: () {},
        ),
      ),
    );
  } catch (error) {
    if (context.mounted) {
      showAdminMessage(context, readableAdminError(error), error: true);
    }
  }
}

class _ApplicantDetailPanel extends StatefulWidget {
  const _ApplicantDetailPanel({
    required this.repository,
    required this.application,
    required this.onStatusChanged,
    this.scholar,
  });

  final AdminRepository repository;
  final AdminApplication application;
  final VoidCallback onStatusChanged;
  final ScholarRecord? scholar;

  @override
  State<_ApplicantDetailPanel> createState() => _ApplicantDetailPanelState();
}

class _ApplicantDetailPanelState extends State<_ApplicantDetailPanel>
    with RealtimeSyncMixin {
  @override
  Set<String> get realtimeTables => const {
    'users',
    'scholarship_applications',
    'interview_schedules',
    'scholarship_documents',
    'applicant_education',
    'notifications',
  };
  @override
  Future<void> refreshRealtime() async {
    _reload();
    await _future;
  }

  late Future<ApplicantDetail> _future = widget.repository.getApplicantDetail(
    widget.application,
  );

  void _reload() => setState(() {
    _future = widget.repository
        .getApplication(widget.application.id)
        .then(widget.repository.getApplicantDetail);
  });

  Future<void> _decision(String status) async {
    String? remarks;
    if (status == 'rejected') {
      remarks = await showAdminTextDialog(
        context,
        title: 'Reject application?',
        label: 'Rejection remarks (required)',
      );
      if (remarks == null || remarks.trim().isEmpty) {
        if (remarks != null && mounted) {
          showAdminMessage(
            context,
            'Rejection remarks are required.',
            error: true,
          );
        }
        return;
      }
    } else if (status == 'under_review') {
      final confirmed = await confirmAdminAction(
        context,
        title: 'Set to Under Review?',
        message:
            'Move ${widget.application.name}\'s application to Under Review for further review?',
        confirmLabel: 'Set to Under Review',
      );
      if (!confirmed) return;
    } else if (!await confirmAdminAction(
      context,
      title: 'Approve application?',
      message: 'This will approve ${widget.application.name} as a scholar.',
      confirmLabel: 'Approve Application',
    )) {
      return;
    }
    if (!mounted) return;
    await runAdminAction(
      context,
      () => widget.repository.transitionApplication(
        widget.application.id,
        status,
        note: remarks,
      ),
      'Application decision saved.',
      () {
        adminApplicationsRefreshNotifier.value++;
        widget.onStatusChanged();
        _reload();
      },
    );
  }

  Future<void> _openDocument(AdminDocument document) {
    // Start one authenticated download and share it with the preview builder.
    final download = widget.repository.downloadDocument(document.storagePath);
    return showDialog<void>(
      context: context,
      builder: (context) =>
          _DocumentPreviewDialog(document: document, download: download),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(
      backgroundColor: AppColors.background,
      foregroundColor: _pageInk,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: const Border(bottom: BorderSide(color: NseapColors.border)),
      titleTextStyle: const TextStyle(
        color: _pageInk,
        fontSize: 17,
        fontWeight: FontWeight.w800,
      ),
      title: Text(widget.scholar == null ? 'Application' : 'Scholar Record'),
      leading: IconButton(
        tooltip: 'Close',
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.close_rounded),
      ),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _reload,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: FutureBuilder<ApplicantDetail>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          if (snapshot.hasError) {
            return AdminStatePanel.error(
              message: readableAdminError(snapshot.error),
              onRetry: _reload,
            );
          }
          return const AdminStatePanel.loading();
        }
        final detail = snapshot.requireData;
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            _ProfileHero(detail: detail),
            const SizedBox(height: 14),
            if (widget.scholar case final scholar?)
              _DetailSection(
                title: 'Scholar Record',
                icon: Icons.school_outlined,
                child: _InfoGrid(
                  values: {
                    'Scholar ID': scholar.scholarId,
                    'Scholar Status': adminLabel(scholar.status),
                    'Date Applied': adminDateLabel(
                      detail.application.submittedAt,
                      withTime: true,
                    ),
                    'Date Accepted': adminDateLabel(
                      scholar.acceptedAt,
                      withTime: true,
                    ),
                  },
                ),
              ),
            _DetailSection(
              title: 'Personal Information',
              icon: Icons.person_outline,
              child: _InfoGrid(
                values: {
                  'Full Name': detail.application.name,
                  'Date of Birth': adminDateLabel(detail.dateOfBirth),
                  'Sex': detail.sex,
                  'Contact Number': detail.contactNumber,
                  'Email Address': detail.application.email,
                  'Complete Address': detail.address,
                  'Barangay': _barangayLabel(detail.application),
                },
              ),
            ),
            _DetailSection(
              title: 'Educational Information',
              icon: Icons.school_outlined,
              child: _InfoGrid(
                values: {
                  'School': detail.application.school,
                  'Course / Program': detail.application.course,
                  'Year Level': detail.yearLevel,
                  'Student ID Number': detail.studentIdNumber,
                },
              ),
            ),
            _DetailSection(
              title: 'Parent/Guardian Information',
              icon: Icons.family_restroom_outlined,
              child: _InfoGrid(
                values: {
                  'Father Name': detail.fatherName,
                  'Father Occupation': detail.fatherOccupation,
                  'Father Income Range': detail.fatherIncomeRange,
                  'Mother Name': detail.motherName,
                  'Mother Occupation': detail.motherOccupation,
                  'Mother Income Range': detail.motherIncomeRange,
                  'Household Monthly Income': detail.householdIncome,
                  'Household Members': detail.householdMembers,
                },
              ),
            ),
            _DetailSection(
              title: 'Scholarship Application Information',
              icon: Icons.assignment_outlined,
              child: _InfoGrid(
                values: {
                  'Application ID': detail.application.number,
                  'Date Submitted': adminDateLabel(
                    detail.application.submittedAt,
                    withTime: true,
                  ),
                  'Current Status': _statusLabel(detail.application.status),
                  'Interview Schedule': adminDateLabel(
                    detail.interviewAt,
                    withTime: true,
                  ),
                  'Interview Status': adminLabel(
                    detail.interviewStatus ?? 'not_scheduled',
                  ),
                },
              ),
            ),
            _DetailSection(
              title: 'Uploaded Requirements',
              icon: Icons.folder_copy_outlined,
              child: detail.documents.isEmpty
                  ? const _InlineEmpty('No requirements uploaded.')
                  : AdminRequirementsList(
                      documents: detail.documents,
                      download: widget.repository.downloadDocument,
                      onPreview: _openDocument,
                      archiveName: '${detail.application.number}-requirements',
                    ),
            ),
            _DetailSection(
              title: 'Interview Management',
              icon: Icons.event_available_outlined,
              child: _InfoGrid(
                values: {
                  'Interview Date': adminDateLabel(detail.interviewAt),
                  'Time': detail.interviewAt == null
                      ? 'Not scheduled'
                      : TimeOfDay.fromDateTime(
                          detail.interviewAt!,
                        ).format(context),
                  'Location': detail.interviewLocation ?? 'Not scheduled',
                  'Status': adminLabel(
                    detail.interviewStatus ?? 'not_scheduled',
                  ),
                },
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({required this.detail});
  final ApplicantDetail detail;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: NseapColors.border),
      boxShadow: const [_pageShadow],
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFF2FAF5), Colors.white],
        stops: [0, 0.55],
      ),
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: NseapColors.gold, width: 2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14101828),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: CircleAvatar(
            radius: 28,
            backgroundColor: NseapColors.gold,
            foregroundColor: NseapColors.primary,
            child: Text(
              detail.application.name.isEmpty
                  ? 'A'
                  : detail.application.name[0].toUpperCase(),
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                detail.application.name,
                style: const TextStyle(
                  color: _pageInk,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                detail.application.number,
                style: const TextStyle(
                  color: NseapColors.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        _ApplicationBadge(detail.application.status),
      ],
    ),
  );
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({
    required this.title,
    required this.icon,
    required this.child,
  });
  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: _WhiteCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: NseapColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: NseapColors.primary, size: 18),
              ),
              const SizedBox(width: 11),
              Text(
                title,
                style: const TextStyle(
                  color: NseapColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          Divider(height: 28, color: NseapColors.border.withValues(alpha: 0.7)),
          child,
        ],
      ),
    ),
  );
}

class _InfoGrid extends StatelessWidget {
  const _InfoGrid({required this.values});
  final Map<String, String> values;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth >= 520
          ? (constraints.maxWidth - 18) / 2
          : constraints.maxWidth;
      return Wrap(
        spacing: 18,
        runSpacing: 16,
        children: [
          for (final entry in values.entries)
            SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.key.toUpperCase(),
                    style: const TextStyle(
                      color: NseapColors.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    entry.value,
                    style: const TextStyle(
                      color: _pageInk,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}

class _DocumentPreviewDialog extends StatelessWidget {
  const _DocumentPreviewDialog({
    required this.document,
    required this.download,
  });

  final AdminDocument document;
  final Future<Uint8List> download;

  bool get _isPdf =>
      document.mimeType == 'application/pdf' ||
      document.fileName.toLowerCase().endsWith('.pdf');

  bool get _isImage =>
      document.mimeType.startsWith('image/') ||
      RegExp(
        r'\.(jpe?g|png)$',
        caseSensitive: false,
      ).hasMatch(document.fileName);

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: _pageInk,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: const Border(bottom: BorderSide(color: NseapColors.border)),
        titleTextStyle: const TextStyle(
          color: _pageInk,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
        title: Text(document.fileName),
        leading: IconButton(
          tooltip: 'Close preview',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded),
        ),
      ),
      body: FutureBuilder<Uint8List>(
        future: download,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AdminStatePanel.error(
              message: readableAdminError(snapshot.error),
              onRetry: () => Navigator.pop(context),
            );
          }
          if (!snapshot.hasData) return const AdminStatePanel.loading();

          final bytes = snapshot.requireData;
          if (_isPdf) {
            return PdfPreview(
              build: (_) async => bytes,
              pdfFileName: document.fileName,
              allowSharing: false,
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
            );
          }
          if (_isImage) {
            return ColoredBox(
              color: AppColors.textDark,
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 5,
                child: Center(
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => AdminStatePanel.error(
                      message: 'The uploaded image could not be displayed.',
                      onRetry: () => Navigator.pop(context),
                    ),
                  ),
                ),
              ),
            );
          }
          return AdminStatePanel.error(
            message: 'This document format cannot be previewed.',
            onRetry: () => Navigator.pop(context),
          );
        },
      ),
    ),
  );
}

class _ApplicationBadge extends StatelessWidget {
  const _ApplicationBadge(this.status);
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'submitted' => AppColors.goldDark,
      'needs_revision' => _pageOrange,
      'interview_scheduled' || 'interview_completed' => NseapColors.primary,
      'scholar' => NseapColors.primary,
      'rejected' || 'withdrawn' => _pageRed,
      _ => AppColors.goldDark,
    };
    return _SmallTag(_statusLabel(status), color);
  }
}

class _SmallTag extends StatelessWidget {
  const _SmallTag(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.11),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: 0.18)),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    ),
  );
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Center(
      child: Text(
        message,
        style: const TextStyle(color: NseapColors.textSecondary),
      ),
    ),
  );
}

class _WhiteCard extends StatelessWidget {
  const _WhiteCard({required this.child, required this.padding});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: NseapColors.border),
      boxShadow: const [_pageShadow],
    ),
    child: child,
  );
}

String _barangayLabel(AdminApplication item) {
  if (item.address.trim().isEmpty) return 'Not recorded';
  final parts = item.address.split(',');
  return parts.first.trim().isEmpty ? 'Not recorded' : parts.first.trim();
}

String _statusLabel(String status) => switch (status) {
  'submitted' || 'pending' => 'Pending',
  'needs_revision' => 'Incomplete',
  'interview_scheduled' => 'For Interview',
  'interview_completed' => 'Interview Completed',
  'scholar' => 'Approved',
  'rejected' || 'withdrawn' => 'Rejected',
  'under_review' || 'final_evaluation' => 'Under Review',
  _ => adminLabel(status),
};
