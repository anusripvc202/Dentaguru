import 'package:flutter/material.dart';
import '../../../../core/models/specialty_clinical_config.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/prescription_pdf_generator.dart';

/// Dynamic multi-specialty E-Prescription creation modal.
/// Adapts clinical fields to the doctor's registered specialization across ALL medical departments.
/// Strictly manual doctor entry & approval — never auto-generates medicines with AI.
class SpecialtyPrescriptionModal extends StatefulWidget {
  final String patientId;
  final String patientName;
  final String doctorId;
  final String doctorName;
  final String doctorSpecialty;
  final String doctorQualification;
  final String clinicName;
  final String? appointmentId;
  final String? initialDiagnosis;
  final String? initialSymptoms;
  final void Function(Map<String, dynamic> savedRecord)? onIssued;

  const SpecialtyPrescriptionModal({
    super.key,
    required this.patientId,
    required this.patientName,
    required this.doctorId,
    required this.doctorName,
    required this.doctorSpecialty,
    this.doctorQualification = '',
    this.clinicName = 'GS HEALTH Clinic',
    this.appointmentId,
    this.initialDiagnosis,
    this.initialSymptoms,
    this.onIssued,
  });

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required String patientId,
    required String patientName,
    required String doctorId,
    required String doctorName,
    required String doctorSpecialty,
    String doctorQualification = '',
    String clinicName = 'GS HEALTH Clinic',
    String? appointmentId,
    String? initialDiagnosis,
    String? initialSymptoms,
    void Function(Map<String, dynamic> savedRecord)? onIssued,
  }) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SpecialtyPrescriptionModal(
        patientId: patientId,
        patientName: patientName,
        doctorId: doctorId,
        doctorName: doctorName,
        doctorSpecialty: doctorSpecialty,
        doctorQualification: doctorQualification,
        clinicName: clinicName,
        appointmentId: appointmentId,
        initialDiagnosis: initialDiagnosis,
        initialSymptoms: initialSymptoms,
        onIssued: onIssued,
      ),
    );
  }

  @override
  State<SpecialtyPrescriptionModal> createState() => _SpecialtyPrescriptionModalState();
}

class _SpecialtyPrescriptionModalState extends State<SpecialtyPrescriptionModal> {
  final PatientProblemService _problemService = PatientProblemService();
  late final SpecialtyClinicalProfile _profile;

  late final TextEditingController _diagnosisController;
  final Map<String, TextEditingController> _sectionControllers = {};
  final TextEditingController _followUpController = TextEditingController();
  final TextEditingController _generalAdviceController = TextEditingController();

  // Current medication draft inputs (doctor enters manually)
  final TextEditingController _medNameController = TextEditingController();
  final TextEditingController _dosageController = TextEditingController();
  final TextEditingController _frequencyController = TextEditingController();
  final TextEditingController _durationController = TextEditingController();
  final TextEditingController _medInstructionsController = TextEditingController();

  final List<Map<String, dynamic>> _medications = [];
  int? _editingIndex;
  bool _doctorApproved = true;
  bool _isSaving = false;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _profile = SpecialtyClinicalConfig.forSpecialty(widget.doctorSpecialty);
    _diagnosisController = TextEditingController(text: (widget.initialDiagnosis ?? '').trim());

