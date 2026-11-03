import 'package:flutter/material.dart';
import 'package:nseapscholarship/services/realtime_sync.dart';
import 'package:nseapscholarship/admin/widgets/dashboard/dashboard_export.dart';
import 'package:nseapscholarship/admin/widgets/dashboard/nseap_bar_growth_chart.dart';
import 'package:nseapscholarship/admin/widgets/dashboard/nseap_progress_bar.dart';
import 'package:nseapscholarship/admin/widgets/dashboard/nseap_statistic_card.dart';
import 'package:nseapscholarship/admin/widgets/dashboard/nseap_table_card.dart';
import 'package:nseapscholarship/theme/nseap_theme.dart';

import '../../admin_navigation.dart';
import '../../data/admin_repository.dart';
import '../../models/admin_models.dart';
import '../../widgets/admin_widgets.dart';
import '../../../utils/academic_year.dart';

/// Modern responsive Admin Dashboard UI — NSEAP Scholarship Portal
/// Academic Year + Semester filters now actually filter all metrics.
class DashboardAdminPage extends StatefulWidget {
  const DashboardAdminPage({
    required this.repository,
    required this.onNavigate,
    super.key,
  });

  final AdminRepository repository;
  final ValueChanged<AdminSection> onNavigate;

  @override
  State<DashboardAdminPage> createState() => _DashboardAdminPageState();
}

List<String> get _academicYears => AcademicYearUtils.generateAcademicYears();
const _allAcademicYear = 'All';

enum GrowthRange { h24, d7, m30 }

extension GrowthRangeLabel on GrowthRange {
  String get label => switch (this) {
    GrowthRange.h24 => 'Last 24 hours',
    GrowthRange.d7 => 'Last 7 days',
    GrowthRange.m30 => 'Last 1 month',
  };
}

