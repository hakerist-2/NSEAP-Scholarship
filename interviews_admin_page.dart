import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:nseapscholarship/services/realtime_sync.dart';
import 'package:nseapscholarship/theme/nseap_theme.dart';
import 'package:printing/printing.dart';

import '../../../utils/academic_year.dart';
import '../../../models/interview_slot.dart';
import '../../admin_navigation.dart';
import '../../data/admin_repository.dart';
import '../../models/admin_models.dart';
import '../../widgets/admin_widgets.dart';
import '../shared/admin_page_support.dart';

/// Manages interview slots, live check-ins, and secure QR workflows.
class InterviewsAdminPage extends StatefulWidget {
  const InterviewsAdminPage({required this.repository, super.key});

  final AdminRepository repository;

  @override
  State<InterviewsAdminPage> createState() => _InterviewsAdminPageState();
}

class _InterviewsAdminPageState extends State<InterviewsAdminPage>
    with RealtimeSyncMixin {
  @override
  Set<String> get realtimeTables => const {
    'users',
    'scholarship_applications',
    'interview_schedules',
    'interview_slots',
    'interview_daily_limits',
    'applicant_check_ins',
    'scholarship_documents',
    'application_periods',
  };
  @override
  Future<void> refreshRealtime() async {
    _reload();
    await _future;
  }

  late Future<
    (
      List<ApplicantCheckIn>,
      List<InterviewSlot>,
      List<AdminApplication>,
      List<ApplicantInterview>,
      Map<String, int>,
      List<ApplicantApplicationPeriod>,
    )
  >
  _future = _load();
  String _search = '';
  String _status = 'all';
  String _scheduledFilter = 'all';
  String _sessionFilter = 'all';
  String _academicYear = AcademicYearUtils.currentAcademicYear();
  List<String> _academicYearOptions = [AcademicYearUtils.currentAcademicYear()];
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    adminApplicationsRefreshNotifier.addListener(_reload);
  }

  Future<
    (
      List<ApplicantCheckIn>,
      List<InterviewSlot>,
      List<AdminApplication>,
      List<ApplicantInterview>,
      Map<String, int>,
      List<ApplicantApplicationPeriod>,
    )
  >
  _load() async {
    final values = await Future.wait<dynamic>([
      widget.repository.getCheckInQueue(),
      widget.repository.getInterviewSlots(),
      widget.repository.getApplications(),
      widget.repository.getApplicantInterviews(),
      widget.repository.getDailyInterviewLimits(),
      widget.repository.getApplicationPeriods(),
    ]);
    final slots = values[1] as List<InterviewSlot>;
    final interviews = values[3] as List<ApplicantInterview>;
    final periods = values[5] as List<ApplicantApplicationPeriod>;
    final options = <String>{
      AcademicYearUtils.currentAcademicYear(),
      ...slots.map((slot) => slot.academicYear),
      ...interviews.map((interview) => interview.academicYear),
      ...periods.map((period) => period.academicYear),
    }.where((year) => year.isNotEmpty).toList()..sort((a, b) => b.compareTo(a));
    if (mounted && !_listEquals(_academicYearOptions, options)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _academicYearOptions = options);
      });
    }
    return (
      values[0] as List<ApplicantCheckIn>,
      values[1] as List<InterviewSlot>,
      values[2] as List<AdminApplication>,
      values[3] as List<ApplicantInterview>,
      values[4] as Map<String, int>,
      values[5] as List<ApplicantApplicationPeriod>,
    );
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _reload() {
    if (mounted) {
      setState(() {
        _future = _load();
      });
    }
  }

  @override
  void dispose() {
    adminApplicationsRefreshNotifier.removeListener(_reload);
    super.dispose();
  }

  Future<void> _edit([InterviewSlot? slot]) async {
    List<String> academicYears;
    try {
      final data = await _future;
      academicYears =
          data.$6
              .map((period) => period.academicYear)
              .where((year) => year.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
    } catch (error) {
      if (mounted) {
        showAdminMessage(context, readableAdminError(error), error: true);
      }
      return;
    }
    if (academicYears.isEmpty && slot == null) {
      if (mounted) {
        showAdminMessage(
          context,
          'Create an Application Window before creating interview slots.',
          error: true,
        );
      }
      return;
    }
    if (slot != null && !academicYears.contains(slot.academicYear)) {
      academicYears.add(slot.academicYear);
      academicYears.sort();
    }
    final initialAcademicYear =
        slot?.academicYear ??
        (academicYears.contains(_academicYear)
            ? _academicYear
            : academicYears.first);
    if (!mounted) return;
    final result = await _slotDialog(
      context,
      slot,
      academicYears: academicYears,
      initialAcademicYear: initialAcademicYear,
    );
    if (result == null || !mounted) return;
    // Enforce 15 slots per day maximum (from start → end)
    try {
      final data = await _future;
      final slots = data.$2;
      final targetDay = DateTime(
        result.$1.year,
        result.$1.month,
        result.$1.day,
      );
      int countForDay = 0;
      for (final s in slots) {
        if (slot != null && s.id == slot.id) continue;
        final sDay = DateTime(
          s.startsAt.year,
          s.startsAt.month,
          s.startsAt.day,
        );
        final eDay = DateTime(s.endsAt.year, s.endsAt.month, s.endsAt.day);
        for (
          var d = sDay;
          !d.isAfter(eDay);
          d = d.add(const Duration(days: 1))
        ) {
          if (_isSameDay(d, targetDay)) {
            countForDay++;
            break;
          }
        }
      }
      if (countForDay >= 15) {
        if (mounted) {
          showAdminMessage(
            context,
            'Maximum 15 interview slots per day reached for ${adminDateLabel(targetDay)}.',
            error: true,
          );
        }
        return;
      }
    } catch (_) {}
    if (!mounted) return;
    await runAdminAction(
      context,
      () => widget.repository.saveInterviewSlot(
        id: slot?.id,
        startsAt: result.$1,
        endsAt: result.$2,
        location: result.$3,
        maximumSlots: 15,
        status: result.$4,
        academicYear: result.$5,
        dailyLimit: 15,
      ),
      slot == null ? 'Interview slot created.' : 'Interview slot updated.',
      () {
        setState(() {
          _academicYear = result.$5;
          _selectedDay = null;
          _future = _load();
        });
      },
    );
  }

  Future<void> _deleteSlot(InterviewSlot slot) async {
    final booked = slot.bookingCount;
    final confirmed = await confirmAdminAction(
      context,
      title: 'Delete interview slot?',
      message:
          'Delete slot on ${adminDateLabel(slot.startsAt, withTime: true)} at ${slot.location} '
          '(${slot.academicYear})? '
          '${booked > 0 ? '$booked booked applicant${booked == 1 ? '' : 's'} will be released and must set a new schedule. ' : 'No applicants are booked on this slot. '}'
          'This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !mounted) return;
    try {
      final released = await widget.repository.deleteInterviewSlot(slot.id);
      if (!mounted) return;
      showAdminMessage(
        context,
        released > 0
            ? 'Interview slot deleted. $released booked applicant${released == 1 ? '' : 's'} can now set a new schedule.'
            : 'Interview slot deleted.',
      );
      adminApplicationsRefreshNotifier.value++;
      setState(() {
        if (_academicYear != 'all' && _academicYear == slot.academicYear) {
          _academicYear = 'all';
        }
        _selectedDay = null;
        _future = _load();
      });
    } catch (error) {
      if (mounted) {
        showAdminMessage(context, readableAdminError(error), error: true);
      }
    }
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 1, 1, 1);
    final lastDate = now.add(const Duration(days: 730));
    Map<String, int> slotCounts = {};
    Map<String, int> scheduledCounts = {};
    try {
      final data = await _future;
      final slots = data.$2;
      final interviews = data.$4;
      for (final s in slots) {
        if (_academicYear != 'all' && s.academicYear != _academicYear) {
          continue;
        }
        // Count every calendar day covered by the slot (start → end)
        final startDay = DateTime(
          s.startsAt.year,
          s.startsAt.month,
          s.startsAt.day,
        );
        final endDay = DateTime(s.endsAt.year, s.endsAt.month, s.endsAt.day);
        for (
          var d = startDay;
          !d.isAfter(endDay);
          d = d.add(const Duration(days: 1))
        ) {
          final k =
              '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
          slotCounts[k] = (slotCounts[k] ?? 0) + 1;
        }
      }
      for (final iv in interviews) {
        if (_academicYear != 'all' && iv.academicYear != _academicYear) {
          continue;
        }
        if (iv.status == 'cancelled') continue;
        final d = iv.scheduledAt;
        final k =
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        scheduledCounts[k] = (scheduledCounts[k] ?? 0) + 1;
      }
    } catch (_) {
      // If data not ready, fall back to empty counts — still shows picker
    }
    if (!mounted) return;
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (_) => _HighlightedInterviewDatePicker(
        initialDate: _selectedDay ?? now,
        firstDate: firstDate,
        lastDate: lastDate,
        slotCounts: slotCounts,
        scheduledCounts: scheduledCounts,
      ),
    );
    if (picked != null) {
      setState(
        () => _selectedDay = DateTime(picked.year, picked.month, picked.day),
      );
    }
  }

  void _clearDay() => setState(() => _selectedDay = null);

  Future<void> _startInterview(ApplicantCheckIn item) async {
    await runAdminAction(
      context,
      () => widget.repository.startInterview(item.id),
      'Interview started.',
      _reload,
    );
  }

  Future<void> _openApplication(
    String applicationId, {
    ApplicantCheckIn? checkIn,
    String? interviewStatus,
  }) async {
    try {
      final application = await widget.repository.getApplication(applicationId);
      final detail = await widget.repository.getApplicantDetail(application);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _ApplicationDialog(
          detail: detail,
          interviewStatus: interviewStatus ?? detail.interviewStatus,
          onOpenDocument: _openDocument,
          onStartInterview: checkIn?.checkInStatus == 'checked_in'
              ? () {
                  Navigator.pop(context);
                  _startInterview(checkIn!);
                }
              : null,
          onCompleteInterview: () async {
            Navigator.pop(context);
            await _completeInterview(applicationId);
          },
        ),
      );
    } catch (error) {
      if (mounted) {
        showAdminMessage(context, readableAdminError(error), error: true);
      }
    }
  }

  Future<void> _completeInterview(String applicationId) async {
    final confirmed = await confirmAdminAction(
      context,
      title: 'Mark interview as completed?',
      message:
          'This will update the interview schedule status to Completed for this applicant.',
      confirmLabel: 'Interview Completed',
    );
    if (!confirmed || !mounted) return;
    await runAdminAction(
      context,
      () => widget.repository.completeApplicationInterview(applicationId),
      'Interview marked as completed.',
      () {
        adminApplicationsRefreshNotifier.value++;
        _reload();
      },
    );
  }

  Future<void> _viewDocuments(String applicationId) async {
    try {
      final application = await widget.repository.getApplication(applicationId);
      final detail = await widget.repository.getApplicantDetail(application);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _DocumentsDialog(
          applicantName: application.name,
          documents: detail.documents,
          onOpen: _openDocument,
        ),
      );
    } catch (error) {
      if (mounted) {
        showAdminMessage(context, readableAdminError(error), error: true);
      }
    }
  }

  void _openDocument(AdminDocument document) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _DocumentPreviewPage(
          document: document,
          download: widget.repository.downloadDocument(document.storagePath),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AdminPageFrame(
    header: LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 720;
        final titleBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Interviews',
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
              'Coordinate interview schedules and slots',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 12.5),
            ),
            const SizedBox(height: 6),
            Text(
              _academicYear == 'all'
                  ? 'All academic years · Updated just now'
                  : 'Academic Year $_academicYear',
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
        final filter = _AcademicYearFilterBar(
          value: _academicYear,
          options: _academicYearOptions,
          onChanged: (value) => setState(() {
            _academicYear = value;
            _selectedDay = null;
          }),
        );
        final action = FilledButton.icon(
          onPressed: _edit,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Create Interview Schedule'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              titleBlock,
              const SizedBox(height: 12),
              filter,
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerRight, child: action),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: 12),
            filter,
            const SizedBox(width: 10),
            action,
          ],
        );
      },
    ),
    toolbar: Column(
      children: [
        AdminToolbar(
          hint: 'Search applicant, reference, or location',
          onSearch: (value) => setState(() => _search = value.toLowerCase()),
          filter: adminStatusFilter(_status, const [
            'all',
            'open',
            'closed',
            'cancelled',
          ], (value) => setState(() => _status = value)),
        ),
        const SizedBox(height: 12),
        _DayFilterBar(
          selectedDay: _selectedDay,
          onPick: _pickDay,
          onToday: () => setState(() {
            final now = DateTime.now();
            if (now.weekday == DateTime.saturday) {
              _selectedDay = DateTime(
                now.year,
                now.month,
                now.day,
              ).add(const Duration(days: 2));
            } else if (now.weekday == DateTime.sunday) {
              _selectedDay = DateTime(
                now.year,
                now.month,
                now.day,
              ).add(const Duration(days: 1));
            } else {
              _selectedDay = DateTime(now.year, now.month, now.day);
            }
          }),
          onClear: _clearDay,
        ),
      ],
    ),
    body:
        AdminAsyncView<
          (
            List<ApplicantCheckIn>,
            List<InterviewSlot>,
            List<AdminApplication>,
            List<ApplicantInterview>,
            Map<String, int>,
            List<ApplicantApplicationPeriod>,
          )
        >(
          future: _future,
          isEmpty: (_) => false,
          onRetry: _reload,
          builder: (context, data) {
            final slots = data.$2
                .where(
                  (item) =>
                      (_academicYear == 'all' ||
                          item.academicYear == _academicYear) &&
                      item.location.toLowerCase().contains(_search) &&
                      (_status == 'all' || item.status == _status),
                )
                .toList();
            final dailyLimits = data.$5;
            final applicationsById = {
              for (final application in data.$3) application.id: application,
            };
            final allScheduled = <_ScheduledApplicant>[];
            for (final interview in data.$4) {
              if (_academicYear != 'all' &&
                  interview.academicYear != _academicYear) {
                continue;
              }
              if (!{
                'scheduled',
                'rescheduled',
                'arrived',
                'completed',
              }.contains(interview.status)) {
                continue;
              }
              final application = applicationsById[interview.applicationId];
              if (application == null) continue;
              final searchText =
                  '${application.name} ${application.number} ${interview.location}'
                      .toLowerCase();
              if (!searchText.contains(_search)) continue;
              final isCompleted = interview.status == 'completed';
              if (_scheduledFilter == 'for_interview' && isCompleted) continue;
              if (_scheduledFilter == 'completed' && !isCompleted) continue;
              final session = interviewSessionOf(interview.scheduledAt);
              if (_sessionFilter == 'morning' &&
                  session != kInterviewSessionMorning) {
                continue;
              }
              if (_sessionFilter == 'afternoon' &&
                  session != kInterviewSessionAfternoon) {
                continue;
              }
              allScheduled.add(
                _ScheduledApplicant(
                  application: application,
                  interview: interview,
                ),
              );
            }
            final scheduledApplicants = _selectedDay == null
                ? allScheduled
                : allScheduled
                      .where(
                        (e) =>
                            _isSameDay(e.interview.scheduledAt, _selectedDay!),
                      )
                      .toList();
            final dayLabel = _selectedDay == null
                ? 'All dates'
                : adminDateLabel(_selectedDay, withTime: false);
            final String daySummary = _selectedDay == null
                ? '${scheduledApplicants.length} schedules'
                : '${scheduledApplicants.length} on $dayLabel';
            return ListView(
              children: [
                _SectionHeading(
                  title: 'Scheduled Applicants',
                  subtitle: daySummary,
                  icon: Icons.event_note_outlined,
                ),
                if (_selectedDay != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.filter_alt_outlined,
                          size: 14,
                          color: Color(0xFF64748B),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _selectedDay!.weekday == DateTime.saturday ||
                                    _selectedDay!.weekday == DateTime.sunday
                                ? 'Weekend — office closed'
                                : 'Showing interviews for $dayLabel — tap Pick date or Clear to see all.',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ),
                        if (scheduledApplicants.isEmpty)
                          const Icon(
                            Icons.event_busy_outlined,
                            size: 14,
                            color: Color(0xFF94A3B8),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                _ScheduledStatusFilter(
                  value: _scheduledFilter,
                  onChanged: (value) =>
                      setState(() => _scheduledFilter = value),
                ),
                const SizedBox(height: 10),
                _ScheduledSessionFilter(
                  value: _sessionFilter,
                  onChanged: (value) => setState(() => _sessionFilter = value),
                ),
                const SizedBox(height: 10),
                _ScheduledApplicantCollection(
                  items: scheduledApplicants,
                  onViewApplication: (item) => _openApplication(
                    item.application.id,
                    interviewStatus: item.interview.status,
                  ),
                  onViewDocuments: (item) =>
                      _viewDocuments(item.application.id),
                ),
                const SizedBox(height: 40),
                _SectionHeading(
                  title: 'Slots',
                  subtitle: '${slots.length} schedule windows',
                  icon: Icons.calendar_month_outlined,
                ),
                const SizedBox(height: 10),
                _SlotCollection(
                  items: slots,
                  onEdit: _edit,
                  onDelete: _deleteSlot,
                  dailyLimits: dailyLimits,
                ),
              ],
            );
          },
        ),
  );
}

