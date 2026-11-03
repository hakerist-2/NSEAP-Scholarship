import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nseapscholarship/services/realtime_sync.dart';
import 'package:flutter/services.dart';
import 'package:nseapscholarship/admin/widgets/dashboard/dashboard_export.dart';
import 'package:nseapscholarship/theme/nseap_theme.dart';
import 'package:printing/printing.dart';

import '../../data/admin_repository.dart';
import '../../models/admin_models.dart';
import '../../widgets/admin_widgets.dart';
import '../../widgets/requirement_download_button.dart';
import '../shared/admin_page_support.dart';
import '../../../utils/academic_year.dart';
import 'walkin_scholar_form_page.dart';

/// Strips characters that the Inter font cannot render (shows as □ with X).
String _safeText(String value) {
  final buf = StringBuffer();
  for (final rune in value.runes) {
    if (rune == 0x09 || rune == 0x0A || rune == 0x0D) {
      buf.write(String.fromCharCode(rune));
    } else if (rune >= 0x20 && rune <= 0xD7FF) {
      buf.write(String.fromCharCode(rune));
    } else if (rune >= 0xE000 && rune <= 0xFFFD) {
      buf.write(String.fromCharCode(rune));
    } else if (rune >= 0x10000 && rune <= 0x10FFFF) {
      buf.write(String.fromCharCode(rune));
    }
  }
  return buf.toString();
}

/// Reviews activation requests and manages active scholar records.
class ScholarsAdminPage extends StatefulWidget {
  const ScholarsAdminPage({required this.repository, super.key});
  final AdminRepository repository;

  @override
  State<ScholarsAdminPage> createState() => _ScholarsAdminPageState();
}