class _DashboardAdminPageState extends State<DashboardAdminPage>
    with RealtimeSyncMixin {
  @override
  Set<String> get realtimeTables => const {
    'users',
    'scholarship_applications',
    'scholar_profiles',
    'semester_submissions',
    'semester_periods',
    'interview_schedules',
    'scholarship_documents',
    'announcements',
    'notifications',
  };
  @override
  Future<void> refreshRealtime() async {
    _reload();
    await _future;
  }

  late Future<DashboardOverview> _future = widget.repository
      .getDashboardOverview();
  String _year = _allAcademicYear;
  String _semester = '1st Semester';
  GrowthRange _growthRange = GrowthRange.d7;
  bool _exporting = false;

  int _yearStart(String year) => AcademicYearUtils.parseStartYear(year);

  void _reload() {
    setState(() {
      _future = widget.repository.getDashboardOverview();
    });
  }

  // Delegates to centralized helper — June {start} – April {start+1}
  bool _inAcademicYear(DateTime? dt, String year) =>
      AcademicYearUtils.isInAcademicYear(dt, year);

  bool _inAcademicSemester(DateTime? dt, String year, String semester) =>
      AcademicYearUtils.isInAcademicSemester(dt, year, semester);

  // Kept for backward compat where only year check is needed (e.g., chips)
  bool _inYear(DateTime? dt, String year) => _inAcademicYear(dt, year);

  bool _inSemester(DateTime? dt, String year, String semester) =>
      _inAcademicSemester(dt, year, semester);

  bool _matchesFilters(DateTime? dt) =>
      _inAcademicSemester(dt, _year, _semester);

  // Dummy chart per year/semester — June-Oct (1st, 5 months) / Nov-Apr (2nd, 6 months)
  List<int> _dummyChart(String year, String semester) {
    if (year.toLowerCase() == 'all') {
      // Aggregate all years for "All" view
      final all = <int>[];
      for (final y in _academicYears) {
        final c = _dummyChart(y, semester);
        if (all.isEmpty) {
          all.addAll(c);
        } else {
          for (var i = 0; i < all.length && i < c.length; i++) {
            all[i] += c[i];
          }
        }
      }
      return all;
    }
    final isFirst = semester == '1st Semester';
    final offset = _yearStart(year) - 2026;
    final base = offset <= 0
        ? (isFirst
              ? const [1120, 1480, 1820, 2100, 2380] // Jun-Oct (5)
              : const [1380, 1620, 1750, 1880, 2050, 2220]) // Nov-Apr (6)
        : (isFirst
              ? const [1120, 1480, 1820, 2100, 2380]
              : const [1380, 1620, 1750, 1880, 2050, 2220]);
    if (offset <= 0) return base;
    return base.map((v) => v + offset * 160).toList();
  }

  List<String> _chartLabels(String semester) => semester == '1st Semester'
      ? const ['Jun', 'Jul', 'Aug', 'Sep', 'Oct']
      : const ['Nov', 'Dec', 'Jan', 'Feb', 'Mar', 'Apr'];

  // ── New growth (W1-W4) — respects Academic Year/Semester + growth window
  bool _inGrowthWindow(DateTime? dt, GrowthRange r) {
    if (dt == null) return false;
    final now = DateTime.now();
    final diff = now.difference(dt);
    return switch (r) {
      GrowthRange.h24 => diff.inHours < 24 && !diff.isNegative,
      GrowthRange.d7 => diff.inDays < 7 && !diff.isNegative,
      GrowthRange.m30 => diff.inDays < 30 && !diff.isNegative,
    };
  }

  List<String> _growthLabels(GrowthRange r) => switch (r) {
    GrowthRange.h24 => const [
      '00:00',
      '04:00',
      '08:00',
      '12:00',
      '16:00',
      '20:00',
    ],
    GrowthRange.d7 => const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
    GrowthRange.m30 => const ['W1', 'W2', 'W3', 'W4'],
  };

  List<int> _dummyAppGrowth(GrowthRange r, String year, String semester) {
    if (year.toLowerCase() == 'all') {
      final all = <int>[];
      for (final y in _academicYears) {
        final c = _dummyAppGrowth(r, y, semester);
        if (all.isEmpty) {
          all.addAll(c);
        } else {
          for (var i = 0; i < all.length && i < c.length; i++) {
            all[i] += c[i];
          }
        }
      }
      return all;
    }
    final off = _yearStart(year) - 2026;
    final semFactor = semester == '2nd Semester' ? 0.86 : 1.0;
    List<int> base;
    switch (r) {
      case GrowthRange.h24:
        base = const [3, 5, 8, 6, 9, 12];
        break;
      case GrowthRange.d7:
        base = const [12, 18, 22, 16, 25, 30, 28];
        break;
      case GrowthRange.m30:
        base = const [45, 58, 62, 70];
        break;
    }
    return base
        .map((v) => ((v + off * 4) * semFactor).round().clamp(0, 9999))
        .toList();
  }

  List<int> _dummyScholarGrowth(GrowthRange r, String year, String semester) {
    // Scholar slightly lower than applicant
    return _dummyAppGrowth(
      r,
      year,
      semester,
    ).map((v) => (v * 0.62).round()).toList();
  }

  List<int> _appGrowthForRange(
    List<AdminApplication> apps,
    GrowthRange r,
    bool hasLive,
    String year,
    String semester,
  ) {
    if (!hasLive) {
      // No dummy — show empty chart when no live data.
      return switch (r) {
        GrowthRange.h24 => List.filled(6, 0),
        GrowthRange.d7 => List.filled(7, 0),
        GrowthRange.m30 => List.filled(4, 0),
      };
    }
    final now = DateTime.now();
    List<int> buckets;
    switch (r) {
      case GrowthRange.h24:
        buckets = List.filled(6, 0);
        for (final a in apps) {
          final dt = a.submittedAt;
          if (dt == null || !_matchesFilters(dt)) continue;
          final diffH = now.difference(dt).inHours;
          if (diffH < 0 || diffH >= 24) continue;
          final idx = (diffH ~/ 4).clamp(
            0,
            5,
          ); // 0:0-4h ago etc, reverse for chronological
          // We want oldest left, newest right: diff 20-24h -> idx 5 -> should be leftmost (0)
          // So invert: idx = 5 - (diffH ~/4)
          final inv = 5 - idx;
          buckets[inv]++;
        }
        break;
      case GrowthRange.d7:
        buckets = List.filled(7, 0);
        for (final a in apps) {
          final dt = a.submittedAt;
          if (dt == null || !_matchesFilters(dt)) continue;
          final diffD = now
              .difference(DateTime(dt.year, dt.month, dt.day))
              .inDays;
          if (diffD < 0 || diffD >= 7) continue;
          final inv = 6 - diffD;
          buckets[inv]++;
        }
        break;
      case GrowthRange.m30:
        buckets = List.filled(4, 0);
        for (final a in apps) {
          final dt = a.submittedAt;
          if (dt == null || !_matchesFilters(dt)) continue;
          final diffD = now.difference(dt).inDays;
          if (diffD < 0 || diffD >= 30) continue;
          final week = (diffD ~/ 7).clamp(0, 3); // 0 = 0-7d ago (most recent)
          final inv = 3 - week; // oldest W1 left
          buckets[inv]++;
        }
        break;
    }
    // If all zero (no recent), fall back to dummy scaled down to avoid empty chart
    if (buckets.every((v) => v == 0)) {
      // keep zeros but ensure at least one dummy hint? No, show zeros with empty state handled by chart
    }
    return buckets;
  }

  List<int> _scholarGrowthForRange(
    List<ScholarRecord> scholars,
    List<AdminApplication> apps,
    DashboardOverview? data,
    GrowthRange r,
    bool hasLive,
    String year,
    String semester,
  ) {
    if (!hasLive || scholars.isEmpty) {
      return switch (r) {
        GrowthRange.h24 => List.filled(6, 0),
        GrowthRange.d7 => List.filled(7, 0),
        GrowthRange.m30 => List.filled(4, 0),
      };
    }
    // Use scholar startedAt filtered by year/semester + window
    // If startedAt is null for many, fallback to application scholar date
    final now = DateTime.now();
    List<int> buckets;
    switch (r) {
      case GrowthRange.h24:
        buckets = List.filled(6, 0);
        for (final s in scholars) {
          final dt = s.startedAt;
          if (dt == null ||
              !_inYear(dt, year) ||
              !_inSemester(dt, year, semester)) {
            continue;
          }
          final diffH = now.difference(dt).inHours;
          if (diffH < 0 || diffH >= 24) continue;
          final inv = 5 - (diffH ~/ 4).clamp(0, 5);
          buckets[inv]++;
        }
        break;
      case GrowthRange.d7:
        buckets = List.filled(7, 0);
        for (final s in scholars) {
          final dt = s.startedAt;
          if (dt == null ||
              !_inYear(dt, year) ||
              !_inSemester(dt, year, semester)) {
            continue;
          }
          final diffD = now
              .difference(DateTime(dt.year, dt.month, dt.day))
              .inDays;
          if (diffD < 0 || diffD >= 7) continue;
          final inv = 6 - diffD;
          buckets[inv]++;
        }
        break;
      case GrowthRange.m30:
        buckets = List.filled(4, 0);
        for (final s in scholars) {
          final dt = s.startedAt;
          if (dt == null ||
              !_inYear(dt, year) ||
              !_inSemester(dt, year, semester)) {
            continue;
          }
          final diffD = now.difference(dt).inDays;
          if (diffD < 0 || diffD >= 30) continue;
          final inv = 3 - (diffD ~/ 7).clamp(0, 3);
          buckets[inv]++;
        }
        break;
    }
    return buckets;
  }

  // Right-side stats for growth cards (Approved/Rejected, Submitted/NotSubmitted) within selected year/semester + window
  ({int approved, int rejected}) _approvedRejectedForWindow(
    List<AdminApplication> apps,
    GrowthRange r,
    String year,
    String semester,
  ) {
    final inWindow = apps.where(
      (a) =>
          _matchesFilters(a.submittedAt) && _inGrowthWindow(a.submittedAt, r),
    );
    final approved = inWindow.where((a) => a.status == 'scholar').length;
    final rejected = inWindow.where((a) => a.status == 'rejected').length;
    return (approved: approved, rejected: rejected);
  }

  ({int submitted, int notSubmitted}) _submittedNotSubmittedForWindow(
    List<ScholarRecord> scholars,
    List<SemesterSubmission> submissions,
    GrowthRange r,
    String year,
    String semester,
  ) {
    final isAll = year.toLowerCase() == 'all';
    final filteredSubs = submissions.where(
      (s) =>
          (isAll || s.academicYear == year) &&
          s.semester == semester &&
          _inGrowthWindow(s.submittedAt, r),
    );
    final byUser = <String, SemesterSubmission>{};
    for (final s in filteredSubs) {
      final cur = byUser[s.userId];
      if (cur == null ||
          (s.submittedAt != null &&
              cur.submittedAt != null &&
              s.submittedAt!.isAfter(cur.submittedAt!))) {
        byUser[s.userId] = s;
      } else if (cur == null) {
        byUser[s.userId] = s;
      }
    }
    final submittedUsers = byUser.keys.toSet();
    final scholarsInYearSem = scholars
        .where(
          (s) =>
              _inYear(s.startedAt, year) &&
              _inSemester(s.startedAt, year, semester),
        )
        .toList();
    final submitted = scholarsInYearSem
        .where((s) => submittedUsers.contains(s.userId))
        .length;
    final notSubmitted = (scholarsInYearSem.length - submitted).clamp(
      0,
      scholarsInYearSem.length,
    );
    return (submitted: submitted, notSubmitted: notSubmitted);
  }

  // Analytics demo per filter — scales onwards from 2026-2027.
  List<NseapProgressBarItem> _schoolsFor(String year, String semester) {
    if (year.toLowerCase() == 'all') {
      final all = <String, NseapProgressBarItem>{};
      for (final y in _academicYears) {
        for (final item in _schoolsFor(y, semester)) {
          final prev = all[item.label];
          if (prev == null) {
            all[item.label] = item;
          } else {
            all[item.label] = NseapProgressBarItem(
              label: item.label,
              value: prev.value + item.value,
              fraction: (prev.fraction + item.fraction) / 2,
              valueLabel: '${prev.value + item.value}',
            );
          }
        }
      }
      final list = all.values.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final maxV = list.isEmpty ? 1 : list.first.value;
      return list
          .take(4)
          .map(
            (e) => NseapProgressBarItem(
              label: e.label,
              value: e.value,
              fraction: e.value / maxV,
              valueLabel: '${e.value}',
            ),
          )
          .toList();
    }
    return <NseapProgressBarItem>[];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF5F6FA),
      child: FutureBuilder<DashboardOverview>(
        future: _future,
        builder: (context, snapshot) {
          final data = snapshot.data;
          final filteredApps = data == null
              ? <AdminApplication>[]
              : data.applications
                    .where((a) => _matchesFilters(a.submittedAt))
                    .toList();
          final filteredScholars = data == null
              ? <ScholarRecord>[]
              : data.scholars
                    .where((s) => _matchesFilters(s.startedAt))
                    .toList();

          // Live vs demo counts -- when live data exists use filtered lists,
          // otherwise show zeros (no dummy data).
          final hasLive =
              data != null &&
              (data.applications.isNotEmpty || data.scholars.isNotEmpty);

          final appGrowth = _appGrowthForRange(
            filteredApps,
            _growthRange,
            hasLive,
            _year,
            _semester,
          );
          final growthLabels = _growthLabels(_growthRange);

          final recentApps = hasLive
              ? filteredApps
                    .take(5)
                    .map(
                      (a) => RecentApplicationRow(
                        name: a.name.isEmpty ? 'Applicant ${a.number}' : a.name,
                        date: adminDateLabel(a.submittedAt),
                        status: a.status,
                      ),
                    )
                    .toList()
              : <RecentApplicationRow>[];

          final recentScholars = hasLive
              ? filteredScholars
                    .take(5)
                    .map(
                      (s) => RecentScholarRow(
                        name: s.name,
                        program: 'BSIT',
                        yearLevel: '3rd Year',
                        status: s.status,
                      ),
                    )
                    .toList()
              : <RecentScholarRow>[];

          return SingleChildScrollView(
            padding: EdgeInsets.zero,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1440),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 1100;
                      final isTablet = constraints.maxWidth >= 720;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _DashboardHeader(
                            year: _year,
                            semester: _semester,
                            onYearChanged: (v) =>
                                setState(() => _year = v ?? _year),
                            onSemesterChanged: (v) =>
                                setState(() => _semester = v ?? _semester),
                            onRefresh: _reload,
                          ),
                          if (snapshot.hasError) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Color(0xFFFECACA)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.warning_amber_rounded,
                                    size: 18,
                                    color: Color(0xFFDC2626),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Live data unavailable — showing demo metrics for $_year $_semester. ${readableAdminError(snapshot.error)}',
                                      style: const TextStyle(
                                        color: Color(0xFF991B1B),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: _reload,
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          // Filter badge
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            children: [
                              Chip(
                                label: Text(_year),
                                backgroundColor: const Color(0xFFEFF6FF),
                                side: const BorderSide(
                                  color: Color(0xFFDBEAFE),
                                ),
                                labelStyle: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Chip(
                                label: Text(_semester),
                                backgroundColor: const Color(0xFFF8FAFC),
                                side: const BorderSide(
                                  color: Color(0xFFE2E8F0),
                                ),
                                labelStyle: const TextStyle(
                                  color: Color(0xFF334155),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (hasLive)
                                Chip(
                                  label: Text('${filteredApps.length} records'),
                                  backgroundColor: const Color(0xFFECFDF5),
                                  side: const BorderSide(
                                    color: Color(0xFFA7F3D0),
                                  ),
                                  labelStyle: const TextStyle(
                                    color: Color(0xFF065F46),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          _StatsGrid(
                            onNavigate: widget.onNavigate,
                            liveData: data,
                            year: _year,
                            semester: _semester,
                            filteredApps: filteredApps,
                            filteredScholars: filteredScholars,
                          ),
                          const SizedBox(height: 18),
                          _GrowthSectionHeader(
                            range: _growthRange,
                            onChanged: (v) => setState(
                              () => _growthRange = v ?? _growthRange,
                            ),
                          ),
                          const SizedBox(height: 12),
                          LayoutBuilder(
                            builder: (context, c) {
                              return NseapBarGrowthCard(
                                title: '',
                                subtitle: '',
                                values: appGrowth,
                                labels: growthLabels,
                                barColor: AppColors.primary,
                                rightStats: const [],
                              );
                            },
                          ),
                          const SizedBox(height: 18),
                          LayoutBuilder(
                            builder: (context, c) {
                              final cols = isWide
                                  ? 3
                                  : isTablet
                                  ? 2
                                  : 1;
                              final schools = hasLive
                                  ? _schoolsFromLive(filteredApps)
                                  : <NseapProgressBarItem>[];
                              final programs = hasLive
                                  ? _programsFromLive(filteredApps)
                                  : <NseapProgressBarItem>[];
                              final barangays = hasLive
                                  ? _barangaysFromLive(filteredApps)
                                  : <NseapProgressBarItem>[];
                              final children = [
                                NseapAnalyticsCard(
                                  title: 'Top Schools',
                                  subtitle: 'By application volume · $_year',
                                  icon: Icons.school_outlined,
                                  items: schools,
                                ),
                                NseapAnalyticsCard(
                                  title: 'Top Program',
                                  subtitle: 'Top programs · $_semester',
                                  icon: Icons.menu_book_outlined,
                                  items: programs,
                                ),
                                NseapAnalyticsCard(
                                  title: 'Top Barangay',
                                  subtitle: 'Applicants by barangay · $_year',
                                  icon: Icons.location_on_outlined,
                                  items: barangays,
                                ),
                              ];
                              if (cols == 3) {
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (
                                      var i = 0;
                                      i < children.length;
                                      i++
                                    ) ...[
                                      Expanded(child: children[i]),
                                      if (i < 2) const SizedBox(width: 14),
                                    ],
                                  ],
                                );
                              }
                              if (cols == 2) {
                                return Column(
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(child: children[0]),
                                        const SizedBox(width: 14),
                                        Expanded(child: children[1]),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    children[2],
                                  ],
                                );
                              }
                              return Column(
                                children: [
                                  for (var i = 0; i < children.length; i++) ...[
                                    children[i],
                                    if (i < children.length - 1)
                                      const SizedBox(height: 14),
                                  ],
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 18),
                          LayoutBuilder(
                            builder: (context, c) {
                              final sideBySide = c.maxWidth >= 900;
                              final appsCard = NseapTableCard(
                                title: 'Recent Applications',
                                subtitle:
                                    '$_year · $_semester · ${recentApps.length} records',
                                columns: const [
                                  DataColumn(label: Text('Applicant Name')),
                                  DataColumn(label: Text('Date')),
                                  DataColumn(label: Text('Status')),
                                ],
                                rows: buildApplicationRows(recentApps),
                                action: TextButton(
                                  onPressed: () => widget.onNavigate(
                                    AdminSection.applicants,
                                  ),
                                  child: const Text('View all'),
                                ),
                              );
                              final scholarsCard = NseapTableCard(
                                title: 'Recent Scholars',
                                subtitle:
                                    '$_year · $_semester · ${recentScholars.length} records',
                                columns: const [
                                  DataColumn(label: Text('Scholar Name')),
                                  DataColumn(label: Text('Program')),
                                  DataColumn(label: Text('Year Level')),
                                ],
                                rows: recentScholars
                                    .map(
                                      (r) => DataRow(
                                        cells: [
                                          DataCell(
                                            Text(
                                              r.name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                          DataCell(Text(r.program)),
                                          DataCell(Text(r.yearLevel)),
                                        ],
                                      ),
                                    )
                                    .toList(),
                                action: TextButton(
                                  onPressed: () =>
                                      widget.onNavigate(AdminSection.scholars),
                                  child: const Text('View all'),
                                ),
                              );

                              if (sideBySide) {
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: appsCard),
                                    const SizedBox(width: 14),
                                    Expanded(child: scholarsCard),
                                  ],
                                );
                              }
                              return Column(
                                children: [
                                  appsCard,
                                  const SizedBox(height: 14),
                                  scholarsCard,
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  List<int> _trendFromFiltered(List<AdminApplication> apps, String semester) {
    // Kept for legacy, now maps to academic months: Jun-Oct / Nov-Apr
    final months = semester == '1st Semester'
        ? [6, 7, 8, 9, 10]
        : [11, 12, 1, 2, 3, 4];
    return months
        .map((m) => apps.where((a) => a.submittedAt?.month == m).length)
        .toList();
  }

  List<NseapProgressBarItem> _schoolsFromLive(List<AdminApplication> apps) {
    if (apps.isEmpty) return [];
    final counts = <String, int>{};
    for (final a in apps) {
      final k = a.school.isEmpty ? 'Unknown School' : a.school;
      counts[k] = (counts[k] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(4).toList();
    final maxV = top.isEmpty ? 1 : top.first.value;
    return top
        .map(
          (e) => NseapProgressBarItem(
            label: e.key,
            value: e.value,
            fraction: e.value / maxV,
            valueLabel: '${e.value}',
            showPercentage: false,
          ),
        )
        .toList();
  }

  List<NseapProgressBarItem> _programsFromLive(List<AdminApplication> apps) {
    if (apps.isEmpty) return [];
    final counts = <String, int>{};
    for (final a in apps) {
      final raw = a.course.trim();
      final k = raw.isEmpty ? 'Unknown Program' : raw;
      counts[k] = (counts[k] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(4).toList();
    final maxV = top.isEmpty ? 1 : top.first.value;
    return top
        .map(
          (e) => NseapProgressBarItem(
            label: e.key,
            value: e.value,
            fraction: e.value / maxV,
            valueLabel: '${e.value}',
            showPercentage: false,
          ),
        )
        .toList();
  }

  List<NseapProgressBarItem> _barangaysFromLive(List<AdminApplication> apps) {
    if (apps.isEmpty) return [];
    final counts = <String, int>{};
    for (final a in apps) {
      final raw = a.address.trim();
      String k;
      if (raw.isEmpty) {
        k = 'Unknown Barangay';
      } else {
        // Extract barangay (first part before comma) e.g. "Abagao, Lal-lo, Cagayan" -> "Abagao"
        final first = raw.split(',').first.trim();
        k = first.isEmpty ? raw : first;
        // Normalize empty
        if (k.isEmpty) k = 'Unknown Barangay';
      }
      counts[k] = (counts[k] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(4).toList();
    final maxV = top.isEmpty ? 1 : top.first.value;
    return top
        .map(
          (e) => NseapProgressBarItem(
            label: e.key,
            value: e.value,
            fraction: e.value / maxV,
            valueLabel: '${e.value}',
            showPercentage: false,
          ),
        )
        .toList();
  }

  List<NseapProgressBarItem> _programsFor(String year, String semester) {
    if (year.toLowerCase() == 'all') {
      final all = <String, NseapProgressBarItem>{};
      for (final y in _academicYears) {
        for (final item in _programsFor(y, semester)) {
          final prev = all[item.label];
          if (prev == null) {
            all[item.label] = item;
          } else {
            all[item.label] = NseapProgressBarItem(
              label: item.label,
              value: prev.value + item.value,
              fraction: (prev.fraction + item.fraction) / 2,
              valueLabel: '${prev.value + item.value}',
            );
          }
        }
      }
      final list = all.values.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final maxV = list.isEmpty ? 1 : list.first.value;
      return list
          .take(4)
          .map(
            (e) => NseapProgressBarItem(
              label: e.label,
              value: e.value,
              fraction: e.value / maxV,
              valueLabel: '${e.value}',
            ),
          )
          .toList();
    }
    return <NseapProgressBarItem>[];
  }

  List<NseapProgressBarItem> _barangaysFor(String year, String semester) {
    if (year.toLowerCase() == 'all') {
      final all = <String, NseapProgressBarItem>{};
      for (final y in _academicYears) {
        for (final item in _barangaysFor(y, semester)) {
          final prev = all[item.label];
          if (prev == null) {
            all[item.label] = item;
          } else {
            all[item.label] = NseapProgressBarItem(
              label: item.label,
              value: prev.value + item.value,
              fraction: (prev.fraction + item.fraction) / 2,
              valueLabel: '${prev.value + item.value}',
            );
          }
        }
      }
      final list = all.values.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final maxV = list.isEmpty ? 1 : list.first.value;
      return list
          .take(4)
          .map(
            (e) => NseapProgressBarItem(
              label: e.label,
              value: e.value,
              fraction: e.value / maxV,
              valueLabel: '${e.value}',
            ),
          )
          .toList();
    }
    return <NseapProgressBarItem>[];
  }

  List<RecentApplicationRow> _dummyRecentApps(String year, String semester) {
    final isFirst = semester == '1st Semester';
    if (year == '2024-2025') {
      return isFirst
          ? const [
              RecentApplicationRow(
                name: 'Juan Dela Cruz',
                date: 'Mar 12, 2024',
                status: 'under_review',
              ),
              RecentApplicationRow(
                name: 'Maria Santos',
                date: 'Feb 11, 2024',
                status: 'pending',
              ),
              RecentApplicationRow(
                name: 'Josefa Reyes',
                date: 'Jan 10, 2024',
                status: 'scholar',
              ),
              RecentApplicationRow(
                name: 'Mark Villanueva',
                date: 'Apr 09, 2024',
                status: 'rejected',
              ),
              RecentApplicationRow(
                name: 'Anna Balagtas',
                date: 'May 08, 2024',
                status: 'interview_scheduled',
              ),
            ]
          : const [
              RecentApplicationRow(
                name: 'Luis Garcia',
                date: 'Sep 12, 2024',
                status: 'pending',
              ),
              RecentApplicationRow(
                name: 'Nina Torres',
                date: 'Oct 11, 2024',
                status: 'under_review',
              ),
              RecentApplicationRow(
                name: 'Paula Cruz',
                date: 'Nov 10, 2024',
                status: 'scholar',
              ),
              RecentApplicationRow(
                name: 'Ramon Diaz',
                date: 'Aug 09, 2024',
                status: 'rejected',
              ),
              RecentApplicationRow(
                name: 'Sonia Lim',
                date: 'Dec 08, 2024',
                status: 'interview_scheduled',
              ),
            ];
    }
    if (year == '2026-2027') {
      return isFirst
          ? const [
              RecentApplicationRow(
                name: 'Miguel Reyes',
                date: 'Feb 12, 2026',
                status: 'pending',
              ),
              RecentApplicationRow(
                name: 'Sofia Lim',
                date: 'Mar 11, 2026',
                status: 'under_review',
              ),
              RecentApplicationRow(
                name: 'Andre Cruz',
                date: 'Jan 10, 2026',
                status: 'scholar',
              ),
              RecentApplicationRow(
                name: 'Ella Domingo',
                date: 'Apr 09, 2026',
                status: 'rejected',
              ),
              RecentApplicationRow(
                name: 'Joshua Tan',
                date: 'Jun 08, 2026',
                status: 'interview_scheduled',
              ),
            ]
          : const [
              RecentApplicationRow(
                name: 'Karla Mendoza',
                date: 'Aug 12, 2026',
                status: 'scholar',
              ),
              RecentApplicationRow(
                name: 'Victor Santos',
                date: 'Sep 11, 2026',
                status: 'pending',
              ),
              RecentApplicationRow(
                name: 'Bianca Reyes',
                date: 'Oct 10, 2026',
                status: 'under_review',
              ),
              RecentApplicationRow(
                name: 'Harold Villanueva',
                date: 'Nov 09, 2026',
                status: 'rejected',
              ),
              RecentApplicationRow(
                name: 'Jenna Balagtas',
                date: 'Dec 08, 2026',
                status: 'interview_scheduled',
              ),
            ];
    }
    // Onwards 2027+ — generate from year
    final y = _yearStart(year);
    if (y > 2026) {
      return isFirst
          ? [
              RecentApplicationRow(
                name: 'Miguel Reyes',
                date: 'Feb 12, $y',
                status: 'pending',
              ),
              RecentApplicationRow(
                name: 'Sofia Lim',
                date: 'Mar 11, $y',
                status: 'under_review',
              ),
              RecentApplicationRow(
                name: 'Andre Cruz',
                date: 'Jan 10, $y',
                status: 'scholar',
              ),
              RecentApplicationRow(
                name: 'Ella Domingo',
                date: 'Apr 09, $y',
                status: 'rejected',
              ),
              RecentApplicationRow(
                name: 'Joshua Tan',
                date: 'Jun 08, $y',
                status: 'interview_scheduled',
              ),
            ]
          : [
              RecentApplicationRow(
                name: 'Karla Mendoza',
                date: 'Aug 12, $y',
                status: 'scholar',
              ),
              RecentApplicationRow(
                name: 'Victor Santos',
                date: 'Sep 11, $y',
                status: 'pending',
              ),
              RecentApplicationRow(
                name: 'Bianca Reyes',
                date: 'Oct 10, $y',
                status: 'under_review',
              ),
              RecentApplicationRow(
                name: 'Harold Villanueva',
                date: 'Nov 09, $y',
                status: 'rejected',
              ),
              RecentApplicationRow(
                name: 'Jenna Balagtas',
                date: 'Dec 08, $y',
                status: 'interview_scheduled',
              ),
            ];
    }
    return isFirst
        ? const [
            RecentApplicationRow(
              name: 'Miguel Reyes',
              date: 'Feb 12, 2026',
              status: 'pending',
            ),
            RecentApplicationRow(
              name: 'Sofia Lim',
              date: 'Mar 11, 2026',
              status: 'under_review',
            ),
            RecentApplicationRow(
              name: 'Andre Cruz',
              date: 'Jan 10, 2026',
              status: 'scholar',
            ),
            RecentApplicationRow(
              name: 'Ella Domingo',
              date: 'Apr 09, 2026',
              status: 'rejected',
            ),
            RecentApplicationRow(
              name: 'Joshua Tan',
              date: 'Jun 08, 2026',
              status: 'interview_scheduled',
            ),
          ]
        : const [
            RecentApplicationRow(
              name: 'Karla Mendoza',
              date: 'Aug 12, 2026',
              status: 'scholar',
            ),
            RecentApplicationRow(
              name: 'Victor Santos',
              date: 'Sep 11, 2026',
              status: 'pending',
            ),
            RecentApplicationRow(
              name: 'Bianca Reyes',
              date: 'Oct 10, 2026',
              status: 'under_review',
            ),
            RecentApplicationRow(
              name: 'Harold Villanueva',
              date: 'Nov 09, 2026',
              status: 'rejected',
            ),
            RecentApplicationRow(
              name: 'Jenna Balagtas',
              date: 'Dec 08, 2026',
              status: 'interview_scheduled',
            ),
          ];
  }

  List<RecentScholarRow> _dummyRecentScholars(String year, String semester) {
    if (_yearStart(year) > 2026) {
      return const [
        RecentScholarRow(
          name: 'Andre Cruz',
          program: 'BSIT',
          yearLevel: '4th Year',
        ),
        RecentScholarRow(
          name: 'Ella Domingo',
          program: 'BSED',
          yearLevel: '3rd Year',
        ),
        RecentScholarRow(
          name: 'Joshua Tan',
          program: 'BSN',
          yearLevel: '2nd Year',
        ),
        RecentScholarRow(
          name: 'Miguel Reyes',
          program: 'BSCrim',
          yearLevel: '1st Year',
        ),
        RecentScholarRow(
          name: 'Sofia Lim',
          program: 'BSIT',
          yearLevel: '2nd Year',
        ),
      ];
    }
    if (year == '2024-2025') {
      return const [
        RecentScholarRow(
          name: 'Carlo Mendoza',
          program: 'BSIT',
          yearLevel: '3rd Year',
        ),
        RecentScholarRow(
          name: 'Elena Domingo',
          program: 'BSED',
          yearLevel: '2nd Year',
        ),
        RecentScholarRow(
          name: 'Rico Gutierrez',
          program: 'BSN',
          yearLevel: '4th Year',
        ),
        RecentScholarRow(
          name: 'Sofia Lim',
          program: 'BSCrim',
          yearLevel: '1st Year',
        ),
        RecentScholarRow(
          name: 'Paolo Rivera',
          program: 'BSIT',
          yearLevel: '2nd Year',
        ),
      ];
    }
    if (year == '2026-2027') {
      return const [
        RecentScholarRow(
          name: 'Andre Cruz',
          program: 'BSIT',
          yearLevel: '4th Year',
        ),
        RecentScholarRow(
          name: 'Ella Domingo',
          program: 'BSED',
          yearLevel: '3rd Year',
        ),
        RecentScholarRow(
          name: 'Joshua Tan',
          program: 'BSN',
          yearLevel: '2nd Year',
        ),
        RecentScholarRow(
          name: 'Miguel Reyes',
          program: 'BSCrim',
          yearLevel: '1st Year',
        ),
        RecentScholarRow(
          name: 'Sofia Lim',
          program: 'BSIT',
          yearLevel: '2nd Year',
        ),
      ];
    }
    return semester == '2nd Semester'
        ? const [
            RecentScholarRow(
              name: 'Luis Garcia',
              program: 'BSIT',
              yearLevel: '2nd Year',
            ),
            RecentScholarRow(
              name: 'Nina Torres',
              program: 'BSED',
              yearLevel: '3rd Year',
            ),
            RecentScholarRow(
              name: 'Ramon Diaz',
              program: 'BSN',
              yearLevel: '1st Year',
            ),
            RecentScholarRow(
              name: 'Sonia Lim',
              program: 'BSCrim',
              yearLevel: '4th Year',
            ),
            RecentScholarRow(
              name: 'Paula Cruz',
              program: 'BSIT',
              yearLevel: '3rd Year',
            ),
          ]
        : const [
            RecentScholarRow(
              name: 'Carlo Mendoza',
              program: 'BSIT',
              yearLevel: '3rd Year',
            ),
            RecentScholarRow(
              name: 'Elena Domingo',
              program: 'BSED',
              yearLevel: '2nd Year',
            ),
            RecentScholarRow(
              name: 'Rico Gutierrez',
              program: 'BSN',
              yearLevel: '4th Year',
            ),
            RecentScholarRow(
              name: 'Sofia Lim',
              program: 'BSCrim',
              yearLevel: '1st Year',
            ),
            RecentScholarRow(
              name: 'Paolo Rivera',
              program: 'BSIT',
              yearLevel: '2nd Year',
            ),
          ];
  }

  // —— Stats for export fallback (returns 0 when no live data) ——
  int _expTotal(String y, String s) => 0;

  int _expApproved(String y, String s) => 0;

  int _expRejected(String y, String s) => 0;

  int _expInterview(String y, String s) => 0;

  int _expScholars(String y) => 0;

  String _activeTrend(int cur, int prev) {
    if (prev == 0) return '0.0%';
    final pct = (cur - prev) / prev * 100;
    final clamped = pct < 0 ? 0.0 : pct;
    return '+${clamped.toStringAsFixed(1)}%';
  }

  (String, String) _prevPeriodExport(String y, String s) {
    final start = int.tryParse(y.split('-').first) ?? 2026;
    if (s == '1st Semester') {
      final ps = start - 1;
      return ('$ps-${ps + 1}', '2nd Semester');
    }
    return (y, '1st Semester');
  }

  Future<void> _exportPdf(
    DashboardOverview? data,
    List<AdminApplication> filteredApps,
    List<ScholarRecord> filteredScholars,
    List<int> appGrowth,
    List<int> scholarGrowth,
    List<String> growthLabels,
    List<RecentApplicationRow> recentApps,
    List<RecentScholarRow> recentScholars,
  ) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final hasLive = data != null && data.applications.isNotEmpty;
      String fmt(int n) => n.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]},',
      );
      final total = hasLive ? filteredApps.length : _expTotal(_year, _semester);
      final approved = hasLive
          ? filteredApps.where((a) => a.status == 'scholar').length
          : _expApproved(_year, _semester);
      final rejected = hasLive
          ? filteredApps.where((a) => a.status == 'rejected').length
          : _expRejected(_year, _semester);
      final interview = hasLive
          ? filteredApps.where((a) => a.status == 'interview_scheduled').length
          : _expInterview(_year, _semester);
      final scholars = hasLive ? filteredScholars.length : _expScholars(_year);
      final (prevY, prevS) = _prevPeriodExport(_year, _semester);
      int prevCount(
        bool Function(AdminApplication) test,
        int Function(String, String) dummy,
      ) {
        if (hasLive) {
          return data.applications
              .where(
                (a) =>
                    test(a) &&
                    _inYear(a.submittedAt, prevY) &&
                    _inSemester(a.submittedAt, prevY, prevS),
              )
              .length;
        }
        return dummy(prevY, prevS);
      }

      final totalPrev = prevCount((_) => true, _expTotal);
      String share(int part, int whole) {
        if (whole == 0) return '0.0%';
        final pct = part / whole * 100;
        final clamped = pct < 0 ? 0.0 : (pct > 100 ? 100.0 : pct);
        return '${clamped.toStringAsFixed(1)}%';
      }

      final kpis = [
        {
          'metric': 'Total Applications',
          'value': fmt(total),
          'trend': _activeTrend(
            total,
            totalPrev == 0 && total != 0 ? _expTotal(prevY, prevS) : totalPrev,
          ),
        },
        {
          'metric': 'Approved Applications',
          'value': fmt(approved),
          'trend': share(approved, total),
        },
        {
          'metric': 'Rejected Applications',
          'value': fmt(rejected),
          'trend': share(rejected, total),
        },
        {
          'metric': 'Scheduled Interview',
          'value': fmt(interview),
          'trend': share(interview, total),
        },
        {
          'metric': 'Total Scholars',
          'value': fmt(scholars),
          'trend': share(scholars, total),
        },
      ];
      final schools =
          (hasLive
                  ? _schoolsFromLive(filteredApps)
                  : _schoolsFor(_year, _semester))
              .map(
                (e) => {
                  'label': e.label,
                  'value': e.valueLabel ?? '${e.value}',
                  'share': '${(e.fraction * 100).round()}%',
                },
              )
              .toList();
      final programs = _programsFor(_year, _semester)
          .map(
            (e) => {
              'label': e.label,
              'value': e.valueLabel ?? '${e.value}',
              'share': '${(e.fraction * 100).round()}%',
            },
          )
          .toList();
      final barangays = _barangaysFor(_year, _semester)
          .map(
            (e) => {
              'label': e.label,
              'value': e.valueLabel ?? '${e.value}',
              'share': '${(e.fraction * 100).round()}%',
            },
          )
          .toList();
      final appRows = recentApps
          .map((r) => [r.name, r.date, r.status])
          .toList();
      final scholarRows = recentScholars
          .map((r) => [r.name, r.program, r.yearLevel])
          .toList();
      await exportDashboardPdf(
        year: _year,
        semester: _semester,
        kpis: kpis,
        growthLabels: growthLabels,
        appGrowth: appGrowth,
        scholarGrowth: scholarGrowth,
        topSchools: schools,
        topPrograms: programs,
        topBarangays: barangays,
        recentApps: appRows,
        recentScholars: scholarRows,
      );
      if (mounted) {
        showAdminMessage(context, 'PDF downloaded — $_year $_semester');
      }
    } catch (e) {
      if (mounted) {
        showAdminMessage(context, readableAdminError(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportCsv(
    DashboardOverview? data,
    List<AdminApplication> filteredApps,
    List<ScholarRecord> filteredScholars,
    List<int> appGrowth,
    List<int> scholarGrowth,
    List<String> growthLabels,
    List<RecentApplicationRow> recentApps,
    List<RecentScholarRow> recentScholars,
  ) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final hasLive = data != null && data.applications.isNotEmpty;
      String fmt(int n) => n.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]},',
      );
      final total = hasLive ? filteredApps.length : _expTotal(_year, _semester);
      final approved = hasLive
          ? filteredApps.where((a) => a.status == 'scholar').length
          : _expApproved(_year, _semester);
      final rejected = hasLive
          ? filteredApps.where((a) => a.status == 'rejected').length
          : _expRejected(_year, _semester);
      final interview = hasLive
          ? filteredApps.where((a) => a.status == 'interview_scheduled').length
          : _expInterview(_year, _semester);
      final scholars = hasLive ? filteredScholars.length : _expScholars(_year);
      final (prevY2, prevS2) = _prevPeriodExport(_year, _semester);
      int prevCount2(
        bool Function(AdminApplication) test,
        int Function(String, String) dummy,
      ) {
        if (hasLive) {
          return data.applications
              .where(
                (a) =>
                    test(a) &&
                    _inYear(a.submittedAt, prevY2) &&
                    _inSemester(a.submittedAt, prevY2, prevS2),
              )
              .length;
        }
        return dummy(prevY2, prevS2);
      }

      final totalPrev2 = prevCount2((_) => true, _expTotal);
      String share2(int part, int whole) {
        if (whole == 0) return '0.0%';
        final pct = part / whole * 100;
        final clamped = pct < 0 ? 0.0 : (pct > 100 ? 100.0 : pct);
        return '${clamped.toStringAsFixed(1)}%';
      }

      final kpis = [
        {
          'metric': 'Total Applications',
          'value': fmt(total),
          'trend': _activeTrend(
            total,
            totalPrev2 == 0 && total != 0
                ? _expTotal(prevY2, prevS2)
                : totalPrev2,
          ),
        },
        {
          'metric': 'Approved Applications',
          'value': fmt(approved),
          'trend': share2(approved, total),
        },
        {
          'metric': 'Rejected Applications',
          'value': fmt(rejected),
          'trend': share2(rejected, total),
        },
        {
          'metric': 'Scheduled Interview',
          'value': fmt(interview),
          'trend': share2(interview, total),
        },
        {
          'metric': 'Total Scholars',
          'value': fmt(scholars),
          'trend': share2(scholars, total),
        },
      ];
      final schools =
          (hasLive
                  ? _schoolsFromLive(filteredApps)
                  : _schoolsFor(_year, _semester))
              .map(
                (e) => {
                  'label': e.label,
                  'value': e.valueLabel ?? '${e.value}',
                  'share': '${(e.fraction * 100).round()}%',
                },
              )
              .toList();
      final programs = _programsFor(_year, _semester)
          .map(
            (e) => {
              'label': e.label,
              'value': e.valueLabel ?? '${e.value}',
              'share': '${(e.fraction * 100).round()}%',
            },
          )
          .toList();
      final barangays = _barangaysFor(_year, _semester)
          .map(
            (e) => {
              'label': e.label,
              'value': e.valueLabel ?? '${e.value}',
              'share': '${(e.fraction * 100).round()}%',
            },
          )
          .toList();
      final appRows = recentApps
          .map((r) => [r.name, r.date, r.status])
          .toList();
      final scholarRows = recentScholars
          .map((r) => [r.name, r.program, r.yearLevel])
          .toList();
      await exportDashboardCsv(
        year: _year,
        semester: _semester,
        kpis: kpis,
        growthLabels: growthLabels,
        appGrowth: appGrowth,
        scholarGrowth: scholarGrowth,
        topSchools: schools,
        topPrograms: programs,
        topBarangays: barangays,
        recentApps: appRows,
        recentScholars: scholarRows,
      );
      if (mounted) {
        // Also copy CSV to clipboard as fallback for non-web download
        showAdminMessage(
          context,
          'CSV downloaded (Excel-ready) — $_year $_semester',
        );
      }
    } catch (e) {
      if (mounted) {
        showAdminMessage(context, readableAdminError(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}

/// Header per spec: Dashboard / Real-time metrics ... + dropdowns + Export button.
class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.year,
    required this.semester,
    required this.onYearChanged,
    required this.onSemesterChanged,
    required this.onRefresh,
  });
  final String year;
  final String semester;
  final ValueChanged<String?> onYearChanged;
  final ValueChanged<String?> onSemesterChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 680;
        final titleBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Dashboard',
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
              'Real-time metrics for the Scholarship Cycle',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 12.5),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '${DateTime.now().year}-${DateTime.now().year + 1} · Updated just now',
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: onRefresh,
                  child: const Icon(
                    Icons.refresh_rounded,
                    size: 14,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ],
        );
        final controls = Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _HeaderDropdown(
              value: year,
              items: [_allAcademicYear, ..._academicYears],
              label: 'Academic Year',
              onChanged: onYearChanged,
            ),
            _HeaderDropdown(
              value: semester,
              items: const ['1st Semester', '2nd Semester'],
              label: 'Semester',
              onChanged: onSemesterChanged,
            ),
          ],
        );
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [titleBlock, const SizedBox(height: 14), controls],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: 16),
            controls,
          ],
        );
      },
    );
  }
}

class _HeaderDropdown extends StatelessWidget {
  const _HeaderDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
    required this.label,
  });
  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
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
          items: items
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _GrowthSectionHeader extends StatelessWidget {
  const _GrowthSectionHeader({required this.range, required this.onChanged});
  final GrowthRange range;
  final ValueChanged<GrowthRange?> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 560;
        final titleBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Application Analytics',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Applications over time · ${range.label}',
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );
        final filter = Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<GrowthRange>(
              value: range,
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
              items: GrowthRange.values
                  .map(
                    (r) => DropdownMenuItem(
                      value: r,
                      child: Text(
                        r.label,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        );
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              titleBlock,
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerRight, child: filter),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: 16),
            filter,
          ],
        );
      },
    );
  }
}

