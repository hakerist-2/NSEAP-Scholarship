import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:nseapscholarship/services/realtime_sync.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../data/admin_repository.dart';
import '../../models/admin_models.dart';
import '../../../utils/academic_year.dart';
import '../../widgets/admin_widgets.dart';
import '../../utils/download.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NSEAP Budget Report — Semester Budget Monitoring & Payout Documentation
// Spec-aligned: Approved-only, semester (1st/2nd), annual rollup, payout docs.
// Design: Primary #165EF0 (Blue), Gold #FAB801, White, Background #F5F7F6, Muted #66706B
// Desktop/web optimized, modern professional LGU appropriate.
// ─────────────────────────────────────────────────────────────────────────────

/// Budget report colors — updated to blue primary per request.
abstract final class NseapBudgetColors {
  static const green = Color(0xFF165EF0); // primary blue (kept name for compat)
  static const greenDark = Color(0xFF104BC4);
  static const greenSoft = Color(0xFFEFF6FF);
  static const greenLight = Color(0xFFD6E4FF);
  static const gold = Color(0xFFFAB801);
  static const goldSoft = Color(0xFFFFF7D9);
  static const goldLight = Color(0xFFFFF7D9);
  static const lightGrayBg = Color(0xFFF5F7F6); // spec Background
  static const cardBorder = Color(0xFFE2E8E5);
  static const textPrimary = Color(0xFF101828);
  static const textSecondary = Color(0xFF66706B); // spec Muted

  // Aliases for clarity — prefer blue naming in new code
  static const blue = green;
  static const blueDark = greenDark;
  static const blueSoft = greenSoft;
  static const blueLight = greenLight;
}

String _formatPeso(double amount) {
  final fixed = amount.toStringAsFixed(2);
  final parts = fixed.split('.');
  final withCommas = parts[0].replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
  return '₱$withCommas.${parts[1]}';
}

// PDF-safe: Helvetica in pdf package lacks ₱ glyph (shows ☐ with x), so use PHP prefix for PDF export.
String _formatPesoPdf(double amount) {
  final fixed = amount.toStringAsFixed(2);
  final parts = fixed.split('.');
  final withCommas = parts[0].replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
  return 'PHP $withCommas.${parts[1]}';
}

String _formatPesoCompact(double amount) {
  if (amount >= 1000000) return '₱${(amount / 1000000).toStringAsFixed(2)}M';
  if (amount >= 1000) return '₱${(amount / 1000).toStringAsFixed(1)}K';
  return _formatPeso(amount);
}

String _formatInt(int v) => v.toString().replaceAllMapped(
  RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
  (m) => '${m[1]},',
);

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

class PayoutFile {
  PayoutFile({
    required this.fileName,
    required this.fileType,
    required this.uploadDate,
    required this.uploadedBy,
    required this.bytes,
  });

  final String fileName;
  final String fileType; // pdf|xlsx|csv|png|jpg|jpeg
  final DateTime uploadDate;
  final String uploadedBy;
  final Uint8List bytes;

  int get size => bytes.length;
}

class SemesterBudget {
  SemesterBudget({
    required this.academicYear,
    required this.semester, // '1st Semester' | '2nd Semester'
    required this.totalBudget,
    required this.cashPerScholar,
    this.payoutFile,
  });

  final int academicYear;
  final String semester;
  double totalBudget;
  double cashPerScholar;
  PayoutFile? payoutFile;

  String get key => '$academicYear-$semester';

  /// Display label for academic year in "2026-2027" format.
  String get academicYearLabel => AcademicYearUtils.format(academicYear);

  // ── Automatic calculations — approved-only ─────────
  int releasedAmount(int approvedCount) => approvedCount * cashPerScholar ~/ 1;
  double released(int approvedCount) => approvedCount * cashPerScholar;
  double remaining(int approvedCount) => totalBudget - released(approvedCount);
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers — Approved-only logic
// ─────────────────────────────────────────────────────────────────────────────

bool _isApprovedStatus(String s) {
  final v = s.toLowerCase().trim();
  // Spec: only 'Approved' is included. Legacy data may store 'active'/'scholar'
  // as approved — treat them as approved for backward compatibility.
  return v == 'approved' || v == 'scholar' || v == 'active';
}

bool _isGraduatedStatus(String s) => s.toLowerCase().trim() == 'graduated';
bool _isTerminatedStatus(String s) {
  final v = s.toLowerCase().trim();
  return v == 'terminated' || v == 'archived' || v == 'suspended';
}

/// Normalizes an academic period label ("2027–2028" / " 2027-2028 ") to
/// "2027-2028" so en/em dashes from typed input still match stored values.
String _normalizeAcademicPeriod(String value) =>
    value.trim().replaceAll('–', '-').replaceAll('—', '-');

/// Normalizes semester labels so budget values ("1st Semester"/"2nd Semester")
/// match DB values ("First Semester"/"Second Semester").
String _normalizeSemesterLabel(String value) {
  final low = value.toLowerCase().trim();
  if (low.contains('1st') || low.contains('first')) return 'First Semester';
  if (low.contains('2nd') || low.contains('second')) {
    return 'Second Semester';
  }
  if (low.contains('summer')) return 'Summer';
  return value.trim();
}

/// Counts Approved Scholars that belong to the academic period of [year]
/// (e.g. 2027 → "2027-2028"). When [semester] is provided, only scholars
/// with a semester submission for that exact period AND semester count —
/// a 2nd Semester 2026-2027 budget never picks up 1st Semester-only records,
/// so scholars who did not submit for the 2nd semester (or were terminated
/// since the 1st) cannot leak into the count.
///
/// Status rules: only Approved (legacy 'scholar'/'active') count. Pending,
/// Under Review, Rejected, Terminated, Graduated scholars and scholars from
/// any other academic period/semester are never counted. The `started_at`
/// fallback applies only to period-level checks (no [semester]) — semester
/// budgets always require that semester's records.
int _approvedCountForPeriod(
  int year,
  List<ScholarRecord> scholars,
  List<SemesterSubmission> submissions, {
  String? semester,
}) {
  final period = _normalizeAcademicPeriod(AcademicYearUtils.format(year));
  final sem = semester == null ? null : _normalizeSemesterLabel(semester);
  final memberUserIds = submissions
      .where(
        (s) =>
            _normalizeAcademicPeriod(s.academicYear) == period &&
            (sem == null || _normalizeSemesterLabel(s.semester) == sem),
      )
      .map((s) => s.userId)
      .toSet();
  return scholars.where((s) {
    if (!_isApprovedStatus(s.status)) return false;
    if (_isGraduatedStatus(s.status) || _isTerminatedStatus(s.status)) {
      return false;
    }
    if (memberUserIds.contains(s.userId)) return true;
    return sem == null &&
        AcademicYearUtils.isInAcademicYear(s.startedAt, period);
  }).length;
}

// ─────────────────────────────────────────────────────────────────────────────
// Main Page
// ─────────────────────────────────────────────────────────────────────────────

class ReportsAdminPage extends StatefulWidget {
  const ReportsAdminPage({required this.repository, super.key});
  final AdminRepository repository;

  @override
  State<ReportsAdminPage> createState() => _ReportsAdminPageState();
}

class _ReportsAdminPageState extends State<ReportsAdminPage>
    with RealtimeSyncMixin {
  @override
  Set<String> get realtimeTables => const {
    'users',
    'scholarship_applications',
    'scholar_profiles',
    'semester_submissions',
    'semester_periods',
    'budget_supporting_documents',
  };
  @override
  Future<void> refreshRealtime() async {
    _reload();
    await _future;
  }

  late Future<AdminReportData> _future = widget.repository.getAdminReportData();
  int _selectedYear = 2026;
  bool _exporting = false;
  bool _generatingReadyList = false;

  // Academic year starts at 2026-2027 per LGU spec — no previous year.
  // Generates 2026-2027 .. (current+2) so future AYs appear automatically.
  List<int> get _availableYears {
    final cur = AcademicYearUtils.academicYearStartForDate(DateTime.now());
    final effectiveCur = cur < AcademicYearUtils.baseYear
        ? AcademicYearUtils.baseYear
        : cur;
    return [
      for (int y = AcademicYearUtils.baseYear; y <= effectiveCur + 2; y++) y,
    ];
  }

  static const _semesters = ['1st Semester', '2nd Semester'];

  // Admin-editable semester budgets — key: "$year-$semester"
  // Seed with spec example: 2026 1st & 2nd — ₱400,000 budget, ₱3,000 cash/scholar
  final Map<String, SemesterBudget> _budgets = {
    '2026-1st Semester': SemesterBudget(
      academicYear: 2026,
      semester: '1st Semester',
      totalBudget: 400000,
      cashPerScholar: 3000,
    ),
    '2026-2nd Semester': SemesterBudget(
      academicYear: 2026,
      semester: '2nd Semester',
      totalBudget: 400000,
      cashPerScholar: 3000,
    ),
  };

  String _key(int y, String s) => '$y-$s';
  SemesterBudget? _budgetFor(int y, String s) => _budgets[_key(y, s)];
  List<SemesterBudget> _budgetsForYear(int y) => _semesters
      .map((s) => _budgetFor(y, s))
      .whereType<SemesterBudget>()
      .toList();
  List<SemesterBudget> get _allBudgets {
    final list = _budgets.values.toList()
      ..sort((a, b) {
        final c = b.academicYear.compareTo(a.academicYear);
        if (c != 0) return c;
        return a.semester.compareTo(b.semester);
      });
    return list;
  }

  /// Per-scholar stipend for the selected academic year, taken from the
  /// semester budget created via "New Semester Budget" (1st Semester budget
  /// first, then 2nd). Falls back to the legacy ₱3,000 only when no budget
  /// exists yet for the year.
  double get _stipendForSelectedYear {
    final budgets = _budgetsForYear(_selectedYear);
    if (budgets.isEmpty) return 3000.0;
    return budgets.first.cashPerScholar;
  }

  int _totalCount(List<ScholarRecord> scholars) => scholars.length;
  int _graduatedCount(List<ScholarRecord> scholars) =>
      scholars.where((s) => _isGraduatedStatus(s.status)).length;
  int _terminatedCount(List<ScholarRecord> scholars) =>
      scholars.where((s) => _isTerminatedStatus(s.status)).length;

  void _reload() {
    setState(() {
      _future = widget.repository.getAdminReportData();
    });
  }

  // ── CRUD: Semester Budget ──────────────────────────────────────────────

  Future<void> _showBudgetForm({SemesterBudget? existing}) async {
    AdminReportData? report;
    try {
      report = await _future;
    } catch (_) {
      report = null;
    }
    final loadedReport = report;
    if (!mounted) return;
    final result = await showDialog<SemesterBudget>(
      context: context,
      builder: (_) => _SemesterBudgetFormDialog(
        existing: existing,
        existingKeys: _budgets.keys.toSet(),
        approvedCountForPeriod: loadedReport == null
            ? null
            : (year) => _approvedCountForPeriod(
                year,
                loadedReport.scholars,
                loadedReport.submissions,
              ),
      ),
    );
    if (result == null) return;
    final k = result.key;
    // Validation: duplicate check done inside dialog, but re-check for safety
    if (_budgets.containsKey(k) && existing?.key != k) {
      if (!mounted) return;
      showAdminMessage(
        context,
        'Budget for $k already exists. Edit the existing record instead.',
        error: true,
      );
      return;
    }
    setState(() => _budgets[k] = result);
    if (mounted)
      showAdminMessage(
        context,
        existing == null
            ? 'Semester budget created.'
            : 'Semester budget updated.',
      );
  }

  Future<void> _deleteBudget(SemesterBudget b) async {
    final ok = await confirmAdminAction(
      context,
      title: 'Delete semester budget?',
      message:
          'Delete ${b.academicYearLabel} ${b.semester} budget (₱${_formatPeso(b.totalBudget)})? This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!ok) return;
    setState(() => _budgets.remove(b.key));
    if (mounted) showAdminMessage(context, 'Budget deleted.');
  }

  static const _supportedDocTypes = {
    'pdf',
    'xlsx',
    'csv',
    'png',
    'jpg',
    'jpeg',
  };

  // Supporting documents for a semester budget report, persisted in the
  // `budget-documents` storage bucket and `budget_supporting_documents`
  // table, keyed by "$academicYearLabel|$semester".
  int _budgetDocsVersion = 0;

  String _budgetDocsMime(String ext) => switch (ext) {
    'pdf' => 'application/pdf',
    'xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'csv' => 'text/csv',
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    _ => 'application/octet-stream',
  };

  Future<void> _uploadSemesterBudgetDocs(SemesterBudget budget) async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: ['pdf', 'xlsx', 'csv', 'png', 'jpg', 'jpeg'],
    );
    if (res == null || res.files.isEmpty) return;
    final admin = await widget.repository.getCurrentAdmin();
    final uploadedBy = admin?.name ?? admin?.email ?? 'Administrator';
    var uploaded = 0;
    var skipped = 0;
    for (final f in res.files) {
      final bytes = f.bytes;
      final ext = (f.extension ?? f.name.split('.').last).toLowerCase();
      if (bytes == null ||
          !_supportedDocTypes.contains(ext) ||
          bytes.length > 10 * 1024 * 1024) {
        skipped++;
        continue;
      }
      try {
        await widget.repository.uploadBudgetSupportingDocument(
          academicYear: budget.academicYearLabel,
          semester: budget.semester,
          fileName: f.name,
          bytes: bytes,
          mimeType: _budgetDocsMime(ext),
          uploadedBy: uploadedBy,
        );
        uploaded++;
      } catch (_) {
        skipped++;
      }
    }
    if (!mounted) return;
    setState(() => _budgetDocsVersion++);
    if (uploaded > 0) {
      showAdminMessage(
        context,
        'Uploaded $uploaded supporting document${uploaded == 1 ? '' : 's'}'
        '${skipped > 0 ? ' ($skipped skipped)' : ''}.',
      );
    } else {
      showAdminMessage(
        context,
        'No files uploaded. Only PDF, XLSX, CSV, PNG, JPG up to 10 MB are allowed.',
        error: true,
      );
    }
  }

