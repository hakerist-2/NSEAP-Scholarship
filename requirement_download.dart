import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../models/admin_models.dart';

export 'save_requirement_native.dart'
    if (dart.library.html) 'save_requirement_web.dart';

String requirementFileName(String name) {
  final sanitized = name
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
      .replaceAll(RegExp(r'[. ]+$'), '')
      .trim();
  return sanitized.isEmpty ? 'requirement' : sanitized;
}

/// Build a complete ZIP, preserving same-named uploads as separate entries.
/// A failed fetch aborts the export rather than saving an incomplete archive.
Future<Uint8List> buildRequirementsZip(
  List<AdminDocument> documents,
  Future<Uint8List> Function(String storagePath) download, {
  void Function(int completed, int total)? onProgress,
}) async {
  final archive = Archive();
  final names = <String>{};
  for (var index = 0; index < documents.length; index++) {
    final document = documents[index];
    final bytes = await download(document.storagePath);
    final original = requirementFileName(document.fileName);
    final dot = original.lastIndexOf('.');
    final stem = dot > 0 ? original.substring(0, dot) : original;
    final extension = dot > 0 ? original.substring(dot) : '';
    var name = original;
    var suffix = 2;
    while (!names.add(name.toLowerCase())) {
      name = '$stem (${suffix++})$extension';
    }
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
    onProgress?.call(index + 1, documents.length);
  }
  // Uploaded PDFs/images are already compressed; storing avoids a long
  // synchronous compression pass in the browser.
  return Uint8List.fromList(ZipEncoder().encode(archive, level: 0));
}