/// 5 KPI cards — always horizontal, equal height, scrolls on narrow.
/// Percentages are now active: vs previous cycle (previous semester).
class _StatsGrid extends StatelessWidget {
  const _StatsGrid({
    required this.onNavigate,
    required this.liveData,
    required this.year,
    required this.semester,
    required this.filteredApps,
    required this.filteredScholars,
  });
  final ValueChanged<AdminSection> onNavigate;
  final DashboardOverview? liveData;
  final String year;
  final String semester;
  final List<AdminApplication> filteredApps;
  final List<ScholarRecord> filteredScholars;

  // --- active helpers — June 2026-Apr 2027, 1st: Jun-Oct, 2nd: Nov-Apr ---
  bool _inYearSt(DateTime? dt, String y) {
    if (y.toLowerCase() == 'all') return true;
    if (dt == null) return false;
    final start = int.tryParse(y.split('-').first) ?? dt.year;
    if (dt.year == start && dt.month >= 6) return true;
    if (dt.year == start + 1 && dt.month >= 1 && dt.month <= 4) return true;
    return false;
  }

  bool _inSemesterSt(DateTime? dt, String y, String s) {
    if (dt == null) return false;
    if (y.toLowerCase() == 'all') {
      if (s == '1st Semester') return dt.month >= 6 && dt.month <= 10;
      if (dt.month >= 11 || dt.month <= 4) {
        if (dt.month >= 11) return true;
        if (dt.month >= 1 && dt.month <= 4) return true;
      }
      return false;
    }
    final start = int.tryParse(y.split('-').first) ?? dt.year;
    if (s == '1st Semester') {
      return dt.year == start && dt.month >= 6 && dt.month <= 10;
    } else {
      if (dt.year == start && dt.month >= 11) return true;
      if (dt.year == start + 1 && dt.month >= 1 && dt.month <= 4) return true;
      return false;
    }
  }