    for (final sec in _profile.prescriptionSchema.sections) {
      final initialText = (sec.key == 'symptoms' && (widget.initialSymptoms ?? '').trim().isNotEmpty)
          ? widget.initialSymptoms!.trim()
          : '';
      _sectionControllers[sec.key] = TextEditingController(text: initialText);
    }
  }

  @override
  void dispose() {
    _diagnosisController.dispose();
    for (final c in _sectionControllers.values) {
      c.dispose();
    }
    _followUpController.dispose();
    _generalAdviceController.dispose();
    _medNameController.dispose();
    _dosageController.dispose();
    _frequencyController.dispose();
    _durationController.dispose();
    _medInstructionsController.dispose();
    super.dispose();
  }

  void _addOrUpdateMedicationItem() {
    final name = _medNameController.text.trim();
    if (name.isEmpty) {
      setState(() => _validationError = 'Enter a medication name before adding it to the prescription.');
      return;
    }
    final item = <String, dynamic>{
      'name': name,
      'dosage': _dosageController.text.trim(),
      'frequency': _frequencyController.text.trim(),
      'duration': _durationController.text.trim(),
      'instructions': _medInstructionsController.text.trim(),
      'status': 'Active',
    };
    setState(() {
      _validationError = null;
      if (_editingIndex != null && _editingIndex! >= 0 && _editingIndex! < _medications.length) {
        _medications[_editingIndex!] = item;
        _editingIndex = null;
      } else {
        _medications.add(item);
      }
      _medNameController.clear();
      _dosageController.clear();
      _frequencyController.clear();
      _durationController.clear();
      _medInstructionsController.clear();
    });
  }

  void _startEditingItem(int index) {
    final item = _medications[index];
    setState(() {
      _editingIndex = index;
      _medNameController.text = (item['name'] ?? '').toString();
      _dosageController.text = (item['dosage'] ?? '').toString();
      _frequencyController.text = (item['frequency'] ?? '').toString();
      _durationController.text = (item['duration'] ?? '').toString();
      _medInstructionsController.text = (item['instructions'] ?? '').toString();
    });
  }

  void _removeItem(int index) {
    setState(() {
      _medications.removeAt(index);
      if (_editingIndex == index) {
        _editingIndex = null;
        _medNameController.clear();
        _dosageController.clear();
        _frequencyController.clear();
        _durationController.clear();
        _medInstructionsController.clear();
      } else if (_editingIndex != null && _editingIndex! > index) {
        _editingIndex = _editingIndex! - 1;
      }
    });
  }

  Future<void> _pickFollowUpDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      final formatted =
          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      setState(() {
        _followUpController.text = formatted;
      });
    }
  }

  Map<String, dynamic> _buildDraftRecordPayload(List<Map<String, dynamic>> effectiveItems) {
    final diagnosis = _diagnosisController.text.trim();
    final sections = <String, dynamic>{};
    for (final sec in _profile.prescriptionSchema.sections) {
      final val = _sectionControllers[sec.key]?.text.trim() ?? '';
      if (val.isNotEmpty) {
        sections[sec.key] = val;
      }
    }
    final primaryMedLabel = effectiveItems.isNotEmpty
        ? effectiveItems.map((m) => (m['name'] ?? '').toString()).where((s) => s.isNotEmpty).take(2).join(', ')
        : 'Clinical Care Plan';
    final todayIso = DateTime.now().toIso8601String();

    return {
      'id': 'RX-${DateTime.now().millisecondsSinceEpoch}',
      'patient_id': widget.patientId,
      'patientId': widget.patientId,
      'patientName': widget.patientName,
      'dentistId': widget.doctorId,
      'doctorId': widget.doctorId,
      'appointmentId': widget.appointmentId ?? '',
      'recordSource': 'doctor_issued',
      'type': 'prescription',
      'category': 'Prescription',
      'specialty': _profile.name,
      'department': _profile.name,
      'title': diagnosis.isNotEmpty ? diagnosis : '${_profile.name} E-Prescription',
      'diagnosis': diagnosis.isNotEmpty ? diagnosis : '${_profile.name} Consultation',
      'symptoms': (sections['symptoms'] ?? widget.initialSymptoms ?? '').toString(),
      'subtitle': '${_profile.name} · ${diagnosis.isNotEmpty ? diagnosis : "Clinical Assessment"} ($primaryMedLabel)',
      'doctorName': widget.doctorName,
      'doctorQualification': widget.doctorQualification,
      'clinicName': widget.clinicName,
      'clinicalSections': sections,
      'followUpDate': _followUpController.text.trim(),
      'instructions': _generalAdviceController.text.trim(),
      'advice': _generalAdviceController.text.trim(),
      'approvedByDoctor': _doctorApproved,
      'date': todayIso.split('T').first,
      'issuedAt': todayIso,
      'items': effectiveItems,
    };
  }

  Future<void> _submitPrescription() async {
    final diagnosis = _diagnosisController.text.trim();
    if (diagnosis.isEmpty) {
      setState(() => _validationError = 'Please enter ${_profile.prescriptionSchema.diagnosisLabel}.');
      return;
    }
    if (!_doctorApproved) {
      setState(() => _validationError = 'Doctor review & approval confirmation is required before issuing.');
      return;
    }

    // Include any unsaved medication currently typed into the draft input
    final effectiveItems = List<Map<String, dynamic>>.from(_medications);
    if (_medNameController.text.trim().isNotEmpty) {
      final draft = <String, dynamic>{
        'name': _medNameController.text.trim(),
        'dosage': _dosageController.text.trim(),
        'frequency': _frequencyController.text.trim(),
        'duration': _durationController.text.trim(),
        'instructions': _medInstructionsController.text.trim(),
        'status': 'Active',
      };
      if (_editingIndex != null && _editingIndex! >= 0 && _editingIndex! < effectiveItems.length) {
        effectiveItems[_editingIndex!] = draft;
      } else {
        effectiveItems.add(draft);
      }
    }

    if (effectiveItems.isEmpty && _sectionControllers.values.every((c) => c.text.trim().isEmpty)) {
      setState(() => _validationError = 'Please add at least one medication or specialty clinical instruction.');
      return;
    }

    setState(() {
      _isSaving = true;
      _validationError = null;
    });

    final record = _buildDraftRecordPayload(effectiveItems);

    try {
      final apiRes = await ApiService().createMedicalRecord(
        patientId: widget.patientId.isNotEmpty ? widget.patientId : widget.patientName,
        patientName: widget.patientName,
        dentistId: widget.doctorId,
        appointmentId: widget.appointmentId,
        type: 'prescription',
        title: record['title'].toString(),
        subtitle: record['subtitle'].toString(),
        doctorName: widget.doctorName,
        doctorQualification: widget.doctorQualification,
        clinicName: widget.clinicName,
        specialty: _profile.name,
        department: _profile.name,
        diagnosis: record['diagnosis'].toString(),
        symptoms: record['symptoms'].toString(),
        clinicalSections: Map<String, dynamic>.from(record['clinicalSections'] as Map),
        followUpDate: record['followUpDate'].toString(),
        instructions: record['instructions'].toString(),
        approvedByDoctor: true,
        items: effectiveItems,
      );

      final savedRecord = (apiRes['record'] is Map<String, dynamic>)
          ? <String, dynamic>{...record, ...Map<String, dynamic>.from(apiRes['record'] as Map)}
          : record;

      _problemService.addMedicalRecord(savedRecord);
      _problemService.addNotification(
        recipientRole: 'Patient',
        recipientId: widget.patientId.isNotEmpty ? widget.patientId : widget.patientName,
        title: 'New ${_profile.name} E-Prescription Issued',
        message:
            '${widget.doctorName} (${_profile.name}) issued your E-Prescription for ${record['diagnosis']}. View or download PDF in Locker.',
      );

      widget.onIssued?.call(savedRecord);
      if (!mounted) return;
      Navigator.of(context).pop(savedRecord);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _validationError = 'Unable to issue prescription: $e';
        });
      }
    }
  }

  InputDecoration _fieldDecoration(String label, {String? hint, IconData? icon}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
      prefixIcon: icon != null ? Icon(icon, size: 18, color: AppTheme.gsNavy) : null,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.gsNavy, width: 1.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final schema = _profile.prescriptionSchema;
    return Dialog(
      key: const Key('specialty_prescription_modal'),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header with dynamic Specialty Badge
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.gsNavy.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.receipt_long_rounded, color: AppTheme.gsNavy, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Flexible(
                              child: Text(
                                'Issue E-Prescription',
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5, color: AppTheme.textDark),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              key: const Key('rx_specialty_badge'),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: AppTheme.gsNavy.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _profile.name,
                                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppTheme.gsNavy),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Patient: ${widget.patientName} · ${widget.doctorName}',
                          style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20, color: AppTheme.textMuted),
                    onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // 1. Specialty-Specific Diagnosis Field
              TextField(
                key: const Key('rx_diagnosis_input'),
                controller: _diagnosisController,
                style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13.5, fontWeight: FontWeight.w600),
                decoration: _fieldDecoration(
                  schema.diagnosisLabel,
                  hint: schema.diagnosisPlaceholder,
                  icon: Icons.medical_information_outlined,
                ),
              ),
              const SizedBox(height: 12),

              // 2. Dynamic Specialty-Specific Clinical Sections
              for (final sec in schema.sections) ...[
                TextField(
                  key: Key('rx_section_${sec.key}'),
                  controller: _sectionControllers[sec.key],
                  maxLines: sec.multiline ? 2 : 1,
                  style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                  decoration: _fieldDecoration(
                    sec.label,
                    hint: sec.placeholder,
                  ),
                ),
                const SizedBox(height: 10),
              ],

              // 3. Manual Medication Entry (Add / Edit / Remove multiple prescription items)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.medication_rounded, size: 16, color: AppTheme.gsNavy),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _editingIndex != null
                                ? 'Edit Medication Item #${_editingIndex! + 1}'
                                : 'Medications (Doctor Manual Entry)',
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppTheme.textDark),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_medications.isNotEmpty)
                          Text(
                            '${_medications.length} added',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.gsNavy),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Added Medication Items List with Edit & Remove
                    if (_medications.isNotEmpty) ...[
                      ..._medications.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final item = entry.value;
                        final summary = [
                          (item['dosage'] ?? '').toString(),
                          (item['frequency'] ?? '').toString(),
                          (item['duration'] ?? '').toString(),
                        ].where((s) => s.trim().isNotEmpty).join(' · ');
                        return Container(
                          key: Key('rx_med_item_$idx'),
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _editingIndex == idx ? AppTheme.gsNavy : const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${idx + 1}. ℞ ${item['name']}',
                                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.textDark),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (summary.isNotEmpty)
                                      Text(
                                        summary,
                                        style: const TextStyle(fontSize: 11, color: AppTheme.textMedium),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                              IconButton(
                                key: Key('rx_edit_item_$idx'),
                                tooltip: 'Edit item',
                                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                padding: EdgeInsets.zero,
                                icon: const Icon(Icons.edit_outlined, size: 16, color: AppTheme.gsNavy),
                                onPressed: () => _startEditingItem(idx),
                              ),
                              IconButton(
                                key: Key('rx_remove_item_$idx'),
                                tooltip: 'Remove item',
                                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                padding: EdgeInsets.zero,
                                icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AppTheme.gsRed),
                                onPressed: () => _removeItem(idx),
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 6),
                    ],

                    TextField(
                      key: const Key('rx_med_name_input'),
                      controller: _medNameController,
                      style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w600),
                      decoration: _fieldDecoration('Medication Name & Strength', hint: 'Enter prescribed medicine manually...'),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const Key('rx_med_dosage_input'),
                            controller: _dosageController,
                            style: const TextStyle(color: Color(0xFF0F172A), fontSize: 12.5),
                            decoration: _fieldDecoration('Dosage', hint: 'e.g. 1 Tablet'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            key: const Key('rx_med_frequency_input'),
                            controller: _frequencyController,
                            style: const TextStyle(color: Color(0xFF0F172A), fontSize: 12.5),
                            decoration: _fieldDecoration('Frequency', hint: 'e.g. 1-0-1'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const Key('rx_med_duration_input'),
                            controller: _durationController,
                            style: const TextStyle(color: Color(0xFF0F172A), fontSize: 12.5),
                            decoration: _fieldDecoration('Duration', hint: 'e.g. 5 Days'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            key: const Key('rx_med_instructions_input'),
                            controller: _medInstructionsController,
                            style: const TextStyle(color: Color(0xFF0F172A), fontSize: 12.5),
                            decoration: _fieldDecoration('Usage Note', hint: 'e.g. After food'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        key: const Key('rx_add_medication_btn'),
                        onPressed: _addOrUpdateMedicationItem,
                        icon: Icon(_editingIndex != null ? Icons.check_rounded : Icons.add_rounded, size: 16),
                        label: Text(
                          _editingIndex != null ? 'Update Item' : 'Add Medication',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.gsNavy,
                          side: const BorderSide(color: AppTheme.gsNavy),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // 4. General Instructions & Follow-up Date
              TextField(
                key: const Key('rx_general_advice_input'),
                controller: _generalAdviceController,
                maxLines: 2,
                style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13),
                decoration: _fieldDecoration(
                  'Additional Advice / Instructions',
                  hint: 'Dietary, lifestyle, or general care instructions...',
                ),
              ),
              const SizedBox(height: 10),

              if (schema.showFollowUpDate)
                TextField(
                  key: const Key('rx_followup_date_input'),
                  controller: _followUpController,
                  readOnly: false,
                  style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13),
                  decoration: _fieldDecoration(
                    'Follow-up Date',
                    hint: 'YYYY-MM-DD (optional)',
                    icon: Icons.event_repeat_rounded,
                  ).copyWith(
                    suffixIcon: IconButton(
                      tooltip: 'Pick Follow-up Date',
                      icon: const Icon(Icons.calendar_today_rounded, size: 16, color: AppTheme.gsNavy),
                      onPressed: _pickFollowUpDate,
                    ),
                  ),
                ),

              const SizedBox(height: 10),

              // Doctor Manual Approval Checkbox
              CheckboxListTile(
                key: const Key('rx_doctor_approval_checkbox'),
                value: _doctorApproved,
                activeColor: AppTheme.gsNavy,
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'I have clinically reviewed and manually approved this prescription.',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textDark),
                ),
                onChanged: (v) => setState(() => _doctorApproved = v ?? false),
              ),

              if (_validationError != null) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.gsRed.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.gsRed.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    _validationError!,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.gsRed),
                  ),
                ),
              ],

              // Action Buttons: Preview PDF + Approve & Issue
              Row(
                children: [
                  OutlinedButton.icon(
                    key: const Key('rx_preview_pdf_btn'),
                    onPressed: _isSaving
                        ? null
                        : () {
                            final previewItems = List<Map<String, dynamic>>.from(_medications);
                            if (_medNameController.text.trim().isNotEmpty) {
                              previewItems.add({
                                'name': _medNameController.text.trim(),
                                'dosage': _dosageController.text.trim(),
                                'frequency': _frequencyController.text.trim(),
                                'duration': _durationController.text.trim(),
                                'instructions': _medInstructionsController.text.trim(),
                              });
                            }
                            PrescriptionPdfGenerator.showPreviewDialog(
                              context,
                              record: _buildDraftRecordPayload(previewItems),
                            );
                          },
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                    label: const Text('PDF', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.gsNavy,
                      side: const BorderSide(color: AppTheme.gsNavy),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      key: const Key('rx_submit_button'),
                      onPressed: _isSaving ? null : _submitPrescription,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.check_circle_rounded, size: 18),
                      label: Text(
                        _isSaving ? 'Issuing...' : 'Approve & Issue E-Prescription',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.gsNavy,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
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
    );
  }
}