  Future<void> _openBudgetSupportingDoc(BudgetSupportingDocument doc) async {
    try {
      final bytes = await widget.repository.downloadBudgetDocument(
        doc.storagePath,
      );
      if (!mounted) return;
      await _viewPayoutFile(
        PayoutFile(
          fileName: doc.fileName,
          fileType: doc.fileType,
          uploadDate: doc.uploadedAt,
          uploadedBy: doc.uploadedBy,
          bytes: bytes,
        ),
      );
    } catch (e) {
      if (mounted) {
        showAdminMessage(context, readableAdminError(e), error: true);
      }
    }
  }

  Future<void> _downloadBudgetSupportingDoc(
    BudgetSupportingDocument doc,
  ) async {
    try {
      final bytes = await widget.repository.downloadBudgetDocument(
        doc.storagePath,
      );
      if (!mounted) return;
      await _downloadPayoutFile(
        PayoutFile(
          fileName: doc.fileName,
          fileType: doc.fileType,
          uploadDate: doc.uploadedAt,
          uploadedBy: doc.uploadedBy,
          bytes: bytes,
        ),
      );
    } catch (e) {
      if (mounted) {
        showAdminMessage(context, readableAdminError(e), error: true);
      }
    }
  }

  Future<void> _removeBudgetSupportingDoc(BudgetSupportingDocument doc) async {
    final ok = await confirmAdminAction(
      context,
      title: 'Remove supporting document?',
      message:
          'Remove ${doc.fileName} from ${doc.academicYear} ${doc.semester}? This cannot be undone.',
      confirmLabel: 'Remove',
    );
    if (!ok || !mounted) return;
    try {
      await widget.repository.deleteBudgetSupportingDocument(doc);
      if (!mounted) return;
      setState(() => _budgetDocsVersion++);
      showAdminMessage(context, 'Supporting document removed.');
    } catch (e) {
      if (mounted) {
        showAdminMessage(context, readableAdminError(e), error: true);
      }
    }
  }