  (String, String) _prevPeriod(String y, String s) {
    final start = int.tryParse(y.split('-').first) ?? 2026;
    if (s == '1st Semester') {
      final ps = start - 1;
      return ('$ps-${ps + 1}', '2nd Semester');
    }
    return (y, '1st Semester');
  }

  String _trend(int cur, int prev) {
    if (prev == 0) return '0.0%';
    final pct = (cur - prev) / prev * 100;
    final clamped = pct < 0 ? 0.0 : pct;
    return '+${clamped.toStringAsFixed(1)}%';
  }

  bool _isUp(int cur, int prev) {
    if (prev == 0) return cur >= 0;
    return cur >= prev;
  }

  @override
  Widget build(BuildContext context) {
    final hasLive =
        liveData != null &&
        (liveData!.applications.isNotEmpty || liveData!.scholars.isNotEmpty);
    // When live exists, derive from filtered lists; show 0 while loading or when no data.
    final totalApps = liveData == null
        ? 0
        : hasLive
        ? filteredApps.length
        : 0;
    final approved = liveData == null
        ? 0
        : hasLive
        ? filteredApps.where((a) => a.status == 'scholar').length
        : 0;
    final rejected = liveData == null
        ? 0
        : hasLive
        ? filteredApps.where((a) => a.status == 'rejected').length
        : 0;
    final interview = liveData == null
        ? 0
        : hasLive
        ? filteredApps.where((a) => a.status == 'interview_scheduled').length
        : 0;
    final int scholars = liveData == null
        ? 0
        : hasLive
        ? filteredScholars.length
        : 0;

    String fmt(int n) => n.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );

