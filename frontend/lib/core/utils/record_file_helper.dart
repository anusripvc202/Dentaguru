import 'dart:typed_data';
import 'record_file_helper_stub.dart'
    if (dart.library.html) 'record_file_helper_web.dart';

class PickedRecordFile {
  final String name;
  final String extension;
  final String mimeType;
  final int sizeBytes;
  final Uint8List bytes;

  const PickedRecordFile({
    required this.name,
    required this.extension,
    required this.mimeType,
    required this.sizeBytes,
    required this.bytes,
  });

  bool get isImage {
    final ext = extension.toUpperCase();
    return ext == 'JPG' || ext == 'JPEG' || ext == 'PNG';
  }

  bool get isPdf => extension.toUpperCase() == 'PDF';

  String get formattedSize => RecordFileHelper.formatFileSize(sizeBytes);
}

class RecordFileHelper {
  RecordFileHelper._();

  static const List<String> allowedExtensions = ['JPG', 'JPEG', 'PNG', 'PDF'];
  static const List<String> allowedCategories = [
    'Dental X-ray',
    'Prescription',
    'Dental Report',
    'Lab Report',
    'Treatment Documents',
    'Other',
  ];
  static const int maxFileSizeBytes = 20 * 1024 * 1024; // 20 MB

  /// Optional override for deterministic widget/integration tests
  static Future<PickedRecordFile?> Function()? testFilePickerOverride;

  static String extractExtension(String fileName, {String? mimeType}) {
    final cleanName = fileName.trim();
    if (cleanName.contains('.')) {
      final ext = cleanName.split('.').last.trim().toUpperCase();
      if (ext.isNotEmpty) return ext;
    }
    final cleanMime = (mimeType ?? '').trim().toLowerCase();
    if (cleanMime == 'application/pdf') return 'PDF';
    if (cleanMime == 'image/png') return 'PNG';
    if (cleanMime == 'image/jpeg' || cleanMime == 'image/jpg') return 'JPG';
    return '';
  }

  static String resolveMimeType(String extension, {String? rawMimeType}) {
    final ext = extension.trim().toUpperCase();
    if (ext == 'PDF') return 'application/pdf';
    if (ext == 'PNG') return 'image/png';
    if (ext == 'JPG' || ext == 'JPEG') return 'image/jpeg';
    return rawMimeType ?? 'application/octet-stream';
  }

  static String? validatePickedFile(PickedRecordFile file) {
    return validateFile(
      fileName: file.name,
      sizeBytes: file.sizeBytes,
      mimeType: file.mimeType,
    );
  }

  static String? validateFile({
    required String fileName,
    required int sizeBytes,
    String? mimeType,
  }) {
    final ext = extractExtension(fileName, mimeType: mimeType);
    if (ext.isEmpty || !allowedExtensions.contains(ext)) {
      return 'Unsupported file format. Please select a JPG, JPEG, PNG, or PDF file.';
    }
    if (sizeBytes <= 0) {
      return 'The selected file is empty.';
    }
    if (sizeBytes > maxFileSizeBytes) {
      return 'File size exceeds the 20 MB limit.';
    }
    return null;
  }

  static String formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  static Future<PickedRecordFile?> pickRecordFile() async {
    if (testFilePickerOverride != null) {
      return await testFilePickerOverride!();
    }
    final raw = await pickPlatformRecordFile();
    if (raw == null) return null;

    final String name = (raw['name'] ?? '').toString();
    final String rawMime = (raw['mimeType'] ?? '').toString();
    final Uint8List bytes = raw['bytes'] is Uint8List ? raw['bytes'] as Uint8List : Uint8List(0);
    final int sizeBytes = raw['sizeBytes'] is int ? raw['sizeBytes'] as int : bytes.length;
    final String ext = extractExtension(name, mimeType: rawMime);
    final String mime = resolveMimeType(ext, rawMimeType: rawMime);

    return PickedRecordFile(
      name: name,
      extension: ext,
      mimeType: mime,
      sizeBytes: sizeBytes,
      bytes: bytes,
    );
  }

  static Future<bool> downloadRecordFile({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    return await downloadPlatformRecordFile(
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
    );
  }

  static Future<bool> downloadOrOpenFile({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    return await downloadRecordFile(
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
    );
  }
}