class _AcademicYearFilterBar extends StatelessWidget {
  const _AcademicYearFilterBar({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = <String>{
      'all',
      ...options.where((year) => year.isNotEmpty),
      if (value.isNotEmpty) value,
    }.toList();
    final effectiveValue = items.contains(value) ? value : items.first;
    return Container(
      height: 42,
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
          value: effectiveValue,
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.school_outlined,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  SizedBox(width: 8),
                  Text('All'),
                ],
              ),
            ),
            ...options
                .where((year) => year.isNotEmpty)
                .map(
                  (year) => DropdownMenuItem(
                    value: year,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.school_outlined,
                          size: 16,
                          color: AppColors.primary,
                        ),
                        SizedBox(width: 8),
                        Text(year),
                      ],
                    ),
                  ),
                ),
          ],
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
        ),
      ),
    );
  }
}

class _DayFilterBar extends StatelessWidget {
  const _DayFilterBar({
    required this.selectedDay,
    required this.onPick,
    required this.onToday,
    required this.onClear,
  });
  final DateTime? selectedDay;
  final VoidCallback onPick;
  final VoidCallback onToday;
  final VoidCallback onClear;
  @override
  Widget build(BuildContext context) {
    final label = selectedDay == null
        ? 'All dates'
        : '${selectedDay!.month.toString().padLeft(2, '0')}/${selectedDay!.day.toString().padLeft(2, '0')}/${selectedDay!.year}';
    final weekday = selectedDay == null
        ? null
        : [
            'Mon',
            'Tue',
            'Wed',
            'Thu',
            'Fri',
            'Sat',
            'Sun',
          ][selectedDay!.weekday - 1];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A101828),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final badge = Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: selectedDay == null
                  ? const Color(0xFFF8FAFC)
                  : AppColors.primary,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selectedDay == null
                    ? const Color(0xFFE2E8F0)
                    : AppColors.primary,
              ),
            ),
            child: Text(
              weekday == null ? label : '$label • $weekday',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: selectedDay == null
                    ? const Color(0xFF334155)
                    : Colors.white,
              ),
            ),
          );
          final actions = Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.date_range_rounded, size: 16),
                label: const Text('Pick date'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              OutlinedButton(
                onPressed: onToday,
                child: const Text('Today', style: TextStyle(fontSize: 12)),
              ),
              if (selectedDay != null)
                IconButton(
                  tooltip: 'Clear (show all)',
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFF1F5F9),
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                ),
            ],
          );
          if (c.maxWidth < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_rounded,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Scheduled interviews for:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF334155),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                badge,
                const SizedBox(height: 8),
                actions,
              ],
            );
          }
          return Row(
            children: [
              const Icon(
                Icons.calendar_today_rounded,
                size: 16,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              const Text(
                'Scheduled interviews for:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF334155),
                ),
              ),
              const SizedBox(width: 8),
              badge,
              const Spacer(),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: NseapColors.primary),
      const SizedBox(width: 9),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
      Text(subtitle, style: const TextStyle(color: NseapColors.textSecondary)),
    ],
  );
}

