import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/models/prescription_template_model.dart';

/// GS HEALTH – Patient Record Screen (Doctor view)
/// Vertically scrollable single page combining header, patient details, 4 stats,
/// Write Rx & Refer actions, and 3 tabs (Tooth chart & notes, Visits, Treatments).
class DoctorPatientRecordScreen extends StatefulWidget {
  final PatientProfile patient;
  final VoidCallback? onWriteRx;
  final VoidCallback? onRefer;
  final int? visitsCountOverride;
  final int? completedCountOverride;
  final int? treatmentsCountOverride;
  final int? consultsCountOverride;
  final Set<int>? plannedTeethOverride;
  final bool showToothChart;

  const DoctorPatientRecordScreen({
    super.key,
    required this.patient,
    this.onWriteRx,
    this.onRefer,
    this.visitsCountOverride,
    this.completedCountOverride,
    this.treatmentsCountOverride,
    this.consultsCountOverride,
    this.plannedTeethOverride,
    this.showToothChart = false,
  });

  @override
  State<DoctorPatientRecordScreen> createState() => _DoctorPatientRecordScreenState();
}

class _DoctorPatientRecordScreenState extends State<DoctorPatientRecordScreen> {
  final PatientProblemService _patientService = PatientProblemService();
  int _selectedTabIndex = 0; // 0: Tooth chart & notes, 1: Visits, 2: Treatments
  late Set<int> _plannedTeeth;

  @override
  void initState() {
    super.initState();
    _plannedTeeth = widget.plannedTeethOverride != null
        ? Set<int>.from(widget.plannedTeethOverride!)
        : <int>{};
  }