  Future<void> _pickPayoutFile(SemesterBudget budget) async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
      type: FileType.custom,
      allowedExtensions: ['pdf', 'xlsx', 'csv', 'png', 'jpg', 'jpeg'],
    );
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    final bytes = f.bytes;
    if (bytes == null) {
      if (mounted)
        showAdminMessage(context, 'Unable to read file bytes.', error: true);
      return;
    }
    final ext = (f.extension ?? f.name.split('.').last).toLowerCase();
    if (!_supportedDocTypes.contains(ext)) {
      if (mounted)
        showAdminMessage(
          context,
          'Only PDF, XLSX, CSV, PNG, JPG are allowed.',
          error: true,
        );
      return;
    }
    final user = await widget.repository.getCurrentAdmin();
    final payout = PayoutFile(
      fileName: f.name,
      fileType: ext,
      uploadDate: DateTime.now(),
      uploadedBy: user?.name ?? user?.email ?? 'Administrator',
      bytes: bytes,
    );
    setState(() => budget.payoutFile = payout);
    if (mounted) showAdminMessage(context, 'Payout list uploaded: ${f.name}');
  }

  bool _printingPayout = false;

  List<ScholarRecord> _filterApprovedBySemester(
    List<ScholarRecord> approvedList,
    List<SemesterSubmission> submissions,
    String semester,
  ) {
    final userIdsInSemester = submissions
        .where((s) => s.semester == semester)
        .map((s) => s.userId)
        .toSet();
    return approvedList
        .where((s) => userIdsInSemester.contains(s.userId))
        .toList();
  }

  Future<void> _printSemesterPayout(
    SemesterBudget budget,
    List<ScholarRecord> approvedList, {
    List<SemesterSubmission>? submissions,
  }) async {
    final sem = budget.semester;
    final filteredList = submissions != null
        ? _filterApprovedBySemester(approvedList, submissions, sem)
        : approvedList;

    if (_printingPayout) return;
    setState(() => _printingPayout = true);
    try {
      final cash = budget.cashPerScholar;
      final totalAmount = filteredList.length * cash;
      final ayLabel = budget.academicYearLabel;
      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.fromLTRB(18, 16, 18, 16),
          header: (_) => pw.Column(
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'LGU LAL-LO',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromHex('#165EF0'),
                          letterSpacing: 1.2,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Nueva Segovia Educational Assistance Program (NSEAP)',
                        style: const pw.TextStyle(
                          fontSize: 7,
                          color: PdfColors.grey600,
                        ),
                      ),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromHex('#165EF0'),
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Text(
                      '$ayLabel | $sem',
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 8,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          footer: (ctx) => pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Generated on ${_todayLabel()} | Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                style: const pw.TextStyle(
                  fontSize: 6,
                  color: PdfColors.grey600,
                ),
              ),
              pw.Text(
                'Confidential - For official use only',
                style: pw.TextStyle(
                  fontSize: 6,
                  fontStyle: pw.FontStyle.italic,
                  color: PdfColor.fromHex('#66706B'),
                ),
              ),
            ],
          ),
          build: (_) => [
            pw.Center(
              child: pw.Column(
                children: [
                  pw.Text(
                    'SCHOLAR PAYOUT LIST - $sem',
                    style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromHex('#0F172A'),
                      letterSpacing: 0.6,
                    ),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    'Academic Year $ayLabel  |  Approved Scholars  |  Stipend ${_formatPesoPdf(cash)} per scholar',
                    style: pw.TextStyle(
                      fontSize: 8,
                      color: PdfColor.fromHex('#334155'),
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Total Scholars: ${filteredList.length}    |    Total Amount: ${_formatPesoPdf(totalAmount)}',
                    style: pw.TextStyle(
                      fontSize: 7,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromHex('#165EF0'),
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            pw.TableHelper.fromTextArray(
              headers: [
                '#',
                'Scholar ID',
                'Name',
                'Barangay',
                'School',
                'Stipend',
                'Signature',
              ],
              data: [
                for (int i = 0; i < filteredList.length; i++)
                  [
                    '${i + 1}',
                    filteredList[i].scholarId.trim().isEmpty
                        ? '-'
                        : filteredList[i].scholarId,
                    filteredList[i].name.trim().isEmpty
                        ? '-'
                        : filteredList[i].name,
                    (filteredList[i].barangay.trim().isEmpty ||
                            filteredList[i].barangay == 'Not recorded')
                        ? '-'
                        : filteredList[i].barangay,
                    (filteredList[i].school.trim().isEmpty ||
                            filteredList[i].school == 'Not recorded')
                        ? '-'
                        : filteredList[i].school,
                    _formatPesoPdf(cash),
                    '',
                  ],
              ],
              headerStyle: pw.TextStyle(
                color: PdfColor.fromHex('#0F172A'),
                fontWeight: pw.FontWeight.bold,
                fontSize: 7,
              ),
              headerDecoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F1F5F9'),
                border: pw.Border(
                  bottom: pw.BorderSide(
                    color: PdfColor.fromHex('#0F172A'),
                    width: 0.8,
                  ),
                ),
              ),
              cellStyle: pw.TextStyle(
                fontSize: 7,
                color: PdfColor.fromHex('#1E293B'),
              ),
              cellHeight: 15,
              headerHeight: 17,
              columnWidths: {
                0: const pw.FixedColumnWidth(22),
                1: const pw.FixedColumnWidth(95),
                2: const pw.FlexColumnWidth(2.6),
                3: const pw.FlexColumnWidth(1.6),
                4: const pw.FlexColumnWidth(1.8),
                5: const pw.FixedColumnWidth(70),
                6: const pw.FixedColumnWidth(110),
              },
              cellAlignments: {
                0: pw.Alignment.center,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerLeft,
                3: pw.Alignment.centerLeft,
                4: pw.Alignment.centerLeft,
                5: pw.Alignment.centerRight,
                6: pw.Alignment.center,
              },
              border: pw.TableBorder.all(
                color: PdfColor.fromHex('#E2E8F0'),
                width: 0.4,
              ),
            ),
          ],
        ),
      );
      final bytes = await pdf.save();
      await Printing.sharePdf(
        bytes: bytes,
        filename:
            'NSEAP_Payout_${ayLabel.replaceAll('-', '_')}_${sem.replaceAll(' ', '')}.pdf',
      );
      await Printing.layoutPdf(onLayout: (_) async => bytes);
      if (mounted) {
        showAdminMessage(
          context,
          'Payout list printed - $ayLabel $sem (${filteredList.length} scholars).',
        );
      }
    } catch (_) {
      if (mounted) {
        showAdminMessage(context, 'Unable to print payout list.', error: true);
      }
    } finally {
      if (mounted) setState(() => _printingPayout = false);
    }
  }

  Future<void> _printSemesterBudgetReport(
    SemesterBudget budget,
    int totalScholars,
    int approvedScholars,
    int graduatedScholars,
    int terminatedScholars,
  ) async {
    if (_printingPayout) return;
    setState(() => _printingPayout = true);
    try {
      final cash = budget.cashPerScholar;
      final totalBudget = budget.totalBudget;
      final released = budget.released(approvedScholars);
      final remaining = budget.remaining(approvedScholars);
      final ayLabel = budget.academicYearLabel;
      final sem = budget.semester;
      final reportDate = _todayLabel();
      final navy = PdfColor.fromHex('#1E293B');
      final lightBg = PdfColor.fromHex('#F8FAFC');
      final thinBorder = pw.BorderSide(
        color: PdfColor.fromHex('#E2E8F0'),
        width: 0.5,
      );

      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(36, 30, 36, 30),
          build: (_) => [
            // -- Header --
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'NSEAP',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromHex('#165EF0'),
                        letterSpacing: 1.0,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'LGU Lal-lo Scholarship Management System',
                      style: const pw.TextStyle(
                        fontSize: 7,
                        color: PdfColors.grey600,
                      ),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    _metaRow('Report Date', reportDate),
                    pw.SizedBox(height: 2),
                    _metaRow('Status', 'Final'),
                    pw.SizedBox(height: 2),
                    _metaRow('Prepared By', 'Scholarship Office'),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 14),
            pw.Divider(color: PdfColors.grey300, thickness: 0.8),
            pw.SizedBox(height: 10),

            // -- Title --
            pw.Text(
              'SEMESTER BUDGET & COMPUTATION REPORT',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: navy,
                letterSpacing: 0.4,
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              'Academic Year $ayLabel | $sem (Approved-Only Computation)',
              style: pw.TextStyle(
                fontSize: 9,
                color: PdfColor.fromHex('#475569'),
              ),
            ),
            pw.SizedBox(height: 14),

            // -- Table 1: Budget & Scholar Summary --
            pw.Text(
              'BUDGET & SCHOLAR SUMMARY',
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: navy,
                letterSpacing: 0.5,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: pw.BoxDecoration(color: navy),
              headerAlignment: pw.Alignment.centerLeft,
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellAlignment: pw.Alignment.centerLeft,
              cellAlignments: {
                1: pw.Alignment.centerRight,
                3: pw.Alignment.centerRight,
              },
              border: pw.TableBorder(
                horizontalInside: thinBorder,
                verticalInside: thinBorder,
              ),
              headerPadding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              oddRowDecoration: pw.BoxDecoration(color: lightBg),
              headers: ['Metric', 'Value', 'Metric', 'Value'],
              data: [
                ['Academic Year', ayLabel, 'Semester', sem],
                [
                  'Total Budget',
                  _formatPesoPdf(totalBudget),
                  'Cash Assistance / Scholar',
                  _formatPesoPdf(cash),
                ],
                [
                  'Total Scholars',
                  '$totalScholars',
                  'Approved Scholars',
                  '$approvedScholars',
                ],
                [
                  'Graduated Scholars',
                  '$graduatedScholars',
                  'Terminated Scholars',
                  '$terminatedScholars',
                ],
              ],
            ),
            pw.SizedBox(height: 16),

            // -- Table 2: Budget Allocation & Computation --
            pw.Text(
              'BUDGET ALLOCATION & COMPUTATION',
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: navy,
                letterSpacing: 0.5,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: pw.BoxDecoration(color: navy),
              headerAlignment: pw.Alignment.centerLeft,
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellAlignment: pw.Alignment.centerLeft,
              cellAlignments: {3: pw.Alignment.centerRight},
              border: pw.TableBorder(
                horizontalInside: thinBorder,
                verticalInside: thinBorder,
              ),
              headerPadding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              oddRowDecoration: pw.BoxDecoration(color: lightBg),
              headers: [
                'Description',
                'Formula / Basis',
                'Calculation',
                'Amount',
              ],
              data: [
                [
                  'Total Approved Budget',
                  'Initial Allocation',
                  '-',
                  _formatPesoPdf(totalBudget),
                ],
                [
                  'Approved Disbursements',
                  '$approvedScholars Scholars x ${_formatPesoPdf(cash)}',
                  '$approvedScholars x ${_formatPesoPdf(cash)}',
                  _formatPesoPdf(released),
                ],
                [
                  'Remaining Balance',
                  'Total Budget - Total Released',
                  '${_formatPesoPdf(totalBudget)} - ${_formatPesoPdf(released)}',
                  _formatPesoPdf(remaining),
                ],
              ],
            ),
            pw.SizedBox(height: 16),

            // -- Table 3: Calculation Logic Reference --
            pw.Text(
              'CALCULATION LOGIC REFERENCE',
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: navy,
                letterSpacing: 0.5,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: pw.BoxDecoration(color: navy),
              headerAlignment: pw.Alignment.centerLeft,
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellAlignment: pw.Alignment.centerLeft,
              border: pw.TableBorder(
                horizontalInside: thinBorder,
                verticalInside: thinBorder,
              ),
              headerPadding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              oddRowDecoration: pw.BoxDecoration(color: lightBg),
              headers: ['Formula Name', 'Expression'],
              data: [
                [
                  'Total Released',
                  'Approved Scholars x Cash Assistance Per Scholar',
                ],
                ['Remaining Budget', 'Total Budget - Total Released Amount'],
              ],
            ),
          ],
          footer: (ctx) => pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Generated on $reportDate | Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                style: const pw.TextStyle(
                  fontSize: 6,
                  color: PdfColors.grey600,
                ),
              ),
              pw.Text(
                'Confidential - For official use only',
                style: pw.TextStyle(
                  fontSize: 6,
                  fontStyle: pw.FontStyle.italic,
                  color: PdfColor.fromHex('#66706B'),
                ),
              ),
            ],
          ),
        ),
      );

      final bytes = await pdf.save();
      await Printing.sharePdf(
        bytes: bytes,
        filename:
            'NSEAP_Budget_Report_${sem.replaceAll(' ', '_')}_$ayLabel.pdf',
      );
      if (mounted) {
        showAdminMessage(context, '$sem budget report exported as PDF.');
      }
    } catch (_) {
      if (mounted) {
        showAdminMessage(
          context,
          'Unable to print budget report.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _printingPayout = false);
    }
  }

  static pw.Widget _metaRow(String label, String value) => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        '$label: ',
        style: pw.TextStyle(fontSize: 7, color: PdfColor.fromHex('#64748B')),
      ),
      pw.Text(
        value,
        style: pw.TextStyle(
          fontSize: 7,
          fontWeight: pw.FontWeight.bold,
          color: PdfColor.fromHex('#0F172A'),
        ),
      ),
    ],
  );

  void _viewDetails(SemesterBudget b, AdminReportData data) {
    final approved = _approvedCountForPeriod(
      b.academicYear,
      data.scholars,
      data.submissions,
      semester: b.semester,
    );
    final total = _totalCount(data.scholars);
    final grad = _graduatedCount(data.scholars);
    final term = _terminatedCount(data.scholars);
    final approvedList = _approvedScholarsForReadyList(
      data.scholars,
      applications: data.applications,
    );
    showDialog<void>(
      context: context,
      builder: (_) => _BudgetDetailsDialog(
        budget: b,
        approved: approved,
        total: total,
        graduated: grad,
        terminated: term,
        onPrint: () {
          Navigator.pop(context);
          _printSemesterBudgetReport(b, total, approved, grad, term);
        },
        onViewFile: b.payoutFile == null
            ? null
            : () => _viewPayoutFile(b.payoutFile!),
        onDownloadFile: b.payoutFile == null
            ? null
            : () => _downloadPayoutFile(b.payoutFile!),
        repository: widget.repository,
        docsVersion: _budgetDocsVersion,
        onUploadDoc: () => _uploadSemesterBudgetDocs(b),
        onViewDoc: _openBudgetSupportingDoc,
        onDownloadDoc: _downloadBudgetSupportingDoc,
        onDeleteDoc: _removeBudgetSupportingDoc,
      ),
    );
  }

  bool _isImageDoc(PayoutFile f) =>
      f.fileType == 'png' || f.fileType == 'jpg' || f.fileType == 'jpeg';

  Future<void> _viewPayoutFile(PayoutFile f) async {
    final title = f.fileName;
    if (_isImageDoc(f)) {
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: SizedBox(
            width: 900,
            height: 700,
            child: Column(
              children: [
                AppBar(
                  backgroundColor: NseapBudgetColors.green,
                  foregroundColor: Colors.white,
                  title: Text(title, style: const TextStyle(fontSize: 14)),
                  automaticallyImplyLeading: false,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                Expanded(
                  child: InteractiveViewer(
                    child: Center(
                      child: Image.memory(f.bytes, fit: BoxFit.contain),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${f.fileType.toUpperCase()} | ${_formatFileSize(f.size)} | ${f.uploadedBy}',
                          style: const TextStyle(
                            color: NseapBudgetColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () => _downloadPayoutFile(f),
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: const Text('Download'),
                        style: FilledButton.styleFrom(
                          backgroundColor: NseapBudgetColors.green,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }
    if (f.fileType == 'pdf') {
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: SizedBox(
            width: 900,
            height: 700,
            child: Column(
              children: [
                AppBar(
                  backgroundColor: NseapBudgetColors.green,
                  foregroundColor: Colors.white,
                  title: Text(title, style: const TextStyle(fontSize: 14)),
                  automaticallyImplyLeading: false,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.picture_as_pdf_rounded,
                          size: 64,
                          color: NseapBudgetColors.green,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${f.fileType.toUpperCase()} | ${_formatFileSize(f.size)} | ${f.uploadedBy}',
                          style: const TextStyle(
                            color: NseapBudgetColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () => _downloadPayoutFile(f),
                          icon: const Icon(Icons.download_rounded, size: 18),
                          label: const Text('Download'),
                          style: FilledButton.styleFrom(
                            backgroundColor: NseapBudgetColors.green,
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
      );
    } else {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Type: ${f.fileType.toUpperCase()}'),
              Text('Size: ${_formatFileSize(f.size)}'),
              Text('Uploaded: ${_formatDateTime(f.uploadDate)}'),
              Text('By: ${f.uploadedBy}'),
              const SizedBox(height: 12),
              const Text(
                'Preview not available for this format. Please download to view.',
                style: TextStyle(color: NseapBudgetColors.textSecondary),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () => _downloadPayoutFile(f),
              style: FilledButton.styleFrom(
                backgroundColor: NseapBudgetColors.green,
              ),
              child: const Text('Download'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _downloadPayoutFile(PayoutFile f) async {
    try {
      final mime = switch (f.fileType) {
        'pdf' => 'application/pdf',
        'xlsx' =>
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'csv' => 'text/csv',
        'png' => 'image/png',
        'jpg' || 'jpeg' => 'image/jpeg',
        _ => 'application/octet-stream',
      };
      await downloadBytes(f.bytes, f.fileName, mime);
      if (mounted) showAdminMessage(context, 'Downloading ${f.fileName}');
    } catch (e) {
      if (mounted)
        showAdminMessage(context, readableAdminError(e), error: true);
    }
  }

  static String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  static String _formatDateTime(DateTime d) {
    final two = (int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  // ── Export ─────────────────────────────────────────────────────────────

  Future<void> _exportYear(int year, AdminReportData data) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final budgets = _budgetsForYear(year);
      if (budgets.isEmpty) {
        showAdminMessage(context, 'No budgets for $year to export.');
        return;
      }
      int approvedFor(SemesterBudget b) => _approvedCountForPeriod(
        b.academicYear,
        data.scholars,
        data.submissions,
        semester: b.semester,
      );

      final annualBudget = budgets.fold<double>(0, (s, b) => s + b.totalBudget);
      final annualReleased = budgets.fold<double>(
        0,
        (s, b) => s + b.released(approvedFor(b)),
      );
      final annualRemaining = annualBudget - annualReleased;

      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(28),
          build: (_) => [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'NSEAP',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromHex('#165EF0'),
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'LGU Lal-lo Scholarship Management System',
                      style: const pw.TextStyle(
                        fontSize: 8,
                        color: PdfColors.grey600,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'BUDGET REPORT',
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromHex('#0F172A'),
                      ),
                    ),
                    pw.Text(
                      'Academic Year ${AcademicYearUtils.format(year)} | Approved-only | Annual Summary',
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey600,
                      ),
                    ),
                  ],
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#165EF0'),
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Text(
                    AcademicYearUtils.format(year),
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 14),
            pw.Divider(color: PdfColors.grey300, thickness: 0.8),
            pw.SizedBox(height: 10),
            // Annual summary row
            pw.Row(
              children: [
                _pdfKpi('Total Annual Budget', _formatPesoPdf(annualBudget)),
                pw.SizedBox(width: 10),
                _pdfKpi(
                  'Total Annual Released',
                  _formatPesoPdf(annualReleased),
                ),
                pw.SizedBox(width: 10),
                _pdfKpi(
                  'Total Annual Remaining',
                  _formatPesoPdf(annualRemaining),
                  highlight: true,
                ),
              ],
            ),
            pw.SizedBox(height: 14),
            pw.Text(
              'Semester Breakdown - ${_formatDateLabel()}',
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromHex('#101828'),
              ),
            ),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headers: [
                'Academic Year',
                'Semester',
                'Total Budget',
                'Approved Scholars',
                'Cash Assistance',
                'Released',
                'Remaining',
              ],
              data: budgets
                  .map(
                    (b) => [
                      b.academicYearLabel,
                      b.semester,
                      _formatPesoPdf(b.totalBudget),
                      '${approvedFor(b)}',
                      _formatPesoPdf(b.cashPerScholar),
                      _formatPesoPdf(b.released(approvedFor(b))),
                      _formatPesoPdf(b.remaining(approvedFor(b))),
                    ],
                  )
                  .toList(),
              headerStyle: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
                fontSize: 8,
              ),
              headerDecoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#165EF0'),
              ),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellAlignments: {
                0: pw.Alignment.center,
                1: pw.Alignment.center,
                2: pw.Alignment.centerRight,
                3: pw.Alignment.center,
                4: pw.Alignment.centerRight,
                5: pw.Alignment.centerRight,
                6: pw.Alignment.centerRight,
              },
              border: pw.TableBorder.all(
                color: PdfColor.fromHex('#E5E7EB'),
                width: 0.5,
              ),
              headerHeight: 22,
              cellHeight: 20,
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              'Note: Released = Approved Scholars x Cash Assistance. Approved Scholars are counted from each semester\'s records only. Remaining = Total Budget - Released. Approved-only logic; Graduated/Terminated excluded.',
              style: pw.TextStyle(
                fontSize: 7,
                color: PdfColor.fromHex('#66706B'),
              ),
            ),
            pw.Spacer(),
            pw.Divider(color: PdfColors.grey300, thickness: 0.5),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Generated on ${_todayLabel()} | LGU Scholarship Office',
                  style: const pw.TextStyle(
                    fontSize: 7,
                    color: PdfColors.grey600,
                  ),
                ),
                pw.Text(
                  'Confidential - For official use only',
                  style: pw.TextStyle(
                    fontSize: 7,
                    fontStyle: pw.FontStyle.italic,
                    color: PdfColor.fromHex('#66706B'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
      final bytes = await pdf.save();
      await Printing.sharePdf(
        bytes: bytes,
        filename:
            'NSEAP_Budget_Report_${AcademicYearUtils.format(year)}_Semester.pdf',
      );
      if (mounted)
        showAdminMessage(
          context,
          'Budget report ${AcademicYearUtils.format(year)} exported.',
        );
    } catch (_) {
      if (mounted)
        showAdminMessage(context, 'Unable to export report.', error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ── Ready List (Approved Scholars) — simple table ────────────────
  // Fixed: approved = scholar_status approved/scholar/active (per budget logic),
  // plus fallback enrichment of barangay/school via applications when join is empty.
  // Previous error: school/barangay showed "Not recorded" and list was empty when
  // scholar_status had different casing or when data came from applications only.

  List<ScholarRecord> _approvedScholarsForReadyList(
    List<ScholarRecord> all, {
    List<AdminApplication>? applications,
    List<SemesterSubmission>? submissions,
    String? academicYearLabel,
  }) {
    // Primary filter: scholar_status approved/scholar/active (case-insensitive).
    // Exclude graduated/terminated explicitly. Approved list is alphabetical and
    // across all years (simple ready list) — no per-year submission intersection
    // to avoid empty/year-mismatch errors reported.
    Iterable<ScholarRecord> filtered = all.where(
      (s) =>
          _isApprovedStatus(s.status) &&
          !_isGraduatedStatus(s.status) &&
          !_isTerminatedStatus(s.status),
    );
    // If filter yields nothing (e.g., legacy statuses), fallback to include
    // any non-terminated/non-graduated as approved to avoid empty ready list.
    var list = filtered.toList();
    if (list.isEmpty) {
      final fallback = all
          .where(
            (s) =>
                !_isGraduatedStatus(s.status) && !_isTerminatedStatus(s.status),
          )
          .toList();
      // Only use fallback if it has items and primary was truly empty due to status mismatch.
      if (fallback.isNotEmpty && fallback.length != all.length) {
        list = fallback;
      } else if (list.isEmpty && fallback.isEmpty) {
        // No fallback — return primary empty.
      }
    }
    // Enrich missing school/barangay from applications map if provided.
    if (applications != null && applications.isNotEmpty) {
      final appByUser = <String, AdminApplication>{
        for (final a in applications) a.userId: a,
      };
      list = list.map((s) {
        final needsSchool =
            s.school.trim().isEmpty || s.school == 'Not recorded';
        final needsBarangay =
            s.barangay.trim().isEmpty || s.barangay == 'Not recorded';
        final needsScholarId = s.scholarId.trim().isEmpty;
        if (!needsSchool && !needsBarangay && !needsScholarId) return s;
        final app = appByUser[s.userId];
        if (app == null) return s;
        final enrichedBarangay = needsBarangay
            ? _extractBarangayFromAddress(app.address)
            : s.barangay;
        final enrichedSchool = needsSchool && app.school.trim().isNotEmpty
            ? app.school
            : s.school;
        final enrichedScholarId = needsScholarId && app.number.trim().isNotEmpty
            ? app.number
            : s.scholarId;
        if (enrichedBarangay == s.barangay &&
            enrichedSchool == s.school &&
            enrichedScholarId == s.scholarId) {
          return s;
        }
        return ScholarRecord(
          id: s.id,
          userId: s.userId,
          scholarId: enrichedScholarId,
          name: s.name,
          email: s.email,
          status: s.status,
          startedAt: s.startedAt,
          barangay: enrichedBarangay,
          school: enrichedSchool,
        );
      }).toList();
    }
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  String _extractBarangayFromAddress(String address) {
    if (address.trim().isEmpty) return 'Not recorded';
    final parts = address.split(',');
    final first = parts.first.trim();
    if (first.isEmpty) return 'Not recorded';
    // If address contains "Barangay X" try to extract that part.
    for (final p in parts) {
      final t = p.trim();
      if (t.toLowerCase().contains('barangay')) return t;
    }
    return first;
  }

  Future<void> _generateReadyListPdf(List<ScholarRecord> approvedList) async {
    if (approvedList.isEmpty) {
      showAdminMessage(context, 'No approved scholars to generate.');
      return;
    }
    if (_generatingReadyList) return;
    setState(() => _generatingReadyList = true);
    try {
      // Stipend comes from the semester budget input for this year — not a
      // fixed ₱3,000.
      final cash = _stipendForSelectedYear;
      final totalAmount = approvedList.length * cash;
      final ayLabel = AcademicYearUtils.format(_selectedYear);
      final navy = PdfColor.fromHex('#1E293B');
      final primaryBlue = PdfColor.fromHex('#1A56DB');
      final cellPad = const pw.EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 8,
      );

      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.fromLTRB(36, 30, 36, 30),
          header: (_) => pw.Column(
            children: [
              // -- Top row: LGU left, AY badge right --
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'LGU LAL-LO',
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: primaryBlue,
                          letterSpacing: 0.8,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Nueva Segovia Educational Assistance Program',
                        style: pw.TextStyle(
                          fontSize: 7.5,
                          color: PdfColor.fromHex('#64748B'),
                        ),
                      ),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: pw.BoxDecoration(
                      color: primaryBlue,
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Text(
                      ayLabel,
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 9,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 14),
              pw.Divider(color: PdfColors.grey300, thickness: 0.8),
              pw.SizedBox(height: 10),
              // -- Center title block --
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      'PAYROLL SHEET',
                      style: pw.TextStyle(
                        fontSize: 15,
                        fontWeight: pw.FontWeight.bold,
                        color: navy,
                        letterSpacing: 0.6,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Academic Year $ayLabel | Stipend ${_formatPesoPdf(cash)} per scholar',
                      style: pw.TextStyle(
                        fontSize: 8.5,
                        color: PdfColor.fromHex('#475569'),
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      'Total Scholars: ${approvedList.length}',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: primaryBlue,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 14),
            ],
          ),
          footer: (ctx) => pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Generated on ${_todayLabel()} | Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                style: const pw.TextStyle(
                  fontSize: 6,
                  color: PdfColors.grey600,
                ),
              ),
              pw.Text(
                'Confidential - For official use only',
                style: pw.TextStyle(
                  fontSize: 6,
                  fontStyle: pw.FontStyle.italic,
                  color: PdfColor.fromHex('#66706B'),
                ),
              ),
            ],
          ),
          build: (_) => [
            pw.TableHelper.fromTextArray(
              headers: [
                '#',
                'Scholar ID',
                'Name',
                'Barangay',
                'School',
                'Stipend',
                'Signature',
              ],
              data: [
                for (int i = 0; i < approvedList.length; i++)
                  [
                    '${i + 1}',
                    approvedList[i].scholarId.trim().isEmpty
                        ? '-'
                        : approvedList[i].scholarId,
                    approvedList[i].name.trim().isEmpty
                        ? '-'
                        : approvedList[i].name,
                    (approvedList[i].barangay.trim().isEmpty ||
                            approvedList[i].barangay == 'Not recorded')
                        ? '-'
                        : approvedList[i].barangay,
                    (approvedList[i].school.trim().isEmpty ||
                            approvedList[i].school == 'Not recorded')
                        ? '-'
                        : approvedList[i].school,
                    _formatPesoPdf(cash),
                    '',
                  ],
              ],
              headerStyle: pw.TextStyle(
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold,
                color: navy,
              ),
              headerDecoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F1F5F9'),
              ),
              headerPadding: cellPad,
              cellStyle: pw.TextStyle(
                fontSize: 8,
                color: PdfColor.fromHex('#1E293B'),
              ),
              cellPadding: cellPad,
              cellAlignments: {
                0: pw.Alignment.center,
                5: pw.Alignment.centerRight,
                6: pw.Alignment.center,
              },
              columnWidths: {
                0: const pw.FixedColumnWidth(30),
                1: const pw.FixedColumnWidth(110),
                2: const pw.FlexColumnWidth(2.5),
                3: const pw.FlexColumnWidth(1.5),
                4: const pw.FlexColumnWidth(2.0),
                5: const pw.FixedColumnWidth(75),
                6: const pw.FixedColumnWidth(90),
              },
              border: pw.TableBorder.all(
                color: PdfColor.fromHex('#E2E8F0'),
                width: 0.5,
              ),
              oddRowDecoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F8FAFC'),
              ),
            ),
            // Total amount below the table — same column widths so the value
            // sits in the Stipend column with digits aligned to the stipend
            // amounts above.
            pw.TableHelper.fromTextArray(
              data: [
                [
                  '',
                  '',
                  '',
                  '',
                  'TOTAL AMOUNT',
                  _formatPesoPdf(totalAmount),
                  '',
                ],
              ],
              headerCount: 0,
              cellStyle: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: navy,
              ),
              cellPadding: cellPad,
              cellAlignments: {
                4: pw.Alignment.centerRight,
                5: pw.Alignment.centerRight,
              },
              columnWidths: {
                0: const pw.FixedColumnWidth(30),
                1: const pw.FixedColumnWidth(110),
                2: const pw.FlexColumnWidth(2.5),
                3: const pw.FlexColumnWidth(1.5),
                4: const pw.FlexColumnWidth(2.0),
                5: const pw.FixedColumnWidth(75),
                6: const pw.FixedColumnWidth(90),
              },
              border: pw.TableBorder(
                left: pw.BorderSide(
                  color: PdfColor.fromHex('#E2E8F0'),
                  width: 0.5,
                ),
                right: pw.BorderSide(
                  color: PdfColor.fromHex('#E2E8F0'),
                  width: 0.5,
                ),
                bottom: pw.BorderSide(
                  color: PdfColor.fromHex('#E2E8F0'),
                  width: 0.5,
                ),
                verticalInside: pw.BorderSide(
                  color: PdfColor.fromHex('#E2E8F0'),
                  width: 0.5,
                ),
              ),
              rowDecoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F1F5F9'),
              ),
            ),
          ],
        ),
      );
      final bytes = await pdf.save();
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'NSEAP_Payroll_Sheet_${ayLabel.replaceAll('-', '_')}.pdf',
      );
      if (mounted) {
        showAdminMessage(
          context,
          'Payroll sheet generated (${approvedList.length} scholars).',
        );
      }
    } catch (_) {
      if (mounted) {
        showAdminMessage(
          context,
          'Unable to generate payroll sheet.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _generatingReadyList = false);
    }
  }

  static pw.Widget _pdfReadySignBox(String role, String name) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.Text(
        role,
        style: pw.TextStyle(fontSize: 7, color: PdfColor.fromHex('#64748B')),
      ),
      pw.SizedBox(height: 22),
      pw.Container(width: 150, height: 0.7, color: PdfColors.grey600),
      pw.SizedBox(height: 3),
      pw.Text(
        name,
        style: pw.TextStyle(
          fontSize: 7,
          fontWeight: pw.FontWeight.bold,
          color: PdfColor.fromHex('#0F172A'),
        ),
      ),
    ],
  );

  static pw.Widget _pdfKpi(
    String label,
    String value, {
    bool highlight = false,
  }) => pw.Expanded(
    child: pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: highlight ? PdfColor.fromHex('#EFF6FF') : PdfColors.white,
        border: pw.Border.all(color: PdfColor.fromHex('#E5E7EB'), width: 0.6),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 7,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromHex('#66706B'),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromHex(highlight ? '#165EF0' : '#0F172A'),
            ),
          ),
        ],
      ),
    ),
  );

  static String _todayLabel() {
    final d = DateTime.now();
    const m = [
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
    ];
    return '${m[d.month - 1]} ${d.day}, ${d.year}';
  }

  static String _formatDateLabel() {
    final d = DateTime.now();
    return '${d.month}/${d.day}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return AdminAsyncView<AdminReportData>(
      future: _future,
      isEmpty: (_) => false,
      onRetry: _reload,
      builder: (context, data) {
        final yearBudgets = _budgetsForYear(_selectedYear);
        final annualBudget = yearBudgets.fold<double>(
          0,
          (s, b) => s + b.totalBudget,
        );
        final annualReleased = yearBudgets.fold<double>(
          0,
          (s, b) =>
              s +
              b.released(
                _approvedCountForPeriod(
                  b.academicYear,
                  data.scholars,
                  data.submissions,
                  semester: b.semester,
                ),
              ),
        );
        final annualRemaining = annualBudget - annualReleased;
        final readyList = _approvedScholarsForReadyList(
          data.scholars,
          applications: data.applications,
          submissions: data.submissions,
          academicYearLabel: AcademicYearUtils.format(_selectedYear),
        );

        return SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1280),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header — year selector, export, refresh
                    _BudgetReportHeader(
                      selectedYear: _selectedYear,
                      availableYears: _availableYears,
                      onYearChanged: (y) => setState(() => _selectedYear = y),
                      onRefresh: _reload,
                      onExport: () => _exportYear(_selectedYear, data),
                      exporting: _exporting,
                      onNewBudget: () => _showBudgetForm(),
                    ),
                    const SizedBox(height: 16),

                    // Annual Budget Summary — per spec section 10
                    _AnnualBudgetSummary(
                      year: _selectedYear,
                      totalBudget: annualBudget,
                      totalReleased: annualReleased,
                      totalRemaining: annualRemaining,
                      hasBudgets: yearBudgets.isNotEmpty,
                    ),
                    const SizedBox(height: 16),

                    // Semester cards -- 1st & 2nd -- Print replaces Upload Payout
                    _SemesterCardsSection(
                      year: _selectedYear,
                      budgets: yearBudgets,
                      scholars: data.scholars,
                      submissions: data.submissions,
                      onEdit: (b) => _showBudgetForm(existing: b),
                      onDelete: _deleteBudget,
                      onView: (b) => _viewDetails(b, data),
                      onUpload: _uploadSemesterBudgetDocs,
                      repository: widget.repository,
                      docsVersion: _budgetDocsVersion,
                      onPrint: (b) => _printSemesterBudgetReport(
                        b,
                        _totalCount(data.scholars),
                        _approvedCountForPeriod(
                          b.academicYear,
                          data.scholars,
                          data.submissions,
                          semester: b.semester,
                        ),
                        _graduatedCount(data.scholars),
                        _terminatedCount(data.scholars),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Budget Report Table
                    _BudgetReportTable(
                      budgets: _allBudgets,
                      approvedFor: (b) => _approvedCountForPeriod(
                        b.academicYear,
                        data.scholars,
                        data.submissions,
                        semester: b.semester,
                      ),
                      onView: (b) => _viewDetails(b, data),
                      onEdit: (b) => _showBudgetForm(existing: b),
                      onUpload: _uploadSemesterBudgetDocs,
                      onPrint: (b) => _printSemesterBudgetReport(
                        b,
                        _totalCount(data.scholars),
                        _approvedCountForPeriod(
                          b.academicYear,
                          data.scholars,
                          data.submissions,
                          semester: b.semester,
                        ),
                        _graduatedCount(data.scholars),
                        _terminatedCount(data.scholars),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Ready List — per-scholar payroll report
                    _ReadyListSection(
                      approvedScholars: readyList,
                      stipend: _stipendForSelectedYear,
                      academicYearLabel: AcademicYearUtils.format(
                        _selectedYear,
                      ),
                      isGenerating: _generatingReadyList,
                      onGenerate: () => _generateReadyListPdf(readyList),
                    ),
                    const SizedBox(height: 18),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _BudgetReportHeader extends StatelessWidget {
  const _BudgetReportHeader({
    required this.selectedYear,
    required this.availableYears,
    required this.onYearChanged,
    required this.onRefresh,
    required this.onExport,
    required this.exporting,
    required this.onNewBudget,
  });

  final int selectedYear;
  final List<int> availableYears;
  final ValueChanged<int> onYearChanged;
  final VoidCallback onRefresh;
  final VoidCallback onExport;
  final bool exporting;
  final VoidCallback onNewBudget;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NseapBudgetColors.cardBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final narrow = c.maxWidth < 760;
          final title = const Text(
            'Budget Report',
            style: TextStyle(
              color: NseapBudgetColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              height: 1.1,
            ),
          );
          final controls = Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              NseapYearSelector(
                value: selectedYear,
                years: availableYears,
                onChanged: onYearChanged,
              ),
              NseapExportButton(onPressed: onExport, exporting: exporting),
              IconButton(
                tooltip: 'Refresh',
                onPressed: onRefresh,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: NseapBudgetColors.cardBorder),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  fixedSize: const Size(42, 42),
                ),
                icon: const Icon(
                  Icons.refresh_rounded,
                  size: 18,
                  color: NseapBudgetColors.textSecondary,
                ),
              ),
              FilledButton.icon(
                onPressed: onNewBudget,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text(
                  'New Semester Budget',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: NseapBudgetColors.green,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          );
          if (narrow)
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [title, const SizedBox(height: 16), controls],
            );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: title),
              const SizedBox(width: 18),
              controls,
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Annual Summary — spec 10
// ─────────────────────────────────────────────────────────────────────────────

class _AnnualBudgetSummary extends StatelessWidget {
  const _AnnualBudgetSummary({
    required this.year,
    required this.totalBudget,
    required this.totalReleased,
    required this.totalRemaining,
    required this.hasBudgets,
  });

  final int year;
  final double totalBudget;
  final double totalReleased;
  final double totalRemaining;
  final bool hasBudgets;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NseapBudgetColors.cardBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080F172A),
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
              Expanded(
                child: Text(
                  '${AcademicYearUtils.format(year)} Annual Budget',
                  style: const TextStyle(
                    color: NseapBudgetColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              if (!hasBudgets)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Color(0xFFFECACA)),
                  ),
                  child: const Text(
                    'No budgets yet',
                    style: TextStyle(
                      color: Color(0xFFB42318),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, c) {
              final triple = [
                _AnnualKpi(
                  label: 'Total Budget',
                  value: _formatPeso(totalBudget),
                ),
                _AnnualKpi(
                  label: 'Total Released',
                  value: _formatPeso(totalReleased),
                ),
                _AnnualKpi(
                  label: 'Total Remaining',
                  value: _formatPeso(totalRemaining),
                  isHighlighted: true,
                  isNegative: totalRemaining < 0,
                ),
              ];
              if (c.maxWidth < 720) {
                return Column(
                  children: [
                    for (final k in triple)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: k,
                      ),
                  ],
                );
              }
              return Row(
                children: [
                  for (int i = 0; i < triple.length; i++) ...[
                    Expanded(child: triple[i]),
                    if (i != 2) const SizedBox(width: 12),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AnnualKpi extends StatelessWidget {
  const _AnnualKpi({
    required this.label,
    required this.value,
    this.isHighlighted = false,
    this.isNegative = false,
  });
  final String label;
  final String value;
  final bool isHighlighted;
  final bool isNegative;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: isHighlighted
            ? (isNegative ? const Color(0xFFFEF2F2) : const Color(0xFFEFF6FF))
            : NseapBudgetColors.lightGrayBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isNegative
              ? const Color(0xFFFECACA)
              : NseapBudgetColors.cardBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: NseapBudgetColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                color: isNegative
                    ? const Color(0xFFB42318)
                    : isHighlighted
                    ? NseapBudgetColors.green
                    : NseapBudgetColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Semester Cards Section
// ─────────────────────────────────────────────────────────────────────────────

class _SemesterCardsSection extends StatelessWidget {
  const _SemesterCardsSection({
    required this.year,
    required this.budgets,
    required this.scholars,
    required this.submissions,
    required this.onEdit,
    required this.onDelete,
    required this.onPrint,
    required this.onView,
    required this.onUpload,
    required this.repository,
    required this.docsVersion,
  });

  final int year;
  final List<SemesterBudget> budgets;
  final List<ScholarRecord> scholars;
  final List<SemesterSubmission> submissions;
  final ValueChanged<SemesterBudget> onEdit;
  final ValueChanged<SemesterBudget> onDelete;
  final ValueChanged<SemesterBudget> onPrint;
  final ValueChanged<SemesterBudget> onView;
  final ValueChanged<SemesterBudget> onUpload;
  final AdminRepository repository;
  final int docsVersion;

  int _approvedForYear(int year, String semester) =>
      _approvedCountForPeriod(year, scholars, submissions, semester: semester);

  int get _totalCount => scholars.length;
  int get _graduatedCount =>
      scholars.where((s) => s.status == 'graduated').length;
  int get _terminatedCount =>
      scholars.where((s) => s.status == 'terminated').length;

  @override
  Widget build(BuildContext context) {
    SemesterBudget? b1;
    SemesterBudget? b2;
    for (final b in budgets) {
      if (b.semester == '1st Semester') b1 = b;
      if (b.semester == '2nd Semester') b2 = b;
    }

    return LayoutBuilder(
      builder: (context, c) {
        final isNarrow = c.maxWidth < 760;
        final cards = [
          _SemesterBudgetCard(
            budget: b1,
            fallbackYear: year,
            fallbackSemester: '1st Semester',
            approved: b1 != null
                ? _approvedForYear(b1.academicYear, b1.semester)
                : 0,
            totalScholars: _totalCount,
            graduatedScholars: _graduatedCount,
            terminatedScholars: _terminatedCount,
            onEdit: onEdit,
            onDelete: b1 == null ? null : () => onDelete(b1!),
            onPrint: b1 == null ? null : () => onPrint(b1!),
            onView: b1 == null ? null : () => onView(b1!),
            onUpload: b1 == null ? null : () => onUpload(b1!),
            repository: repository,
            docsVersion: docsVersion,
          ),
          _SemesterBudgetCard(
            budget: b2,
            fallbackYear: year,
            fallbackSemester: '2nd Semester',
            approved: b2 != null
                ? _approvedForYear(b2.academicYear, b2.semester)
                : 0,
            totalScholars: _totalCount,
            graduatedScholars: _graduatedCount,
            terminatedScholars: _terminatedCount,
            onEdit: onEdit,
            onDelete: b2 == null ? null : () => onDelete(b2!),
            onPrint: b2 == null ? null : () => onPrint(b2!),
            onView: b2 == null ? null : () => onView(b2!),
            onUpload: b2 == null ? null : () => onUpload(b2!),
            repository: repository,
            docsVersion: docsVersion,
          ),
        ];
        if (isNarrow) {
          return Column(
            children: [cards[0], const SizedBox(height: 12), cards[1]],
          );
        }
        return Row(
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 14),
            Expanded(child: cards[1]),
          ],
        );
      },
    );
  }
}

class _SemesterBudgetCard extends StatelessWidget {
  const _SemesterBudgetCard({
    required this.budget,
    required this.fallbackYear,
    required this.fallbackSemester,
    required this.approved,
    required this.totalScholars,
    required this.graduatedScholars,
    required this.terminatedScholars,
    required this.onEdit,
    required this.onDelete,
    required this.onPrint,
    required this.onView,
    required this.onUpload,
    required this.repository,
    required this.docsVersion,
  });

  final SemesterBudget? budget;
  final int fallbackYear;
  final String fallbackSemester;
  final int approved;
  final int totalScholars;
  final int graduatedScholars;
  final int terminatedScholars;
  final ValueChanged<SemesterBudget> onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onPrint;
  final VoidCallback? onView;
  final VoidCallback? onUpload;
  final AdminRepository repository;
  final int docsVersion;

  @override
  Widget build(BuildContext context) {
    final isEmpty = budget == null;
    final b = budget;
    final released = b == null ? 0.0 : b.released(approved);
    final remaining = b == null ? 0.0 : b.remaining(approved);
    final exceeds = b != null && released > b.totalBudget;

    if (isEmpty) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: NseapBudgetColors.cardBorder,
            style: BorderStyle.solid,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x080F172A),
              blurRadius: 14,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              fallbackSemester,
              style: const TextStyle(
                color: NseapBudgetColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              'No budget set',
              style: const TextStyle(
                color: NseapBudgetColors.textSecondary,
                fontSize: 11.5,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              decoration: BoxDecoration(
                color: NseapBudgetColors.lightGrayBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: NseapBudgetColors.cardBorder),
              ),
              child: const Column(
                children: [
                  Text(
                    'No budget record for this semester.',
                    style: TextStyle(
                      color: NseapBudgetColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Create one to start monitoring.',
                    style: TextStyle(
                      color: NseapBudgetColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => onEdit(
                SemesterBudget(
                  academicYear: fallbackYear,
                  semester: fallbackSemester,
                  totalBudget: 0,
                  cashPerScholar: 0,
                ),
              ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text(
                'Create Budget',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: NseapBudgetColors.green,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final data = b!;
    final dataSemester = data.semester;
    final dataTotal = data.totalBudget;
    final dataCash = data.cashPerScholar;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: exceeds
              ? const Color(0xFFFECACA)
              : NseapBudgetColors.cardBorder,
          width: exceeds ? 1.2 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080F172A),
            blurRadius: 14,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with 3-dot menu: Upload, View details, Edit, Export, Delete
          Row(
            children: [
              Expanded(
                child: Text(
                  dataSemester,
                  style: const TextStyle(
                    color: NseapBudgetColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Semester budget actions',
                icon: const Icon(
                  Icons.more_vert_rounded,
                  color: NseapBudgetColors.textSecondary,
                ),
                onSelected: (value) {
                  if (value == 'upload') onUpload?.call();
                  if (value == 'view') onView?.call();
                  if (value == 'edit') onEdit(data);
                  if (value == 'print') onPrint?.call();
                  if (value == 'delete') onDelete?.call();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'upload',
                    child: Row(
                      children: [
                        Icon(Icons.upload_file_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('Upload documents'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'view',
                    child: Row(
                      children: [
                        Icon(Icons.visibility_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('View details'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Edit budget'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'print',
                    child: Row(
                      children: [
                        Icon(Icons.picture_as_pdf_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Export PDF'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                          color: Color(0xFFB42318),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Delete budget',
                          style: TextStyle(color: Color(0xFFB42318)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: NseapBudgetColors.cardBorder),
          const SizedBox(height: 12),

          // Amount rows — spec 10: Budget, Approved, Released, Remaining
          _SemesterRow(label: 'Budget', value: _formatPeso(dataTotal)),
          const SizedBox(height: 8),
          _SemesterRow(label: 'Approved Scholars', value: _formatInt(approved)),
          const SizedBox(height: 8),
          _SemesterRow(label: 'Stipend', value: _formatPeso(dataCash)),
          const SizedBox(height: 8),
          _SemesterRow(
            label: 'Released',
            value: _formatPeso(released),
            valueStyle: const TextStyle(
              color: NseapBudgetColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: exceeds
                  ? const Color(0xFFFEF2F2)
                  : const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: exceeds
                    ? const Color(0xFFFECACA)
                    : NseapBudgetColors.green.withValues(alpha: 0.18),
              ),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'REMAINING',
                    style: TextStyle(
                      color: NseapBudgetColors.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                Text(
                  _formatPeso(remaining),
                  style: TextStyle(
                    color: exceeds
                        ? const Color(0xFFB42318)
                        : NseapBudgetColors.green,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          if (exceeds) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: Color(0xFFB42318),
                  ),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Warning: The calculated scholarship assistance exceeds the available semester budget.',
                      style: TextStyle(
                        color: Color(0xFFB42318),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          InkWell(
            onTap: onView,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: NseapBudgetColors.lightGrayBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: NseapBudgetColors.cardBorder),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.attach_file_rounded,
                    size: 16,
                    color: NseapBudgetColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _BudgetDocCount(
                      repository: repository,
                      academicYear: data.academicYearLabel,
                      semester: dataSemester,
                      version: docsVersion,
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: NseapBudgetColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows how many persisted supporting documents a semester budget has.
class _BudgetDocCount extends StatefulWidget {
  const _BudgetDocCount({
    required this.repository,
    required this.academicYear,
    required this.semester,
    required this.version,
  });

  final AdminRepository repository;
  final String academicYear;
  final String semester;
  final int version;

  @override
  State<_BudgetDocCount> createState() => _BudgetDocCountState();
}

class _BudgetDocCountState extends State<_BudgetDocCount>
    with RealtimeSyncMixin {
  @override
  Set<String> get realtimeTables => const {'budget_supporting_documents'};
  @override
  Future<void> refreshRealtime() => _load();
  int? _count;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _BudgetDocCount oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.version != widget.version ||
        oldWidget.academicYear != widget.academicYear ||
        oldWidget.semester != widget.semester) {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final docs = await widget.repository.getBudgetSupportingDocuments(
        academicYear: widget.academicYear,
        semester: widget.semester,
      );
      if (!mounted) return;
      setState(() => _count = docs.length);
    } catch (_) {
      if (mounted) setState(() => _count = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _count;
    return Text(
      count == null
          ? 'Loading supporting documents…'
          : count == 0
          ? 'No supporting documents yet'
          : '$count supporting document${count == 1 ? '' : 's'}',
      style: const TextStyle(
        color: NseapBudgetColors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// Lists the persisted supporting documents for one semester budget with
/// view, download, and remove actions.
class _BudgetDocListSection extends StatefulWidget {
  const _BudgetDocListSection({
    required this.repository,
    required this.academicYear,
    required this.semester,
    required this.version,
    required this.onView,
    required this.onDownload,
    required this.onDelete,
  });

  final AdminRepository repository;
  final String academicYear;
  final String semester;
  final int version;
  final ValueChanged<BudgetSupportingDocument> onView;
  final ValueChanged<BudgetSupportingDocument> onDownload;
  final ValueChanged<BudgetSupportingDocument> onDelete;

  @override
  State<_BudgetDocListSection> createState() => _BudgetDocListSectionState();
}

class _BudgetDocListSectionState extends State<_BudgetDocListSection>
    with RealtimeSyncMixin {
  @override
  Set<String> get realtimeTables => const {'budget_supporting_documents'};
  @override
  Future<void> refreshRealtime() async => setState(() => _future = _load());
  late Future<List<BudgetSupportingDocument>> _future = _load();

  Future<List<BudgetSupportingDocument>> _load() =>
      widget.repository.getBudgetSupportingDocuments(
        academicYear: widget.academicYear,
        semester: widget.semester,
      );

  @override
  void didUpdateWidget(covariant _BudgetDocListSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.version != widget.version ||
        oldWidget.academicYear != widget.academicYear ||
        oldWidget.semester != widget.semester) {
      setState(() => _future = _load());
    }
  }

  IconData _iconFor(String fileType) => switch (fileType) {
    'pdf' => Icons.picture_as_pdf_rounded,
    'xlsx' || 'csv' => Icons.table_chart_rounded,
    'png' || 'jpg' || 'jpeg' => Icons.image_rounded,
    _ => Icons.description_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<BudgetSupportingDocument>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: NseapBudgetColors.lightGrayBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: NseapBudgetColors.cardBorder),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Loading supporting documents…',
                    style: TextStyle(
                      color: NseapBudgetColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        if (snapshot.hasError) {
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Could not load supporting documents.',
                    style: TextStyle(color: Color(0xFFB42318), fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _future = _load()),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        final docs = snapshot.data ?? const <BudgetSupportingDocument>[];
        if (docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: NseapBudgetColors.lightGrayBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: NseapBudgetColors.cardBorder),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.upload_file_rounded,
                  size: 20,
                  color: NseapBudgetColors.textSecondary,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No supporting documents yet. Use Upload to attach payroll sheets, disbursement proofs, or receipts.',
                    style: TextStyle(
                      color: NseapBudgetColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        return Column(
          children: [
            for (final doc in docs) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: NseapBudgetColors.cardBorder),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: NseapBudgetColors.greenSoft,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: NseapBudgetColors.green.withValues(
                                alpha: 0.14,
                              ),
                            ),
                          ),
                          child: Icon(
                            _iconFor(doc.fileType),
                            color: NseapBudgetColors.green,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                doc.fileName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${doc.fileType.toUpperCase()} | ${_ReportsAdminPageState._formatFileSize(doc.fileSize)} | ${doc.uploadedBy}',
                                style: const TextStyle(
                                  color: NseapBudgetColors.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'View',
                          onPressed: () => widget.onView(doc),
                          icon: const Icon(Icons.visibility_outlined, size: 18),
                        ),
                        IconButton(
                          tooltip: 'Download',
                          onPressed: () => widget.onDownload(doc),
                          icon: const Icon(Icons.download_rounded, size: 18),
                        ),
                        IconButton(
                          tooltip: 'Remove',
                          onPressed: () => widget.onDelete(doc),
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                            color: Color(0xFFB42318),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    _BudgetDetailsDialog._detailKeyValue(
                      'Upload date',
                      _ReportsAdminPageState._formatDateTime(doc.uploadedAt),
                    ),
                    _BudgetDetailsDialog._detailKeyValue(
                      'Uploaded by',
                      doc.uploadedBy,
                    ),
                  ],
                ),
              ),
              if (doc != docs.last) const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }
}

class _SemesterRow extends StatelessWidget {
  const _SemesterRow({
    required this.label,
    required this.value,
    this.sub,
    this.valueStyle,
  });
  final String label;
  final String value;
  final String? sub;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: NseapBudgetColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              value,
              style:
                  valueStyle ??
                  const TextStyle(
                    color: NseapBudgetColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            if (sub != null)
              Text(
                sub!,
                style: const TextStyle(
                  color: NseapBudgetColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Budget Report Table — spec 11
// ─────────────────────────────────────────────────────────────────────────────

class _BudgetReportTable extends StatelessWidget {
  const _BudgetReportTable({
    required this.budgets,
    required this.approvedFor,
    required this.onView,
    required this.onEdit,
    required this.onPrint,
    required this.onUpload,
  });
  final List<SemesterBudget> budgets;
  final int Function(SemesterBudget budget) approvedFor;
  final ValueChanged<SemesterBudget> onView;
  final ValueChanged<SemesterBudget> onEdit;
  final ValueChanged<SemesterBudget> onPrint;
  final ValueChanged<SemesterBudget> onUpload;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NseapBudgetColors.cardBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(
                bottom: BorderSide(color: NseapBudgetColors.cardBorder),
              ),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Budget Report Table',
                    style: TextStyle(
                      color: NseapBudgetColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: NseapBudgetColors.greenSoft,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: NseapBudgetColors.green.withValues(alpha: 0.14),
                    ),
                  ),
                  child: Text(
                    '${budgets.length} record${budgets.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      color: NseapBudgetColors.green,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (budgets.isEmpty)
            const SizedBox(
              height: 160,
              child: AdminStatePanel.empty(
                title: 'No budgets yet',
                message:
                    'Create a semester budget to populate the report table.',
              ),
            )
          else
            LayoutBuilder(
              builder: (context, c) {
                if (c.maxWidth < 820) {
                  // Mobile cards
                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(12),
                    itemCount: budgets.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final b = budgets[i];
                      final approved = approvedFor(b);
                      final released = b.released(approved);
                      final remaining = b.remaining(approved);
                      final exceeds = released > b.totalBudget;
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: exceeds
                                ? const Color(0xFFFECACA)
                                : NseapBudgetColors.cardBorder,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: NseapBudgetColors.greenSoft,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '${b.academicYearLabel} | ${b.semester}',
                                    style: const TextStyle(
                                      color: NseapBudgetColors.green,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                if (exceeds)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEF2F2),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: const Color(0xFFFECACA),
                                      ),
                                    ),
                                    child: const Text(
                                      'Exceeds budget',
                                      style: TextStyle(
                                        color: Color(0xFFB42318),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _mobileRow(
                              'Total Budget',
                              _formatPeso(b.totalBudget),
                            ),
                            _mobileRow(
                              'Approved Scholars',
                              _formatInt(approved),
                            ),
                            _mobileRow(
                              'Stipend',
                              _formatPeso(b.cashPerScholar),
                            ),
                            _mobileRow('Released', _formatPeso(released)),
                            _mobileRow(
                              'Remaining',
                              _formatPeso(remaining),
                              highlight: true,
                              negative: exceeds,
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => onView(b),
                                    icon: const Icon(
                                      Icons.visibility_outlined,
                                      size: 16,
                                    ),
                                    label: const Text('View'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  tooltip: 'Upload documents',
                                  onPressed: () => onUpload(b),
                                  icon: const Icon(
                                    Icons.upload_file_rounded,
                                    size: 16,
                                  ),
                                  style: IconButton.styleFrom(
                                    backgroundColor:
                                        NseapBudgetColors.lightGrayBg,
                                    side: const BorderSide(
                                      color: NseapBudgetColors.cardBorder,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  onPressed: () => onEdit(b),
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 16,
                                  ),
                                  style: IconButton.styleFrom(
                                    backgroundColor:
                                        NseapBudgetColors.lightGrayBg,
                                    side: const BorderSide(
                                      color: NseapBudgetColors.cardBorder,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  );
                }
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(
                      const Color(0xFFF8FAFC),
                    ),
                    headingRowHeight: 44,
                    dataRowMinHeight: 56,
                    dataRowMaxHeight: 56,
                    horizontalMargin: 16,
                    columnSpacing: 18,
                    headingTextStyle: const TextStyle(
                      color: NseapBudgetColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                    dataTextStyle: const TextStyle(
                      color: NseapBudgetColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    columns: const [
                      DataColumn(label: Text('ACADEMIC YEAR')),
                      DataColumn(label: Text('SEMESTER')),
                      DataColumn(label: Text('TOTAL BUDGET'), numeric: true),
                      DataColumn(
                        label: Text('APPROVED SCHOLARS'),
                        numeric: true,
                      ),
                      DataColumn(label: Text('STIPEND'), numeric: true),
                      DataColumn(label: Text('RELEASED'), numeric: true),
                      DataColumn(label: Text('REMAINING'), numeric: true),
                      DataColumn(label: Text('ACTION')),
                    ],
                    rows: budgets.map((b) {
                      final approved = approvedFor(b);
                      final released = b.released(approved);
                      final remaining = b.remaining(approved);
                      final exceeds = released > b.totalBudget;
                      return DataRow(
                        cells: [
                          DataCell(
                            Text(
                              b.academicYearLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          DataCell(Text(b.semester)),
                          DataCell(Text(_formatPeso(b.totalBudget))),
                          DataCell(Text(_formatInt(approved))),
                          DataCell(Text(_formatPeso(b.cashPerScholar))),
                          DataCell(Text(_formatPeso(released))),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: exceeds
                                    ? const Color(0xFFFEF2F2)
                                    : const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: exceeds
                                      ? const Color(0xFFFECACA)
                                      : NseapBudgetColors.green.withValues(
                                          alpha: 0.18,
                                        ),
                                ),
                              ),
                              child: Text(
                                _formatPeso(remaining),
                                style: TextStyle(
                                  color: exceeds
                                      ? const Color(0xFFB42318)
                                      : NseapBudgetColors.green,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'View details',
                                  onPressed: () => onView(b),
                                  icon: const Icon(
                                    Icons.visibility_outlined,
                                    size: 16,
                                  ),
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    side: const BorderSide(
                                      color: NseapBudgetColors.cardBorder,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                PopupMenuButton<String>(
                                  onSelected: (v) {
                                    if (v == 'edit') onEdit(b);
                                    if (v == 'print') onPrint(b);
                                    if (v == 'view') onView(b);
                                    if (v == 'upload') onUpload(b);
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: 'upload',
                                      child: Text('Upload documents'),
                                    ),
                                    PopupMenuItem(
                                      value: 'view',
                                      child: Text('View Details'),
                                    ),
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Text('Edit Budget'),
                                    ),
                                    PopupMenuItem(
                                      value: 'print',
                                      child: Text('Export'),
                                    ),
                                  ],
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
  }

  static Widget _mobileRow(
    String label,
    String value, {
    bool highlight = false,
    bool negative = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: NseapBudgetColors.textSecondary,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: highlight
                ? (negative ? const Color(0xFFB42318) : NseapBudgetColors.green)
                : NseapBudgetColors.textPrimary,
            fontSize: 12.5,
            fontWeight: highlight ? FontWeight.w800 : FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable: Year Selector & Export Button (kept compatible)
// ─────────────────────────────────────────────────────────────────────────────

class NseapYearSelector extends StatelessWidget {
  const NseapYearSelector({
    required this.value,
    required this.years,
    required this.onChanged,
    super.key,
  });
  final int value;
  final List<int> years;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: NseapBudgetColors.lightGrayBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NseapBudgetColors.cardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 8),
          const Text(
            'Academic Year',
            style: TextStyle(
              color: NseapBudgetColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: NseapBudgetColors.cardBorder),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: value,
                icon: const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: NseapBudgetColors.textSecondary,
                  ),
                ),
                style: const TextStyle(
                  color: NseapBudgetColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
                borderRadius: BorderRadius.circular(10),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                items: years
                    .map(
                      (y) => DropdownMenuItem(
                        value: y,
                        child: Text(
                          '$y-${y + 1}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) onChanged(v);
                },
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

class NseapExportButton extends StatelessWidget {
  const NseapExportButton({
    required this.onPressed,
    this.exporting = false,
    super.key,
  });
  final VoidCallback onPressed;
  final bool exporting;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 42,
    child: FilledButton.icon(
      onPressed: exporting ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: NseapBudgetColors.green,
        foregroundColor: Colors.white,
        disabledBackgroundColor: NseapBudgetColors.green.withValues(alpha: 0.6),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 0,
      ),
      icon: exporting
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.picture_as_pdf_rounded, size: 18),
      label: Text(
        exporting ? 'Exporting...' : 'Export Report',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Budget Form Dialog — validation per spec 14
// ─────────────────────────────────────────────────────────────────────────────

class _SemesterBudgetFormDialog extends StatefulWidget {
  const _SemesterBudgetFormDialog({
    this.existing,
    required this.existingKeys,
    this.approvedCountForPeriod,
  });
  final SemesterBudget? existing;
  final Set<String> existingKeys;

  /// Returns the number of Approved Scholars recorded for the given academic
  /// period start year. Null when the report data is unavailable (the
  /// no-approved-scholars check is then skipped).
  final int Function(int year)? approvedCountForPeriod;

  @override
  State<_SemesterBudgetFormDialog> createState() =>
      _SemesterBudgetFormDialogState();
}

class _SemesterBudgetFormDialogState extends State<_SemesterBudgetFormDialog> {
  late String _semester;
  late final TextEditingController _periodCtrl;
  late final TextEditingController _budgetCtrl;
  late final TextEditingController _cashCtrl;
  String? _periodError;
  String? _budgetError;
  String? _cashError;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _semester = e?.semester ?? '1st Semester';
    _periodCtrl = TextEditingController(
      text: e == null ? '' : AcademicYearUtils.format(e.academicYear),
    );
    _budgetCtrl = TextEditingController(
      text: e == null || e.totalBudget == 0
          ? ''
          : e.totalBudget.toStringAsFixed(0),
    );
    _cashCtrl = TextEditingController(
      text: e == null || e.cashPerScholar == 0
          ? ''
          : e.cashPerScholar.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _periodCtrl.dispose();
    _budgetCtrl.dispose();
    _cashCtrl.dispose();
    super.dispose();
  }

  double _parse(String s) =>
      double.tryParse(s.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;

  Future<void> _save() async {
    final period = _periodCtrl.text.trim();
    final budget = _parse(_budgetCtrl.text);
    final cash = _parse(_cashCtrl.text);
    final hasError = <String, String?>{};
    if (period.isEmpty) {
      hasError['period'] = 'Academic Period is required.';
    } else if (!RegExp(r'^\d{4}\s*[-–]\s*\d{4}$').hasMatch(period)) {
      hasError['period'] = 'Use format YYYY-YYYY, e.g. 2026-2027.';
    }
    if (budget <= 0)
      hasError['budget'] = 'Total Budget must be greater than ₱0.';
    if (cash <= 0)
      hasError['cash'] = 'Cash Assistance must be greater than ₱0.';

    int? year;
    if (hasError['period'] == null) {
      year = int.parse(period.substring(0, 4));
      final key = '$year-$_semester';
      final isDuplicate =
          widget.existing?.key != key && widget.existingKeys.contains(key);
      if (isDuplicate)
        hasError['duplicate'] =
            'Budget for $key already exists. Edit the existing record instead.';
    }

    setState(() {
      _periodError = hasError['period'];
      _budgetError = hasError['budget'];
      _cashError = hasError['cash'];
    });
    if (hasError.isNotEmpty) {
      if (hasError['duplicate'] != null) {
        showAdminMessage(context, hasError['duplicate']!, error: true);
      }
      return;
    }
    final result = SemesterBudget(
      academicYear: year!,
      semester: _semester,
      totalBudget: budget,
      cashPerScholar: cash,
      payoutFile: widget.existing?.payoutFile,
    );
    // Creating a budget for an academic period with no Approved Scholars
    // records: warn before creating (counts stay 0 until records exist).
    if (!widget.existingKeys.contains(result.key)) {
      final approvedForPeriod = widget.approvedCountForPeriod?.call(
        result.academicYear,
      );
      if (approvedForPeriod != null && approvedForPeriod == 0) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              'No Approved Scholars Record',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            content: Text(
              'There are currently no approved scholars recorded for the '
              '${AcademicYearUtils.format(result.academicYear).replaceFirst('-', '–')} '
              'academic period. The beneficiary count and released amount '
              'will remain at 0 until approved scholar records are available '
              'for this academic period.',
              style: const TextStyle(
                color: NseapBudgetColors.textSecondary,
                height: 1.5,
                fontSize: 13.5,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: NseapBudgetColors.green,
                ),
                child: const Text('Continue'),
              ),
            ],
          ),
        );
        if (proceed != true) return;
      }
    }
    if (!mounted) return;
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        isEdit ? 'Edit Semester Budget' : 'New Semester Budget',
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _periodCtrl,
                decoration: InputDecoration(
                  labelText: 'Academic Period *',
                  hintText: 'e.g., 2026-2027',
                  border: const OutlineInputBorder(),
                  errorText: _periodError,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _semester,
                decoration: const InputDecoration(
                  labelText: 'Semester *',
                  border: OutlineInputBorder(),
                ),
                items: const ['1st Semester', '2nd Semester']
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setState(() => _semester = v ?? _semester),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _budgetCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Total Budget *',
                  hintText: 'e.g., 400000',
                  prefixText: '₱ ',
                  border: const OutlineInputBorder(),
                  errorText: _budgetError,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _cashCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Cash Assistance per Scholar *',
                  hintText: 'e.g., 3000',
                  prefixText: '₱ ',
                  border: const OutlineInputBorder(),
                  errorText: _cashError,
                ),
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
          onPressed: _save,
          style: FilledButton.styleFrom(
            backgroundColor: NseapBudgetColors.green,
          ),
          child: Text(isEdit ? 'Update' : 'Create'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Budget Details Dialog — spec 12
// ─────────────────────────────────────────────────────────────────────────────

class _BudgetDetailsDialog extends StatelessWidget {
  const _BudgetDetailsDialog({
    required this.budget,
    required this.approved,
    required this.total,
    required this.graduated,
    required this.terminated,
    this.onUpload,
    this.onPrint,
    this.onViewFile,
    this.onDownloadFile,
    this.repository,
    this.docsVersion = 0,
    this.onUploadDoc,
    this.onViewDoc,
    this.onDownloadDoc,
    this.onDeleteDoc,
  });

  final SemesterBudget budget;
  final int approved;
  final int total;
  final int graduated;
  final int terminated;
  final VoidCallback? onUpload;
  final VoidCallback? onPrint;
  final VoidCallback? onViewFile;
  final VoidCallback? onDownloadFile;
  final AdminRepository? repository;
  final int docsVersion;
  final VoidCallback? onUploadDoc;
  final ValueChanged<BudgetSupportingDocument>? onViewDoc;
  final ValueChanged<BudgetSupportingDocument>? onDownloadDoc;
  final ValueChanged<BudgetSupportingDocument>? onDeleteDoc;

  @override
  Widget build(BuildContext context) {
    final released = budget.released(approved);
    final remaining = budget.remaining(approved);
    final exceeds = released > budget.totalBudget;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 820),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
              decoration: const BoxDecoration(
                color: NseapBudgetColors.green,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${budget.academicYearLabel} • ${budget.semester}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Budget Information
                    _DetailsSection(
                      title: 'Budget Information',
                      child: _InfoGrid(
                        values: {
                          'Academic Year': budget.academicYearLabel,
                          'Semester': budget.semester,
                          'Total Budget': _formatPeso(budget.totalBudget),
                          'Cash Assistance per Scholar': _formatPeso(
                            budget.cashPerScholar,
                          ),
                        },
                      ),
                    ),
                    // Scholar Information — spec 12: Total, Approved, Graduated, Terminated
                    _DetailsSection(
                      title: 'Scholar Information',
                      child: _InfoGrid(
                        values: {
                          'Total Scholars': _formatInt(total),
                          'Approved Scholars': _formatInt(approved),
                          'Graduated': _formatInt(graduated),
                          'Terminated': _formatInt(terminated),
                        },
                      ),
                    ),
                    // Computation
                    _DetailsSection(
                      title: 'Computation',
                      child: Column(
                        children: [
                          _InfoGrid(
                            values: {
                              'Approved Scholars': _formatInt(approved),
                              'Cash Assistance': _formatPeso(
                                budget.cashPerScholar,
                              ),
                              'Total Released Amount': _formatPeso(released),
                              'Remaining Budget': _formatPeso(remaining),
                            },
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: exceeds
                                  ? const Color(0xFFFEF2F2)
                                  : const Color(0xFFF0FDF4),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: exceeds
                                    ? const Color(0xFFFECACA)
                                    : NseapBudgetColors.green.withValues(
                                        alpha: 0.18,
                                      ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  exceeds
                                      ? Icons.warning_amber_rounded
                                      : Icons.check_circle_outline_rounded,
                                  size: 16,
                                  color: exceeds
                                      ? const Color(0xFFB42318)
                                      : NseapBudgetColors.green,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    exceeds
                                        ? 'Warning: The calculated scholarship assistance exceeds the available semester budget.'
                                        : 'Formula: Approved ($approved) x ${_formatPeso(budget.cashPerScholar)} = ${_formatPeso(released)} -> Remaining = ${_formatPeso(budget.totalBudget)} - ${_formatPeso(released)}',
                                    style: TextStyle(
                                      color: exceeds
                                          ? const Color(0xFFB42318)
                                          : NseapBudgetColors.green,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                        ],
                      ),
                    ),
                    // Supporting Documents -- persisted per semester budget
                    _DetailsSection(
                      title: 'Supporting Documents',
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          OutlinedButton.icon(
                            onPressed: onUploadDoc,
                            icon: const Icon(
                              Icons.upload_file_rounded,
                              size: 16,
                            ),
                            label: const Text(
                              'Upload',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: NseapBudgetColors.green,
                              side: BorderSide(
                                color: NseapBudgetColors.green.withValues(
                                  alpha: 0.4,
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: onPrint,
                            icon: const Icon(
                              Icons.picture_as_pdf_outlined,
                              size: 16,
                            ),
                            label: const Text(
                              'Export',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: NseapBudgetColors.green,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (repository != null &&
                              onViewDoc != null &&
                              onDownloadDoc != null &&
                              onDeleteDoc != null)
                            _BudgetDocListSection(
                              repository: repository!,
                              academicYear: budget.academicYearLabel,
                              semester: budget.semester,
                              version: docsVersion,
                              onView: onViewDoc!,
                              onDownload: onDownloadDoc!,
                              onDelete: onDeleteDoc!,
                            ),
                          if (budget.payoutFile == null &&
                              (repository == null ||
                                  onViewDoc == null ||
                                  onDownloadDoc == null ||
                                  onDeleteDoc == null))
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: NseapBudgetColors.lightGrayBg,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: NseapBudgetColors.cardBorder,
                                ),
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.picture_as_pdf_outlined,
                                    size: 20,
                                    color: NseapBudgetColors.green,
                                  ),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Budget report ready. Use Export PDF to download the semester report.',
                                      style: TextStyle(
                                        color: NseapBudgetColors.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (budget.payoutFile != null) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: NseapBudgetColors.cardBorder,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: NseapBudgetColors.greenSoft,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color: NseapBudgetColors.green
                                                .withValues(alpha: 0.14),
                                          ),
                                        ),
                                        child: Icon(switch (budget
                                            .payoutFile!
                                            .fileType) {
                                          'pdf' => Icons.picture_as_pdf_rounded,
                                          'xlsx' => Icons.table_chart_rounded,
                                          _ => Icons.description_rounded,
                                        }, color: NseapBudgetColors.green),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              budget.payoutFile!.fileName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 13,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            Text(
                                              '${budget.payoutFile!.fileType.toUpperCase()} | ${_ReportsAdminPageState._formatFileSize(budget.payoutFile!.size)}',
                                              style: const TextStyle(
                                                color: NseapBudgetColors
                                                    .textSecondary,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'View',
                                        onPressed: onViewFile,
                                        icon: const Icon(
                                          Icons.visibility_outlined,
                                          size: 18,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Download',
                                        onPressed: onDownloadFile,
                                        icon: const Icon(
                                          Icons.download_rounded,
                                          size: 18,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 16),
                                  _detailKeyValue(
                                    'File name',
                                    budget.payoutFile!.fileName,
                                  ),
                                  _detailKeyValue(
                                    'File type',
                                    budget.payoutFile!.fileType.toUpperCase(),
                                  ),
                                  _detailKeyValue(
                                    'Upload date',
                                    _ReportsAdminPageState._formatDateTime(
                                      budget.payoutFile!.uploadDate,
                                    ),
                                  ),
                                  _detailKeyValue(
                                    'Uploaded by',
                                    budget.payoutFile!.uploadedBy,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: NseapBudgetColors.cardBorder),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _detailKeyValue(String k, String v) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            k,
            style: const TextStyle(
              color: NseapBudgetColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            v,
            style: const TextStyle(
              color: NseapBudgetColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class _DetailsSection extends StatelessWidget {
  const _DetailsSection({
    required this.title,
    required this.child,
    this.trailing,
  });
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NseapBudgetColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: NseapBudgetColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const Divider(height: 16),
          child,
        ],
      ),
    );
  }
}

class _InfoGrid extends StatelessWidget {
  const _InfoGrid({required this.values});
  final Map<String, String> values;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final isWide = c.maxWidth >= 520;
        final w = isWide ? (c.maxWidth - 16) / 2 : c.maxWidth;
        return Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            for (final e in values.entries)
              SizedBox(
                width: w,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.key.toUpperCase(),
                      style: const TextStyle(
                        color: NseapBudgetColors.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      e.value,
                      style: const TextStyle(
                        color: NseapBudgetColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
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

// ─────────────────────────────────────────────────────────────────────────────
// Ready List — simple payout table for approved scholars
// ─────────────────────────────────────────────────────────────────────────────

class _ReadyListSection extends StatelessWidget {
  const _ReadyListSection({
    required this.approvedScholars,
    required this.stipend,
    required this.academicYearLabel,
    required this.onGenerate,
    required this.isGenerating,
  });

  final List<ScholarRecord> approvedScholars;

  /// Per-scholar stipend from the semester budget for this academic year.
  final double stipend;
  final String academicYearLabel;
  final VoidCallback onGenerate;
  final bool isGenerating;

  @override
  Widget build(BuildContext context) {
    final count = approvedScholars.length;
    final total = count * stipend;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NseapBudgetColors.cardBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080F172A),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final titleRow = Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Payroll sheet',
                      style: TextStyle(
                        color: NseapBudgetColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              );
              final actions = Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  FilledButton.icon(
                    onPressed: count == 0 || isGenerating ? null : onGenerate,
                    icon: isGenerating
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.picture_as_pdf_rounded, size: 18),
                    label: Text(isGenerating ? 'Generating...' : 'Generate'),
                    style: FilledButton.styleFrom(
                      backgroundColor: NseapBudgetColors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              );
              final narrow = constraints.maxWidth < 620;
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    titleRow,
                    const SizedBox(height: 12),
                    Align(alignment: Alignment.centerLeft, child: actions),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: titleRow),
                  const SizedBox(width: 12),
                  actions,
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: NseapBudgetColors.cardBorder),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _ReadyChip(
                label: 'Approved Scholars',
                value: '$count',
                color: NseapBudgetColors.green,
              ),
              _ReadyChip(
                label: 'Stipend',
                value: _formatPeso(stipend),
                color: const Color(0xFFB45309),
              ),
              _ReadyChip(
                label: 'A.Y.',
                value: academicYearLabel,
                color: const Color(0xFF0F766E),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (count == 0)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: NseapBudgetColors.lightGrayBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: NseapBudgetColors.cardBorder),
              ),
              child: const Text(
                'No approved scholars yet. Ready list will be available once scholars are approved.',
                style: TextStyle(
                  color: NseapBudgetColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            )
          else
            _ReadyListSimpleTable(
              scholars: approvedScholars,
              stipend: stipend,
              total: total,
            ),
        ],
      ),
    );
  }
}

class _ReadyChip extends StatelessWidget {
  const _ReadyChip({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.18)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _ReadyListSimpleTable extends StatelessWidget {
  const _ReadyListSimpleTable({
    required this.scholars,
    required this.stipend,
    required this.total,
  });
  final List<ScholarRecord> scholars;

  /// Per-scholar stipend from the semester budget for this academic year.
  final double stipend;
  final double total;

  Widget _headerCell(
    String text, {
    bool center = false,
    bool alignRight = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF475569),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
        textAlign: center
            ? TextAlign.center
            : alignRight
            ? TextAlign.right
            : TextAlign.left,
      ),
    );
  }

  Widget _bodyCell(
    String text, {
    bool center = false,
    bool alignRight = false,
    bool bold = false,
    Color color = const Color(0xFF0F172A),
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
          color: color,
        ),
        textAlign: center
            ? TextAlign.center
            : alignRight
            ? TextAlign.right
            : TextAlign.left,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
        softWrap: false,
      ),
    );
  }

  Widget _signatureCell() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 11, horizontal: 8),
      child: SizedBox(height: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = scholars.take(6).toList();
    final hasMore = scholars.length > 6;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Table(
            border: TableBorder.all(color: const Color(0xFFE2E8F0), width: 0.8),
            columnWidths: const {
              0: FixedColumnWidth(36),
              1: FlexColumnWidth(1.5),
              2: FlexColumnWidth(2.4),
              3: FlexColumnWidth(1.4),
              4: FlexColumnWidth(1.6),
              5: FlexColumnWidth(1.0),
              6: FlexColumnWidth(1.4),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
                children: [
                  _headerCell('#', center: true),
                  _headerCell('SCHOLAR ID'),
                  _headerCell('NAME'),
                  _headerCell('BARANGAY'),
                  _headerCell('SCHOOL'),
                  _headerCell('STIPEND', alignRight: true),
                  _headerCell('SIGNATURE', center: true),
                ],
              ),
              for (int i = 0; i < preview.length; i++)
                TableRow(
                  decoration: const BoxDecoration(color: Colors.white),
                  children: [
                    _bodyCell(
                      '${i + 1}',
                      center: true,
                      bold: true,
                      color: const Color(0xFF334155),
                    ),
                    _bodyCell(
                      preview[i].scholarId.trim().isEmpty
                          ? '-'
                          : preview[i].scholarId,
                      bold: true,
                    ),
                    _bodyCell(
                      preview[i].name.trim().isEmpty ? '-' : preview[i].name,
                    ),
                    _bodyCell(
                      preview[i].barangay.trim().isEmpty ||
                              preview[i].barangay == 'Not recorded'
                          ? '-'
                          : preview[i].barangay,
                      color: const Color(0xFF334155),
                    ),
                    _bodyCell(
                      preview[i].school.trim().isEmpty ||
                              preview[i].school == 'Not recorded'
                          ? '-'
                          : preview[i].school,
                    ),
                    _bodyCell(
                      _formatPeso(stipend),
                      alignRight: true,
                      bold: true,
                    ),
                    _signatureCell(),
                  ],
                ),
              // Total amount — value sits in the STIPEND column so digits
              // line up with the stipend amounts above it.
              TableRow(
                decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
                children: [
                  _bodyCell(''),
                  _bodyCell(''),
                  _bodyCell(''),
                  _bodyCell(''),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 11,
                      horizontal: 8,
                    ),
                    child: const Text(
                      'TOTAL AMOUNT',
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 11,
                      horizontal: 8,
                    ),
                    child: Text(
                      _formatPeso(total),
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  _signatureCell(),
                ],
              ),
            ],
          ),
          if (hasMore)
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                border: Border(
                  top: BorderSide(color: Color(0xFFE2E8F0), width: 0.8),
                ),
              ),
              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
              child: Text(
                '+ ${scholars.length - 6} more scholar(s) - included in the generated PDF',
                style: const TextStyle(
                  color: Color(0xFF475569),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}

// ── Legacy compatibility — keep old BudgetReport symbol for any stray import
@Deprecated('Use SemesterBudget')
typedef BudgetReport = SemesterBudget;

class BudgetSummaryGrid extends StatelessWidget {
  const BudgetSummaryGrid({super.key, required dynamic report});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class BudgetUtilizationSection extends StatelessWidget {
  const BudgetUtilizationSection({super.key, required dynamic report});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class BudgetSummaryCard extends StatelessWidget {
  const BudgetSummaryCard({
    super.key,
    required String label,
    required String value,
    required String compactValue,
    required String subtitle,
    required IconData icon,
    required Color accent,
    required Color softBg,
    required Color borderAccent,
    Widget? trailing,
    bool isHighlighted = false,
  });
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class BudgetUtilizationProgress extends StatelessWidget {
  const BudgetUtilizationProgress({
    super.key,
    required double value,
    Color color = NseapBudgetColors.green,
    Color backgroundColor = const Color(0xFFE5E7EB),
    double height = 10,
  });
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class BudgetReportHeader extends StatelessWidget {
  const BudgetReportHeader({
    super.key,
    required int selectedYear,
    required List<int> availableYears,
    required ValueChanged<int> onYearChanged,
    required VoidCallback onRefresh,
    required VoidCallback onExport,
    required bool exporting,
  });
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class BudgetAdminInputSection extends StatelessWidget {
  const BudgetAdminInputSection({
    super.key,
    required int year,
    required TextEditingController annualController,
    required TextEditingController releasedController,
    required dynamic report,
    required double rawAnnual,
    required double rawReleased,
    required bool isOverReleased,
  });
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
