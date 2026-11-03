import 'dart:typed_data';

Future<void> downloadBytes(Uint8List bytes, String filename, String mimeType) async {
  // No-op on non-web: caller should fallback to Printing.sharePdf
}
