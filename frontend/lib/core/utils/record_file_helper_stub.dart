import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

const MethodChannel _recordFilesChannel =
    MethodChannel('com.example.dentaguru/record_files');

Future<Map<String, dynamic>?> pickPlatformRecordFile() async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      final dynamic result =
          await _recordFilesChannel.invokeMethod<dynamic>('pickRecordFile');
      if (result == null) return null;
      if (result is Map) {
        final rawBytes = result['bytes'];
        final Uint8List bytes = rawBytes is Uint8List
            ? rawBytes
            : (rawBytes is List<int>
                ? Uint8List.fromList(rawBytes)
                : Uint8List(0));
        if (bytes.isEmpty) return null;
        return {
          'name': (result['name'] ?? '').toString(),
          'mimeType': (result['mimeType'] ?? '').toString(),
          'bytes': bytes,
          'sizeBytes': result['sizeBytes'] is int
              ? result['sizeBytes'] as int
              : bytes.length,
        };
      }
      return null;
    } on MissingPluginException {
      // Fallback for test or non-Android runtimes without native channel handler
    }
  }

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
  if (bytes.isEmpty || fileName.trim().isEmpty) return false;

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      final bool? ok = await _recordFilesChannel.invokeMethod<bool>(
        'saveAndOpenRecordFile',
        <String, dynamic>{
          'bytes': bytes,
          'fileName': fileName.trim(),
          'mimeType': mimeType.trim(),
        },
      );
      return ok == true;
    } on PlatformException catch (e) {
      debugPrint('⚠️ Android record save/open failed: ${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  return false;
}
