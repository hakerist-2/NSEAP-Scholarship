import 'dart:typed_data';

import 'download_web.dart';

Future<bool> saveRequirementBytes(
  Uint8List bytes,
  String filename,
  String mimeType,
) async {
  await downloadBytes(bytes, filename, mimeType);
  return true;
}