  String _formatPhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10) {
      return '+91 $digits';
    } else if (digits.length > 10 && digits.startsWith('91')) {
      return '+91 ${digits.substring(2)}';
    } else if (raw.isNotEmpty) {
      return raw.startsWith('+') ? raw : '+$raw';
    }
    return '+91 9000000200';
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'P';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  List<PatientConsultationRequest> _getPatientRequests() {
    final cleanPhone = widget.patient.phone.replaceAll(RegExp(r'\D'), '');
    final raw10 = cleanPhone.length >= 10 ? cleanPhone.substring(cleanPhone.length - 10) : cleanPhone;
    final nameLower = widget.patient.name.trim().toLowerCase();
    final pId = widget.patient.id.trim();

    return _patientService.requests.where((r) {
      if (pId.isNotEmpty && r.patientId == pId) return true;
      if (nameLower.isNotEmpty && r.patientName.trim().toLowerCase() == nameLower) return true;
      final rPhone = r.patientPhone.replaceAll(RegExp(r'\D'), '');
      if (raw10.isNotEmpty && rPhone.contains(raw10)) return true;
      return false;
    }).toList();
  }

  List<Map<String, dynamic>> _getPatientRecords() {
    final nameLower = widget.patient.name.trim().toLowerCase();
    final pId = widget.patient.id.trim();

    return _patientService.medicalRecords.where((rec) {
      final recPid = (rec['patientId'] ?? rec['patient_id'] ?? '').toString().trim();
      final recName = (rec['patientName'] ?? '').toString().trim().toLowerCase();
      if (pId.isNotEmpty && recPid == pId) return true;
      if (nameLower.isNotEmpty && recName == nameLower) return true;
      return false;
    }).toList();
  }

  void _handleWriteRx(BuildContext context) {
    if (widget.onWriteRx != null) {
      widget.onWriteRx!();
      return;
    }
    _showInternalPrescriptionModal(context);
  }

  void _handleRefer(BuildContext context) {
    if (widget.onRefer != null) {
      widget.onRefer!();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Referral flow initiated for ${widget.patient.name}.'),
        backgroundColor: AppTheme.gsNavy,
      ),
    );
  }

  void _showInternalPrescriptionModal(BuildContext context) {
    final pName = widget.patient.name.isNotEmpty ? widget.patient.name : 'Patient';
    final diagnosisController = TextEditingController(text: 'Dental Evaluation');
    final medController = TextEditingController(text: 'Amoxicillin 500mg');
    final dosageController = TextEditingController(text: '1 Capsule');
    final frequencyController = TextEditingController(text: 'Every 8 Hours (1-1-1)');
    final durationController = TextEditingController(text: '5 Days');
    final notesController = TextEditingController(
      text: 'Take after meals with plenty of water. Complete the full antibiotic course.',
    );

    String selectedMedicationName = 'Amoxicillin 500mg';
    String selectedDiagnosisPreset = 'Dental Evaluation';

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 520),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4A6B5D).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.receipt_long_rounded, color: Color(0xFF4A6B5D), size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Issue E-Prescription',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF0F172A)),
                                ),
                                Text(
                                  'Patient: $pName',
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(dialogCtx).pop(),
                            icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                      const Divider(height: 24, color: Color(0xFFE2E8F0)),
                      const Text('Diagnosis / Clinical Condition',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: Color(0xFF0F172A))),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        key: const Key('rx_modal_diagnosis_dropdown'),
                        isExpanded: true,
                        initialValue: dentalDiagnosisPresets.contains(selectedDiagnosisPreset)
                            ? selectedDiagnosisPreset
                            : 'Dental Evaluation',
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        items: dentalDiagnosisPresets.map((d) {
                          return DropdownMenuItem(
                            value: d,
                            child: Text(d, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() {
                              selectedDiagnosisPreset = val;
                              diagnosisController.text = val;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 14),
                      const Text('Prescribed Medication',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: Color(0xFF0F172A))),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        key: const Key('rx_modal_medication_dropdown'),
                        isExpanded: true,
                        initialValue: dentalPrescriptionTemplates.any((t) => t.name == selectedMedicationName)
                            ? selectedMedicationName
                            : 'Amoxicillin 500mg',
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        items: dentalPrescriptionTemplates.map((template) {
                          return DropdownMenuItem(
                            value: template.name,
                            child: Text('${template.name} (${template.category})',
                                style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            final matched = dentalPrescriptionTemplates.firstWhere(
                              (t) => t.name == val,
                              orElse: () => dentalPrescriptionTemplates.first,
                            );
                            setModalState(() {
                              selectedMedicationName = val;
                              medController.text = matched.name;
                              dosageController.text = matched.defaultDosage;
                              frequencyController.text = matched.defaultFrequency;
                              durationController.text = matched.defaultDuration;
                              notesController.text = matched.defaultInstructions;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Dosage',
                                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF0F172A))),
                                const SizedBox(height: 4),
                                TextField(
                                  controller: dosageController,
                                  decoration: InputDecoration(
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                  ),
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Duration',
                                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF0F172A))),
                                const SizedBox(height: 4),
                                TextField(
                                  controller: durationController,
                                  decoration: InputDecoration(
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                  ),
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Text('Frequency',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF0F172A))),
                      const SizedBox(height: 4),
                      TextField(
                        controller: frequencyController,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        ),
                        style: const TextStyle(fontSize: 12.5),
                      ),
                      const SizedBox(height: 14),
                      const Text('Instructions / Notes for Patient',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF0F172A))),
                      const SizedBox(height: 4),
                      TextField(
                        controller: notesController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        ),
                        style: const TextStyle(fontSize: 12.5),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        key: const Key('rx_modal_submit_button'),
                        icon: const Icon(Icons.check_circle_rounded, size: 18),
                        label: const Text('Send Digital E-Prescription to Patient',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4A6B5D),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          final diagnosis = diagnosisController.text.trim();
                          final medName = medController.text.trim();
                          final dosage = dosageController.text.trim();
                          final freq = frequencyController.text.trim();
                          final duration = durationController.text.trim();
                          final notes = notesController.text.trim();

                          final newRecord = {
                            'id': 'REC-${DateTime.now().millisecondsSinceEpoch}',
                            'patient_id': widget.patient.id.isNotEmpty ? widget.patient.id : pName,
                            'patientName': pName,
                            'type': 'prescription',
                            'title': diagnosis.isNotEmpty ? diagnosis : 'Digital Prescription Slips',
                            'diagnosis': diagnosis.isNotEmpty ? diagnosis : 'Dental Care',
                            'subtitle': 'Diagnosis: ${diagnosis.isNotEmpty ? diagnosis : "Dental Care"} (${medName.isNotEmpty ? medName : "Medication"})',
                            'doctorId': _patientService.currentDoctor?.id ?? '',
                            'doctorName': _patientService.currentDoctor?.name ?? 'Attending Dentist',
                            'clinicName': _patientService.currentDoctor?.clinicName ?? 'GS HEALTH Dental Clinic',
                            'date': DateTime.now().toString().split(' ').first,
                            'instructions': notes,
                            'items': [
                              {
                                'name': medName.isNotEmpty ? medName : 'Amoxicillin 500mg',
                                'dosage': dosage.isNotEmpty ? dosage : '1 Capsule',
                                'frequency': freq.isNotEmpty ? freq : 'Twice Daily',
                                'duration': duration.isNotEmpty ? duration : '7 Days',
                                'instructions': notes,
                                'status': 'Active',
                              }
                            ],
                          };

                          _patientService.addMedicalRecord(newRecord);

                          await ApiService().createMedicalRecord(
                            patientId: widget.patient.id.isNotEmpty ? widget.patient.id : pName,
                            type: 'prescription',
                            title: 'Digital Prescription Slips',
                            subtitle: 'Diagnosis: ${diagnosis.isNotEmpty ? diagnosis : "Dental Care"} (${medName.isNotEmpty ? medName : "Medication"})',
                            doctorName: _patientService.currentDoctor?.name ?? 'Attending Dentist',
                            clinicName: _patientService.currentDoctor?.clinicName ?? 'GS HEALTH Dental Clinic',
                            items: [
                              {
                                'name': medName.isNotEmpty ? medName : 'Amoxicillin 500mg',
                                'dosage': dosage.isNotEmpty ? dosage : '1 Capsule',
                                'frequency': freq.isNotEmpty ? freq : 'Twice Daily',
                                'duration': duration.isNotEmpty ? duration : '7 Days',
                                'instructions': notes,
                                'status': 'Active',
                              }
                            ],
                          );

                          _patientService.addNotification(
                            recipientRole: 'Patient',
                            recipientId: pName,
                            title: '💊 New E-Prescription Issued!',
                            message: 'Dr. ${_patientService.currentDoctor?.name ?? "Attending Dentist"} has issued an E-Prescription for $diagnosis.',
                          );

                          if (context.mounted) {
                            Navigator.of(dialogCtx).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('💊 Digital E-Prescription issued to $pName! Live in Patient Health Locker.'),
                                backgroundColor: const Color(0xFF4A6B5D),
                                duration: const Duration(seconds: 3),
                              ),
                            );
                            setState(() {});
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final patientRequests = _getPatientRequests();
    final patientRecords = _getPatientRecords();

    final visitsCount = widget.visitsCountOverride ?? patientRequests.length;
    final completedCount = widget.completedCountOverride ??
        patientRequests.where((r) => r.status == 'COMPLETED' || r.status == 'CONFIRMED').length;
    final treatmentsCount = widget.treatmentsCountOverride ?? patientRecords.length;
    final consultsCount = widget.consultsCountOverride ??
        (patientRequests.where((r) => r.problemCategory.toLowerCase().contains('consult')).isNotEmpty
            ? patientRequests.where((r) => r.problemCategory.toLowerCase().contains('consult')).length
            : (patientRequests.isNotEmpty ? patientRequests.length : 0));

    final languagesStr = widget.patient.languages.isNotEmpty
        ? widget.patient.languages.join(', ')
        : 'English, Hindi';
    final cityStr = widget.patient.city.isNotEmpty ? widget.patient.city : 'Mumbai';
    final phoneStr = _formatPhone(widget.patient.phone);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: SingleChildScrollView(
          key: const Key('doctor_patient_record_scroll_view'),
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header (Back button + Patient record + Patient Name) ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  InkWell(
                    key: const Key('patient_record_back_button'),
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(22),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.chevron_left_rounded,
                          size: 26,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Patient record',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF64748B),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.patient.name.isNotEmpty ? widget.patient.name : 'Riya Sharma',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                            letterSpacing: -0.4,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // ── Patient Information Card ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top: Avatar + Name + Contact Details
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: widget.patient.photoBytes != null && widget.patient.photoBytes!.isNotEmpty
                              ? Image.memory(widget.patient.photoBytes!, fit: BoxFit.cover)
                              : Center(
                                  child: Text(
                                    _getInitials(widget.patient.name),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20,
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.patient.name.isNotEmpty ? widget.patient.name : 'Riya Sharma',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(Icons.phone_outlined, size: 14, color: Color(0xFF64748B)),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      phoneStr,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF64748B),
                                        fontWeight: FontWeight.w500,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.location_on_outlined, size: 14, color: Color(0xFF64748B)),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      cityStr,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF64748B),
                                        fontWeight: FontWeight.w500,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.translate_rounded, size: 14, color: Color(0xFF64748B)),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      languagesStr,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF64748B),
                                        fontWeight: FontWeight.w500,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 4 Stat Cards in a row (Responsive width, numbers & labels never truncated)
                    Row(
                      children: [
                        _buildStatCard(
                          keyName: 'stat_visits',
                          value: '$visitsCount',
                          label: 'Visits',
                        ),
                        const SizedBox(width: 8),
                        _buildStatCard(
                          keyName: 'stat_completed',
                          value: '$completedCount',
                          label: 'Completed',
                        ),
                        const SizedBox(width: 8),
                        _buildStatCard(
                          keyName: 'stat_treatments',
                          value: '$treatmentsCount',
                          label: 'Treatments',
                        ),
                        const SizedBox(width: 8),
                        _buildStatCard(
                          keyName: 'stat_consults',
                          value: '$consultsCount',
                          label: 'Consults',
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Two Action Buttons side by side
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            key: const Key('patient_record_write_rx_button'),
                            onPressed: () => _handleWriteRx(context),
                            icon: const Icon(Icons.edit_note_rounded, size: 18),
                            label: const Text(
                              'Write Rx',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4A6B5D),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              elevation: 0,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            key: const Key('patient_record_refer_button'),
                            onPressed: () => _handleRefer(context),
                            icon: const Icon(Icons.share_outlined, size: 16, color: Color(0xFF0F172A)),
                            label: const Text(
                              'Refer',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFEDF2EE),
                              foregroundColor: const Color(0xFF0F172A),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // ── Horizontal Tabs (Visits, Treatments, and optional Tooth chart & notes) ──
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    if (widget.showToothChart) ...[
                      _buildTabPill(
                        keyName: 'tab_tooth_chart',
                        index: 0,
                        title: 'Tooth chart & notes',
                      ),
                      const SizedBox(width: 8),
                    ],
                    _buildTabPill(
                      keyName: 'tab_visits',
                      index: widget.showToothChart ? 1 : 0,
                      title: 'Visits ($visitsCount)',
                    ),
                    const SizedBox(width: 8),
                    _buildTabPill(
                      keyName: 'tab_treatments',
                      index: widget.showToothChart ? 2 : 1,
                      title: 'Treatments ($treatmentsCount)',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Tab Content ──
              if (widget.showToothChart && _selectedTabIndex == 0) ...[
                _buildToothChartTab(),
              ] else if (_selectedTabIndex == (widget.showToothChart ? 1 : 0)) ...[
                _buildVisitsTab(patientRequests),
              ] else ...[
                _buildTreatmentsTab(patientRecords),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required String keyName,
    required String value,
    required String label,
  }) {
    return Expanded(
      child: Container(
        key: Key(keyName),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF64748B),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabPill({
    required String keyName,
    required int index,
    required String title,
  }) {
    final isSelected = _selectedTabIndex == index;
    return InkWell(
      key: Key(keyName),
      onTap: () => setState(() => _selectedTabIndex = index),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF4A6B5D) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF4A6B5D) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF0F172A),
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  // ── Tab 0: Tooth Chart & Notes (Screenshot 2 & 3) ──
  Widget _buildToothChartTab() {
    return Column(
      key: const Key('tooth_chart_tab_content'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Note: As strictly instructed, do NOT display "Add treatment note" button!
        // Tooth Chart 4 Quadrants Container
        Container(
          key: const Key('tooth_chart_container'),
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildQuadrantSection('Upper right', [18, 17, 16, 15, 14, 13, 12, 11]),
              const SizedBox(height: 14),
              _buildQuadrantSection('Upper left', [21, 22, 23, 24, 25, 26, 27, 28]),
              const SizedBox(height: 14),
              _buildQuadrantSection('Lower left', [31, 32, 33, 34, 35, 36, 37, 38]),
              const SizedBox(height: 14),
              _buildQuadrantSection('Lower right', [48, 47, 46, 45, 44, 43, 42, 41]),
              const SizedBox(height: 16),
              // Status Legend (Planned indicator)
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE5A93C),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Planned',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Empty state: No treatment notes yet
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: Color(0xFFF1F5F9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.medical_services_outlined,
                  color: Color(0xFF64748B),
                  size: 28,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'No treatment notes yet',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Add a note after each visit to build the tooth chart.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuadrantSection(String title, List<int> teeth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: teeth.map((tooth) {
            final isPlanned = _plannedTeeth.contains(tooth);
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    if (isPlanned) {
                      _plannedTeeth.remove(tooth);
                    } else {
                      _plannedTeeth.add(tooth);
                    }
                  });
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isPlanned ? const Color(0xFFE5A93C) : const Color(0xFFE2E8F0),
                      width: isPlanned ? 1.5 : 1,
                    ),
                  ),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '$tooth',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: isPlanned ? const Color(0xFFB45309) : const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Tab 1: Visits Tab ──
  Widget _buildVisitsTab(List<PatientConsultationRequest> requests) {
    if (requests.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.calendar_today_outlined,
                color: Color(0xFF64748B),
                size: 26,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'No visits recorded yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Appointments and consultation visits will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      key: const Key('patient_visits_list'),
      children: requests.map((req) {
        final dateStr = req.confirmedDate?.isNotEmpty == true
            ? req.confirmedDate!
            : '${req.submittedAt.day}/${req.submittedAt.month}/${req.submittedAt.year}';
        final isCompleted = req.status == 'COMPLETED' || req.status == 'CONFIRMED';
        final statusColor = isCompleted ? const Color(0xFF4A6B5D) : const Color(0xFFE5A93C);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4A6B5D).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.event_available_rounded,
                            color: Color(0xFF4A6B5D),
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            dateStr,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      req.status,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                req.problemCategory.isNotEmpty ? req.problemCategory : 'Dental Consultation',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0F172A),
                ),
              ),
              if (req.problemDescription.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  req.problemDescription,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── Tab 2: Treatments Tab ──
  Widget _buildTreatmentsTab(List<Map<String, dynamic>> records) {
    if (records.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.folder_open_outlined,
                color: Color(0xFF64748B),
                size: 26,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'No treatments recorded yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Treatment procedures, prescriptions, and dental reports will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      key: const Key('patient_treatments_list'),
      children: records.map((rec) {
        final title = (rec['title'] ?? 'Treatment Procedure').toString();
        final category = (rec['category'] ?? rec['type'] ?? 'Dental Care').toString();
        final date = (rec['date'] ?? '').toString();
        final description = (rec['subtitle'] ?? rec['instructions'] ?? rec['description'] ?? '').toString();

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4A6B5D).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      category,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF4A6B5D),
                      ),
                    ),
                  ),
                ],
              ),
              if (date.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  date,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
              if (description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  description,
                  style: const TextStyle(fontSize: 12.5, color: Color(0xFF334155)),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }
}
