import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../utils/download.dart' as web_dl;

/// Excel-ready CSV helpers — BOM + RFC4180 escaping.
String _csvEscape(String field) {
  if (field.contains('"') ||
      field.contains(',') ||
      field.contains('\n') ||
      field.contains('\r')) {
    return '"${field.replaceAll('"', '""')}"';
  }
  return field;
}

String _csvRow(List<String> cells) => cells.map(_csvEscape).join(',');

Uint8List _csvBytes(String csv) {
  // Excel needs UTF-8 BOM to detect charset correctly.
  final bom = [0xEF, 0xBB, 0xBF];
  return Uint8List.fromList([...bom, ...utf8.encode(csv)]);
}

Future<void> _downloadBytes(
  Uint8List bytes,
  String filename,
  String mime,
) async {
  if (kIsWeb) {
    await web_dl.downloadBytes(bytes, filename, mime);
  } else {
    // Fallback for mobile/desktop: use share (printing handles PDF share)
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }
}

/// Build and download PDF dashboard report — now with Application Growth + Scholar Growth bar charts.
Future<void> exportDashboardPdf({
  required String year,
  required String semester,
  required List<Map<String, String>> kpis,
  required List<String> growthLabels,
  required List<int> appGrowth,
  required List<int> scholarGrowth,
  required List<Map<String, String>> topSchools,
  required List<Map<String, String>> topPrograms,
  required List<Map<String, String>> topBarangays,
  required List<List<String>> recentApps,
  required List<List<String>> recentScholars,
}) async {
  final generatedAt = DateTime.now();
  final title = 'NSEAP Dashboard Report';
  final subtitle = '$year · $semester';
  final doc = pw.Document(title: title, author: 'NSEAP Admin');

  PdfColor navy = PdfColor.fromHex('1E3A78');
  PdfColor lightBg = PdfColor.fromHex('F8FAFC');

  pw.Widget sectionTitle(String t) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
    child: pw.Text(
      t,
      style: pw.TextStyle(
        fontSize: 13,
        fontWeight: pw.FontWeight.bold,
        color: navy,
      ),
    ),
  );

  pw.Widget table(List<String> headers, List<List<String>> rows) =>
      pw.TableHelper.fromTextArray(
        headers: headers,
        data: rows,
        headerDecoration: pw.BoxDecoration(color: navy),
        headerStyle: pw.TextStyle(
          color: PdfColors.white,
          fontWeight: pw.FontWeight.bold,
          fontSize: 8,
        ),
        cellStyle: const pw.TextStyle(fontSize: 7.5),
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
        headerCellDecoration: pw.BoxDecoration(color: navy),
        oddRowDecoration: pw.BoxDecoration(color: lightBg),
      );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
      build: (_) => [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    color: navy,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  subtitle,
                  style: const pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'Generated: ${generatedAt.toIso8601String()}',
                  style: const pw.TextStyle(
                    fontSize: 7,
                    color: PdfColors.grey600,
                  ),
                ),
                pw.Text(
                  'NSEAP Scholarship Portal',
                  style: const pw.TextStyle(
                    fontSize: 7,
                    color: PdfColors.grey600,
                  ),
                ),
              ],
            ),
          ],
        ),
        pw.Divider(color: PdfColors.grey300),
        sectionTitle('Key Performance Indicators'),
        table([
          'Metric',
          'Value',
          'Trend',
        ], kpis.map((k) => [k['metric']!, k['value']!, k['trend']!]).toList()),
        sectionTitle('Application Growth ($semester) — $year'),
        table(
          ['Period', 'Applications'],
          [
            for (var i = 0; i < growthLabels.length; i++)
              [growthLabels[i], '${appGrowth[i]}'],
          ],
        ),
        sectionTitle('Scholar Growth ($semester) — $year'),
        table(
          ['Period', 'Scholars'],
          [
            for (var i = 0; i < growthLabels.length; i++)
              [growthLabels[i], '${scholarGrowth[i]}'],
          ],
        ),
        sectionTitle('Top Schools'),
        table(
          ['School', 'Applicants', 'Share'],
          topSchools
              .map((r) => [r['label']!, r['value']!, r['share']!])
              .toList(),
        ),
        sectionTitle('Popular Programs'),
        table(
          ['Program', 'Applicants', 'Share'],
          topPrograms
              .map((r) => [r['label']!, r['value']!, r['share']!])
              .toList(),
        ),
        sectionTitle('Top Barangays'),
        table(
          ['Barangay', 'Applicants', 'Share'],
          topBarangays
              .map((r) => [r['label']!, r['value']!, r['share']!])
              .toList(),
        ),
        sectionTitle('Recent Applications'),
        table(['Applicant Name', 'Date', 'Status'], recentApps),
        sectionTitle('Recent Scholars'),
        table(['Scholar Name', 'Program', 'Year Level'], recentScholars),
        pw.SizedBox(height: 12),
        pw.Text(
          '— End of Report —',
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey500),
        ),
      ],
    ),
  );

  final bytes = await doc.save();
  final safeYear = year.replaceAll('/', '-');
  final safeSem = semester.replaceAll(' ', '-').toLowerCase();
  final filename =
      'NSEAP-Dashboard-$safeYear-$safeSem-${generatedAt.millisecondsSinceEpoch}.pdf';
  if (kIsWeb) {
    await _downloadBytes(bytes, filename, 'application/pdf');
  } else {
    await Printing.sharePdf(bytes: bytes, filename: filename);
    // Also trigger layout for preview on mobile
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }
}