class _ScheduledStatusFilter extends StatelessWidget {
  const _ScheduledStatusFilter({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(String key, String label) {
      final selected = value == key;
      return ChoiceChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : const Color(0xFF334155),
          ),
        ),
        selected: selected,
        onSelected: (_) => onChanged(key),
        showCheckmark: false,
        selectedColor: AppColors.primary,
        backgroundColor: Colors.white,
        checkmarkColor: Colors.white,
        labelPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        side: BorderSide(
          color: selected ? AppColors.primary : const Color(0xFFE2E8F0),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        chip('all', 'All'),
        chip('for_interview', 'For Interview'),
        chip('completed', 'Completed'),
      ],
    );
  }
}

class _ScheduledSessionFilter extends StatelessWidget {
  const _ScheduledSessionFilter({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(String key, String label, IconData icon) {
      final selected = value == key;
      return ChoiceChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? Colors.white : const Color(0xFF334155),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : const Color(0xFF334155),
              ),
            ),
          ],
        ),
        selected: selected,
        onSelected: (_) => onChanged(key),
        showCheckmark: false,
        selectedColor: AppColors.primary,
        backgroundColor: Colors.white,
        checkmarkColor: Colors.white,
        labelPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        side: BorderSide(
          color: selected ? AppColors.primary : const Color(0xFFE2E8F0),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        chip('all', 'All Sessions', Icons.schedule_outlined),
        chip('morning', 'Morning', Icons.wb_sunny_outlined),
        chip('afternoon', 'Afternoon', Icons.wb_twilight_outlined),
      ],
    );
  }
}

