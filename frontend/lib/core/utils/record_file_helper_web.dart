// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

Future<Map<String, dynamic>?> pickPlatformRecordFile() async {
  final completer = Completer<Map<String, dynamic>?>();
  final input = html.FileUploadInputElement()
    ..accept = '.jpg,.jpeg,.png,.pdf,image/jpeg,image/png,application/pdf'
    ..style.display = 'none';

  input.onChange.listen((_) {
    final files = input.files;
    if (files == null || files.isEmpty) {
      if (!completer.isCompleted) completer.complete(null);
      input.remove();
      return;
    }
    final file = files.first;
    final reader = html.FileReader();
    reader.onLoadEnd.listen((_) {
      try {
        final result = reader.result;
        Uint8List bytes = Uint8List(0);
        if (result is Uint8List) {
          bytes = result;
        } else if (result is ByteBuffer) {
          bytes = result.asUint8List();
        } else if (result is List<int>) {
          bytes = Uint8List.fromList(result);
        }
        if (!completer.isCompleted) {
          completer.complete({
            'name': file.name,
            'mimeType': file.type,
            'bytes': bytes,
            'sizeBytes': bytes.isNotEmpty ? bytes.length : file.size,
          });
        }
      } catch (_) {
        if (!completer.isCompleted) completer.complete(null);
      } finally {
        input.remove();
      }
    });
    reader.onError.listen((_) {
      if (!completer.isCompleted) completer.complete(null);
      input.remove();
    });
    reader.readAsArrayBuffer(file);
  });

  html.document.body?.append(input);
  input.click();
  return completer.future;
}

Future<bool> downloadPlatformRecordFile({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) async {
  try {
    final safeMime = mimeType.isNotEmpty ? mimeType : 'application/octet-stream';
    final dataUri = 'data:$safeMime;base64,${base64Encode(bytes)}';
    final anchor = html.AnchorElement(href: dataUri)
      ..setAttribute('download', fileName)
      ..style.display = 'none';
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    return true;
  } catch (_) {
    return false;
  }
}
