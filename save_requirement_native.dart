import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<bool> saveRequirementBytes(
  Uint8List bytes,
  String filename,
  String mimeType,
) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Save requirements',
    fileName: filename,
    bytes: bytes,
  );
  return path != null;
}