class _InterviewStatusChip extends StatelessWidget {
  const _InterviewStatusChip(this.status);

  final String status;

  @override
  Widget build(BuildContext context) {
    if (status == 'completed') {
      return const AdminStatusChip('completed');
    }
    return const NseapStatusBadge(
      label: 'For Interview',
      tone: NseapStatusTone.info,
    );
  }
}

class _InterviewSessionChip extends StatelessWidget {
  const _InterviewSessionChip(this.scheduledAt);

  final DateTime scheduledAt;

  @override
  Widget build(BuildContext context) {
    final isMorning =
        interviewSessionOf(scheduledAt) == kInterviewSessionMorning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isMorning ? const Color(0xFFFEF9C3) : const Color(0xFFE0F2FE),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isMorning ? const Color(0xFFFDE68A) : const Color(0xFFBAE6FD),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isMorning ? Icons.wb_sunny_outlined : Icons.wb_twilight_outlined,
            size: 14,
            color: isMorning
                ? const Color(0xFFA16207)
                : const Color(0xFF0369A1),
          ),
          const SizedBox(width: 6),
          Text(
            isMorning ? 'Morning' : 'Afternoon',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isMorning
                  ? const Color(0xFF854D0E)
                  : const Color(0xFF0C4A6E),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduledApplicant {
  const _ScheduledApplicant({
    required this.application,
    required this.interview,
  });

  final AdminApplication application;
  final ApplicantInterview interview;
}

class _ScheduledApplicantCollection extends StatelessWidget {
  const _ScheduledApplicantCollection({
    required this.items,
    required this.onViewApplication,
    required this.onViewDocuments,
  });

  final List<_ScheduledApplicant> items;
  final ValueChanged<_ScheduledApplicant> onViewApplication;
  // Kept for compatibility but no longer shown in UI (documents action removed).
  final ValueChanged<_ScheduledApplicant> onViewDocuments;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Container(
        height: 160,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderLight),
          boxShadow: AppElevation.shadowXs,
        ),
        child: const AdminStatePanel.empty(
          title: 'No scheduled applicants',
          message: 'Applicants appear here after choosing an interview slot.',
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 820;
        if (isNarrow) {
          return Column(
            children: items.map((item) {
              final interviewLabel = adminDateLabel(
                item.interview.scheduledAt,
                withTime: true,
              );
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.borderLight),
                    boxShadow: AppElevation.shadowXs,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => onViewApplication(item),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.1,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    item.application.name.isEmpty
                                        ? 'A'
                                        : item.application.name
                                              .trim()[0]
                                              .toUpperCase(),
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.application.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14.5,
                                          color: Color(0xFF0F172A),
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        item.application.number,
                                        style: const TextStyle(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                _InterviewStatusChip(item.interview.status),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Divider(
                              height: 1,
                              color: AppColors.borderLight,
                            ),
                            const SizedBox(height: 12),
                            _MobileField(
                              icon: Icons.event_outlined,
                              label: 'Interview',
                              value: interviewLabel,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.schedule_outlined,
                                    size: 14,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Session',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.5,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      _InterviewSessionChip(
                                        item.interview.scheduledAt,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _MobileField(
                              icon: Icons.location_on_outlined,
                              label: 'Location',
                              value: item.interview.location,
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.tonalIcon(
                                onPressed: () => onViewApplication(item),
                                icon: const Icon(
                                  Icons.visibility_outlined,
                                  size: 18,
                                ),
                                label: const Text('View Application'),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
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
            }).toList(),
          );
        }

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderLight),
            boxShadow: AppElevation.shadowXs,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAFC),
                  border: Border(
                    bottom: BorderSide(color: AppColors.borderLight),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.groups_outlined,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${items.length} scheduled',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: const WidgetStatePropertyAll(
                    Color(0xFFF8FAFC),
                  ),
                  headingRowHeight: 44,
                  dataRowMinHeight: 64,
                  dataRowMaxHeight: 64,
                  horizontalMargin: 16,
                  columnSpacing: 28,
                  dividerThickness: 1,
                  headingTextStyle: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: AppColors.textSecondary,
                  ),
                  dataTextStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF0F172A),
                  ),
                  columns: const [
                    DataColumn(label: Text('APPLICANT')),
                    DataColumn(label: Text('INTERVIEW')),
                    DataColumn(label: Text('SESSION')),
                    DataColumn(label: Text('LOCATION')),
                    DataColumn(label: Text('STATUS')),
                    DataColumn(label: Text('ACTION')),
                  ],
                  rows: items.map((item) {
                    return DataRow(
                      color: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.hovered)) {
                          return const Color(0xFFF8FAFC);
                        }
                        return null;
                      }),
                      cells: [
                        DataCell(
                          Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.1,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  item.application.name.isEmpty
                                      ? 'A'
                                      : item.application.name
                                            .trim()[0]
                                            .toUpperCase(),
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.application.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  Text(
                                    item.application.number,
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        DataCell(
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.calendar_month_outlined,
                                  size: 14,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                adminDateLabel(
                                  item.interview.scheduledAt,
                                  withTime: true,
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        DataCell(
                          _InterviewSessionChip(item.interview.scheduledAt),
                        ),
                        DataCell(
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on_outlined,
                                size: 14,
                                color: AppColors.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 180,
                                ),
                                child: Text(
                                  item.interview.location,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        DataCell(_InterviewStatusChip(item.interview.status)),
                        DataCell(
                          FilledButton.tonalIcon(
                            onPressed: () => onViewApplication(item),
                            icon: const Icon(
                              Icons.visibility_outlined,
                              size: 16,
                            ),
                            label: const Text('View'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              visualDensity: VisualDensity.compact,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MobileField extends StatelessWidget {
  const _MobileField({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 14, color: AppColors.textSecondary),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F172A),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _SlotCollection extends StatelessWidget {
  const _SlotCollection({
    required this.items,
    required this.onEdit,
    required this.onDelete,
    this.dailyLimits = const {},
  });

  final List<InterviewSlot> items;
  final ValueChanged<InterviewSlot> onEdit;
  final ValueChanged<InterviewSlot> onDelete;
  final Map<String, int> dailyLimits;

  String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _dayLabel(DateTime d) {
    const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${wd[d.weekday - 1]}, ${adminDateLabel(d)}';
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Container(
        height: 140,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderLight),
          boxShadow: AppElevation.shadowXs,
        ),
        child: const AdminStatePanel.empty(
          title: 'No slots yet',
          message: 'Create interview slots to open scheduling for applicants.',
        ),
      );
    }
    final grouped = <String, List<InterviewSlot>>{};
    for (final s in items) {
      final k = _dayKey(s.startsAt);
      grouped.putIfAbsent(k, () => []).add(s);
    }
    final sortedKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    Widget dayHeader(DateTime day, List<InterviewSlot> daySlots) {
      final isWeekend =
          day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
      final count = daySlots.length;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          gradient: isWeekend
              ? const LinearGradient(
                  colors: [Color(0xFFFEF2F2), Color(0xFFFFF1F2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : const LinearGradient(
                  colors: [Color(0xFFF8FAFC), Color(0xFFFFFFFF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          border: Border(
            bottom: BorderSide(
              color: isWeekend
                  ? const Color(0xFFFECACA)
                  : AppColors.borderLight,
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isWeekend
                    ? const Color(0xFFDC2626).withValues(alpha: 0.1)
                    : AppColors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isWeekend
                      ? const Color(0xFFFECACA)
                      : AppColors.primary.withValues(alpha: 0.14),
                ),
              ),
              child: Icon(
                isWeekend ? Icons.block_rounded : Icons.calendar_today_rounded,
                size: 16,
                color: isWeekend ? const Color(0xFFDC2626) : AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _dayLabel(day),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                      letterSpacing: -0.2,
                      color: isWeekend
                          ? const Color(0xFF991B1B)
                          : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$count slot${count == 1 ? '' : 's'} • ${isWeekend ? 'Office closed' : 'Mon–Fri schedule'}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        for (final k in sortedKeys) ...[
          Builder(
            builder: (_) {
              final daySlots = grouped[k]!;
              daySlots.sort((a, b) => a.startsAt.compareTo(b.startsAt));
              final day = daySlots.first.startsAt;
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.borderLight),
                  boxShadow: AppElevation.shadowXs,
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    dayHeader(day, daySlots),
                    LayoutBuilder(
                      builder: (context, c) {
                        final isNarrow = c.maxWidth < 820;
                        if (isNarrow) {
                          return Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              children: [
                                for (final item in daySlots) ...[
                                  _SlotMobileCard(
                                    item: item,
                                    onEdit: () => onEdit(item),
                                    onDelete: () => onDelete(item),
                                  ),
                                  if (item != daySlots.last)
                                    const SizedBox(height: 10),
                                ],
                              ],
                            ),
                          );
                        }
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            headingRowColor: const WidgetStatePropertyAll(
                              Color(0xFFF8FAFC),
                            ),
                            headingRowHeight: 46,
                            dataRowMinHeight: 74,
                            dataRowMaxHeight: 74,
                            horizontalMargin: 16,
                            columnSpacing: 20,
                            dividerThickness: 1,
                            headingTextStyle: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.7,
                              color: AppColors.textSecondary,
                            ),
                            dataTextStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF0F172A),
                            ),
                            columns: const [
                              DataColumn(label: Text('START')),
                              DataColumn(label: Text('END')),
                              DataColumn(label: Text('LOCATION')),
                              DataColumn(label: Text('STATUS')),
                              DataColumn(label: Text('BOOKED')),
                              DataColumn(label: Text('ACTION')),
                            ],
                            rows: daySlots.map((item) {
                              return DataRow(
                                color: WidgetStateProperty.resolveWith((
                                  states,
                                ) {
                                  if (states.contains(WidgetState.hovered)) {
                                    return const Color(0xFFF8FAFC);
                                  }
                                  return null;
                                }),
                                cells: [
                                  DataCell(_SlotStartCell(item: item)),
                                  DataCell(_SlotEndCell(item: item)),
                                  DataCell(
                                    Row(
                                      children: [
                                        const SizedBox(width: 8),
                                        ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            maxWidth: 160,
                                          ),
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item.location,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              const SizedBox(height: 1),
                                              const Text(
                                                'Interview venue',
                                                style: TextStyle(
                                                  fontSize: 10.5,
                                                  color:
                                                      AppColors.textSecondary,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  DataCell(AdminStatusChip(item.status)),
                                  DataCell(
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: item.bookingCount > 0
                                            ? const Color(0xFFEFF6FF)
                                            : const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: item.bookingCount > 0
                                              ? const Color(0xFFDBEAFE)
                                              : const Color(0xFFE2E8F0),
                                        ),
                                      ),
                                      child: Text(
                                        '${item.bookingCount} booked',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: item.bookingCount > 0
                                              ? AppColors.primary
                                              : const Color(0xFF64748B),
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _SlotActionButton(
                                          tooltip: 'Edit slot',
                                          icon: Icons.edit_outlined,
                                          onPressed: () => onEdit(item),
                                          variant: _SlotActionVariant.edit,
                                        ),
                                        const SizedBox(width: 8),
                                        _SlotActionButton(
                                          tooltip: 'Delete slot',
                                          icon: Icons.delete_outline_rounded,
                                          onPressed: () => onDelete(item),
                                          variant: _SlotActionVariant.delete,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

class _SlotStartCell extends StatelessWidget {
  const _SlotStartCell({required this.item});
  final InterviewSlot item;

  String _timeLabel(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    final ap = d.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ap';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'STARTS',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              _timeLabel(item.startsAt),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: Color(0xFF0F172A),
                letterSpacing: -0.2,
              ),
            ),
            Text(
              adminDateLabel(item.startsAt),
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SlotEndCell extends StatelessWidget {
  const _SlotEndCell({required this.item});
  final InterviewSlot item;

  String _timeLabel(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    final ap = d.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ap';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ENDS',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              _timeLabel(item.endsAt),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: Color(0xFF0F172A),
                letterSpacing: -0.2,
              ),
            ),
            Text(
              adminDateLabel(item.endsAt),
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

enum _SlotActionVariant { edit, delete }

class _SlotActionButton extends StatelessWidget {
  const _SlotActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    required this.variant,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final _SlotActionVariant variant;

  @override
  Widget build(BuildContext context) {
    final isDelete = variant == _SlotActionVariant.delete;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isDelete ? const Color(0xFFDC2626) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDelete ? const Color(0xFFDC2626) : AppColors.borderLight,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x080F172A),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            icon,
            size: 16,
            color: isDelete ? Colors.white : const Color(0xFF334155),
          ),
        ),
      ),
    );
  }
}

class _SlotMobileCard extends StatelessWidget {
  const _SlotMobileCard({
    required this.item,
    required this.onEdit,
    required this.onDelete,
  });

  final InterviewSlot item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  String _t(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    final ap = d.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ap';
  }

  @override
  Widget build(BuildContext context) {
    final startsDate = adminDateLabel(item.startsAt);
    final endsDate = adminDateLabel(item.endsAt);
    final showEndsDate = startsDate != endsDate;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080F172A),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top bar — time hero + status
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFF8FAFC), Colors.white],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              border: Border(bottom: BorderSide(color: AppColors.borderLight)),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.22),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.schedule_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_t(item.startsAt)} → ${_t(item.endsAt)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          letterSpacing: -0.3,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        showEndsDate ? '$startsDate → $endsDate' : startsDate,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AdminStatusChip(item.status),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFDBEAFE)),
                  ),
                  child: Text(
                    item.academicYear,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Text(
                    '${item.bookingCount} booked',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF475569),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Modern Start / End split panel
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.10,
                                    ),
                                    borderRadius: BorderRadius.circular(7),
                                  ),
                                  child: const Icon(
                                    Icons.login_rounded,
                                    size: 12,
                                    color: AppColors.primary,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  'START',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.6,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _t(item.startsAt),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                letterSpacing: -0.3,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              startsDate,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Vertical divider + in-between connector
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 1,
                          height: 28,
                          color: AppColors.borderLight,
                        ),
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.borderLight),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x0A0F172A),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.arrow_forward_rounded,
                            size: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 28,
                          color: AppColors.borderLight,
                        ),
                      ],
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(7),
                                    border: Border.all(
                                      color: AppColors.borderLight,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.logout_rounded,
                                    size: 12,
                                    color: Color(0xFF475569),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  'END',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.6,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _t(item.endsAt),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                letterSpacing: -0.3,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              endsDate,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
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

          // Actions
          Container(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text(
                      'Edit',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      side: const BorderSide(color: AppColors.borderLight),
                      foregroundColor: const Color(0xFF334155),
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                    label: Text(
                      item.bookingCount > 0
                          ? 'Delete (${item.bookingCount})'
                          : 'Delete',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      backgroundColor: const Color(0xFFFEF2F2),
                      foregroundColor: const Color(0xFFDC2626),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: const BorderSide(color: Color(0xFFFECACA)),
                      ),
                      elevation: 0,
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

class _ApplicationDialog extends StatelessWidget {
  const _ApplicationDialog({
    required this.detail,
    required this.onOpenDocument,
    required this.onCompleteInterview,
    this.interviewStatus,
    this.onStartInterview,
  });

  final ApplicantDetail detail;
  final String? interviewStatus;
  final ValueChanged<AdminDocument> onOpenDocument;
  final VoidCallback onCompleteInterview;
  final VoidCallback? onStartInterview;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFFF8FAFC),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      title: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: NseapColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                detail.application.name.isEmpty
                    ? 'A'
                    : detail.application.name[0].toUpperCase(),
                style: const TextStyle(
                  color: NseapColors.primary,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.application.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: AppColors.grey900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail.application.number,
                  style: const TextStyle(
                    color: NseapColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          AdminStatusChip(detail.application.status),
        ],
      ),
      content: SizedBox(
        width: 740,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _InterviewSectionCard(
                title: 'Personal Information',
                icon: Icons.person_outline_rounded,
                child: _InterviewInfoGrid(
                  values: {
                    'Full Name': detail.application.name,
                    'Date of Birth': adminDateLabel(detail.dateOfBirth),
                    'Sex': detail.sex,
                    'Contact Number': detail.contactNumber,
                    'Email Address': detail.application.email,
                    'Complete Address': detail.address,
                    'Barangay': detail.address.split(',').first.trim().isEmpty
                        ? 'Not recorded'
                        : detail.address.split(',').first.trim(),
                  },
                ),
              ),
              const SizedBox(height: 12),
              _InterviewSectionCard(
                title: 'Parent/Guardian Information',
                icon: Icons.family_restroom_outlined,
                child: _InterviewInfoGrid(
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
              const SizedBox(height: 12),
              _InterviewSectionCard(
                title: 'Uploaded Documents',
                icon: Icons.folder_copy_outlined,
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: NseapColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${detail.documents.length} files',
                    style: const TextStyle(
                      color: NseapColors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                child: detail.documents.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.grey100,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.inbox_outlined,
                                color: NseapColors.textSecondary,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'No documents uploaded.',
                              style: TextStyle(
                                color: NseapColors.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        children: [
                          for (final document in detail.documents)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: InkWell(
                                onTap: () => onOpenDocument(document),
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: NseapColors.border,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: NseapColors.primary.withValues(
                                            alpha: 0.09,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.description_outlined,
                                          color: NseapColors.primary,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              document.requirementTitle ??
                                                  adminLabel(document.type),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 13,
                                                color: AppColors.grey900,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              document.fileName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color:
                                                    NseapColors.textSecondary,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      const Icon(
                                        Icons.visibility_outlined,
                                        size: 18,
                                        color: NseapColors.textSecondary,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if ((interviewStatus ?? detail.interviewStatus) == 'completed')
          FilledButton.icon(
            onPressed: null,
            icon: const Icon(Icons.check_circle_rounded, size: 18),
            label: const Text('Completed'),
          )
        else
          FilledButton.icon(
            onPressed: onCompleteInterview,
            icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
            label: const Text('Interview Completed'),
            style: FilledButton.styleFrom(backgroundColor: NseapColors.primary),
          ),
      ],
    );
  }
}

class _InterviewSectionCard extends StatelessWidget {
  const _InterviewSectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NseapColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A101828),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
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
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: AppColors.grey900,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              // ignore: use_null_aware_elements
              if (trailing != null) trailing!,
            ],
          ),
          const Divider(height: 22),
          child,
        ],
      ),
    );
  }
}

class _InterviewInfoGrid extends StatelessWidget {
  const _InterviewInfoGrid({required this.values});

  final Map<String, String> values;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 520;
        final itemWidth = isWide
            ? (constraints.maxWidth - 16) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 16,
          runSpacing: 14,
          children: [
            for (final entry in values.entries)
              SizedBox(
                width: itemWidth,
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
                      entry.value.isEmpty ? 'Not recorded' : entry.value,
                      style: const TextStyle(
                        color: AppColors.grey900,
                        fontSize: 13,
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
}

class _DocumentsDialog extends StatelessWidget {
  const _DocumentsDialog({
    required this.applicantName,
    required this.documents,
    required this.onOpen,
  });

  final String applicantName;
  final List<AdminDocument> documents;
  final ValueChanged<AdminDocument> onOpen;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('$applicantName Documents'),
    content: SizedBox(
      width: 680,
      child: documents.isEmpty
          ? const SizedBox(
              height: 160,
              child: AdminStatePanel.empty(
                title: 'No documents submitted',
                message:
                    'Application documents will appear here once uploaded.',
              ),
            )
          : ListView.separated(
              shrinkWrap: true,
              itemCount: documents.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final document = documents[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                  leading: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: NseapColors.primary.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.insert_drive_file_outlined,
                      color: NseapColors.primary,
                    ),
                  ),
                  title: Text(
                    document.requirementTitle ?? adminLabel(document.type),
                  ),
                  subtitle: Text(
                    document.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.visibility_outlined),
                  onTap: () => onOpen(document),
                );
              },
            ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}

class _DocumentPreviewPage extends StatelessWidget {
  const _DocumentPreviewPage({required this.document, required this.download});

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
  );
}

Future<(DateTime, DateTime, String, String, String)?> _slotDialog(
  BuildContext context,
  InterviewSlot? slot, {
  required List<String> academicYears,
  required String initialAcademicYear,
}) async {
  DateTime startsAt =
      slot?.startsAt ?? DateTime.now().add(const Duration(days: 1));
  // Normalize to next weekday if weekend
  if (startsAt.weekday == DateTime.saturday) {
    startsAt = startsAt.add(const Duration(days: 2));
  }
  if (startsAt.weekday == DateTime.sunday) {
    startsAt = startsAt.add(const Duration(days: 1));
  }
  DateTime endsAt = slot?.endsAt ?? startsAt.add(const Duration(hours: 1));
  if (endsAt.weekday == DateTime.saturday) {
    endsAt = endsAt.add(const Duration(days: 2));
  }
  if (endsAt.weekday == DateTime.sunday) {
    endsAt = endsAt.add(const Duration(days: 1));
  }
  final location = TextEditingController(
    text: slot?.location ?? 'LGU Scholarship Office',
  );
  var status = slot?.status ?? 'open';
  var academicYear = initialAcademicYear;
  String fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  Future<DateTime?> pickDateTime(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      selectableDayPredicate: (d) =>
          d.weekday >= DateTime.monday && d.weekday <= DateTime.friday,
      helpText: 'Select weekday (Mon–Fri, no office weekends)',
    );
    if (date == null) return null;
    if (!context.mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) {
      return DateTime(
        date.year,
        date.month,
        date.day,
        initial.hour,
        initial.minute,
      );
    }
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  final result = await showDialog<(DateTime, DateTime, String, String, String)>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(
          slot == null ? 'New interview slot' : 'Edit interview slot',
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: academicYear,
                  decoration: const InputDecoration(
                    labelText: 'Academic Year',
                    helperText:
                        'Years come from configured Application Windows.',
                  ),
                  items: academicYears
                      .map(
                        (year) =>
                            DropdownMenuItem(value: year, child: Text(year)),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => academicYear = value ?? academicYear),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFDBEAFE)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Office closed weekends — only Mon–Fri selectable.',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Starts',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  subtitle: Text(
                    fmt(startsAt),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  trailing: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await pickDateTime(startsAt);
                      if (picked != null) setState(() => startsAt = picked);
                    },
                    icon: const Icon(Icons.calendar_today_rounded, size: 16),
                    label: const Text('Pick'),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Ends',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  subtitle: Text(
                    fmt(endsAt),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  trailing: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await pickDateTime(endsAt);
                      if (picked != null) setState(() => endsAt = picked);
                    },
                    icon: const Icon(Icons.calendar_today_rounded, size: 16),
                    label: const Text('Pick'),
                  ),
                ),
                adminDialogField(location, 'Location'),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const ['open', 'closed', 'cancelled']
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(adminLabel(item)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => status = value ?? status),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (startsAt.weekday == DateTime.saturday ||
                  startsAt.weekday == DateTime.sunday ||
                  endsAt.weekday == DateTime.saturday ||
                  endsAt.weekday == DateTime.sunday) {
                showAdminMessage(
                  context,
                  'Weekends are closed — pick Mon–Fri only.',
                  error: true,
                );
                return;
              }
              if (!endsAt.isAfter(startsAt)) {
                showAdminMessage(
                  context,
                  'End time must be after start time.',
                  error: true,
                );
                return;
              }
              Navigator.pop(context, (
                startsAt,
                endsAt,
                location.text.trim(),
                status,
                academicYear,
              ));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  location.dispose();
  return result;
}

/// Blue-highlighted date picker for interview schedule.
///
/// Days that have interview slots (start → end) are highlighted in blue
/// (`AppColors.primary`) and show a count badge of how many interviews are
/// scheduled on that day (`scheduledCounts`).
class _HighlightedInterviewDatePicker extends StatefulWidget {
  const _HighlightedInterviewDatePicker({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.slotCounts,
    required this.scheduledCounts,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final Map<String, int> slotCounts;
  final Map<String, int> scheduledCounts;

  @override
  State<_HighlightedInterviewDatePicker> createState() =>
      _HighlightedInterviewDatePickerState();
}

class _HighlightedInterviewDatePickerState
    extends State<_HighlightedInterviewDatePicker> {
  late DateTime _currentMonth;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime(
      widget.initialDate.year,
      widget.initialDate.month,
      widget.initialDate.day,
    );
    _currentMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
  }

  String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool _isSelectable(DateTime d) {
    if (d.isBefore(
          DateTime(
            widget.firstDate.year,
            widget.firstDate.month,
            widget.firstDate.day,
          ),
        ) ||
        d.isAfter(
          DateTime(
            widget.lastDate.year,
            widget.lastDate.month,
            widget.lastDate.day,
          ),
        )) {
      return false;
    }
    return d.weekday >= DateTime.monday && d.weekday <= DateTime.friday;
  }

  void _prevMonth() {
    final prev = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
    if (prev.isBefore(
      DateTime(widget.firstDate.year, widget.firstDate.month, 1),
    )) {
      return;
    }
    setState(() => _currentMonth = prev);
  }

  void _nextMonth() {
    final next = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
    if (next.isAfter(
      DateTime(widget.lastDate.year, widget.lastDate.month, 1),
    )) {
      return;
    }
    setState(() => _currentMonth = next);
  }

  @override
  Widget build(BuildContext context) {
    const weekDays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final monthLabel =
        '${_monthName(_currentMonth.month)} ${_currentMonth.year}';
    final daysInMonth = DateTime(
      _currentMonth.year,
      _currentMonth.month + 1,
      0,
    ).day;
    final firstWeekday = DateTime(
      _currentMonth.year,
      _currentMonth.month,
      1,
    ).weekday;
    final leadingEmpty = firstWeekday % 7;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.calendar_month_outlined,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      monthLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Previous month',
                    onPressed: _prevMonth,
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  IconButton(
                    tooltip: 'Next month',
                    onPressed: _nextMonth,
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFDBEAFE)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Blue = has slot (max 15/day)',
                      style: TextStyle(fontSize: 11, color: Color(0xFF334155)),
                    ),
                    const Spacer(),
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Red = scheduled',
                      style: TextStyle(fontSize: 11, color: Color(0xFFDC2626)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final wd in weekDays)
                    Expanded(
                      child: Center(
                        child: Text(
                          wd,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: wd == 'Sat' || wd == 'Sun'
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF475569),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  childAspectRatio: 1,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                ),
                itemCount: leadingEmpty + daysInMonth,
                itemBuilder: (context, index) {
                  if (index < leadingEmpty) {
                    return const SizedBox.shrink();
                  }
                  final day = index - leadingEmpty + 1;
                  final date = DateTime(
                    _currentMonth.year,
                    _currentMonth.month,
                    day,
                  );
                  final k = _key(date);
                  final selectable = _isSelectable(date);
                  final hasSlot = widget.slotCounts.containsKey(k);
                  final scheduled = widget.scheduledCounts[k] ?? 0;
                  final isSelected = _isSameDay(date, _selectedDate);
                  final isToday = _isSameDay(date, DateTime.now());

                  BoxDecoration? deco;
                  Color textColor = const Color(0xFF0F172A);
                  if (!selectable) {
                    textColor = const Color(0xFF94A3B8);
                  } else if (isSelected) {
                    deco = const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    );
                    textColor = Colors.white;
                  } else if (hasSlot) {
                    deco = BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.primary, width: 1.2),
                    );
                    textColor = AppColors.primary;
                  } else if (isToday) {
                    deco = const BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.fromBorderSide(
                        BorderSide(color: Color(0xFFCBD5E1)),
                      ),
                    );
                  }

                  final isWeekend =
                      date.weekday == DateTime.saturday ||
                      date.weekday == DateTime.sunday;
                  return InkWell(
                    onTap: selectable
                        ? () => setState(() => _selectedDate = date)
                        : null,
                    customBorder: const CircleBorder(),
                    child: Container(
                      decoration: deco,
                      child: Stack(
                        children: [
                          Center(
                            child: Text(
                              '$day',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: hasSlot || isSelected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: textColor,
                              ),
                            ),
                          ),
                          if (hasSlot &&
                              scheduled > 0 &&
                              !isWeekend &&
                              selectable)
                            Positioned(
                              top: 2,
                              right: 2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDC2626),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${scheduled > 15 ? 15 : scheduled}',
                                  style: const TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, _selectedDate),
                      child: const Text('Select'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _monthName(int m) => const [
    '',
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ][m];
}
