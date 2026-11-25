import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'record_file_helper.dart';
import '../models/specialty_clinical_config.dart';

/// Pure-Dart multi-specialty E-Prescription PDF generator (%PDF-1.4) + in-app preview/download dialog.
class PrescriptionPdfGenerator {
  PrescriptionPdfGenerator._();

  static String _sanitizePdfText(String input) {
    final ascii = input
        .replaceAll('₹', 'Rs. ')
        .replaceAll('•', '-')
        .replaceAll('·', '-')
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll('℞', 'Rx')
        .replaceAll('’', "'")
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll(RegExp(r'[^\x20-\x7E]'), ' ');
    return ascii
        .replaceAll('\\', '\\\\')
        .replaceAll('(', '\\(')
        .replaceAll(')', '\\)');
  }

  static List<String> _wrapText(String text, {int maxChars = 76}) {
    final clean = text.replaceAll('\r', '').trim();
    if (clean.isEmpty) return const [];
    final out = <String>[];
    for (final rawLine in clean.split('\n')) {
      final words = rawLine.trim().split(RegExp(r'\s+'));
      var current = '';
      for (final w in words) {
        if (w.isEmpty) continue;
        if (current.isEmpty) {
          current = w;
        } else if ((current.length + 1 + w.length) <= maxChars) {
          current = '$current $w';
        } else {
          out.add(current);
          current = w;
        }
      }
      if (current.isNotEmpty) out.add(current);
    }
    return out;
  }

