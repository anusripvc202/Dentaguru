import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/widgets/whatsapp_chat_modal.dart';
import '../../../../core/utils/prescription_pdf_generator.dart';
import '../widgets/specialty_prescription_modal.dart';

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

  DoctorModel? _resolveConsultationDoctor() {
    if (_problemService.currentDoctor != null) return _problemService.currentDoctor;
    for (final d in _problemService.allDoctors) {
      if (d.id == widget.dentistId || d.userId == widget.dentistId) {
        return d;
      }
    }
    return null;
  }

  void _showPrescriptionModal() {
    final doc = _resolveConsultationDoctor();
    final effectiveSpecialty = (doc?.specialty.trim().isNotEmpty == true)
        ? doc!.specialty.trim()
        : (widget.category.trim().isNotEmpty ? widget.category.trim() : 'General Medicine');
    final effectiveDocName = (doc?.name.trim().isNotEmpty == true) ? doc!.name.trim() : 'Attending Doctor';
    final effectiveDocQual = (doc?.qualification.trim().isNotEmpty == true) ? doc!.qualification.trim() : '';
    final effectiveClinic = (doc?.clinicName.trim().isNotEmpty == true) ? doc!.clinicName.trim() : 'GS HEALTH Clinic';

    SpecialtyPrescriptionModal.show(
      context,
      patientId: widget.patientId.isNotEmpty ? widget.patientId : widget.patientName,
      patientName: widget.patientName,
      doctorId: doc?.id.isNotEmpty == true ? doc!.id : widget.dentistId,
      doctorName: effectiveDocName,
      doctorSpecialty: effectiveSpecialty,
      doctorQualification: effectiveDocQual,
      clinicName: effectiveClinic,
      appointmentId: widget.requestId,
      initialDiagnosis: widget.category,
      initialSymptoms: widget.symptoms,
      onIssued: (savedRecord) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('E-Prescription issued for ${widget.patientName} ($effectiveSpecialty)!'),
            backgroundColor: AppTheme.gsNavy,
            action: SnackBarAction(
              label: 'View PDF',
              textColor: Colors.white,
              onPressed: () {
                if (mounted) {
                  PrescriptionPdfGenerator.showPreviewDialog(context, record: savedRecord);
                }
              },
            ),
          ),
        );
      },
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
                color: const Color(0x14012A58),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0x40012A58), width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(color: Color(0x14012A58), shape: BoxShape.circle),
                        child: const Icon(Icons.verified_user_rounded, color: Color(0xFFFE3434), size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Active Referral • Accepted by You', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF012A58))),
                            Text('Patient: ${widget.patientName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  Row(
                    children: [
                      const Icon(Icons.event_available_rounded, size: 18, color: Color(0xFFFE3434)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Confirmed Time Slot: $_currentSlot',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF012A58)),
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
                  const Text('Medical Consultation Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark)),
                  const Divider(height: 20),
                  Builder(
                    builder: (context) {
                      final doc = _resolveConsultationDoctor();
                      final spec = (doc?.specialty.trim().isNotEmpty == true)
                          ? doc!.specialty.trim()
                          : (widget.category.trim().isNotEmpty ? widget.category.trim() : 'General Medicine');
                      return _buildDetailRow(Icons.medical_services_rounded, 'Department / Specialty', spec);
                    },
                  ),
                  _buildDetailRow(Icons.category_rounded, 'Category', widget.category),
                  _buildDetailRow(Icons.description_rounded, 'Symptoms & Triage Notes', widget.symptoms),
                  Builder(
                    builder: (context) {
                      final cleanNote = PatientConsultationRequest.sanitizeAdminGuidance(widget.adminNotes);
                      if (cleanNote != null && cleanNote.trim().isNotEmpty) {
                        return _buildDetailRow(Icons.note_alt_rounded, 'Admin Note', cleanNote.trim());
                      }
                      return const SizedBox.shrink();
                    },
                  ),
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
                        backgroundColor: const Color(0xFF012A58),
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
