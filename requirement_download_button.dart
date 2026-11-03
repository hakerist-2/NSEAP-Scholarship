import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/admin_models.dart';
import '../utils/requirement_download.dart';
import 'admin_widgets.dart';

class RequirementDownloadButton extends StatefulWidget {
  const RequirementDownloadButton({
    required this.documents,
    required this.download,
    this.archiveName,
    super.key,
  });

  final List<AdminDocument> documents;
  final Future<Uint8List> Function(String storagePath) download;
  // Supplying an archive name makes this a Download All button, even for
  // records containing only one document.
  final String? archiveName;

  @override
  State<RequirementDownloadButton> createState() =>
      _RequirementDownloadButtonState();
}

class _RequirementDownloadButtonState extends State<RequirementDownloadButton> {
  bool _busy = false;
  int _completed = 0;

  Future<void> _download() async {
    if (_busy || widget.documents.isEmpty) return;
    final documents = List<AdminDocument>.of(widget.documents);
    final download = widget.download;
    final archiveName = widget.archiveName;
    setState(() {
      _busy = true;
      _completed = 0;
    });
    try {
      final Uint8List bytes;
      final String filename;
      final String mimeType;
      if (archiveName != null) {
        bytes = await buildRequirementsZip(
          documents,
          download,
          onProgress: (completed, _) {
            if (mounted) setState(() => _completed = completed);
          },
        );
        filename = '${requirementFileName(archiveName)}.zip';
        mimeType = 'application/zip';
      } else {
        final document = documents.single;
        bytes = await download(document.storagePath);
        filename = requirementFileName(document.fileName);
        mimeType = document.mimeType.isEmpty
            ? 'application/octet-stream'
            : document.mimeType;
      }
      if (!mounted) return;
      final saved = await saveRequirementBytes(bytes, filename, mimeType);
      if (saved && mounted) {
        showAdminMessage(
          context,
          kIsWeb ? 'Download started: $filename' : 'Saved: $filename',
        );
      }
    } catch (error) {
      if (mounted) {
        showAdminMessage(
          context,
          'Unable to download requirements. ${readableAdminError(error)}',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Tooltip(
    message: widget.archiveName != null
        ? 'Download all requirements as a ZIP file'
        : 'Download ${widget.documents.firstOrNull?.fileName ?? 'requirement'}',
    child: TextButton.icon(
      onPressed: _busy || widget.documents.isEmpty ? null : _download,
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      icon: _busy
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.download_rounded, size: 20),
      label: Text(
        _busy
            ? widget.archiveName != null
                  ? 'Preparing $_completed/${widget.documents.length}'
                  : 'Downloading…'
            : widget.archiveName != null
            ? 'Download All'
            : 'Download',
      ),
    ),
  );
}

class AdminRequirementsList extends StatelessWidget {
  const AdminRequirementsList({
    required this.documents,
    required this.download,
    required this.onPreview,
    this.archiveName,
    this.showStatus = false,
    super.key,
  });

  final List<AdminDocument> documents;
  final Future<Uint8List> Function(String storagePath) download;
  final ValueChanged<AdminDocument> onPreview;
  final String? archiveName;
  final bool showStatus;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (archiveName != null)
        Align(
          alignment: Alignment.centerRight,
          child: RequirementDownloadButton(
            documents: documents,
            download: download,
            archiveName: archiveName,
          ),
        ),
      for (final document in documents)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.description_outlined),
          title: Text(document.requirementTitle ?? adminLabel(document.type)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(document.fileName),
              Text(
                '${showStatus ? '${adminLabel(document.status)} | ' : ''}'
                '${adminDateLabel(document.uploadedAt)}',
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: () => onPreview(document),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    icon: const Icon(Icons.visibility_outlined, size: 20),
                    label: const Text('Preview'),
                  ),
                  RequirementDownloadButton(
                    key: ValueKey(document.storagePath),
                    documents: [document],
                    download: download,
                  ),
                ],
              ),
            ],
          ),
        ),
    ],
  );
}
