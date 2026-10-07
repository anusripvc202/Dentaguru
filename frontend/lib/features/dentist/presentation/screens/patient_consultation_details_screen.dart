import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/widgets/whatsapp_chat_modal.dart';

import '../../../../core/models/prescription_template_model.dart';

class PatientConsultationDetailsScreen extends StatefulWidget {
  final String requestId;
  final String patientId;
  final String dentistId;
  final String patientName;
  final String category;
  final String symptoms;
  final String? adminNotes;
  final String location;
  final String status;
  final String confirmedTimeSlot;
  final String? confirmedDate;

  const PatientConsultationDetailsScreen({
    super.key,
    required this.requestId,
    required this.patientId,
    required this.dentistId,
    required this.patientName,
    required this.category,
    required this.symptoms,
    this.adminNotes,
    required this.location,
    required this.status,
    required this.confirmedTimeSlot,
    this.confirmedDate,
  });

  @override
  State<PatientConsultationDetailsScreen> createState() => _PatientConsultationDetailsScreenState();
}

class _PatientConsultationDetailsScreenState extends State<PatientConsultationDetailsScreen> {
  final PatientProblemService _problemService = PatientProblemService();
  late String _currentSlot;

  @override
  void initState() {
    super.initState();
    debugPrint('[NAV] Patient details screen mounted');
    debugPrint('[NAV] Route changed -> PatientConsultationDetailsScreen');
    _currentSlot = widget.confirmedTimeSlot;
    _fetchLatestDetails();
  }

  @override
  void dispose() {
    debugPrint('[NAV] Patient details screen disposed');
    super.dispose();
  }

  Future<void> _fetchLatestDetails() async {
    try {
      final list = await ApiService().fetchDentistAssignedRequests(dentistId: widget.dentistId);
      final match = list.firstWhere(
        (r) => r['_id']?.toString() == widget.requestId || r['id']?.toString() == widget.requestId,
        orElse: () => null,
      );
      if (match != null && mounted) {
        setState(() {
          final slot = match['confirmed_time_slot']?.toString() ?? match['confirmedTimeSlot']?.toString();
          if (slot != null && slot.isNotEmpty) _currentSlot = slot;
        });
      }
    } catch (e) {
      debugPrint('Details screen fetch notice: $e');
    }
  }

  void _showDoctorChatModal() {
    final currentDoc = _problemService.currentDoctor;
    final docName = (currentDoc?.name != null && currentDoc!.name.isNotEmpty) 
        ? currentDoc.name 
        : (widget.dentistId.isNotEmpty ? widget.dentistId : 'DOCTOR');
    
    WhatsAppChatModal.show(
      context,
      patientName: widget.patientName,
      doctorName: docName,
      currentUserRole: 'Dentist',
      patientId: widget.patientId,
      doctorId: currentDoc?.id ?? widget.dentistId,
    );
  }

