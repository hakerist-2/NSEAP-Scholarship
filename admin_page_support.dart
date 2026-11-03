import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../widgets/admin_widgets.dart';

/// Arranges the standard header, toolbar, and scrollable admin page body.
class AdminPageFrame extends StatelessWidget {
  const AdminPageFrame({
    required this.header,
    required this.toolbar,
    required this.body,
    super.key,
  });

  final Widget header;
  final Widget toolbar;
  final Widget body;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1600),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 18),
          toolbar,
          const SizedBox(height: 14),
          Expanded(child: body),
        ],
      ),
    ),
  );
}

/// Generates and opens a printable landscape PDF for tabular admin data.
Future<void> exportAdminTablePdf({
  required String title,
  required List<String> headers,
  required List<List<String>> rows,
}) async {
  final generatedAt = DateTime.now();
  final document = pw.Document(title: title, author: 'NSEAP Admin');
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(30),
      build: (_) => [
        pw.Text(
          title,
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 5),
        pw.Text('Generated: ${generatedAt.toIso8601String()}'),
        pw.Text('Selected records: ${rows.length}'),
        pw.SizedBox(height: 16),
        pw.TableHelper.fromTextArray(
          headers: headers,
          data: rows,
          headerDecoration: pw.BoxDecoration(color: PdfColor.fromHex('165EF0')),
          headerStyle: pw.TextStyle(
            color: PdfColors.white,
            fontWeight: pw.FontWeight.bold,
          ),
          cellStyle: const pw.TextStyle(fontSize: 8),
          cellPadding: const pw.EdgeInsets.all(5),
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
        ),
      ],
    ),
  );
  final fileName = title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  await Printing.layoutPdf(
    name: '$fileName-${generatedAt.millisecondsSinceEpoch}.pdf',
    onLayout: (_) => document.save(),
  );
}

Widget adminStatusFilter(
  String value,
  List<String> values,
  ValueChanged<String> onChanged, {
  Map<String, String> labels = const {},
}) => DropdownButtonFormField<String>(
  initialValue: value,
  isExpanded: true,
  style: const TextStyle(fontSize: 13),
  iconSize: 18,
  decoration: adminFieldDecoration(prefixIcon: Icons.filter_list_rounded),
  items: values
      .map(
        (item) => DropdownMenuItem(
          value: item,
          child: Text(labels[item] ?? adminLabel(item)),
        ),
      )
      .toList(),
  onChanged: (value) {
    if (value != null) onChanged(value);
  },
);

/// Runs an admin mutation with consistent success and error feedback.
Future<void> runAdminAction(
  BuildContext context,
  Future<void> Function() action,
  String successMessage,
  VoidCallback onSuccess,
) async {
  try {
    await action();
    if (!context.mounted) return;
    showAdminMessage(context, successMessage);
    onSuccess();
  } catch (error) {
    if (context.mounted) {
      showAdminMessage(context, readableAdminError(error), error: true);
    }
  }
}

Future<(String, String)?> showAdminChoiceDialog(
  BuildContext context, {
  required String title,
  required String label,
  required List<String> options,
  required String initial,
  required String noteLabel,
}) async {
  var selected = options.contains(initial) ? initial : options.first;
  final note = TextEditingController();
  final result = await showDialog<(String, String)>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selected,
                decoration: InputDecoration(labelText: label),
                items: options
                    .map(
                      (item) => DropdownMenuItem(
                        value: item,
                        child: Text(adminLabel(item)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => selected = value);
                },
              ),
              const SizedBox(height: 14),
              TextField(
                controller: note,
                maxLength: 1500,
                maxLines: 3,
                decoration: InputDecoration(labelText: noteLabel),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, (selected, note.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  note.dispose();
  return result;
}

Future<String?> showAdminTextDialog(
  BuildContext context, {
  required String title,
  required String label,
  bool required = false,
}) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 1500,
        maxLines: 4,
        decoration: InputDecoration(labelText: label),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (required && controller.text.trim().isEmpty) return;
            Navigator.pop(context, controller.text);
          },
          child: const Text('Continue'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

Widget adminDialogField(
  TextEditingController controller,
  String label, {
  bool numeric = false,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 12),
  child: TextField(
    controller: controller,
    keyboardType: numeric ? TextInputType.number : null,
    decoration: InputDecoration(labelText: label),
  ),
);