    return LayoutBuilder(
      builder: (context, c) {
        // Always single horizontal row - shrink cards to fit viewport,
        // no wrapping or horizontal scroll. Compute per-card width here and
        // pass it to cards so NseapStatisticCard can avoid its own
        // LayoutBuilder when inside IntrinsicHeight (LayoutBuilder does not
        // support intrinsics).
        final gap = c.maxWidth < 500
            ? 6.0
            : c.maxWidth < 900
            ? 8.0
            : 12.0;
        final rawCardWidth = (c.maxWidth - gap * 4) / 5;
        final effectiveCardWidth = rawCardWidth.isFinite && rawCardWidth > 0
            ? rawCardWidth
            : c.maxWidth / 5;

        final cards = [
          NseapStatisticCard(
            title: 'Total Applications',
            value: fmt(totalApps),
            icon: Icons.description_outlined,
            iconBg: const Color(0xFFEFF6FF),
            iconColor: AppColors.primary,
            onTap: () => onNavigate(AdminSection.applicants),
            cardWidth: effectiveCardWidth,
          ),
          NseapStatisticCard(
            title: 'Approved Applications',
            value: fmt(approved),
            icon: Icons.verified_outlined,
            iconBg: const Color(0xFFECFDF5),
            iconColor: const Color(0xFF059669),
            onTap: () => onNavigate(AdminSection.applicants),
            cardWidth: effectiveCardWidth,
          ),
          NseapStatisticCard(
            title: 'Rejected Applications',
            value: fmt(rejected),
            icon: Icons.cancel_outlined,
            iconBg: const Color(0xFFFEF2F2),
            iconColor: const Color(0xFFDC2626),
            onTap: () => onNavigate(AdminSection.applicants),
            cardWidth: effectiveCardWidth,
          ),
          NseapStatisticCard(
            title: 'Scheduled Interview',
            value: fmt(interview),
            icon: Icons.event_outlined,
            iconBg: const Color(0xFFFFF7ED),
            iconColor: const Color(0xFFEA580C),
            onTap: () => onNavigate(AdminSection.interviews),
            cardWidth: effectiveCardWidth,
          ),
          NseapStatisticCard(
            title: 'Total Scholars',
            value: fmt(scholars),
            icon: Icons.school_outlined,
            iconBg: const Color(0xFFDBEAFE),
            iconColor: AppColors.primary,
            onTap: () => onNavigate(AdminSection.scholars),
            cardWidth: effectiveCardWidth,
          ),
        ];

        // IntrinsicHeight provides bounded height for Row(stretch) inside
        // SingleChildScrollView's infinite-height Column. It is now safe
        // because cards no longer use LayoutBuilder when cardWidth is supplied.
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                Expanded(child: cards[i]),
                if (i < cards.length - 1) SizedBox(width: gap),
              ],
            ],
          ),
        );
      },
    );
  }

  int _yearStartForStats(String y) => int.tryParse(y.split('-').first) ?? 2026;

  int _dummyTotal(String y, String s) {
    final offset = _yearStartForStats(y) - 2026;
    if (offset > 0) return (s == '1st Semester' ? 13800 : 12100) + offset * 420;
    if (y == '2026-2027') return s == '1st Semester' ? 13800 : 12100;
    return s == '1st Semester' ? 13800 : 12100;
  }

  int _dummyApproved(String y, String s) {
    final offset = _yearStartForStats(y) - 2026;
    if (offset > 0) return (s == '1st Semester' ? 3420 : 2980) + offset * 120;
    if (y == '2026-2027') return s == '1st Semester' ? 3420 : 2980;
    return s == '1st Semester' ? 3420 : 2980;
  }

  int _dummyRejected(String y, String s) {
    final offset = _yearStartForStats(y) - 2026;
    if (offset > 0) return (s == '1st Semester' ? 8620 : 7420) + offset * 260;
    if (y == '2026-2027') return s == '1st Semester' ? 8620 : 7420;
    return s == '1st Semester' ? 8620 : 7420;
  }

  int _dummyInterview(String y, String s) {
    final offset = _yearStartForStats(y) - 2026;
    if (offset > 0) return (s == '1st Semester' ? 1280 : 1120) + offset * 60;
    if (y == '2026-2027') return s == '1st Semester' ? 1280 : 1120;
    return s == '1st Semester' ? 1280 : 1120;
  }

  dynamic _dummyScholars(String y) {
    final offset = _yearStartForStats(y) - 2026;
    if (offset > 0) return 4680 + offset * 180;
    return 4680;
  }
}
