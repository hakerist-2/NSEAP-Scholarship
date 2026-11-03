import 'package:flutter/material.dart';
import 'package:nseapscholarship/services/realtime_sync.dart';

import '../../data/admin_repository.dart';
import '../../models/admin_models.dart';
import '../../widgets/admin_widgets.dart';
import '../shared/admin_page_support.dart';

/// Creates and manages announcements targeted to portal audiences.
class AnnouncementsAdminPage extends StatefulWidget {
  const AnnouncementsAdminPage({required this.repository, super.key});
  final AdminRepository repository;

  @override
  State<AnnouncementsAdminPage> createState() => _AnnouncementsAdminPageState();
}

class _AnnouncementsAdminPageState extends State<AnnouncementsAdminPage>
    with RealtimeSyncMixin {
  @override
  Set<String> get realtimeTables => const {'announcements', 'notifications'};
  @override
  Future<void> refreshRealtime() async {
    _reload();
    await _future;
  }

  late Future<List<AnnouncementRecord>> _future = widget.repository
      .getAnnouncements();
  String _search = '';
  String _audience = 'all_filter';

  void _reload() => setState(() {
    _future = widget.repository.getAnnouncements();
  });

  Future<void> _edit([AnnouncementRecord? item]) async {
    final result = await _announcementDialog(context, item);
    if (result == null) return;
    if (!mounted) return;
    await runAdminAction(
      context,
      () => widget.repository.saveAnnouncement(
        id: item?.id,
        title: result.$1,
        body: result.$2,
        audience: result.$3,
        isActive: result.$4,
        publishedAt: result.$5,
      ),
      'Announcement saved.',
      _reload,
    );
  }

  @override
  Widget build(BuildContext context) => AdminPageFrame(
    header: AdminPageHeader(
      title: 'Announcements',
      action: FilledButton.icon(
        onPressed: _edit,
        icon: const Icon(Icons.add),
        label: const Text('New announcement'),
      ),
    ),
    toolbar: AdminToolbar(
      hint: 'Search title or message',
      onSearch: (value) => setState(() => _search = value.toLowerCase()),
      filter: adminStatusFilter(
        _audience,
        const ['all_filter', 'all', 'applicant', 'scholar'],
        (value) => setState(() => _audience = value),
        labels: const {'all_filter': 'All audiences'},
      ),
    ),
    body: AdminAsyncView<List<AnnouncementRecord>>(
      future: _future,
      isEmpty: (items) => items.isEmpty,
      onRetry: _reload,
      builder: (context, items) {
        final visible = items.where((item) {
          final text = '${item.title} ${item.body}'.toLowerCase();
          return text.contains(_search) &&
              (_audience == 'all_filter' || item.audience == _audience);
        }).toList();
        if (visible.isEmpty) return const AdminStatePanel.empty();
        return ListView.separated(
          itemCount: visible.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final item = visible[index];
            return AdminRecordCard(
              title: item.title,
              subtitle: item.body,
              status: item.isActive ? 'active' : 'archived',
              fields: {
                'Audience': adminLabel(item.audience),
                'Published': adminDateLabel(item.publishedAt, withTime: true),
              },
              actions: [
                FilledButton.tonal(
                  onPressed: () => _edit(item),
                  child: const Text('Edit'),
                ),
                TextButton(
                  onPressed: () async {
                    if (await confirmAdminAction(
                      context,
                      title: 'Delete announcement?',
                      message: 'This action cannot be undone.',
                      confirmLabel: 'Delete',
                    )) {
                      if (!context.mounted) return;
                      await runAdminAction(
                        context,
                        () => widget.repository.deleteAnnouncement(item.id),
                        'Announcement deleted.',
                        _reload,
                      );
                    }
                  },
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        );
      },
    ),
  );
}

Future<(String, String, String, bool, DateTime?)?> _announcementDialog(
  BuildContext context,
  AnnouncementRecord? item,
) async {
  final title = TextEditingController(text: item?.title);
  final body = TextEditingController(text: item?.body);
  var audience = item?.audience ?? 'all';
  var active = item?.isActive ?? true;
  var publishNow = item?.publishedAt != null;
  final result = await showDialog<(String, String, String, bool, DateTime?)>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(item == null ? 'New announcement' : 'Edit announcement'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                adminDialogField(title, 'Title'),
                TextField(
                  controller: body,
                  maxLines: 6,
                  decoration: const InputDecoration(labelText: 'Message'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: audience,
                  decoration: const InputDecoration(labelText: 'Audience'),
                  items: const ['all', 'applicant', 'scholar']
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(adminLabel(value)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => audience = value ?? audience),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  value: active,
                  onChanged: (value) => setState(() => active = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Publish now'),
                  value: publishNow,
                  onChanged: (value) => setState(() => publishNow = value),
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
              if (title.text.trim().isEmpty || body.text.trim().isEmpty) {
                showAdminMessage(
                  context,
                  'Title and message are required.',
                  error: true,
                );
                return;
              }
              Navigator.pop(context, (
                title.text.trim(),
                body.text.trim(),
                audience,
                active,
                publishNow ? DateTime.now() : null,
              ));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  title.dispose();
  body.dispose();
  return result;
}