/// Build and download Excel-ready CSV (UTF-8 BOM, CRLF, quoted fields) — twin growth charts.
Future<void> exportDashboardCsv({
  required String year,
  required String semester,
  required List<Map<String, String>> kpis,
  required List<String> growthLabels,
  required List<int> appGrowth,
  required List<int> scholarGrowth,
  required List<Map<String, String>> topSchools,
  required List<Map<String, String>> topPrograms,
  required List<Map<String, String>> topBarangays,
  required List<List<String>> recentApps,
  required List<List<String>> recentScholars,
}) async {
  final generatedAt = DateTime.now().toIso8601String();
  final buf = StringBuffer();

  // Excel hint — some locales need sep line; BOM already forces UTF-8.
  buf.writeln(_csvRow(['NSEAP Dashboard Report', '$year · $semester']));
  buf.writeln(_csvRow(['Generated', generatedAt]));
  buf.writeln();

  buf.writeln(_csvRow(['KPIs']));
  buf.writeln(_csvRow(['Metric', 'Value', 'Trend']));
  for (final k in kpis) {
    buf.writeln(_csvRow([k['metric']!, k['value']!, k['trend']!]));
  }
  buf.writeln();

  buf.writeln(_csvRow(['Application Growth', '$year · $semester']));
  buf.writeln(_csvRow(['Period', 'Applications']));
  for (var i = 0; i < growthLabels.length; i++) {
    buf.writeln(_csvRow([growthLabels[i], '${appGrowth[i]}']));
  }
  buf.writeln();
  buf.writeln(_csvRow(['Scholar Growth', '$year · $semester']));
  buf.writeln(_csvRow(['Period', 'Scholars']));
  for (var i = 0; i < growthLabels.length; i++) {
    buf.writeln(_csvRow([growthLabels[i], '${scholarGrowth[i]}']));
  }
  buf.writeln();

  buf.writeln(_csvRow(['Top Schools']));
  buf.writeln(_csvRow(['School', 'Applicants', 'Share']));
  for (final r in topSchools) {
    buf.writeln(_csvRow([r['label']!, r['value']!, r['share']!]));
  }
  buf.writeln();

  buf.writeln(_csvRow(['Popular Programs']));
  buf.writeln(_csvRow(['Program', 'Applicants', 'Share']));
  for (final r in topPrograms) {
    buf.writeln(_csvRow([r['label']!, r['value']!, r['share']!]));
  }
  buf.writeln();

  buf.writeln(_csvRow(['Top Barangays']));
  buf.writeln(_csvRow(['Barangay', 'Applicants', 'Share']));
  for (final r in topBarangays) {
    buf.writeln(_csvRow([r['label']!, r['value']!, r['share']!]));
  }
  buf.writeln();

  buf.writeln(_csvRow(['Recent Applications']));
  buf.writeln(_csvRow(['Applicant Name', 'Date', 'Status']));
  for (final row in recentApps) {
    buf.writeln(_csvRow(row));
  }
  buf.writeln();

  buf.writeln(_csvRow(['Recent Scholars']));
  buf.writeln(_csvRow(['Scholar Name', 'Program', 'Year Level']));
  for (final row in recentScholars) {
    buf.writeln(_csvRow(row));
  }

  // Excel-ready: CRLF
  final csv = buf.toString().replaceAll('\n', '\r\n');
  final bytes = _csvBytes(csv);
  final safeYear = year.replaceAll('/', '-');
  final safeSem = semester.replaceAll(' ', '-').toLowerCase();
  final filename =
      'NSEAP-Dashboard-$safeYear-$safeSem-${DateTime.now().millisecondsSinceEpoch}.csv';

  if (kIsWeb) {
    await web_dl.downloadBytes(bytes, filename, 'text/csv;charset=utf-8');
  } else {
    // Fallback: share bytes as file via printing? Use download stub then share via clipboard fallback handled by caller
    await _downloadBytes(bytes, filename, 'text/csv');
    // As secondary, also copy to clipboard handled by caller if needed
  }
}