class _ScholarsAdminPageState extends State<ScholarsAdminPage>
    with RealtimeSyncMixin {
  @override
  Set<String> get realtimeTables => const {
    'users',
    'scholarship_applications',
    'scholar_profiles',
    'semester_submissions',
    'semester_periods',
    'scholar_activation_requests',
  };
  @override
  Future<void> refreshRealtime() async {
    _reload();
    await _scholarsFuture;
  }

  late Future<
    (List<ScholarRecord>, List<SemesterPeriod>, List<SemesterSubmission>)
  >
  _scholarsFuture = _loadScholarData();
  String _search = '';
  String _status = 'all';
  String _academicYear = 'all';
  String _semester = 'all';

  // Fixed semester filter — always First/Second, added on demand like academic year.
  static const _semesterOptions = ['First Semester', 'Second Semester'];
  List<String> get _academicYearOptions =>
      AcademicYearUtils.generateAcademicYears();

  String _normalizeSemester(String value) {
    final low = value.toLowerCase().trim();
    if (low.contains('1st') || low.contains('first')) return 'First Semester';
    if (low.contains('2nd') || low.contains('second')) {
      return 'Second Semester';
    }
    if (low.contains('summer')) return 'Summer';
    return value;
  }

  bool _matchesSemester(String dbValue, String filterValue) {
    if (filterValue == 'all') return true;
    return _normalizeSemester(dbValue) == _normalizeSemester(filterValue);
  }

  bool _isApprovedStatus(String? status) =>
      status == 'verified' || status == 'approved';

  /// A scholar counts as approved when the scholar record itself is approved
  /// or the latest semester submission is verified/approved — unless the
  /// scholar is terminated or graduated.
  bool _isApprovedScholar(ScholarRecord item, String? submissionStatus) =>
      (_isApprovedStatus(item.status) || _isApprovedStatus(submissionStatus)) &&
      !_isScholarTerminatedOrGraduated(item.status);

  /// Keeps KPI counts in sync with the table: a scholar belongs to the
  /// selected period when a submission exists in it or the saved approval
  /// period matches the filters.
  bool _matchesScholarPeriod(
    ScholarRecord item,
    SemesterSubmission? submission,
    String academicYear,
    String semester,
  ) =>
      submission != null ||
      ((academicYear == 'all' || item.approvalAcademicYear == academicYear) &&
          (semester == 'all' ||
              _matchesSemester(item.approvalSemester ?? '', semester)));

  /// Clamps the selected year to 'all' when it matches neither a started
  /// period nor a scholar approval year — same rule as the table, so KPI
  /// counts and visible rows never disagree.
  String _effectiveAcademicYear(
    List<SemesterPeriod> periods,
    List<ScholarRecord> scholars,
  ) {
    final yearSet = periods
        .where((p) => p.status != 'upcoming')
        .map((p) => p.academicYear)
        .where((value) => value.isNotEmpty)
        .toSet();
    yearSet.addAll(
      scholars.map((item) => item.approvalAcademicYear).whereType<String>(),
    );
    return _academicYear == 'all' || yearSet.contains(_academicYear)
        ? _academicYear
        : 'all';
  }

  bool _isPendingStatus(String? status) =>
      status != null &&
      !_isApprovedStatus(status) &&
      status != 'needs_revision' &&
      status != 'cancelled';

  /// Keep cancelled submissions distinct from scholars who never submitted.
  /// Maps verified/approved/pending/under_review → submitted for display.
  String _normalizeSubmissionForDisplay(String? raw) {
    if (raw == 'cancelled') return 'cancelled_submission';
    if (raw == null || raw == 'not_submitted') {
      return 'not_submitted';
    }
    if (raw == 'needs_revision') return 'needs_revision';
    return 'submitted';
  }

  bool _isScholarTerminatedOrGraduated(String status) =>
      status == 'terminated' ||
      status == 'archived' ||
      status == 'cancelled' ||
      status == 'graduated';

  String _listView = 'all';
  final Map<String, ScholarRecord> _selected = {};
  bool _selectionMode = false;
  bool _exporting = false;

  Future<(List<ScholarRecord>, List<SemesterPeriod>, List<SemesterSubmission>)>
  _loadScholarData() async {
    final values = await Future.wait<dynamic>([
      widget.repository.getScholars(),
      widget.repository.getSemesterPeriods(),
      widget.repository.getSemesterSubmissions(),
    ]);
    return (
      values[0] as List<ScholarRecord>,
      values[1] as List<SemesterPeriod>,
      values[2] as List<SemesterSubmission>,
    );
  }

  void _reload() => setState(() {
    _scholarsFuture = _loadScholarData();
  });

  void _select(ScholarRecord item, bool selected) => setState(() {
    if (selected) {
      _selected[item.id] = item;
    } else {
      _selected.remove(item.id);
    }
  });

  void _toggleSelectionMode() => setState(() {
    _selectionMode = !_selectionMode;
    if (!_selectionMode) _selected.clear();
  });

  Future<void> _exportSelected(
    AdminExportFormat format, {
    List<ScholarRecord>? fallback,
  }) async {
    if (_exporting) return;
    final toExport = _selected.isNotEmpty
        ? _selected.values.toList()
        : (fallback ?? <ScholarRecord>[]);
    if (toExport.isEmpty) {
      showAdminMessage(context, 'No scholars to export.');
      return;
    }
    final selected = toExport;
    const headers = [
      'Scholar ID',
      'Name',
      'School',
      'Program',
      'Barangay',
      'Status',
      'Date Applied',
      'Date Accepted',
    ];
    final rows = selected
        .map(
          (item) => [
            item.scholarId,
            item.name,
            item.school,
            item.program,
            item.barangay,
            adminLabel(item.status),
            adminDateLabel(item.appliedAt),
            adminDateLabel(item.acceptedAt),
          ],
        )
        .toList();

    setState(() => _exporting = true);
    try {
      if (format == AdminExportFormat.pdf) {
        // Reuses dashboard's PDF download — same button/logic
        await exportTablePdf(
          title: 'NSEAP Scholars',
          headers: headers,
          rows: rows,
        );
        if (mounted) {
          showAdminMessage(
            context,
            'PDF downloaded (${rows.length} scholars).',
          );
        }
      } else {
        // Reuses dashboard's Excel-ready CSV (BOM + file download)
        await exportTableCsv(
          title: 'NSEAP Scholars',
          headers: headers,
          rows: rows,
        );
        if (mounted) {
          showAdminMessage(
            context,
            'CSV downloaded — Excel-ready (${rows.length} scholars).',
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

  String _mapDbStatusToUi(String dbStatus) => switch (dbStatus) {
    'active' => 'pending',
    'archived' => 'terminated',
    'suspended' => 'terminated',
    _ => dbStatus,
  };

  Future<void> _update(ScholarRecord scholar, String? submissionStatus) async {
    final result = await showAdminChoiceDialog(
      context,
      title: 'Update ${scholar.name}',
      label: 'Scholar status',
      options: const ['pending', 'approved', 'terminated', 'graduated'],
      initial: _mapDbStatusToUi(scholar.status),
      noteLabel: 'Status note',
    );
    if (result == null) return;
    if (!mounted) return;
    // Lock: once the scholar's semester submission is approved/verified
    // (e.g. 1st Semester 2026-2027), the status is final and cannot move
    // to pending, terminated, or graduated.
    if (_isApprovedStatus(submissionStatus) &&
        (result.$1 == 'pending' ||
            result.$1 == 'terminated' ||
            result.$1 == 'graduated')) {
      showAdminMessage(
        context,
        'This scholar has an approved semester submission and the status cannot be changed.',
        error: true,
      );
      return;
    }
    // Enforce: once approved, cannot revert to pending
    if (_isApprovedStatus(scholar.status) && result.$1 == 'pending') {
      showAdminMessage(
        context,
        'Approved scholars cannot be moved back to pending.',
        error: true,
      );
      return;
    }
    await runAdminAction(
      context,
      () => widget.repository.setScholarStatus(
        scholar.userId,
        result.$1,
        note: result.$2,
      ),
      'Scholar status updated.',
      _reload,
    );
  }

  void _openSubmission(ScholarRecord scholar, SemesterSubmission? submission) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ScholarSubmissionPage(
          repository: widget.repository,
          scholar: scholar,
          submission: submission,
        ),
      ),
    );
  }

  Future<void> _openWalkInForm() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => WalkInScholarFormPage(repository: widget.repository),
      ),
    );
    if (saved == true && mounted) {
      setState(() => _listView = 'approved');
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) => AdminPageFrame(
    header: _buildScholarsHeader(),
    toolbar: Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _buildStatusCards(),
    ),
    body: _buildScholars(),
  );

  Widget _buildScholarsHeader() => LayoutBuilder(
    builder: (context, constraints) =>
        FutureBuilder<
          (List<ScholarRecord>, List<SemesterPeriod>, List<SemesterSubmission>)
        >(
          future: _scholarsFuture,
          builder: (context, snapshot) {
            final periods = snapshot.data?.$2;
            final scholars = snapshot.data?.$1;
            List<String> years;
            if (snapshot.connectionState != ConnectionState.done) {
              years = _academicYearOptions;
            } else if (periods != null) {
              // Active status means the application window has started, even
              // when startsAt is still in the future (matches the mobile app).
              bool isUpcomingPeriod(SemesterPeriod p) => p.status == 'upcoming';
              final startedPeriods = periods
                  .where((p) => !isUpcomingPeriod(p))
                  .toList();
              final dbYearSet = startedPeriods
                  .map((item) => item.academicYear)
                  .where((value) => value.isNotEmpty)
                  .toSet();
              // Newly approved scholars carry their approval year even when
              // no semester submission exists yet.
              if (scholars != null) {
                dbYearSet.addAll(
                  scholars
                      .map((item) => item.approvalAcademicYear)
                      .whereType<String>(),
                );
              }
              final dbYears = dbYearSet.toList()
                ..sort((a, b) => b.compareTo(a));
              // Keep dropdown visible after load: fallback to generated years
              // when no started periods exist (e.g., empty DB or all upcoming).
              // Prevents header filter vanishing after FutureBuilder completes.
              if (dbYears.isNotEmpty) {
                years = dbYears;
              } else {
                years = List<String>.from(_academicYearOptions)
                  ..sort((a, b) => b.compareTo(a));
              }
            } else {
              years = _academicYearOptions;
            }
            final showYearFilter = years.isNotEmpty;
            final showSemesterFilter = showYearFilter;
            final effectiveAcademicYear =
                _academicYear == 'all' || years.contains(_academicYear)
                ? _academicYear
                : 'all';
            const semesters = _semesterOptions;
            final effectiveSemester =
                _semester == 'all' || semesters.contains(_semester)
                ? _semester
                : 'all';

            // Right-aligned white pills — parity with Scholar header (scholar_home_page.dart:344).
            final academicYearFilter = showYearFilter
                ? Semantics(
                    label:
                        'Academic Year filter, selected $effectiveAcademicYear',
                    button: true,
                    child: Container(
                      height: 36,
                      constraints: const BoxConstraints(
                        minWidth: 168,
                        maxWidth: 190,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white, width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: effectiveAcademicYear,
                          isExpanded: true,
                          isDense: true,
                          icon: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 18,
                            color: Color(0xFF64748B),
                          ),
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                          dropdownColor: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          items: [
                            const DropdownMenuItem(
                              value: 'all',
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.school_outlined,
                                    size: 14,
                                    color: Color(0xFF165EF0),
                                  ),
                                  SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      'All',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ...years.map(
                              (y) => DropdownMenuItem(
                                value: y,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.school_outlined,
                                      size: 14,
                                      color: Color(0xFF165EF0),
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        y,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          onChanged: (v) => setState(() {
                            _academicYear = v ?? 'all';
                            _semester = 'all';
                          }),
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink();

            final semesterFilter = showSemesterFilter
                ? Semantics(
                    label: 'Semester filter, selected $effectiveSemester',
                    button: true,
                    child: Container(
                      height: 36,
                      constraints: const BoxConstraints(
                        minWidth: 148,
                        maxWidth: 172,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white, width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: effectiveSemester,
                          isExpanded: true,
                          isDense: true,
                          icon: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 18,
                            color: Color(0xFF64748B),
                          ),
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                          dropdownColor: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          items: const [
                            DropdownMenuItem(
                              value: 'all',
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.calendar_month_outlined,
                                    size: 14,
                                    color: Color(0xFF165EF0),
                                  ),
                                  SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      'All',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'First Semester',
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.calendar_month_outlined,
                                    size: 14,
                                    color: Color(0xFF165EF0),
                                  ),
                                  SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      'First Semester',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'Second Semester',
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.calendar_month_outlined,
                                    size: 14,
                                    color: Color(0xFF165EF0),
                                  ),
                                  SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      'Second Semester',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          onChanged: (v) =>
                              setState(() => _semester = v ?? 'all'),
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink();

            final filters = Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (showYearFilter) academicYearFilter,
                if (showSemesterFilter) semesterFilter,
              ],
            );

            const title = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Scholars',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    height: 1,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Manage scholar records and submissions',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 12.5),
                ),
              ],
            );

            final narrow = constraints.maxWidth < 560;
            if (narrow) {
              // Narrow: title on top, filters right-aligned below — matches Scholar header.
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(children: [Expanded(child: title)]),
                  if (showYearFilter || showSemesterFilter) ...[
                    const SizedBox(height: 12),
                    Align(alignment: Alignment.centerRight, child: filters),
                  ],
                ],
              );
            }
            // Wide: title left, filters right-aligned — status + filters stacked on right in Scholar header.
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Expanded(child: title),
                const SizedBox(width: 12),
                Align(alignment: Alignment.centerRight, child: filters),
              ],
            );
          },
        ),
  );

  Widget _buildStatusCards() =>
      FutureBuilder<
        (List<ScholarRecord>, List<SemesterPeriod>, List<SemesterSubmission>)
      >(
        future: _scholarsFuture,
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (data == null) {
            return const SizedBox(
              height: 72,
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final scholars = data.$1;
          final academicYear = _effectiveAcademicYear(data.$2, scholars);
          final filteredSubmissions = data.$3.where(
            (item) =>
                (academicYear == 'all' || item.academicYear == academicYear) &&
                _matchesSemester(item.semester, _semester),
          );
          final submissionByUser = <String, SemesterSubmission>{};
          for (final submission in filteredSubmissions) {
            final current = submissionByUser[submission.userId];
            final currentDate = current?.submittedAt;
            final nextDate = submission.submittedAt;
            if (current == null ||
                (nextDate != null &&
                    (currentDate == null || nextDate.isAfter(currentDate)))) {
              submissionByUser[submission.userId] = submission;
            }
          }
          final approvedUsers = scholars
              .where(
                (item) =>
                    _matchesScholarPeriod(
                      item,
                      submissionByUser[item.userId],
                      academicYear,
                      _semester,
                    ) &&
                    _isApprovedScholar(
                      item,
                      submissionByUser[item.userId]?.status,
                    ),
              )
              .length;
          final pendingUsers = scholars
              .where(
                (item) =>
                    _matchesScholarPeriod(
                      item,
                      submissionByUser[item.userId],
                      academicYear,
                      _semester,
                    ) &&
                    _isPendingStatus(submissionByUser[item.userId]?.status) &&
                    !_isScholarTerminatedOrGraduated(item.status),
              )
              .length;
          final terminatedUsers = scholars
              .where(
                (item) =>
                    item.status == 'archived' ||
                    item.status == 'terminated' ||
                    item.status == 'cancelled',
              )
              .length;
          final graduatedUsers = scholars
              .where((item) => item.status == 'graduated')
              .length;
          return _ScholarStatusStats(
            total: scholars.length,
            pending: pendingUsers,
            approved: approvedUsers,
            terminated: terminatedUsers,
            graduated: graduatedUsers,
            selectedView: _listView,
            onSelected: (value) => setState(() {
              _listView = value;
              _status = 'all';
            }),
          );
        },
      );

  Widget _buildScholars() =>
      AdminAsyncView<
        (List<ScholarRecord>, List<SemesterPeriod>, List<SemesterSubmission>)
      >(
        future: _scholarsFuture,
        isEmpty: (_) => false,
        onRetry: _reload,
        builder: (context, data) {
          final items = data.$1;
          final periods = data.$2;
          final submissions = data.$3;
          // Academic Year: only show periods where application window has started.
          // Active status counts as started even when startsAt is in the future
          // (the admin dialog no longer offers "upcoming"); only rows still
          // stored as upcoming are excluded.
          final academicYear = _effectiveAcademicYear(periods, items);
          // Semester: fixed First/Second Semester filter (always available)
          const semesters = _semesterOptions;
          final semester = _semester == 'all' || semesters.contains(_semester)
              ? _semester
              : 'all';
          final filteredSubmissions = submissions.where(
            (item) =>
                (academicYear == 'all' || item.academicYear == academicYear) &&
                _matchesSemester(item.semester, semester),
          );
          final submissionByUser = <String, SemesterSubmission>{};
          for (final submission in filteredSubmissions) {
            final current = submissionByUser[submission.userId];
            final currentDate = current?.submittedAt;
            final nextDate = submission.submittedAt;
            if (current == null ||
                (nextDate != null &&
                    (currentDate == null || nextDate.isAfter(currentDate)))) {
              submissionByUser[submission.userId] = submission;
            }
          }
          final visible = items.where((item) {
            final submission = submissionByUser[item.userId];
            final submissionStatus = _normalizeSubmissionForDisplay(
              submission?.status,
            );
            final matchesPeriod = _matchesScholarPeriod(
              item,
              submission,
              academicYear,
              semester,
            );
            final text = '${item.scholarId} ${item.name}'.toLowerCase();
            final matchesListView = switch (_listView) {
              'pending' =>
                _isPendingStatus(submissionByUser[item.userId]?.status) &&
                    !_isScholarTerminatedOrGraduated(item.status),
              // Dropdown filters match the visible Submission column, rather
              // than the separate scholar-status KPI rules.
              'submitted' => submissionStatus == 'submitted',
              'not_submitted' => submissionStatus == 'not_submitted',
              'cancelled_submission' =>
                submissionStatus == 'cancelled_submission',
              'approved' => _isApprovedScholar(
                item,
                submissionByUser[item.userId]?.status,
              ),
              'need_revision' => submissionStatus == 'needs_revision',
              'terminated' =>
                item.status == 'archived' ||
                    item.status == 'terminated' ||
                    item.status == 'cancelled',
              'graduated' => item.status == 'graduated',
              _ => true,
            };
            return matchesPeriod &&
                text.contains(_search) &&
                (_status == 'all' || item.status == _status) &&
                matchesListView;
          }).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 650;
                  final isMedium =
                      constraints.maxWidth >= 650 && constraints.maxWidth < 900;
                  final isWide = constraints.maxWidth >= 900;
                  final viewWidth = compact
                      ? constraints.maxWidth
                      : (isWide ? 245.0 : 235.0);
                  final selectWidth = compact ? constraints.maxWidth : 180.0;

                  // Search and filters — View filter aligned on right; AY/Semester now in header
                  final searchField = AdminSearchField(
                    hint: 'Search scholar ID or name',
                    onChanged: (value) =>
                        setState(() => _search = value.toLowerCase()),
                  );
                  // Filter dropdown must NOT contain pending/approved/terminated/graduated
                  // (those are KPI-only). Clamp value to avoid Dropdown error when KPI is active.
                  final effectiveFilterView =
                      const {
                        'all',
                        'submitted',
                        'not_submitted',
                        'cancelled_submission',
                        'need_revision',
                      }.contains(_listView)
                      ? _listView
                      : 'all';
                  final filterDropdowns = Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      SizedBox(
                        width: viewWidth,
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('list-view-$effectiveFilterView'),
                          initialValue: effectiveFilterView,
                          isExpanded: true,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                          iconSize: 18,
                          decoration: adminFieldDecoration(
                            hint: 'View List',
                            prefixIcon: Icons.filter_list_rounded,
                          ),
                          dropdownColor: Colors.white,
                          items: const [
                            DropdownMenuItem(
                              value: 'all',
                              child: Text(
                                'All Scholars',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'submitted',
                              child: Text(
                                'Submitted',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'not_submitted',
                              child: Text(
                                'Not Submitted',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'need_revision',
                              child: Text(
                                'Need Revision',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'cancelled_submission',
                              child: Text(
                                'Cancelled Submission',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                          onChanged: (value) => setState(() {
                            _listView = value ?? 'all';
                            _status = 'all';
                          }),
                        ),
                      ),
                    ],
                  );

                  // Export always blue even when nothing selected — exports visible when no selection
                  final exportButton = AdminExportDropdown(
                    enabled: true,
                    exporting: _exporting,
                    count: _selected.isNotEmpty
                        ? _selected.length
                        : visible.length,
                    onExportPdf: () => _exportSelected(
                      AdminExportFormat.pdf,
                      fallback: visible,
                    ),
                    onExportCsv: () => _exportSelected(
                      AdminExportFormat.csv,
                      fallback: visible,
                    ),
                  );
                  final selectButton = AdminSelectionButton(
                    selectionMode: _selectionMode,
                    onPressed: _toggleSelectionMode,
                  );
                  final walkInButton = FilledButton.icon(
                    onPressed: _openWalkInForm,
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                    label: const Text(
                      'Add Scholar',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                  // Align search and filters horizontally; export + walk-in at top right
                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.end,
                            children: [walkInButton, exportButton],
                          ),
                        ),
                        const SizedBox(height: 8),
                        searchField,
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: filterDropdowns,
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: selectButton,
                        ),
                        if (_selectionMode && visible.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: selectWidth,
                            child: Container(
                              padding: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: NseapColors.border),
                              ),
                              child: Row(
                                children: [
                                  Checkbox(
                                    tristate: true,
                                    value:
                                        visible
                                                .where(
                                                  (item) => _selected
                                                      .containsKey(item.id),
                                                )
                                                .length ==
                                            visible.length
                                        ? true
                                        : visible
                                              .where(
                                                (item) => _selected.containsKey(
                                                  item.id,
                                                ),
                                              )
                                              .isNotEmpty
                                        ? null
                                        : false,
                                    onChanged: (_) => setState(() {
                                      final allSelected =
                                          visible
                                              .where(
                                                (item) => _selected.containsKey(
                                                  item.id,
                                                ),
                                              )
                                              .length ==
                                          visible.length;
                                      if (allSelected) {
                                        for (final item in visible) {
                                          _selected.remove(item.id);
                                        }
                                      } else {
                                        for (final item in visible) {
                                          _selected[item.id] = item;
                                        }
                                      }
                                    }),
                                  ),
                                  Expanded(
                                    child: Text(
                                      'Select all (${visible.length})',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: NseapColors.primaryActive,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_selectionMode) ...[
                            const SizedBox(height: 6),
                            Text(
                              '${_selected.length} selected',
                              style: const TextStyle(
                                color: NseapColors.primaryActive,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ],
                    );
                  }
                  if (isMedium) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.end,
                            children: [walkInButton, exportButton],
                          ),
                        ),
                        const SizedBox(height: 8),
                        searchField,
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: filterDropdowns,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            selectButton,
                            const Spacer(),
                            if (_selectionMode && visible.isNotEmpty)
                              SizedBox(
                                width: selectWidth,
                                child: Container(
                                  padding: const EdgeInsets.only(right: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: NseapColors.border,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Builder(
                                        builder: (context) {
                                          final selectedVisible = visible
                                              .where(
                                                (item) => _selected.containsKey(
                                                  item.id,
                                                ),
                                              )
                                              .length;
                                          final allSelected =
                                              selectedVisible == visible.length;
                                          return Checkbox(
                                            tristate: true,
                                            value: allSelected
                                                ? true
                                                : selectedVisible > 0
                                                ? null
                                                : false,
                                            onChanged: (_) => setState(() {
                                              if (allSelected) {
                                                for (final item in visible) {
                                                  _selected.remove(item.id);
                                                }
                                              } else {
                                                for (final item in visible) {
                                                  _selected[item.id] = item;
                                                }
                                              }
                                            }),
                                          );
                                        },
                                      ),
                                      Expanded(
                                        child: Text(
                                          'Select all (${visible.length})',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: NseapColors.primaryActive,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (_selectionMode) ...[
                              const SizedBox(width: 8),
                              Text(
                                '${_selected.length} selected',
                                style: const TextStyle(
                                  color: NseapColors.primaryActive,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.end,
                          children: [walkInButton, exportButton],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: searchField),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: filterDropdowns,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          selectButton,
                          const Spacer(),
                          if (_selectionMode && visible.isNotEmpty)
                            SizedBox(
                              width: selectWidth,
                              child: Container(
                                padding: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: NseapColors.border),
                                ),
                                child: Row(
                                  children: [
                                    Builder(
                                      builder: (context) {
                                        final selectedVisible = visible
                                            .where(
                                              (item) => _selected.containsKey(
                                                item.id,
                                              ),
                                            )
                                            .length;
                                        final allSelected =
                                            selectedVisible == visible.length;
                                        return Checkbox(
                                          tristate: true,
                                          value: allSelected
                                              ? true
                                              : selectedVisible > 0
                                              ? null
                                              : false,
                                          onChanged: (_) => setState(() {
                                            if (allSelected) {
                                              for (final item in visible) {
                                                _selected.remove(item.id);
                                              }
                                            } else {
                                              for (final item in visible) {
                                                _selected[item.id] = item;
                                              }
                                            }
                                          }),
                                        );
                                      },
                                    ),
                                    Expanded(
                                      child: Text(
                                        'Select all (${visible.length})',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: NseapColors.primaryActive,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (_selectionMode) ...[
                            const SizedBox(width: 8),
                            Text(
                              '${_selected.length} selected',
                              style: const TextStyle(
                                color: NseapColors.primaryActive,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              const Divider(
                height: 1,
                thickness: 1,
                color: AppColors.borderLight,
              ),
              const SizedBox(height: 10),
              Expanded(
                child: visible.isEmpty
                    ? const AdminStatePanel.empty(
                        title: 'No scholars found',
                        message: 'Try changing the search or status filter.',
                      )
                    : AdminResponsiveCollection<ScholarRecord>(
                        items: visible,
                        isSelected: _selectionMode
                            ? (item) => _selected.containsKey(item.id)
                            : null,
                        onSelectionChanged: _selectionMode ? _select : null,
                        columns: const [
                          DataColumn(label: Text('#')),
                          DataColumn(label: Text('Scholar')),
                          DataColumn(label: Text('Scholar ID')),
                          DataColumn(label: Text('Date Applied')),
                          DataColumn(label: Text('Date Accepted')),
                          DataColumn(label: Text('Academic Year')),
                          DataColumn(label: Text('Semester')),
                          DataColumn(label: Text('Status')),
                          DataColumn(label: Text('Submission')),
                          DataColumn(label: Text('Action')),
                        ],
                        cells: (item) => [
                          DataCell(Text('${visible.indexOf(item) + 1}')),
                          DataCell(Text(_safeText(item.name), softWrap: false)),
                          DataCell(Text(_safeText(item.scholarId))),
                          DataCell(Text(adminDateLabel(item.appliedAt))),
                          DataCell(Text(adminDateLabel(item.acceptedAt))),
                          DataCell(
                            Text(
                              _safeText(
                                item.academicYearFor(
                                  submissionByUser[item.userId],
                                ),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DataCell(
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 120),
                              child: Text(
                                _safeText(
                                  item.semesterFor(
                                    submissionByUser[item.userId],
                                  ),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          DataCell(AdminStatusChip(item.status)),
                          DataCell(
                            AdminStatusChip(
                              _normalizeSubmissionForDisplay(
                                submissionByUser[item.userId]?.status,
                              ),
                            ),
                          ),
                          DataCell(
                            PopupMenuButton<String>(
                              tooltip: 'More actions',
                              icon: const Icon(
                                Icons.more_vert_rounded,
                                size: 20,
                              ),
                              onSelected: (value) {
                                if (value == 'view') {
                                  _openSubmission(
                                    item,
                                    submissionByUser[item.userId],
                                  );
                                } else if (value == 'edit') {
                                  _update(
                                    item,
                                    submissionByUser[item.userId]?.status,
                                  );
                                }
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: 'view',
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.visibility_outlined,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        submissionByUser[item.userId] != null
                                            ? 'View submission'
                                            : 'View record',
                                      ),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit_outlined, size: 18),
                                      SizedBox(width: 8),
                                      Text('Update status'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        cardBuilder: (_, item) => Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 560),
                            child: AdminRecordCard(
                              title: _safeText(item.name),
                              subtitle: _safeText(item.scholarId),
                              status: item.status,
                              fields: {
                                'No.': '${visible.indexOf(item) + 1}',
                                'Date Applied': adminDateLabel(item.appliedAt),
                                'Date Accepted': adminDateLabel(
                                  item.acceptedAt,
                                ),
                                'Barangay': _safeText(item.barangay),
                                'Academic Year': item.academicYearFor(
                                  submissionByUser[item.userId],
                                ),
                                'Semester': item.semesterFor(
                                  submissionByUser[item.userId],
                                ),
                                'Submission': adminLabel(
                                  _normalizeSubmissionForDisplay(
                                    submissionByUser[item.userId]?.status,
                                  ),
                                ),
                              },
                              actions: [
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: PopupMenuButton<String>(
                                    tooltip: 'More actions',
                                    icon: const Icon(Icons.more_vert_rounded),
                                    onSelected: (value) {
                                      if (value == 'view') {
                                        _openSubmission(
                                          item,
                                          submissionByUser[item.userId],
                                        );
                                      } else if (value == 'edit') {
                                        _update(
                                          item,
                                          submissionByUser[item.userId]?.status,
                                        );
                                      }
                                    },
                                    itemBuilder: (_) => [
                                      PopupMenuItem(
                                        value: 'view',
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.visibility_outlined,
                                              size: 18,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              submissionByUser[item.userId] !=
                                                      null
                                                  ? 'View submission'
                                                  : 'View record',
                                            ),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Row(
                                          children: [
                                            Icon(Icons.edit_outlined, size: 18),
                                            SizedBox(width: 8),
                                            Text('Update status'),
                                          ],
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
            ],
          );
        },
      );
}

class _ScholarSubmissionPage extends StatefulWidget {
  const _ScholarSubmissionPage({
    required this.repository,
    required this.scholar,
    required this.submission,
  });

  final AdminRepository repository;
  final ScholarRecord scholar;
  final SemesterSubmission? submission;

  @override
  State<_ScholarSubmissionPage> createState() => _ScholarSubmissionPageState();
}

class _ScholarSubmissionPageState extends State<_ScholarSubmissionPage>
    with RealtimeSyncMixin {
  @override
  Set<String> get realtimeTables => const {
    'users',
    'scholarship_applications',
    'scholar_profiles',
    'semester_submissions',
    'scholarship_documents',
  };
  @override
  Future<void> refreshRealtime() async {
    _reload();
    await _future;
  }

  late Future<(ApplicantDetail, List<AdminDocument>, SemesterSubmission?)>
  _future = _load();

  Future<(ApplicantDetail, List<AdminDocument>, SemesterSubmission?)>
  _load() async {
    final submission = widget.submission == null
        ? null
        : await widget.repository.getSemesterSubmission(widget.submission!.id);
    final applicationId =
        submission?.applicationId ?? widget.scholar.applicationId;
    if (applicationId == null || applicationId.isEmpty) {
      throw Exception('No application is linked to this scholar.');
    }
    final application = await widget.repository.getApplication(applicationId);
    final detail = await widget.repository.getApplicantDetail(application);
    if (submission == null) {
      return (detail, <AdminDocument>[], null);
    }
    final documents = await widget.repository.getSemesterSubmissionDocuments(
      submission.id,
    );
    return (detail, documents, submission);
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  String _barangayFromAddress(String address) {
    if (address.trim().isEmpty) return 'Not recorded';
    final parts = address.split(',');
    final first = parts.first.trim();
    return first.isEmpty ? 'Not recorded' : first;
  }

  Future<void> _reviewSubmission(
    String status,
    SemesterSubmission submission,
  ) async {
    if (!submission.canReview) {
      showAdminMessage(
        context,
        submission.reviewUnavailableMessage,
        error: true,
      );
      return;
    }
    if (status == 'needs_revision') {
      final note = await showAdminTextDialog(
        context,
        title: 'Request revision',
        label: 'Revision notes for scholar (required)',
        required: true,
      );
      if (note == null || note.trim().isEmpty) {
        if (note != null && mounted) {
          showAdminMessage(
            context,
            'Revision notes are required.',
            error: true,
          );
        }
        return;
      }
      if (!mounted) return;
      await runAdminAction(
        context,
        () => widget.repository.reviewSemesterSubmission(
          submission.id,
          status,
          note: note,
        ),
        'Revision notes sent to scholar.',
        () {
          if (mounted) Navigator.pop(context);
        },
      );
      if (mounted) _reload();
    } else {
      final confirmed = await confirmAdminAction(
        context,
        title: 'Approve submission?',
        message:
            'Approve ${widget.scholar.name}\u2019s ${submission.academicYear} ${submission.semester} submission?',
        confirmLabel: 'Approve',
      );
      if (!confirmed) return;
      if (!mounted) return;
      await runAdminAction(
        context,
        () => widget.repository.reviewSemesterSubmission(submission.id, status),
        'Submission approved.',
        () {
          if (mounted) Navigator.pop(context);
        },
      );
      if (mounted) _reload();
    }
  }

  void _openDocument(AdminDocument document) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ScholarDocumentPreviewPage(
          document: document,
          download: widget.repository.downloadDocument(document.storagePath),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final submission = widget.submission;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: NseapColors.primary,
        foregroundColor: Colors.white,
        title: Text(
          submission == null ? 'Scholar Record' : 'Scholar Submission',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<(ApplicantDetail, List<AdminDocument>, SemesterSubmission?)>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AdminStatePanel.error(
              message: readableAdminError(snapshot.error),
              onRetry: _reload,
            );
          }
          if (snapshot.connectionState != ConnectionState.done ||
              !snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          final detail = snapshot.requireData.$1;
          final documents = snapshot.requireData.$2;
          final submission = snapshot.requireData.$3;
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Card(
                  elevation: 2,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: NseapColors.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.scholar.name,
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                submission == null
                                    ? '${widget.scholar.scholarId} | Scholar Record'
                                    : '${widget.scholar.scholarId} | '
                                          '${submission.academicYear} | '
                                          '${submission.semester}',
                                style: const TextStyle(
                                  color: AppColors.primaryContainer,
                                ),
                              ),
                              const SizedBox(height: 12),
                              AdminStatusChip(
                                submission?.status ?? widget.scholar.status,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        _ScholarSubmissionSection(
                          title: 'Scholar Record',
                          icon: Icons.school_outlined,
                          child: _ScholarSubmissionInfo(
                            values: {
                              'Scholar ID': widget.scholar.scholarId,
                              'Scholar Status': adminLabel(
                                widget.scholar.status,
                              ),
                              'Date Applied': adminDateLabel(
                                widget.scholar.appliedAt,
                                withTime: true,
                              ),
                              'Date Accepted': adminDateLabel(
                                widget.scholar.acceptedAt,
                                withTime: true,
                              ),
                              'Barangay': widget.scholar.barangay,
                              'Email': detail.application.email,
                            },
                          ),
                        ),
                        _ScholarSubmissionSection(
                          title: 'Personal Information',
                          icon: Icons.person_outline,
                          child: _ScholarSubmissionInfo(
                            values: {
                              'Full Name': detail.application.name,
                              'Date of Birth': adminDateLabel(
                                detail.dateOfBirth,
                              ),
                              'Sex': detail.sex,
                              'Contact Number': detail.contactNumber,
                              'Email Address': detail.application.email,
                              'Complete Address': detail.address,
                              'Barangay': _barangayFromAddress(detail.address),
                            },
                          ),
                        ),
                        _ScholarSubmissionSection(
                          title: 'Educational Information',
                          icon: Icons.school_outlined,
                          child: _ScholarSubmissionInfo(
                            values: {
                              'School': detail.application.school,
                              'Course / Program': detail.application.course,
                              'Year Level': detail.yearLevel,
                              'Student ID Number': detail.studentIdNumber,
                            },
                          ),
                        ),
                        _ScholarSubmissionSection(
                          title: 'Parent/Guardian Information',
                          icon: Icons.family_restroom_outlined,
                          child: _ScholarSubmissionInfo(
                            values: {
                              'Father Name': detail.fatherName,
                              'Father Occupation': detail.fatherOccupation,
                              'Father Income Range': detail.fatherIncomeRange,
                              'Mother Name': detail.motherName,
                              'Mother Occupation': detail.motherOccupation,
                              'Mother Income Range': detail.motherIncomeRange,
                              'Household Monthly Income':
                                  detail.householdIncome,
                              'Household Members': detail.householdMembers,
                            },
                          ),
                        ),
                        _ScholarSubmissionSection(
                          title: 'Scholarship Application Information',
                          icon: Icons.assignment_outlined,
                          child: _ScholarSubmissionInfo(
                            values: {
                              'Application ID': detail.application.number,
                              'Date Submitted': adminDateLabel(
                                detail.application.submittedAt,
                                withTime: true,
                              ),
                              'Current Status': adminLabel(
                                detail.application.status,
                              ),
                              'Interview Schedule': adminDateLabel(
                                detail.interviewAt,
                                withTime: true,
                              ),
                              'Interview Status': adminLabel(
                                detail.interviewStatus ?? 'not_scheduled',
                              ),
                              'Application Remarks': detail.remarks,
                            },
                          ),
                        ),
                        if (submission != null)
                          _ScholarSubmissionSection(
                            title: 'Semester Submission',
                            icon: Icons.calendar_month_outlined,
                            child: _ScholarSubmissionInfo(
                              values: {
                                'Academic Year': submission.academicYear,
                                'Semester': submission.semester,
                                'Submitted': adminDateLabel(
                                  submission.submittedAt,
                                  withTime: true,
                                ),
                                'Review Status':
                                    submission.status == 'cancelled'
                                    ? 'Cancelled Submission'
                                    : adminLabel(submission.status),
                                'Submission ID': submission.id,
                              },
                            ),
                          ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: RequirementDownloadButton(
                            documents: [...detail.documents, ...documents],
                            download: widget.repository.downloadDocument,
                            archiveName: submission == null
                                ? '${widget.scholar.scholarId}-requirements'
                                : '${widget.scholar.scholarId}-${submission.academicYear}-${submission.semester}-requirements',
                          ),
                        ),
                        _ScholarSubmissionSection(
                          title:
                              'Application Requirements (${detail.documents.length})',
                          icon: Icons.folder_copy_outlined,
                          child: detail.documents.isEmpty
                              ? const AdminStatePanel.empty(
                                  title: 'No requirements found',
                                  message:
                                      'No application requirements were uploaded.',
                                )
                              : AdminRequirementsList(
                                  documents: detail.documents,
                                  download: widget.repository.downloadDocument,
                                  onPreview: _openDocument,
                                  showStatus: true,
                                ),
                        ),
                        _ScholarSubmissionSection(
                          title: 'Semester Documents (${documents.length})',
                          icon: Icons.folder_copy_outlined,
                          child: submission == null
                              ? const AdminStatePanel.empty(
                                  title: 'No semester submission',
                                  message:
                                      'This scholar has not submitted for the selected period yet.',
                                )
                              : documents.isEmpty
                              ? const AdminStatePanel.empty(
                                  title: 'No documents found',
                                  message:
                                      'No files are linked to this semester submission.',
                                )
                              : AdminRequirementsList(
                                  documents: documents,
                                  download: widget.repository.downloadDocument,
                                  onPreview: _openDocument,
                                  showStatus: true,
                                ),
                        ),
                        if (submission != null && submission.canReview)
                          _ScholarSubmissionSection(
                            title: 'Review Submission',
                            icon: Icons.rate_review_outlined,
                            child: Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                FilledButton.icon(
                                  onPressed: () =>
                                      _reviewSubmission('approved', submission),
                                  icon: const Icon(
                                    Icons.verified_rounded,
                                    size: 18,
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.success,
                                  ),
                                  label: const Text('Approved'),
                                ),
                                FilledButton.icon(
                                  onPressed: () => _reviewSubmission(
                                    'needs_revision',
                                    submission,
                                  ),
                                  icon: const Icon(
                                    Icons.edit_note_rounded,
                                    size: 18,
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFFD97706),
                                  ),
                                  label: const Text('Need Revision'),
                                ),
                              ],
                            ),
                          )
                        else if (submission != null)
                          _ScholarSubmissionSection(
                            title: 'Review Submission',
                            icon: Icons.rate_review_outlined,
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.divider),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    submission.status == 'cancelled'
                                        ? Icons.cancel_outlined
                                        : submission.status == 'verified' ||
                                              submission.status == 'approved'
                                        ? Icons.verified_rounded
                                        : Icons.edit_note_rounded,
                                    color:
                                        submission.status == 'verified' ||
                                            submission.status == 'approved'
                                        ? AppColors.success
                                        : const Color(0xFFD97706),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      submission.reviewUnavailableMessage,
                                      style: const TextStyle(
                                        color: AppColors.grey600,
                                        fontSize: 13,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                  AdminStatusChip(
                                    submission.status == 'cancelled'
                                        ? 'cancelled_submission'
                                        : submission.status,
                                  ),
                                ],
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
        },
      ),
    );
  }
}

class _ScholarSubmissionSection extends StatelessWidget {
  const _ScholarSubmissionSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 14),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: NseapColors.primary),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 28),
          child,
        ],
      ),
    ),
  );
}

class _ScholarSubmissionInfo extends StatelessWidget {
  const _ScholarSubmissionInfo({required this.values});

  final Map<String, String> values;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const spacing = 16.0;
      final wide = constraints.maxWidth >= 620;
      final width = wide
          ? (constraints.maxWidth - spacing) / 2
          : constraints.maxWidth;
      return Wrap(
        spacing: spacing,
        runSpacing: 14,
        children: [
          for (final entry in values.entries)
            SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.key,
                    style: const TextStyle(
                      color: NseapColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    entry.value,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}

class _ScholarDocumentPreviewPage extends StatelessWidget {
  const _ScholarDocumentPreviewPage({
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: NseapColors.primary,
      foregroundColor: Colors.white,
      title: Text(document.fileName),
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
              child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
            ),
          );
        }
        return AdminStatePanel.error(
          message: 'This document format cannot be previewed.',
          onRetry: () => Navigator.pop(context),
        );
      },
    ),
  );
}

class _ScholarStatusStats extends StatelessWidget {
  const _ScholarStatusStats({
    required this.total,
    required this.pending,
    required this.approved,
    required this.terminated,
    required this.graduated,
    required this.selectedView,
    required this.onSelected,
  });

  final int total;
  final int pending;
  final int approved;
  final int terminated;
  final int graduated;
  final String selectedView;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final values = [
      (
        'Total Scholars',
        total,
        Icons.groups_outlined,
        AppColors.primary,
        'all',
      ),
      (
        'Pending Submission',
        pending,
        Icons.pending_actions_outlined,
        AppColors.goldDark,
        'pending',
      ),
      (
        'Approved Submission',
        approved,
        Icons.verified_outlined,
        const Color(0xFF16835D),
        'approved',
      ),
      (
        'Terminated',
        terminated,
        Icons.block_outlined,
        AppColors.error,
        'terminated',
      ),
      (
        'Graduated',
        graduated,
        Icons.school_outlined,
        const Color(0xFF165EF0),
        'graduated',
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 10.0;
        final width =
            ((constraints.maxWidth - spacing * (values.length - 1)) /
                    values.length)
                .clamp(160.0, 280.0);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var index = 0; index < values.length; index++) ...[
                SizedBox(
                  width: width,
                  child: Material(
                    color: selectedView == values[index].$5
                        ? values[index].$4.withValues(alpha: 0.08)
                        : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: values[index].$4.withValues(
                          alpha: selectedView == values[index].$5 ? 0.9 : 0.32,
                        ),
                        width: selectedView == values[index].$5 ? 2 : 1,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => onSelected(values[index].$5),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: values[index].$4.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                values[index].$3,
                                color: values[index].$4,
                                size: 21,
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${values[index].$2}',
                                    style: TextStyle(
                                      color: values[index].$4,
                                      fontSize: 21,
                                      height: 1,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    values[index].$1,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: NseapColors.textSecondary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
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
                if (index < values.length - 1) const SizedBox(width: spacing),
              ],
            ],
          ),
        );
      },
    );
  }
}
