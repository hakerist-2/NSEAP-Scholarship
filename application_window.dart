import 'package:flutter/material.dart';
import 'package:nseapscholarship/services/realtime_sync.dart';

import '../../data/admin_repository.dart';
import '../../models/admin_models.dart';
import '../../widgets/admin_widgets.dart';
import '../../widgets/document_requirements_editor.dart';
import '../shared/admin_page_support.dart';

const _applicantPeriod = 'applicant';
const _scholarPeriod = 'scholar';

/// Configures applicant intake and scholar semester-submission windows.
class SemesterRequirementsAdminPage extends StatefulWidget {
  const SemesterRequirementsAdminPage({required this.repository, super.key});
  final AdminRepository repository;

  @override
  State<SemesterRequirementsAdminPage> createState() =>
      _SemesterRequirementsAdminPageState();
}

class _SemesterRequirementsAdminPageState
    extends State<SemesterRequirementsAdminPage>
    with RealtimeSyncMixin {
  @override
  Set<String> get realtimeTables => const {
    'application_periods',
    'semester_periods',
  };
  @override
  Future<void> refreshRealtime() async {
    _reload();
    await _future;
  }

  late Future<(List<ApplicantApplicationPeriod>, List<SemesterPeriod>)>
  _future = _load();

  Future<(List<ApplicantApplicationPeriod>, List<SemesterPeriod>)>
  _load() async {
    final values = await Future.wait<dynamic>([
      widget.repository.getApplicationPeriods(),
      widget.repository.getSemesterPeriods(),
    ]);
    return (
      values[0] as List<ApplicantApplicationPeriod>,
      values[1] as List<SemesterPeriod>,
    );
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _createPeriod() async {
    final result = await _periodDialog(context);
    if (result == null || !mounted) return;
    await _savePeriod(result);
  }

  Future<void> _editApplicantPeriod(ApplicantApplicationPeriod period) async {
    final result = await _periodDialog(context, applicantPeriod: period);
    if (result == null || !mounted) return;
    await _savePeriod(result, id: period.id);
  }

  Future<void> _editSemesterPeriod(SemesterPeriod period) async {
    final result = await _periodDialog(context, semesterPeriod: period);
    if (result == null || !mounted) return;
    await _savePeriod(result, id: period.id);
  }

  Future<void> _savePeriod(_PeriodDialogResult result, {String? id}) async {
    final isApplicant = result.type == _applicantPeriod;
    await runAdminAction(
      context,
      () => isApplicant
          ? widget.repository.saveApplicationPeriod(
              id: id,
              academicYear: result.academicYear,
              startsAt: result.startsAt,
              deadline: result.deadline,
              status: result.status,
            )
          : widget.repository.saveSemesterPeriod(
              id: id,
              academicYear: result.academicYear,
              semester: result.semester,
              startsAt: result.startsAt,
              deadline: result.deadline,
              endsAt: result.endsAt,
              status: result.status,
            ),
      isApplicant
          ? 'Applicant application period saved.'
          : 'Scholar semester submission period saved.',
      _reload,
    );
  }

  Future<void> _deleteApplicantPeriod(ApplicantApplicationPeriod period) async {
    if (!await confirmAdminAction(
      context,
      title: 'Delete application period?',
      message: 'Periods linked to submitted applications cannot be deleted.',
      confirmLabel: 'Delete',
    )) {
      return;
    }
    if (!mounted) return;
    await runAdminAction(
      context,
      () => widget.repository.deleteApplicationPeriod(period.id),
      'Applicant application period deleted.',
      _reload,
    );
  }

  Future<void> _deleteSemesterPeriod(SemesterPeriod period) async {
    try {
      final hasSubmissions = await widget.repository
          .semesterPeriodHasSubmissions(period.id);
      if (!mounted) return;
      if (hasSubmissions) {
        await _showProtectedSemesterPeriodDialog();
        return;
      }
    } catch (error) {
      if (mounted) {
        showAdminMessage(context, readableAdminError(error), error: true);
      }
      return;
    }

    if (!await confirmAdminAction(
      context,
      title: 'Delete semester submission period?',
      message: 'Referenced periods cannot be deleted.',
      confirmLabel: 'Delete',
    )) {
      return;
    }
    if (!mounted) return;
    await runAdminAction(
      context,
      () => widget.repository.deleteSemesterPeriod(period.id),
      'Scholar semester submission period deleted.',
      _reload,
    );
  }

  Future<void> _showProtectedSemesterPeriodDialog() {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Cannot Delete Period',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        content: const Text(
          'This semester submission period has existing scholar submissions '
          'and cannot be deleted. You may close or archive the period instead.\n\n'
          'This protects your historical scholarship records.',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 13.5,
            height: 1.55,
            color: Color(0xFF64748B),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AdminPageFrame(
    header: AdminPageHeader(
      title: 'Application Window',
      subtitle:
          'Set when applicants and scholars can submit their requirements.',
      action: FilledButton(
        onPressed: _createPeriod,
        child: const Text('Create period'),
      ),
    ),
    toolbar: const SizedBox.shrink(),
    body: AdminAsyncView<(List<ApplicantApplicationPeriod>, List<SemesterPeriod>)>(
      future: _future,
      isEmpty: (_) => false,
      onRetry: _reload,
      builder: (context, data) => ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          DocumentRequirementsEditor(
            repository: widget.repository,
            audience: 'applicant',
          ),
          const SizedBox(height: 20),
          DocumentRequirementsEditor(
            repository: widget.repository,
            audience: 'scholar',
          ),
          const SizedBox(height: 28),
          _PeriodSectionCard(
            title: 'Applicant Application Periods',
            description:
                'Controls when new applicants can create and submit applications.',
            itemCount: data.$1.length,
            children: [
              if (data.$1.isEmpty)
                const _EmptyPeriodMessage(
                  message: 'No applicant periods have been configured yet.',
                )
              else
                ...data.$1.map(
                  (period) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _PeriodItem(
                      title: '${period.academicYear} · New applicants',
                      startLabel: adminDateLabel(period.startsAt),
                      deadlineLabel: adminDateLabel(
                        period.deadline,
                        withTime: true,
                      ),
                      status: period.effectiveStatus(),
                      onEdit: () => _editApplicantPeriod(period),
                      onDelete: () => _deleteApplicantPeriod(period),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          _PeriodSectionCard(
            title: 'Scholar Semester Submission Periods',
            description:
                'Controls when scholars can submit semester requirements.',
            itemCount: data.$2.length,
            children: [
              if (data.$2.isEmpty)
                const _EmptyPeriodMessage(
                  message:
                      'No scholar submission periods have been configured yet.',
                )
              else
                ...data.$2.map(
                  (period) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _PeriodItem(
                      title: '${period.academicYear} · ${period.semester}',
                      startLabel: adminDateLabel(period.startsAt),
                      deadlineLabel: adminDateLabel(
                        period.deadline,
                        withTime: true,
                      ),
                      status: period.status == 'upcoming'
                          ? 'active'
                          : period.status,
                      onEdit: () => _editSemesterPeriod(period),
                      onDelete: () => _deleteSemesterPeriod(period),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Distinct grouped card for one period type, so applicant and scholar
/// windows are visually separated and easy to tell apart.
class _PeriodSectionCard extends StatelessWidget {
  const _PeriodSectionCard({
    required this.title,
    required this.description,
    required this.itemCount,
    required this.children,
  });

  final String title;
  final String description;
  final int itemCount;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.035),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PeriodSectionHeader(
            title: title,
            description: description,
            itemCount: itemCount,
          ),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    );
  }
}

class _PeriodSectionHeader extends StatelessWidget {
  const _PeriodSectionHeader({
    required this.title,
    required this.description,
    required this.itemCount,
  });

  final String title;
  final String description;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 16,
      runSpacing: 10,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                description,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$itemCount ${itemCount == 1 ? 'period' : 'periods'}',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _PeriodItem extends StatelessWidget {
  const _PeriodItem({
    required this.title,
    required this.startLabel,
    required this.deadlineLabel,
    required this.status,
    required this.onEdit,
    required this.onDelete,
  });

  final String title;
  final String startLabel;
  final String deadlineLabel;
  final String status;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 7),
        Wrap(
          spacing: 18,
          runSpacing: 5,
          children: [
            Text(
              'Starts $startLabel',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              'Deadline $deadlineLabel',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
    final actions = Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AdminStatusChip(status),
        TextButton(onPressed: onEdit, child: const Text('Edit')),
        TextButton(
          onPressed: onDelete,
          style: TextButton.styleFrom(foregroundColor: colorScheme.error),
          child: const Text('Delete'),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 640) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [details, const SizedBox(height: 12), actions],
            );
          }
          return Row(
            children: [
              Expanded(child: details),
              const SizedBox(width: 20),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _EmptyPeriodMessage extends StatelessWidget {
  const _EmptyPeriodMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
          height: 1.5,
        ),
      ),
    );
  }
}

class _PeriodDialogResult {
  const _PeriodDialogResult({
    required this.type,
    required this.academicYear,
    required this.semester,
    required this.startsAt,
    required this.deadline,
    required this.endsAt,
    required this.status,
  });

  final String type;
  final String academicYear;
  final String semester;
  final DateTime startsAt;
  final DateTime deadline;
  final DateTime endsAt;
  final String status;
}

String _formatPickerDate(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  final year = value.year.toString().padLeft(4, '0');
  return '$year-${two(value.month)}-${two(value.day)}';
}

String _formatPickerDateTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${_formatPickerDate(value)} ${two(value.hour)}:${two(value.minute)}';
}

Future<_PeriodDialogResult?> _periodDialog(
  BuildContext context, {
  ApplicantApplicationPeriod? applicantPeriod,
  SemesterPeriod? semesterPeriod,
}) async {
  final editing = applicantPeriod != null || semesterPeriod != null;
  final year = TextEditingController(
    text:
        applicantPeriod?.academicYear ??
        semesterPeriod?.academicYear ??
        '2026-2027',
  );
  var type = applicantPeriod != null ? _applicantPeriod : _scholarPeriod;
  var semester = semesterPeriod?.semester ?? 'First Semester';
  var startDate =
      applicantPeriod?.startsAt ?? semesterPeriod?.startsAt ?? DateTime.now();
  var deadlineDate =
      applicantPeriod?.deadline ??
      semesterPeriod?.deadline ??
      DateTime.now().add(const Duration(days: 30));
  startDate = DateTime(startDate.year, startDate.month, startDate.day);
  const statusOptions = ['active', 'closed', 'archived'];
  final storedStatus =
      applicantPeriod?.status ?? semesterPeriod?.status ?? 'active';
  var status = storedStatus == 'upcoming' ? 'active' : storedStatus;

  final result = await showDialog<_PeriodDialogResult>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        Future<void> pickDate({
          required DateTime current,
          required bool withTime,
          required ValueChanged<DateTime> onPicked,
        }) async {
          final pickedDate = await showDatePicker(
            context: context,
            initialDate: current,
            firstDate: DateTime(2000),
            lastDate: DateTime(2101),
          );
          if (pickedDate == null) return;
          var picked = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            withTime ? current.hour : 0,
            withTime ? current.minute : 0,
          );
          if (withTime) {
            if (!context.mounted) return;
            final pickedTime = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.fromDateTime(current),
            );
            if (pickedTime == null) return;
            picked = DateTime(
              pickedDate.year,
              pickedDate.month,
              pickedDate.day,
              pickedTime.hour,
              pickedTime.minute,
            );
          }
          setState(() => onPicked(picked));
        }

        Widget datePickerField({
          required String label,
          required String value,
          required bool withTime,
          required DateTime current,
          required ValueChanged<DateTime> onPicked,
        }) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            onTap: () => pickDate(
              current: current,
              withTime: withTime,
              onPicked: onPicked,
            ),
            borderRadius: BorderRadius.circular(4),
            child: InputDecorator(
              decoration: InputDecoration(labelText: label),
              child: Text(value),
            ),
          ),
        );

        final isApplicant = type == _applicantPeriod;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
          actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          title: Text(
            editing ? 'Edit period' : 'Create period',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: 'Period for'),
                    items: const [
                      DropdownMenuItem(
                        value: _applicantPeriod,
                        child: Text('Application period for applicants'),
                      ),
                      DropdownMenuItem(
                        value: _scholarPeriod,
                        child: Text('Semester submission for scholars'),
                      ),
                    ],
                    onChanged: editing
                        ? null
                        : (value) => setState(() => type = value ?? type),
                  ),
                  const SizedBox(height: 12),
                  adminDialogField(year, 'Academic year'),
                  if (!isApplicant) ...[
                    DropdownButtonFormField<String>(
                      initialValue: semester,
                      decoration: const InputDecoration(labelText: 'Semester'),
                      items: const ['First Semester', 'Second Semester']
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(item),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setState(() => semester = value ?? semester),
                    ),
                    const SizedBox(height: 12),
                  ],
                  datePickerField(
                    label: 'Start date',
                    value: _formatPickerDate(startDate),
                    withTime: false,
                    current: startDate,
                    onPicked: (picked) => startDate = picked,
                  ),
                  datePickerField(
                    label: isApplicant
                        ? 'Application deadline (date + time)'
                        : 'Submission deadline (date + time)',
                    value: _formatPickerDateTime(deadlineDate),
                    withTime: true,
                    current: deadlineDate,
                    onPicked: (picked) => deadlineDate = picked,
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: statusOptions
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
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (year.text.trim().isEmpty ||
                    startDate.isAfter(deadlineDate)) {
                  showAdminMessage(
                    context,
                    'Enter an academic year and place the deadline after the start date.',
                    error: true,
                  );
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  _PeriodDialogResult(
                    type: type,
                    academicYear: year.text.trim(),
                    semester: semester,
                    startsAt: startDate,
                    deadline: deadlineDate,
                    endsAt: DateTime(
                      deadlineDate.year,
                      deadlineDate.month,
                      deadlineDate.day,
                    ),
                    status: status,
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    ),
  );
  year.dispose();
  return result;
}