  void _showPrescriptionModal() {
    String selectedDiagnosisPreset = dentalDiagnosisPresets.firstWhere(
      (d) => d.toLowerCase().contains(widget.category.toLowerCase()),
      orElse: () => 'Dental Evaluation',
    );
    String selectedMedicationName = 'Amoxicillin 500mg';

    final diagCtrl = TextEditingController(text: selectedDiagnosisPreset);
    final medCtrl = TextEditingController(text: 'Amoxicillin 500mg');
    final dosageCtrl = TextEditingController(text: '1 Capsule (500mg)');
    final frequencyCtrl = TextEditingController(text: 'Three Times Daily (1-1-1)');
    final durationCtrl = TextEditingController(text: '5 Days');
    final adviceCtrl = TextEditingController(text: 'Take after food with plenty of water. Complete full course.');

    Color getCategoryColor(String cat) {
      switch (cat) {
        case 'Antibiotic':
          return const Color(0xFFEF4444);
        case 'Pain & Swelling':
          return const Color(0xFFF59E0B);
        case 'Antiseptic':
          return const Color(0xFF10B981);
        case 'Antacid / PPI':
          return const Color(0xFF6366F1);
        case 'Topical Gel':
          return const Color(0xFF8B5CF6);
        case 'Hemostatic':
          return const Color(0xFFEC4899);
        default:
          return const Color(0xFF0284C7);
      }
    }

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 540),
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.receipt_long_rounded, color: Color(0xFF10B981), size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Issue E-Prescription',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: AppTheme.textDark),
                              ),
                              Text(
                                'Patient: ${widget.patientName}',
                                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20, color: AppTheme.textMuted),
                          onPressed: () => Navigator.pop(dialogCtx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Clinical Diagnosis Dropdown
                    DropdownButtonFormField<String>(
                      initialValue: dentalDiagnosisPresets.contains(selectedDiagnosisPreset) ? selectedDiagnosisPreset : 'Dental Evaluation',
                      isExpanded: true,
                      dropdownColor: Colors.white,
                      decoration: InputDecoration(
                        labelText: 'Clinical Diagnosis',
                        prefixIcon: const Icon(Icons.medical_information_outlined, size: 18, color: AppTheme.primaryBlue),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: dentalDiagnosisPresets.map((d) {
                        return DropdownMenuItem<String>(
                          value: d,
                          child: Text(d, style: const TextStyle(fontSize: 12.5, color: AppTheme.textDark), overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() {
                            selectedDiagnosisPreset = val;
                            if (val != 'Custom Diagnosis...') {
                              diagCtrl.text = val;
                            }
                          });
                        }
                      },
                    ),
                    if (selectedDiagnosisPreset == 'Custom Diagnosis...') ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: diagCtrl,
                        style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                        cursorColor: AppTheme.primaryBlue,
                        decoration: InputDecoration(
                          labelText: 'Enter Custom Diagnosis',
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),

                    // Section Label: Related Dental Medication Dropdown
                    const Row(
                      children: [
                        Icon(Icons.medication_rounded, size: 16, color: Color(0xFF10B981)),
                        SizedBox(width: 6),
                        Text(
                          'Select Related Dental Medication',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Medication Dropdown
                    DropdownButtonFormField<String>(
                      initialValue: dentalPrescriptionTemplates.any((t) => t.name == selectedMedicationName) ? selectedMedicationName : 'Amoxicillin 500mg',
                      isExpanded: true,
                      dropdownColor: Colors.white,
                      decoration: InputDecoration(
                        labelText: 'Choose Medicine & Strength',
                        hintText: 'Select standard dental prescription...',
                        prefixIcon: const Icon(Icons.vaccines_rounded, size: 18, color: Color(0xFF10B981)),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: dentalPrescriptionTemplates.map((template) {
                        return DropdownMenuItem<String>(
                          value: template.name,
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: getCategoryColor(template.category).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  template.category,
                                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: getCategoryColor(template.category)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  template.name,
                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          final matched = dentalPrescriptionTemplates.firstWhere((t) => t.name == val, orElse: () => dentalPrescriptionTemplates.first);
                          setModalState(() {
                            selectedMedicationName = val;
                            medCtrl.text = matched.name;
                            dosageCtrl.text = matched.defaultDosage;
                            frequencyCtrl.text = matched.defaultFrequency;
                            durationCtrl.text = matched.defaultDuration;
                            adviceCtrl.text = matched.defaultInstructions;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 8),

                    // Quick Recommendation Chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          'Amoxicillin 500mg',
                          'Augmentin 625mg (Amox + Clav)',
                          'Zerodol-SP (Aceclo + Para + Serratio)',
                          'Combiflam (Ibuprofen + Paracetamol)',
                          'Hexidine 0.2% (Chlorhexidine Mouthwash)',
                          'Pan-40 (Pantoprazole 40mg)',
                          'Ketorol-DT 10mg (Dispersible)',
                        ].map((quickMed) {
                          final isSelected = medCtrl.text == quickMed;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: InkWell(
                              onTap: () {
                                final matched = dentalPrescriptionTemplates.firstWhere((t) => t.name == quickMed, orElse: () => dentalPrescriptionTemplates.first);
                                setModalState(() {
                                  selectedMedicationName = quickMed;
                                  medCtrl.text = matched.name;
                                  dosageCtrl.text = matched.defaultDosage;
                                  frequencyCtrl.text = matched.defaultFrequency;
                                  durationCtrl.text = matched.defaultDuration;
                                  adviceCtrl.text = matched.defaultInstructions;
                                });
                              },
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isSelected ? const Color(0xFF10B981) : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: isSelected ? const Color(0xFF10B981) : const Color(0xFFE2E8F0)),
                                ),
                                child: Text(
                                  quickMed.split(' (').first,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                    color: isSelected ? Colors.white : AppTheme.textDark,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Medication Name & Strength (Editable)
                    TextField(
                      controller: medCtrl,
                      style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w600),
                      cursorColor: AppTheme.primaryBlue,
                      decoration: InputDecoration(
                        labelText: 'Medication Name & Strength',
                        hintText: 'e.g. Amoxicillin 500mg',
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Dosage & Frequency
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: dosageCtrl,
                            style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                            cursorColor: AppTheme.primaryBlue,
                            decoration: InputDecoration(
                              labelText: 'Dosage',
                              hintText: '1 Capsule',
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: frequencyCtrl,
                            style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                            cursorColor: AppTheme.primaryBlue,
                            decoration: InputDecoration(
                              labelText: 'Frequency',
                              hintText: 'Twice Daily (1-0-1)',
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Duration
                    TextField(
                      controller: durationCtrl,
                      style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                      cursorColor: AppTheme.primaryBlue,
                      decoration: InputDecoration(
                        labelText: 'Duration',
                        hintText: '5 Days',
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Instructions / Additional Notes
                    TextField(
                      controller: adviceCtrl,
                      maxLines: 2,
                      style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                      cursorColor: AppTheme.primaryBlue,
                      decoration: InputDecoration(
                        labelText: 'Instructions / Additional Notes',
                        hintText: 'Take after meals with plenty of water.',
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(dialogCtx),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textMuted)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.check_circle_rounded, size: 18),
                            label: const Text('Send Digital E-Prescription', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () async {
                              final diagnosis = diagCtrl.text.trim();
                              final medName = medCtrl.text.trim();
                              final dosage = dosageCtrl.text.trim();
                              final freq = frequencyCtrl.text.trim();
                              final duration = durationCtrl.text.trim();
                              final notes = adviceCtrl.text.trim();

                              final newRecord = {
                                'id': 'PRES-${DateTime.now().millisecondsSinceEpoch}',
                                'patient_id': widget.patientName,
                                'patientName': widget.patientName,
                                'type': 'prescription',
                                'title': 'Digital Prescription Slips',
                                'subtitle': 'Diagnosis: ${diagnosis.isNotEmpty ? diagnosis : "Dental Care"} (${medName.isNotEmpty ? medName : "Medication"})',
                                'diagnosis': diagnosis,
                                'medication': '$medName ($dosage, $freq, $duration)',
                                'duration': duration,
                                'advice': notes,
                                'issuedAt': DateTime.now().toIso8601String(),
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

                              _problemService.addMedicalRecord(newRecord);

                              await ApiService().createMedicalRecord(
                                patientId: widget.patientName,
                                type: 'prescription',
                                title: 'Digital Prescription Slips',
                                subtitle: 'Diagnosis: ${diagnosis.isNotEmpty ? diagnosis : "Dental Care"} (${medName.isNotEmpty ? medName : "Medication"})',
                                doctorName: 'Attending Dentist',
                                clinicName: 'DentaGuru Dental Clinic',
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

                              _problemService.addNotification(
                                recipientRole: 'Patient',
                                recipientId: widget.patientName,
                                title: '📝 New E-Prescription Issued',
                                message: 'Your doctor issued an E-Prescription for ${diagnosis.isNotEmpty ? diagnosis : "your dental treatment"}. Check Medical Records.',
                              );

                              Navigator.pop(dialogCtx);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('📝 E-Prescription issued successfully for ${widget.patientName}!'),
                                    backgroundColor: const Color(0xFF10B981),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textDark),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Patient Consultation • ${widget.patientName}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textDark),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              'Ref ID: ${widget.requestId}',
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF86EFAC), width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(color: Color(0xFFDCFCE7), shape: BoxShape.circle),
                        child: const Icon(Icons.verified_user_rounded, color: Color(0xFF16A34A), size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Active Referral • Accepted by You', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF15803D))),
                            Text('Patient: ${widget.patientName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  Row(
                    children: [
                      const Icon(Icons.event_available_rounded, size: 18, color: Color(0xFF16A34A)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Confirmed Time Slot: $_currentSlot',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF15803D)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Dental Problem Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark)),
                  const Divider(height: 20),
                  _buildDetailRow(Icons.category_rounded, 'Category', widget.category),
                  _buildDetailRow(Icons.description_rounded, 'Symptoms', widget.symptoms),
                  if (widget.adminNotes != null && widget.adminNotes!.isNotEmpty)
                    _buildDetailRow(Icons.note_alt_rounded, 'Admin Note', widget.adminNotes!),
                  if (widget.location.isNotEmpty)
                    _buildDetailRow(Icons.location_on_rounded, 'Location', widget.location),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.chat_rounded, size: 16),
                      label: const Text('💬 Chat with Patient', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryBlue,
                        side: const BorderSide(color: AppTheme.primaryBlue, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _showDoctorChatModal,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.receipt_long_rounded, size: 16),
                      label: const Text('📝 E-Prescription', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _showPrescriptionModal,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String val) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppTheme.primaryBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(val, style: const TextStyle(fontSize: 13, color: AppTheme.textDark, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
