import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/widgets/whatsapp_chat_modal.dart';

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
    final diagCtrl = TextEditingController(text: '${widget.category} Evaluation');
    final medCtrl = TextEditingController(text: 'Amoxicillin 500mg (1-0-1 after meals x 5 days)');
    final dosageCtrl = TextEditingController(text: '5 Days');
    final adviceCtrl = TextEditingController(text: 'Maintain oral hygiene & rinse with warm salt water.');

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFF10B981).withValues(alpha: 0.12), shape: BoxShape.circle),
              child: const Icon(Icons.receipt_long_rounded, color: Color(0xFF10B981), size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Issue E-Prescription • ${widget.patientName}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: diagCtrl,
                decoration: InputDecoration(
                  labelText: 'Clinical Diagnosis',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: medCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Medication & Dosage Instructions',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: dosageCtrl,
                decoration: InputDecoration(
                  labelText: 'Duration',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: adviceCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Doctor Advice / Precautions',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.check_circle_rounded, size: 16),
            label: const Text('Issue & Send E-Prescription', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              _problemService.addMedicalRecord({
                'id': 'PRES-${DateTime.now().millisecondsSinceEpoch}',
                'patientName': widget.patientName,
                'diagnosis': diagCtrl.text.trim(),
                'medication': medCtrl.text.trim(),
                'duration': dosageCtrl.text.trim(),
                'advice': adviceCtrl.text.trim(),
                'issuedAt': DateTime.now().toIso8601String(),
              });
              _problemService.addNotification(
                recipientRole: 'Patient',
                recipientId: widget.patientName,
                title: '📝 New E-Prescription Issued',
                message: 'Your doctor issued an E-Prescription for ${diagCtrl.text.trim()}. Check Medical Records.',
              );
              Navigator.pop(dialogCtx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('📝 E-Prescription issued successfully for ${widget.patientName}!'),
                  backgroundColor: const Color(0xFF10B981),
                ),
              );
            },
          ),
        ],
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
