import 'package:flutter/material.dart';

import '../../models/document_requirement.dart';
import '../../services/realtime_sync.dart';
import '../data/admin_repository.dart';
import 'admin_widgets.dart';

/// The two reusable requirement lists live alongside the submission windows.
class DocumentRequirementsEditor extends StatefulWidget {
  const DocumentRequirementsEditor({
    required this.repository,
    required this.audience,
    super.key,
  });

  final AdminRepository repository;
  final String audience;

  @override
  State<DocumentRequirementsEditor> createState() =>
      _DocumentRequirementsEditorState();
}

class _DocumentRequirementsEditorState extends State<DocumentRequirementsEditor>
    with RealtimeSyncMixin {
  late Future<List<DocumentRequirement>> _future = _load();
  bool _busy = false;

  String get _label => widget.audience == 'scholar' ? 'Scholar' : 'Applicant';

  @override
  Set<String> get realtimeTables => const {'document_requirements'};

  Future<List<DocumentRequirement>> _load() =>
      widget.repository.getDocumentRequirements(widget.audience);

  @override
  Future<void> refreshRealtime() async {
    setState(() {
      _future = _load();
    });
    try {
      await _future;
    } catch (_) {
      // Keep errors in the card so the admin can retry.
    }
  }

  Future<void> _add(List<DocumentRequirement> requirements) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AddRequirementDialog(
        label: _label,
        onSave: (title, description) =>
            widget.repository.addDocumentRequirement(
              audience: widget.audience,
              title: title,
              description: description,
              sortOrder:
                  requirements.fold<int>(
                    0,
                    (max, r) => r.sortOrder > max ? r.sortOrder : max,
                  ) +
                  1,
            ),
      ),
    );
    if (saved != true || !mounted) return;
    showAdminMessage(context, '$_label requirement added.');
    await refreshRealtime();
  }

  Future<void> _remove(DocumentRequirement requirement) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove requirement?'),
        content: Text(
          'Remove “${requirement.title}” from the $_label list? '
          'This applies to new records and drafts. Submitted records keep their original requirements.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.repository.removeDocumentRequirement(requirement);
      if (!mounted) return;
      showAdminMessage(context, 'Requirement removed.');
      await refreshRealtime();
    } catch (error) {
      if (mounted) {
        showAdminMessage(context, readableAdminError(error), error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: FutureBuilder<List<DocumentRequirement>>(
        future: _future,
        builder: (context, snapshot) {
          final requirements = snapshot.data;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 12,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '$_label Requirements',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: requirements == null || _busy
                        ? null
                        : () => _add(requirements),
                    icon: const Icon(Icons.add),
                    label: const Text('Add requirement'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'All listed documents are required. Changes apply to new records and drafts across all periods.',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              if (snapshot.hasError) ...[
                const Text('Unable to load requirements.'),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: refreshRealtime,
                    child: const Text('Retry'),
                  ),
                ),
              ] else if (requirements == null)
                const Center(child: CircularProgressIndicator())
              else if (requirements.isEmpty)
                const Text(
                  'No documents required. Add a requirement to request an upload.',
                )
              else
                for (final requirement in requirements)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                requirement.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (requirement.description.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  requirement.description,
                                  style: TextStyle(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          tooltip: 'Remove ${requirement.title}',
                          onPressed: _busy ? null : () => _remove(requirement),
                          icon: Icon(Icons.delete_outline, color: colors.error),
                        ),
                      ],
                    ),
                  ),
              if (_busy) const LinearProgressIndicator(),
            ],
          );
        },
      ),
    );
  }
}

class _AddRequirementDialog extends StatefulWidget {
  const _AddRequirementDialog({required this.label, required this.onSave});
  final String label;
  final Future<void> Function(String, String) onSave;

  @override
  State<_AddRequirementDialog> createState() => _AddRequirementDialogState();
}

class _AddRequirementDialogState extends State<_AddRequirementDialog> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_title.text.trim(), _description.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString().contains('23505')
              ? 'A requirement with this name already exists in this list.'
              : readableAdminError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text('Add ${widget.label.toLowerCase()} requirement'),
      scrollable: true,
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _title,
                autofocus: true,
                enabled: !_saving,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Document name',
                  hintText: 'e.g. Certificate of Residency',
                ),
                validator: (value) => (value?.trim().isEmpty ?? true)
                    ? 'Enter a document name.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                enabled: !_saving,
                minLines: 2,
                maxLines: 4,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Upload instructions (optional)',
                ),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Add requirement'),
        ),
      ],
    ),
  );
}