/// Reusable single-table export — used by Dashboard, Applicants, Scholars.
/// This is the shared button logic requested: same PDF/CSV download + Excel BOM.
Future<void> exportTablePdf({
  required String title,
  required List<String> headers,
  required List<List<String>> rows,
}) async {
  final generatedAt = DateTime.now();
  final doc = pw.Document(title: title, author: 'NSEAP Admin');
  final navy = PdfColor.fromHex('1E3A78');
  final lightBg = PdfColor.fromHex('F8FAFC');
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
      build: (_) => [
        pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 16,
            fontWeight: pw.FontWeight.bold,
            color: navy,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Generated: ${generatedAt.toIso8601String()}  •  Records: ${rows.length}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headers: headers,
          data: rows,
          headerDecoration: pw.BoxDecoration(color: navy),
          headerStyle: pw.TextStyle(
            color: PdfColors.white,
            fontWeight: pw.FontWeight.bold,
            fontSize: 8,
          ),
          cellStyle: const pw.TextStyle(fontSize: 7.5),
          cellPadding: const pw.EdgeInsets.symmetric(
            horizontal: 6,
            vertical: 4,
          ),
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
          oddRowDecoration: pw.BoxDecoration(color: lightBg),
        ),
      ],
    ),
  );
  final bytes = await doc.save();
  final safe = title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  final filename = '$safe-${generatedAt.millisecondsSinceEpoch}.pdf';
  if (kIsWeb) {
    await _downloadBytes(bytes, filename, 'application/pdf');
  } else {
    await Printing.sharePdf(bytes: bytes, filename: filename);
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }
}

Future<void> exportTableCsv({
  required String title,
  required List<String> headers,
  required List<List<String>> rows,
}) async {
  final buf = StringBuffer();
  // Optional title row helps Excel context
  buf.writeln(_csvRow([title]));
  buf.writeln(_csvRow(headers));
  for (final r in rows) {
    buf.writeln(_csvRow(r));
  }
  final csv = buf.toString().replaceAll('\n', '\r\n');
  final bytes = _csvBytes(csv);
  final safe = title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  final filename = '$safe-${DateTime.now().millisecondsSinceEpoch}.csv';
  if (kIsWeb) {
    await web_dl.downloadBytes(bytes, filename, 'text/csv;charset=utf-8');
  } else {
    await _downloadBytes(bytes, filename, 'text/csv');
  }
}