  /// Generates a valid `%PDF-1.4` binary document for any multi-specialty prescription record.
  static Uint8List generatePdfBytes(Map<String, dynamic> record) {
    final specialty = (record['specialty'] ?? 'General Medicine').toString().trim();
    final profile = SpecialtyClinicalConfig.forSpecialty(specialty);
    final doctorName = (record['doctorName'] ?? 'Attending Doctor').toString().trim();
    final doctorQual = (record['doctorQualification'] ?? '').toString().trim();
    final clinicName = (record['clinicName'] ?? 'GS HEALTH Clinic').toString().trim();
    final patientName = (record['patientName'] ?? record['patient_id'] ?? 'Patient').toString().trim();
    final diagnosis = (record['diagnosis'] ?? record['title'] ?? 'Clinical Evaluation').toString().trim();
    final dateStr = (record['date'] ?? record['issuedAt'] ?? DateTime.now().toIso8601String().split('T').first).toString().split('T').first;
    final appointmentId = (record['appointmentId'] ?? '').toString().trim();
    final followUpDate = (record['followUpDate'] ?? '').toString().trim();
    final instructions = (record['instructions'] ?? record['advice'] ?? '').toString().trim();
    final rawSections = record['clinicalSections'] is Map ? Map<String, dynamic>.from(record['clinicalSections'] as Map) : <String, dynamic>{};
    final rawItems = record['items'] is List ? record['items'] as List : const [];

    final lines = <({String text, bool bold, double size})>[
      (text: 'GS HEALTH - MULTI-SPECIALTY E-PRESCRIPTION', bold: true, size: 15),
      (text: 'Department / Specialty: ${profile.name}', bold: true, size: 11),
      (text: '--------------------------------------------------------------------------', bold: false, size: 10),
      (text: 'Doctor: $doctorName${doctorQual.isNotEmpty ? " ($doctorQual)" : ""}', bold: true, size: 10.5),
      (text: 'Clinic: $clinicName', bold: false, size: 10),
      (text: 'Date: $dateStr${appointmentId.isNotEmpty ? "   |   Ref/Appointment: $appointmentId" : ""}', bold: false, size: 10),
      (text: 'Patient: $patientName', bold: true, size: 10.5),
      (text: '--------------------------------------------------------------------------', bold: false, size: 10),
      (text: '${profile.prescriptionSchema.diagnosisLabel}:', bold: true, size: 11),
      for (final l in _wrapText(diagnosis)) (text: '  $l', bold: false, size: 10.5),
      (text: '', bold: false, size: 6),
    ];

    // Specialty-specific clinical sections
    for (final sec in profile.prescriptionSchema.sections) {
      final val = (rawSections[sec.key] ?? '').toString().trim();
      if (val.isNotEmpty) {
        lines.add((text: '${sec.label}:', bold: true, size: 10.5));
        for (final l in _wrapText(val)) {
          lines.add((text: '  $l', bold: false, size: 10));
        }
        lines.add((text: '', bold: false, size: 5));
      }
    }

    // Any additional custom clinical sections saved
    for (final entry in rawSections.entries) {
      final alreadyListed = profile.prescriptionSchema.sections.any((s) => s.key == entry.key);
      final val = (entry.value ?? '').toString().trim();
      if (!alreadyListed && val.isNotEmpty) {
        lines.add((text: '${entry.key}:', bold: true, size: 10.5));
        for (final l in _wrapText(val)) {
          lines.add((text: '  $l', bold: false, size: 10));
        }
      }
    }

    lines.add((text: 'Rx MEDICATIONS (Doctor Prescribed & Approved):', bold: true, size: 11));
    if (rawItems.isEmpty) {
      lines.add((text: '  No medications added.', bold: false, size: 10));
    } else {
      for (int i = 0; i < rawItems.length; i++) {
        final item = rawItems[i] is Map ? rawItems[i] as Map : const {};
        final medName = (item['name'] ?? 'Medication').toString().trim();
        final dosage = (item['dosage'] ?? '').toString().trim();
        final freq = (item['frequency'] ?? '').toString().trim();
        final dur = (item['duration'] ?? '').toString().trim();
        final medNotes = (item['instructions'] ?? '').toString().trim();

        final header = '${i + 1}. $medName${dosage.isNotEmpty ? " - $dosage" : ""}';
        for (final l in _wrapText(header)) {
          lines.add((text: '  $l', bold: true, size: 10.5));
        }
        final schedule = [if (freq.isNotEmpty) 'Frequency: $freq', if (dur.isNotEmpty) 'Duration: $dur'].join('  |  ');
        if (schedule.isNotEmpty) {
          lines.add((text: '     $schedule', bold: false, size: 9.8));
        }
        if (medNotes.isNotEmpty) {
          for (final l in _wrapText('Instructions: $medNotes', maxChars: 70)) {
            lines.add((text: '     $l', bold: false, size: 9.5));
          }
        }
      }
    }

    if (instructions.isNotEmpty) {
      lines.add((text: '', bold: false, size: 6));
      lines.add((text: 'General Advice / Instructions:', bold: true, size: 10.5));
      for (final l in _wrapText(instructions)) {
        lines.add((text: '  $l', bold: false, size: 10));
      }
    }

    if (followUpDate.isNotEmpty) {
      lines.add((text: '', bold: false, size: 6));
      lines.add((text: 'Follow-up Date: $followUpDate', bold: true, size: 10.5));
    }

    lines.add((text: '', bold: false, size: 10));
    lines.add((text: '--------------------------------------------------------------------------', bold: false, size: 10));
    lines.add((text: 'Digitally reviewed and approved by $doctorName (${profile.name})', bold: false, size: 9.5));
    lines.add((text: 'Generated via GS HEALTH Multi-Specialty Healthcare Platform', bold: false, size: 9));

    // Build PDF content stream (A4: 595 x 842 pt)
    final streamBuf = StringBuffer();
    streamBuf.writeln('BT');
    double y = 795;
    for (final line in lines) {
      if (y < 48) break;
      final fontKey = line.bold ? '/F2' : '/F1';
      final safe = _sanitizePdfText(line.text);
      if (safe.isNotEmpty) {
        streamBuf.writeln('$fontKey ${line.size.toStringAsFixed(1)} Tf');
        streamBuf.writeln('1 0 0 1 42 ${y.toStringAsFixed(1)} Tm');
        streamBuf.writeln('($safe) Tj');
      }
      y -= (line.size + 4.5);
    }
    streamBuf.writeln('ET');

    final streamBytes = latin1.encode(streamBuf.toString());

    // Assemble PDF objects with accurate xref byte offsets
    final objects = <String>[
      '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n',
      '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n',
      '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R /F2 5 0 R >> >> /Contents 6 0 R >>\nendobj\n',
      '4 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n',
      '5 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>\nendobj\n',
      '6 0 obj\n<< /Length ${streamBytes.length} >>\nstream\n${streamBuf.toString()}endstream\nendobj\n',
    ];

    final pdfBuf = BytesBuilder();
    void writeAscii(String s) => pdfBuf.add(latin1.encode(s));

    writeAscii('%PDF-1.4\n');
    final offsets = <int>[0];
    for (final obj in objects) {
      offsets.add(pdfBuf.length);
      writeAscii(obj);
    }
    final xrefStart = pdfBuf.length;
    writeAscii('xref\n0 ${objects.length + 1}\n');
    writeAscii('0000000000 65535 f \n');
    for (int i = 1; i < offsets.length; i++) {
      writeAscii('${offsets[i].toString().padLeft(10, '0')} 00000 n \n');
    }
    writeAscii('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xrefStart\n%%EOF\n');

    return pdfBuf.toBytes();
  }

