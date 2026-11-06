import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';

Future<Map<String, dynamic>?> pickPlatformRecordFile() async {
  final picker = ImagePicker();
  final XFile? picked = await picker.pickMedia();
  if (picked == null) return null;
  final Uint8List bytes = await picked.readAsBytes();
  return {
    'name': picked.name,
    'mimeType': picked.mimeType ?? '',
    'bytes': bytes,
    'sizeBytes': bytes.length,
  };
}

Future<bool> downloadPlatformRecordFile({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) async {
  return bytes.isNotEmpty && fileName.isNotEmpty;
}