  /// Displays a clean in-app Prescription PDF preview dialog with one-click Download PDF.
  static Future<void> showPreviewDialog(
    BuildContext context, {
    required Map<String, dynamic> record,
  }) async {
    final specialty = (record['specialty'] ?? 'General Medicine').toString().trim();
    final profile = SpecialtyClinicalConfig.forSpecialty(specialty);
    final doctorName = (record['doctorName'] ?? 'Attending Doctor').toString().trim();
    final doctorQual = (record['doctorQualification'] ?? '').toString().trim();
    final clinicName = (record['clinicName'] ?? 'GS HEALTH Clinic').toString().trim();
    final patientName = (record['patientName'] ?? record['patient_id'] ?? 'Patient').toString().trim();
    final diagnosis = (record['diagnosis'] ?? record['title'] ?? 'Clinical Evaluation').toString().trim();
    final dateStr = (record['date'] ?? record['issuedAt'] ?? DateTime.now().toIso8601String().split('T').first).toString().split('T').first;
    final followUpDate = (record['followUpDate'] ?? '').toString().trim();
    final instructions = (record['instructions'] ?? record['advice'] ?? '').toString().trim();
    final rawSections = record['clinicalSections'] is Map ? Map<String, dynamic>.from(record['clinicalSections'] as Map) : <String, dynamic>{};
    final rawItems = record['items'] is List ? record['items'] as List : const [];

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => Dialog(
        key: const Key('prescription_pdf_preview_dialog'),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Branded PDF Document Header
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.gsNavy,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'GS HEALTH E-Prescription',
                              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
                            ),
                            Text(
                              '${profile.name} · $dateStr',
                              style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(dialogCtx).pop(),
                        icon: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Doctor & Patient Summary
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$doctorName${doctorQual.isNotEmpty ? " ($doctorQual)" : ""}',
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppTheme.textDark),
                      ),
                      Text(clinicName, style: const TextStyle(fontSize: 12, color: AppTheme.textMedium)),
                      const Divider(height: 16),
                      Text('Patient: $patientName', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.textDark)),
                      const SizedBox(height: 4),
                      Text(
                        '${profile.prescriptionSchema.diagnosisLabel}: $diagnosis',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.gsNavy),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Specialty-Specific Sections
                for (final sec in profile.prescriptionSchema.sections)
                  if ((rawSections[sec.key] ?? '').toString().trim().isNotEmpty) ...[
                    Text(
                      sec.label,
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppTheme.gsNavy),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      (rawSections[sec.key] ?? '').toString().trim(),
                      style: const TextStyle(fontSize: 12.5, color: AppTheme.textDark, height: 1.35),
                    ),
                    const SizedBox(height: 10),
                  ],

                // Medications List
                const Text(
                  'PRESCRIBED MEDICATIONS',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B), letterSpacing: 0.7),
                ),
                const SizedBox(height: 6),
                if (rawItems.isEmpty)
                  const Text('No medications listed.', style: TextStyle(fontSize: 12.5, color: AppTheme.textMedium))
                else
                  ...rawItems.asMap().entries.map((entry) {
                    final item = entry.value is Map ? entry.value as Map : const {};
                    final name = (item['name'] ?? 'Medication').toString();
                    final dosage = (item['dosage'] ?? '').toString();
                    final freq = (item['frequency'] ?? '').toString();
                    final dur = (item['duration'] ?? '').toString();
                    final note = (item['instructions'] ?? '').toString();
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${entry.key + 1}. ℞ $name${dosage.isNotEmpty ? " ($dosage)" : ""}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textDark),
                          ),
                          if (freq.isNotEmpty || dur.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                [if (freq.isNotEmpty) freq, if (dur.isNotEmpty) dur].join(' · '),
                                style: const TextStyle(fontSize: 11.5, color: AppTheme.textMedium),
                              ),
                            ),
                          if (note.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(note, style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569))),
                            ),
                        ],
                      ),
                    );
                  }),

                if (instructions.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  const Text('Additional Instructions', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppTheme.gsNavy)),
                  const SizedBox(height: 2),
                  Text(instructions, style: const TextStyle(fontSize: 12.5, color: AppTheme.textDark)),
                ],

                if (followUpDate.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.event_repeat_rounded, size: 15, color: AppTheme.gsRed),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Follow-up Date: $followUpDate',
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.gsRed),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(dialogCtx).pop(),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Close'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        key: const Key('download_prescription_pdf_button'),
                        onPressed: () async {
                          final pdfBytes = generatePdfBytes(record);
                          final safePatient = patientName.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
                          final fileName = 'GS_HEALTH_Prescription_${safePatient}_$dateStr.pdf';
                          final ok = await RecordFileHelper.downloadRecordFile(
                            bytes: pdfBytes,
                            fileName: fileName,
                            mimeType: 'application/pdf',
                          );
                          if (dialogCtx.mounted) {
                            ScaffoldMessenger.of(dialogCtx).showSnackBar(
                              SnackBar(
                                content: Text(
                                  ok
                                      ? 'Prescription PDF downloaded ($fileName)'
                                      : 'Prescription PDF generated (${pdfBytes.length} bytes)',
                                ),
                                backgroundColor: AppTheme.gsNavy,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: const Text('Download PDF', style: TextStyle(fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.gsNavy,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
