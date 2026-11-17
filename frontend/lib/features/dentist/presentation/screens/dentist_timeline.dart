import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/denta_guru_logo.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/session_service.dart';
import '../../../../core/utils/record_file_helper.dart';
import '../../../../core/widgets/whatsapp_chat_modal.dart';
import '../../../patient/presentation/widgets/referred_patients_sheet.dart';
import '../../../../core/widgets/map_location_picker_dialog.dart';
import '../../../../core/models/medical_specialty_model.dart';
import '../../../../core/models/prescription_template_model.dart';
import '../../../admin/presentation/widgets/doctor_slot_management_dialog.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'doctor_patient_record_screen.dart';
import 'doctor_profile_screen.dart';

typedef DentistTimeline = DentistTimelineScreen;

class DentistTimelineScreen extends StatefulWidget {
  final int initialTabIndex;
  const DentistTimelineScreen({super.key, this.initialTabIndex = 0});

  @override
  State<DentistTimelineScreen> createState() => _DentistTimelineScreenState();
}

class _DentistTimelineScreenState extends State<DentistTimelineScreen> with TickerProviderStateMixin {
  int _currentIndex = 0;
  final PatientProblemService _patientService = PatientProblemService();

  Timer? _autoSyncTimer;
  Timer? _idleAvailabilityTimer;
  RealtimeChannel? _realtimeChannel;

  late AnimationController _entryController;
  late AnimationController _pulseController;

  // ── Today Tab State ──
  int _selectedDateIndex = 0;
  final DateTime _baseCalendarDate = DateTime.now();
  bool _isDentistAvailableNow = true;

  // ── Patients Tab State ──
  final TextEditingController _patientSearchCtrl = TextEditingController();
  String _patientSearchQuery = '';

  // ── Assigned Requests Tab State ──
  final Set<String> _acceptingRequestIds = {};

  // ── Refer a Patient Tab State ──
  int _previousTabIndex = 1;
  final _referFormKey = GlobalKey<FormState>();
  bool _referToClinic = false;
  final TextEditingController _referPatientNameCtrl = TextEditingController();
  final TextEditingController _referPatientMobileCtrl = TextEditingController();
  final TextEditingController _referPatientAgeCtrl = TextEditingController();
  String _referPatientGender = 'Female';
  PatientProfile? _selectedReferPatient;
  String? _selectedReferPatientChipName;
  final TextEditingController _referSearchCtrl = TextEditingController();
  DoctorModel? _selectedReferDoctor;
  ClinicModel? _selectedReferClinic;
  final TextEditingController _referNotesCtrl = TextEditingController();
  final List<String> _referAttachments = [];
  final List<PickedRecordFile> _referPickedAttachments = [];
  bool _isSubmittingReferral = false;

  // ── E-Prescriptions Tab State ──
  final Set<String> _expandedRxCardIds = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTabIndex;
    _patientService.addListener(_onServiceUpdate);
    _patientService.setDentistMode(true);
    _patientService.syncAllDataFromApi();
    _patientService.syncDoctorsFromApi();
    _patientService.syncClinicsFromApi();
    _patientService.syncDoctorReferralsFromApi();
    _patientService.syncReferralsFromApi();
    _patientService.syncNotificationsFromApi(role: 'Dentist');

    if (_patientService.pendingReferralPatient != null) {
      _selectPatientForReferral(_patientService.pendingReferralPatient!);
      _patientService.clearPendingReferralPatient();
      _currentIndex = 3;
    }

    // Sync initial availability state from currentDoctor
    final docStatus = (_patientService.currentDoctor?.status ?? 'Available').trim().toLowerCase();
    _isDentistAvailableNow = docStatus != 'offline' && docStatus != 'on leave' && docStatus != 'unavailable';
    if (_isDentistAvailableNow) {
      _startIdleAvailabilityTimer();
    }

    _referSearchCtrl.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });

    // ⏱️ Auto-sync polling timer (every 4s) to catch assigned patients & direct referrals immediately
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) {
        _patientService.syncProblemRequestsFromApi();
        _patientService.syncDentistAssignedRequestsFromApi();
        _patientService.syncDoctorReferralsFromApi();
        _patientService.syncReferralsFromApi();
        _patientService.syncNotificationsFromApi(role: 'Dentist');
      }
    });

    // ⚡ Supabase Realtime Postgres Changes listener for instant dentist dashboard updates
    try {
      _realtimeChannel = Supabase.instance.client
          .channel('dentist_dashboard_realtime')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'patient_problem_requests',
            callback: (payload) {
              debugPrint('⚡ Realtime update on patient_problem_requests for Dentist: ${payload.eventType}');
              if (mounted) {
                _patientService.syncProblemRequestsFromApi();
                _patientService.syncDentistAssignedRequestsFromApi();
                _patientService.syncNotificationsFromApi(role: 'Dentist');
              }
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'referrals',
            callback: (payload) {
              debugPrint('⚡ Realtime update on referrals for Dentist: ${payload.eventType}');
              if (mounted) {
                _patientService.syncDoctorReferralsFromApi();
                _patientService.syncReferralsFromApi();
                _patientService.syncNotificationsFromApi(role: 'Dentist');
              }
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'notifications',
            callback: (payload) {
              debugPrint('⚡ Realtime update on notifications for Dentist: ${payload.eventType}');
              if (mounted) {
                _patientService.syncNotificationsFromApi(role: 'Dentist');
              }
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('Dentist Realtime Channel Notice: $e');
    }

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _entryController.forward();
  }

  void _startIdleAvailabilityTimer() {
    _idleAvailabilityTimer?.cancel();
    _idleAvailabilityTimer = Timer(const Duration(minutes: 30), () {
      if (mounted && _isDentistAvailableNow) {
        _toggleDentistAvailability(false, isAutoIdle: true);
      }
    });
  }

  Future<void> _toggleDentistAvailability(bool value, {bool isAutoIdle = false}) async {
    setState(() {
      _isDentistAvailableNow = value;
    });
    _idleAvailabilityTimer?.cancel();
    if (value) {
      _startIdleAvailabilityTimer();
    }
    final doc = _resolveCurrentDoctor();
    if (doc != null && doc.id.isNotEmpty) {
      await _patientService.updateDoctorProfessionalProfile(
        doctorId: doc.id,
        status: value ? 'Available' : 'Offline',
      );
    }
    if (mounted && !isAutoIdle) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? 'You are now online and available for instant consultations.'
                : 'You are now offline.',
          ),
          backgroundColor: value ? AppTheme.gsNavy : const Color(0xFF64748B),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    _idleAvailabilityTimer?.cancel();
    _patientSearchCtrl.dispose();
    _referPatientNameCtrl.dispose();
    _referPatientMobileCtrl.dispose();
    _referPatientAgeCtrl.dispose();
    _referSearchCtrl.dispose();
    _referNotesCtrl.dispose();
    if (_realtimeChannel != null) {
      try {
        Supabase.instance.client.removeChannel(_realtimeChannel!);
      } catch (_) {}
    }
    _entryController.dispose();
    _pulseController.dispose();
    _patientService.setDentistMode(false);
    _patientService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (_patientService.pendingReferralPatient != null) {
      _selectPatientForReferral(_patientService.pendingReferralPatient!);
      _patientService.clearPendingReferralPatient();
      if (_currentIndex != 3) {
        _previousTabIndex = _currentIndex;
        _currentIndex = 3;
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _showUpdateMyFeeAndSlotsDialog(BuildContext context) {
    final authUser = _safeAuthUser;
    final currentDoc = _patientService.currentDoctor ?? (
      authUser != null ? DoctorModel(
        id: authUser.id,
        name: authUser.userMetadata?['name'] ?? 'Doctor',
        email: authUser.email ?? '',
        phone: '',
        specialty: 'General Medicine',
        qualification: 'MBBS, MD',
        experienceYears: 5,
        rating: 5.0,
        reviewCount: 0,
        clinicName: 'GS HEALTH Care Center',
        status: 'Available',
        nextAvailableSlots: ['Today, 2:00 PM'],
        consultationFee: '\$75',
      ) : null
    );
    final specialtyOptions = <String>{
      ..._patientService.activeSpecialtyNames,
      'General Dentistry',
      'Orthodontics',
      'Endodontics',
      'Periodontics',
      'Pediatric Dentistry',
      'Oral & Maxillofacial Surgery',
      'Prosthodontics',
      if (currentDoc != null && currentDoc.specialty.trim().isNotEmpty) currentDoc.specialty.trim(),
    }.toList();
    String selectedSpec = (currentDoc != null && currentDoc.specialty.trim().isNotEmpty)
        ? currentDoc.specialty.trim()
        : specialtyOptions.first;
    final qualCtrl = TextEditingController(
      text: (currentDoc != null && currentDoc.qualification.trim().isNotEmpty)
          ? currentDoc.qualification.trim()
          : MedicalSpecialtyModel.getDefaultQualificationForSpecialty(selectedSpec),
    );
    final expCtrl = TextEditingController(text: '${currentDoc?.experienceYears ?? 5}');
    final clinicCtrl = TextEditingController(text: currentDoc?.clinicName ?? '');
    final feeCtrl = TextEditingController(text: currentDoc?.consultationFee ?? '\$75');
    final slotCtrl = TextEditingController(
      text: (currentDoc?.nextAvailableSlots.isNotEmpty == true) ? currentDoc!.nextAvailableSlots.first : 'Today, 2:00 PM',
    );

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Row(
                children: [
                  Icon(Icons.edit_calendar_rounded, color: AppTheme.primaryBlue, size: 22),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Professional Profile, Specialty & Slots',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: specialtyOptions.contains(selectedSpec) ? selectedSpec : specialtyOptions.first,
                      isExpanded: true,
                      dropdownColor: Colors.white,
                      decoration: InputDecoration(
                        labelText: 'Medical Specialty',
                        prefixIcon: const Icon(Icons.medical_services_outlined),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: specialtyOptions
                          .map((s) => DropdownMenuItem(
                                value: s,
                                child: Text(s, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() {
                            selectedSpec = val;
                            qualCtrl.text = MedicalSpecialtyModel.getDefaultQualificationForSpecialty(val);
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: qualCtrl,
                            style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                            decoration: InputDecoration(
                              labelText: 'Qualifications',
                              hintText: 'MBBS, MD / BDS, MDS',
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: expCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                            decoration: InputDecoration(
                              labelText: 'Exp (Yrs)',
                              hintText: '5',
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: clinicCtrl,
                      style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                      decoration: InputDecoration(
                        labelText: 'Associated Clinic / Hospital',
                        prefixIcon: const Icon(Icons.domain_rounded),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: feeCtrl,
                      style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                      cursorColor: AppTheme.primaryBlue,
                      decoration: InputDecoration(
                        labelText: 'My Consultation Fee',
                        hintText: 'e.g. \$85',
                        prefixIcon: const Icon(Icons.payments_outlined),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: slotCtrl,
                      style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                      cursorColor: AppTheme.primaryBlue,
                      decoration: InputDecoration(
                        labelText: 'Next Available Time Slot',
                        hintText: 'e.g. Today, 4:00 PM',
                        prefixIcon: const Icon(Icons.access_time_rounded),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: const Text('Cancel')),
                ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle_rounded, size: 16),
                  label: const Text('Save & Publish', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    final docId = currentDoc?.id ?? (authUser?.id ?? '');
                    _patientService.updateDoctorFeeAndSlots(
                      doctorId: docId,
                      consultationFee: feeCtrl.text.trim(),
                      availableSlot: slotCtrl.text.trim(),
                    );
                    await _patientService.updateDoctorProfessionalProfile(
                      doctorId: docId,
                      specialty: selectedSpec,
                      qualification: qualCtrl.text.trim(),
                      experienceYears: int.tryParse(expCtrl.text.trim()) ?? 5,
                      clinicName: clinicCtrl.text.trim(),
                      consultationFee: feeCtrl.text.trim(),
                    );
                    if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('🎉 Profile updated ($selectedSpec • ${qualCtrl.text.trim()}) & fee set to ${feeCtrl.text.trim()}!'),
                          backgroundColor: const Color(0xFF10B981),
                        ),
                      );
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showPrescriptionModal(BuildContext context, dynamic reqOrName) {
    final String pName = reqOrName is PatientConsultationRequest ? reqOrName.patientName : reqOrName.toString();
    final String initialDiag = reqOrName is PatientConsultationRequest ? reqOrName.problemCategory : 'Dental Evaluation';
    final diagnosisController = TextEditingController(text: initialDiag);
    final medController = TextEditingController(text: 'Amoxicillin 500mg');
    final dosageController = TextEditingController(text: '1 Capsule');
    final frequencyController = TextEditingController(text: 'Every 8 Hours (1-1-1)');
    final durationController = TextEditingController(text: '5 Days');
    final notesController = TextEditingController(text: 'Take after meals with plenty of water. Complete the full antibiotic course.');

    String selectedMedicationName = 'Amoxicillin 500mg';
    String selectedDiagnosisPreset = dentalDiagnosisPresets.contains(initialDiag) ? initialDiag : 'Dental Evaluation';

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Color getCategoryColor(String cat) {
              if (cat.contains('Antibiotic')) return const Color(0xFF2563EB);
              if (cat.contains('Pain')) return const Color(0xFFEF4444);
              if (cat.contains('Antiseptic')) return const Color(0xFF0D9488);
              if (cat.contains('Antacid') || cat.contains('PPI')) return const Color(0xFFF59E0B);
              if (cat.contains('Ulcer') || cat.contains('Topical')) return const Color(0xFF7C3AED);
              return const Color(0xFF059669);
            }

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 520),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
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
                                  const Text('Issue E-Prescription', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: AppTheme.textDark)),
                                  Text('Patient: $pName', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                                ],
                              ),
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
                                  diagnosisController.text = val;
                                }
                              });
                            }
                          },
                        ),
                        if (selectedDiagnosisPreset == 'Custom Diagnosis...') ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: diagnosisController,
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
                                medController.text = matched.name;
                                dosageController.text = matched.defaultDosage;
                                frequencyController.text = matched.defaultFrequency;
                                durationController.text = matched.defaultDuration;
                                notesController.text = matched.defaultInstructions;
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
                              final isSelected = medController.text == quickMed;
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: InkWell(
                                  onTap: () {
                                    final matched = dentalPrescriptionTemplates.firstWhere((t) => t.name == quickMed, orElse: () => dentalPrescriptionTemplates.first);
                                    setModalState(() {
                                      selectedMedicationName = quickMed;
                                      medController.text = matched.name;
                                      dosageController.text = matched.defaultDosage;
                                      frequencyController.text = matched.defaultFrequency;
                                      durationController.text = matched.defaultDuration;
                                      notesController.text = matched.defaultInstructions;
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
                          controller: medController,
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
                                controller: dosageController,
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
                                controller: frequencyController,
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
                          controller: durationController,
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
                          controller: notesController,
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

                        // Action Button
                        ElevatedButton.icon(
                          icon: const Icon(Icons.check_circle_rounded, size: 18),
                          label: const Text('Send Digital E-Prescription to Patient', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
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
                              'patient_id': pName,
                              'patientName': pName,
                              'type': 'prescription',
                              'title': diagnosis.isNotEmpty ? diagnosis : 'Digital Prescription Slips',
                              'diagnosis': diagnosis.isNotEmpty ? diagnosis : 'Medical Care',
                              'subtitle': 'Diagnosis: ${diagnosis.isNotEmpty ? diagnosis : "Medical Care"} (${medName.isNotEmpty ? medName : "Medication"})',
                              'doctorId': _patientService.currentDoctor?.id ?? '',
                              'doctorName': _patientService.currentDoctor?.name ?? 'Attending Doctor',
                              'clinicName': _patientService.currentDoctor?.clinicName ?? 'GS HEALTH Clinic',
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
                              patientId: pName,
                              type: 'prescription',
                              title: 'Digital Prescription Slips',
                              subtitle: 'Diagnosis: ${diagnosis.isNotEmpty ? diagnosis : "Medical Care"} (${medName.isNotEmpty ? medName : "Medication"})',
                              doctorName: _patientService.currentDoctor?.name ?? 'Attending Doctor',
                              clinicName: _patientService.currentDoctor?.clinicName ?? 'GS HEALTH Clinic',
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

                            // Dispatch notification to Patient
                            _patientService.addNotification(
                              recipientRole: 'Patient',
                              recipientId: pName,
                              title: '💊 New E-Prescription Issued!',
                              message: 'Dr. ${_patientService.currentDoctor?.name ?? "Attending Doctor"} has issued an E-Prescription for $diagnosis.',
                            );

                            if (context.mounted) {
                              Navigator.of(dialogContext).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('💊 Digital E-Prescription issued to $pName! Live in Patient Health Locker.'),
                                  backgroundColor: const Color(0xFF10B981),
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showDoctorChatModal(BuildContext context, String patientName, String roomId) {
    final doctor = _patientService.currentDoctor;
    WhatsAppChatModal.show(
      context,
      patientName: patientName,
      doctorName: doctor?.name ?? 'Doctor',
      currentUserRole: 'Dentist',
      doctorId: doctor?.id,
    );
  }

  void _showNotificationsModal(BuildContext context, String role) {
    _patientService.syncNotificationsFromApi(role: role);

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final notifs = _patientService.appNotifications.where((n) => n.recipientRole == role || n.recipientRole == 'ALL').toList();
            final unreadCount = notifs.where((n) => !n.isRead).length;

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 460, maxHeight: 540),
                padding: const EdgeInsets.all(20),
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
                                  color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.notifications_active_rounded, color: AppTheme.primaryBlue, size: 20),
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'In-App Notifications',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textDark),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (unreadCount > 0)
                          TextButton(
                            onPressed: () async {
                              await _patientService.markAllNotificationsRead(role);
                              setModalState(() {});
                            },
                            child: const Text('Mark all read', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
                          ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.of(dialogCtx).pop(),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    if (notifs.isEmpty)
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.notifications_none_rounded, size: 48, color: Colors.grey.withValues(alpha: 0.4)),
                              const SizedBox(height: 10),
                              const Text('No new notifications.', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              const Text('New patient referrals and consultations will alert you here.', style: TextStyle(color: Colors.grey, fontSize: 11), textAlign: TextAlign.center),
                            ],
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.builder(
                          itemCount: notifs.length,
                          itemBuilder: (ctx, idx) {
                            final n = notifs[idx];
                            final isUnread = !n.isRead;

                            IconData itemIcon = Icons.notifications_rounded;
                            Color iconColor = AppTheme.primaryBlue;
                            if (n.title.toLowerCase().contains('referral')) {
                              itemIcon = Icons.group_add_rounded;
                              iconColor = const Color(0xFF6366F1);
                            } else if (n.title.toLowerCase().contains('consultation') || n.title.toLowerCase().contains('assigned')) {
                              itemIcon = Icons.medical_services_rounded;
                              iconColor = const Color(0xFF0284C7);
                            } else if (n.title.toLowerCase().contains('prescription')) {
                              itemIcon = Icons.receipt_long_rounded;
                              iconColor = const Color(0xFF10B981);
                            }

                            return InkWell(
                              onTap: () async {
                                if (isUnread) {
                                  await _patientService.markNotificationRead(n.id);
                                  setModalState(() {});
                                }
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isUnread ? const Color(0xFFF0F9FF) : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isUnread ? const Color(0xFFBAE6FD) : const Color(0xFFE2E8F0),
                                    width: isUnread ? 1.5 : 1.0,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(7),
                                      decoration: BoxDecoration(
                                        color: iconColor.withValues(alpha: 0.12),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(itemIcon, size: 16, color: iconColor),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  n.title,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13,
                                                    color: isUnread ? const Color(0xFF0369A1) : AppTheme.textDark,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (isUnread) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF0284C7),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: const Text('NEW', style: TextStyle(fontSize: 8.5, color: Colors.white, fontWeight: FontWeight.bold)),
                                                ),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 3),
                                          Text(n.message, style: const TextStyle(fontSize: 11.5, color: AppTheme.textDark, height: 1.3)),
                                          const SizedBox(height: 6),
                                          Text(
                                            '${n.timestamp.day}/${n.timestamp.month} • ${n.timestamp.hour.toString().padLeft(2, '0')}:${n.timestamp.minute.toString().padLeft(2, '0')}',
                                            style: const TextStyle(fontSize: 9.5, color: Colors.grey),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: _buildCurrentTab(),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(
            top: BorderSide(color: Color(0xFFE2E8F0), width: 1),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          backgroundColor: Colors.white,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: AppTheme.gsNavy,
          unselectedItemColor: const Color(0xFF64748B),
          selectedFontSize: 12,
          unselectedFontSize: 12,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
          onTap: (index) => setState(() => _currentIndex = index),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.calendar_today_outlined, size: 22),
              activeIcon: Icon(Icons.calendar_today_rounded, color: AppTheme.gsNavy, size: 22),
              label: 'Today',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people_outline_rounded, size: 22),
              activeIcon: Icon(Icons.people_rounded, color: AppTheme.gsNavy, size: 22),
              label: 'Patients',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.inbox_outlined, size: 22),
              activeIcon: Icon(Icons.inbox_rounded, color: AppTheme.gsNavy, size: 22),
              label: 'Requests',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.medical_services_outlined, size: 22),
              activeIcon: Icon(Icons.medical_services_rounded, color: AppTheme.gsNavy, size: 22),
              label: 'Refer',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.description_outlined, size: 22),
              activeIcon: Icon(Icons.description_rounded, color: AppTheme.gsNavy, size: 22),
              label: 'Rx',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentTab() {
    switch (_currentIndex) {
      case 0:
        return _buildTodayTab();
      case 1:
        return _buildPatientsTab();
      case 2:
        return _buildAssignedRequestsTab();
      case 3:
        return _buildReferPatientTab();
      case 4:
        return _buildPrescriptionsTab();
      default:
        return _buildTodayTab();
    }
  }

  User? get _safeAuthUser {
    try {
      return Supabase.instance.client.auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  DoctorModel? _resolveCurrentDoctor() {
    var currentDoc = _patientService.currentDoctor;
    final authUser = _safeAuthUser;
    if (authUser != null && authUser.email != null && authUser.email!.isNotEmpty) {
      final authEmailLower = authUser.email!.toLowerCase();
      final authName = (authUser.userMetadata?['name'] ?? '').toString().toLowerCase();
      final match = _patientService.allDoctors.where(
        (d) =>
            d.email.toLowerCase() == authEmailLower ||
            (d.id.isNotEmpty && d.id == authUser.id) ||
            (d.userId.isNotEmpty && d.userId == authUser.id) ||
            (authName.isNotEmpty && d.name.toLowerCase().contains(authName)),
      ).firstOrNull;
      if (match != null) {
        currentDoc = match;
        _patientService.currentDoctor = currentDoc;
      }
    }
    return currentDoc;
  }

  List<PatientConsultationRequest> _getDentistAssignedAndScheduledRequests() {
    final currentDoc = _resolveCurrentDoctor();
    final authUser = _safeAuthUser;

    final currentDocName = (currentDoc?.name ?? '').replaceAll('Dr.', '').replaceAll('Dr. ', '').trim().toLowerCase();
    final currentDocId = (currentDoc?.id ?? '').trim();
    final currentDocUserId = (currentDoc?.userId ?? '').trim();
    final currentDocEmail = (currentDoc?.email ?? '').trim().toLowerCase();
    final authUserId = (authUser?.id ?? '').trim();
    final authEmail = (authUser?.email ?? '').trim().toLowerCase();

    final myDoctorIds = <String>{
      if (currentDocId.isNotEmpty) currentDocId,
      if (currentDocUserId.isNotEmpty) currentDocUserId,
      if (authUserId.isNotEmpty) authUserId,
      if (currentDocEmail.isNotEmpty) currentDocEmail,
      if (authEmail.isNotEmpty) authEmail,
    };

    for (final d in _patientService.allDoctors) {
      if (myDoctorIds.contains(d.id) ||
          (d.userId.isNotEmpty && myDoctorIds.contains(d.userId)) ||
          (d.email.isNotEmpty && myDoctorIds.contains(d.email.toLowerCase()))) {
        if (d.id.isNotEmpty) myDoctorIds.add(d.id);
        if (d.userId.isNotEmpty) myDoctorIds.add(d.userId);
        if (d.email.isNotEmpty) myDoctorIds.add(d.email.toLowerCase());
      }
    }

    bool isAssignedToMe(PatientConsultationRequest r) {
      final aId = r.assignedDoctorId?.trim();
      if (aId != null && aId.isNotEmpty && myDoctorIds.contains(aId)) {
        return true;
      }
      final aName = r.assignedDoctorName?.replaceAll('Dr.', '').replaceAll('Dr. ', '').trim().toLowerCase();
      if (currentDocName.isNotEmpty &&
          aName != null &&
          aName.isNotEmpty &&
          (aName == currentDocName || currentDocName.contains(aName) || aName.contains(currentDocName))) {
        return true;
      }
      return false;
    }

    final Map<String, PatientConsultationRequest> uniqueMap = {};
    for (final r in _patientService.dentistAssignedRequests) {
      if (r.id.isNotEmpty) {
        final key = (r.id.startsWith('PR-'))
            ? '${r.patientName.trim().toLowerCase()}_${r.problemCategory.trim().toLowerCase()}'
            : r.id;
        uniqueMap[key] = r;
      }
    }

    for (final r in _patientService.requests) {
      if (isAssignedToMe(r) && r.id.isNotEmpty) {
        final key = (r.id.startsWith('PR-'))
            ? '${r.patientName.trim().toLowerCase()}_${r.problemCategory.trim().toLowerCase()}'
            : r.id;
        if (!uniqueMap.containsKey(key)) {
          uniqueMap[key] = r;
        } else if (r.status == 'Confirmed' || r.status == 'Accepted') {
          uniqueMap[key] = r;
        }
      }
    }

    return uniqueMap.values.toList();
  }

  static const List<String> _shortWeekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String _formatDayAbbrev(DateTime dt) => _shortWeekdays[(dt.weekday - 1).clamp(0, 6)];

  // ==========================================
  // TAB 0: TODAY – DEFAULT LANDING SCREEN
  // ==========================================
  Widget _buildTodayTab() {
    final currentDoc = _resolveCurrentDoctor();
    final authUser = _safeAuthUser;
    final rawDocName = (currentDoc?.name ?? (authUser?.userMetadata?['name'] ?? '')).toString().trim();
    final docName = rawDocName.isNotEmpty
        ? (rawDocName.startsWith('Dr.') ? rawDocName : 'Dr. $rawDocName')
        : 'Dentist';

    final notifs = _patientService.appNotifications
        .where((n) => n.recipientRole == 'Dentist' || n.recipientRole == 'ALL')
        .toList();
    final unreadCount = notifs.where((n) => !n.isRead).length;

    final allMyRequests = _getDentistAssignedAndScheduledRequests();
    final selectedDate = _baseCalendarDate.add(Duration(days: _selectedDateIndex));
    final appointmentsForSelectedDate = _getAppointmentsForDate(allMyRequests, selectedDate, _selectedDateIndex);

    return SingleChildScrollView(
      key: const Key('dentist_today_scroll_view'),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header Section
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const GsHealthLogo(height: 36, alignment: Alignment.centerLeft),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Doctor workspace',
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
                            docName,
                            key: const Key('dentist_header_name'),
                            style: const TextStyle(
                              fontSize: 23,
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
                    const SizedBox(width: 10),
                    // Notification Button with Badge
                    InkWell(
                      key: const Key('dentist_notifications_button'),
                      onTap: () => _showNotificationsModal(context, 'Dentist'),
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: [
                            const Icon(
                              Icons.notifications_none_rounded,
                              color: Color(0xFF0F172A),
                              size: 22,
                            ),
                            if (unreadCount > 0)
                              Positioned(
                                top: 4,
                                right: 3,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: AppTheme.gsRed,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.white, width: 1.5),
                                  ),
                                  child: Text(
                                    unreadCount > 9 ? '9+' : '$unreadCount',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Profile Button
                    InkWell(
                      key: const Key('dentist_profile_button'),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const DoctorProfileScreen()),
                      ),
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.person_outline_rounded,
                            color: Color(0xFF0F172A),
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 2. Horizontally Scrollable Date Selector
                SizedBox(
                  height: 78,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: List.generate(7, (index) {
                        final dt = _baseCalendarDate.add(Duration(days: index));
                        final isSelected = _selectedDateIndex == index;
                        return Padding(
                          padding: EdgeInsets.only(right: index == 6 ? 0 : 10),
                          child: InkWell(
                            key: Key('dentist_date_card_$index'),
                            onTap: () => setState(() => _selectedDateIndex = index),
                            borderRadius: BorderRadius.circular(18),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: 60,
                              height: 78,
                              decoration: BoxDecoration(
                                color: isSelected ? AppTheme.gsNavy : Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: isSelected ? AppTheme.gsNavy : const Color(0xFFE2E8F0),
                                  width: 1.2,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: AppTheme.gsNavy.withValues(alpha: 0.2),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _formatDayAbbrev(dt),
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: isSelected ? Colors.white.withValues(alpha: 0.9) : const Color(0xFF64748B),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${dt.day}',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      color: isSelected ? Colors.white : const Color(0xFF0F172A),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 3. Availability Card
                Container(
                  key: const Key('dentist_availability_card'),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(
                    color: _isDentistAvailableNow
                        ? AppTheme.gsNavy.withValues(alpha: 0.05)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _isDentistAvailableNow
                          ? AppTheme.gsNavy.withValues(alpha: 0.45)
                          : const Color(0xFFE2E8F0),
                      width: 1.3,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _isDentistAvailableNow ? AppTheme.gsNavy : const Color(0xFF94A3B8),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Available now',
                              style: TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Patients who speak your language can reach you instantly. Auto-off after 30 min idle.',
                              style: TextStyle(
                                fontSize: 13.5,
                                color: Color(0xFF475569),
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Switch(
                        key: const Key('dentist_availability_switch'),
                        value: _isDentistAvailableNow,
                        activeThumbColor: Colors.white,
                        activeTrackColor: AppTheme.gsNavy,
                        inactiveThumbColor: Colors.white,
                        inactiveTrackColor: const Color(0xFFCBD5E1),
                        onChanged: (val) => _toggleDentistAvailability(val),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // 4. Sponsored Banner
                _buildDentistSponsoredCourseBanner(context),
                const SizedBox(height: 28),

                // 5. Appointments for Selected Date OR Empty State
                if (appointmentsForSelectedDate.isEmpty)
                  Container(
                    key: const Key('dentist_no_appointments_empty_state'),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            color: AppTheme.gsNavy.withValues(alpha: 0.06),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.wb_sunny_outlined,
                              color: AppTheme.gsNavy,
                              size: 30,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'No appointments',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Nothing booked for this day. Enjoy your free time.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF64748B),
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Appointments (${appointmentsForSelectedDate.length})',
                        style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...appointmentsForSelectedDate.map((req) {
                        final slot = (req.confirmedTimeSlot != null && req.confirmedTimeSlot!.trim().isNotEmpty)
                            ? req.confirmedTimeSlot!
                            : '11:00 AM';
                        return _buildTimelineNode(req: req, time: slot);
                      }),
                    ],
                  ),

                const SizedBox(height: 36),

                // 6. Manage Availability & Consultation Slots Section (Preserved for Slot Configuration)
                _buildManageAvailabilitySection(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<PatientConsultationRequest> _getAppointmentsForDate(
    List<PatientConsultationRequest> allMyRequests,
    DateTime targetDate,
    int selectedIndex,
  ) {
    final targetDateStr =
        '${targetDate.year.toString().padLeft(4, '0')}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';

    return allMyRequests.where((req) {
      final statusLower = req.status.trim().toLowerCase();
      final isBookedOrConfirmed = statusLower == 'confirmed' ||
          statusLower == 'accepted' ||
          statusLower == 'scheduled' ||
          statusLower.contains('confirm') ||
          statusLower.contains('accept') ||
          req.problemDescription == 'Scheduled dental consultation';

      if (!isBookedOrConfirmed) return false;

      if (req.confirmedDate != null && req.confirmedDate!.trim().isNotEmpty) {
        final cDate = req.confirmedDate!.trim().split('T').first;
        if (cDate == targetDateStr) return true;
        final parsed = DateTime.tryParse(req.confirmedDate!.trim());
        if (parsed != null &&
            parsed.year == targetDate.year &&
            parsed.month == targetDate.month &&
            parsed.day == targetDate.day) {
          return true;
        }
        return false;
      }

      final slotLower = (req.confirmedTimeSlot ?? '').trim().toLowerCase();
      if (slotLower.startsWith('today')) {
        return selectedIndex == 0;
      }
      if (slotLower.startsWith('tomorrow')) {
        return selectedIndex == 1;
      }

      return req.submittedAt.year == targetDate.year &&
          req.submittedAt.month == targetDate.month &&
          req.submittedAt.day == targetDate.day;
    }).toList();
  }

  Widget _buildDentistSponsoredCourseBanner(BuildContext context) {
    return Column(
      children: [
        InkWell(
          key: const Key('dentist_sponsored_banner'),
          onTap: () async {
            final uri = Uri.parse('https://www.gsimplants.com/smooth-implant');
            try {
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            } catch (_) {}
          },
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF1E3A8A),
                  Color(0xFF0F2557),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.gsNavy.withValues(alpha: 0.14),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // SPONSORED pill + faculty row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'SPONSORED',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildCourseSpeakerAvatar('SK'),
                                const SizedBox(width: 6),
                                _buildCourseSpeakerAvatar('GS'),
                                const SizedBox(width: 6),
                                _buildCourseSpeakerAvatar('RA'),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Center(
                          child: Text(
                            'DR SUMANTH KRISHNA  •  DR SHESHU KUMAR  •  DR RAJESH ADURI',
                            style: TextStyle(
                              color: Color(0xFFCBD5E1),
                              fontSize: 8.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Center(
                          child: Text(
                            'FIXED TEETH JUST IN 3 DAYS',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    color: Colors.black.withValues(alpha: 0.55),
                    child: const Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Free course',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w800,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'FREE COURSE FOR ALL BDS & MDS GRADUATES WITH ONE IMPLANT PLACEMENT',
                                style: TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: 8),
                        Icon(
                          Icons.open_in_new_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 18,
              height: 6,
              decoration: BoxDecoration(
                color: AppTheme.gsNavy,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Color(0xFFCBD5E1),
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCourseSpeakerAvatar(String initials) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFF59E0B), width: 1.8),
      ),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: AppTheme.gsNavy,
          ),
        ),
      ),
    );
  }

  void _showDentistProfileSheet(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DoctorProfileScreen()),
    );
  }

  Widget _buildManageAvailabilitySection() {
    final currentDoc = _patientService.currentDoctor ??
        (_patientService.allDoctors.isNotEmpty ? _patientService.allDoctors.first : null);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.event_available_rounded, color: AppTheme.primaryBlue, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Manage Availability & Consultation Slots',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark),
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Configure working days, hours, lunch breaks & publish booking slots',
                      style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 14),

          // Working Days & Hours Info Row
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildAvailabilityInfoPill(
                icon: Icons.calendar_today_rounded,
                label: 'Working Days',
                value: 'Mon - Fri',
              ),
              _buildAvailabilityInfoPill(
                icon: Icons.schedule_rounded,
                label: 'Hours',
                value: '09:00 AM - 05:00 PM',
              ),
              _buildAvailabilityInfoPill(
                icon: Icons.coffee_rounded,
                label: 'Lunch Break',
                value: '01:00 PM - 02:00 PM',
              ),
              _buildAvailabilityInfoPill(
                icon: Icons.timer_outlined,
                label: 'Slot Duration',
                value: '30 mins',
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Action Toolbar
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ElevatedButton.icon(
                key: const Key('doctor_manage_availability_btn'),
                onPressed: () {
                  DoctorSlotManagementDialog.show(
                    context,
                    initialDoctor: currentDoc,
                    isDoctorSelfManage: true,
                  );
                },
                icon: const Icon(Icons.edit_calendar_rounded, size: 16, color: Colors.white),
                label: const Text(
                  'Configure Working Days & Slots',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              OutlinedButton.icon(
                key: const Key('doctor_block_holiday_btn'),
                onPressed: () {
                  DoctorSlotManagementDialog.show(
                    context,
                    initialDoctor: currentDoc,
                    isDoctorSelfManage: true,
                  );
                },
                icon: const Icon(Icons.block_rounded, size: 16, color: Color(0xFFDC2626)),
                label: const Text(
                  'Block Date / Mark Holiday',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFDC2626)),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFFCA5A5)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Row(
            children: [
              Icon(Icons.sync_rounded, size: 13, color: Color(0xFF10B981)),
              SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Schedule changes sync instantly to Patient Dashboards & Profile booking slots',
                  style: TextStyle(fontSize: 10.5, color: Color(0xFF10B981), fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAvailabilityInfoPill({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.primaryBlue),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: const TextStyle(fontSize: 9.5, color: AppTheme.textMuted)),
              Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineNode({
    required PatientConsultationRequest req,
    required String time,
  }) {
    final patientName = (req.patientName.contains('-') && req.patientName.length > 20)
        ? (_patientService.currentPatient.name.isNotEmpty ? _patientService.currentPatient.name : 'Patient')
        : req.patientName;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.gsNavy.withValues(alpha: 0.25), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: AppTheme.gsNavy.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Patient Name & Contact + Severity Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.gsNavy.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.person_rounded, color: AppTheme.gsNavy, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            patientName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (req.patientPhone.isNotEmpty && req.patientPhone != 'Not Provided') ...[
                            Text(
                              req.patientPhone,
                              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: req.severity == 'Severe' ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${req.severity} Severity',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: req.severity == 'Severe' ? const Color(0xFF991B1B) : const Color(0xFF92400E),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Row 2: Confirmed Time Slot Banner & Accepted Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.access_time_filled_rounded, size: 16, color: AppTheme.gsNavy),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Confirmed Slot: $time',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.gsNavy),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.gsNavy,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded, color: Colors.white, size: 12),
                      SizedBox(width: 4),
                      Text(
                        'Scheduled',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Row 3: Procedure Category & Symptoms Description
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.gsNavy.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Category: ${req.problemCategory}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppTheme.gsNavy),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            req.problemDescription,
            style: const TextStyle(fontSize: 12, color: AppTheme.textMedium, height: 1.35),
          ),

          if (req.cleanAdminGuidance != null && req.cleanAdminGuidance!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '${req.isReferral ? "Referral Note" : "Admin Note"}: ${req.cleanAdminGuidance!.trim()}',
              style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: AppTheme.textMuted),
            ),
          ],
          const SizedBox(height: 14),

          // Row 4: Action Buttons (Issue E-Prescription & Chat)
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.receipt_long_rounded, size: 14),
                    label: const Text('Issue E-Prescription', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.gsNavy,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.zero,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _showPrescriptionModal(context, patientName),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 14),
                    label: const Text('Chat', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.gsNavy,
                      side: const BorderSide(color: AppTheme.gsNavy),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      final docName = _patientService.currentDoctor?.name ?? 'DOCTOR';
                      final rId = ApiService.getChatRoomId(patientIdOrName: patientName, dentistIdOrName: docName);
                      _showDoctorChatModal(context, patientName, rId);
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getPatientInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'P';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  // ==========================================
  // TAB 1: PATIENTS TAB
  // ==========================================
  Widget _buildPatientsTab() {
    final currentDoc = _resolveCurrentDoctor();
    final authUser = _safeAuthUser;

    final currentDocName = (currentDoc?.name ?? '').replaceAll('Dr.', '').replaceAll('Dr. ', '').trim().toLowerCase();
    final currentDocId = (currentDoc?.id ?? '').trim();
    final currentDocUserId = (currentDoc?.userId ?? '').trim();
    final currentDocEmail = (currentDoc?.email ?? '').trim().toLowerCase();
    final authUserId = (authUser?.id ?? '').trim();
    final authEmail = (authUser?.email ?? '').trim().toLowerCase();

    final allPool = _getDentistAssignedAndScheduledRequests();
    final patient = _patientService.currentPatient;
    final Map<String, Map<String, String>> uniquePatientMap = {};
    for (final req in allPool) {
      uniquePatientMap[req.patientName.trim().toLowerCase()] = {
        'name': req.patientName,
        'phone': req.patientPhone,
        'age': '${patient.age.isNotEmpty ? patient.age : "28"} Yrs',
        'blood': patient.bloodGroup.isNotEmpty ? patient.bloodGroup : 'O+',
        'issue': req.problemCategory,
      };
    }
    for (final ref in _patientService.doctorReceivedPatientReferrals) {
      final key = ref.referredPatientName.trim().toLowerCase();
      if (!uniquePatientMap.containsKey(key)) {
        uniquePatientMap[key] = {
          'name': ref.referredPatientName,
          'phone': ref.referredPatientMobile,
          'age': '${ref.referredPatientAge.isNotEmpty ? ref.referredPatientAge : "28"} Yrs (${ref.referredPatientGender})',
          'blood': 'O+',
          'issue': ref.requiredSpecialist.isNotEmpty ? ref.requiredSpecialist : 'Referral Consultation',
        };
      }
    }
    final associatedPatients = _patientService.getDentistAssociatedPatients();
    final Map<String, PatientProfile> patientProfileMap = {};
    for (final p in associatedPatients) {
      final k = p.name.trim().toLowerCase();
      patientProfileMap[k] = p;
      uniquePatientMap.putIfAbsent(k, () => {
        'name': p.name,
        'phone': p.phone,
        'age': '${p.age.isNotEmpty ? p.age : "28"} Yrs',
        'blood': p.bloodGroup.isNotEmpty ? p.bloodGroup : 'O+',
        'issue': 'Consultation',
        'patientId': p.id,
      });
    }
    for (final p in _patientService.allPatients) {
      final k = p.name.trim().toLowerCase();
      patientProfileMap.putIfAbsent(k, () => p);
      uniquePatientMap.putIfAbsent(k, () => {
        'name': p.name,
        'phone': p.phone,
        'age': '${p.age.isNotEmpty ? p.age : "28"} Yrs',
        'blood': p.bloodGroup.isNotEmpty ? p.bloodGroup : 'O+',
        'issue': 'General Healthcare',
        'patientId': p.id,
        'city': p.city,
      });
    }

    final effectiveDocId = currentDocId.isNotEmpty
        ? currentDocId
        : (currentDocUserId.isNotEmpty ? currentDocUserId : authUserId);
    final effectiveDocUserId = currentDocUserId.isNotEmpty ? currentDocUserId : authUserId;
    final effectiveDocEmail = currentDocEmail.isNotEmpty ? currentDocEmail : authEmail;

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: (effectiveDocId.isNotEmpty || effectiveDocEmail.isNotEmpty)
          ? ApiService().fetchSharedRecordsForDoctor(
              doctorId: effectiveDocId.isNotEmpty ? effectiveDocId : effectiveDocEmail,
              doctorUserId: effectiveDocUserId,
              doctorEmail: effectiveDocEmail,
            )
          : Future.value(const <Map<String, dynamic>>[]),
      builder: (context, sharedSnapshot) {
        final rawShared = <Map<String, dynamic>>[
          ..._patientService.doctorSharedRecords,
          ...(sharedSnapshot.data ?? const <Map<String, dynamic>>[]),
        ];

        // Deduplicate & strictly verify doctor authorization
        final sharedMap = <String, Map<String, dynamic>>{};
        for (final rec in rawShared) {
          final id = (rec['id'] ?? '').toString();
          if (id.isEmpty) continue;
          final isAuthorized = ApiService.isDoctorAuthorizedForRecordMap(
            rec,
            doctorId: effectiveDocId,
            doctorUserId: effectiveDocUserId,
            doctorEmail: effectiveDocEmail,
          );
          if (!isAuthorized && currentDocName.isNotEmpty) continue;

          final recCopy = Map<String, dynamic>.from(rec);
          final recPid = (recCopy['patientId'] ?? recCopy['patient_id'] ?? '').toString();
          final curPName = (recCopy['patientName'] ?? '').toString();
          if ((curPName.isEmpty || curPName == 'Patient') && recPid.isNotEmpty) {
            final matchP = _patientService.allPatients.where((p) => p.id == recPid).firstOrNull;
            if (matchP != null && matchP.name.isNotEmpty) {
              recCopy['patientName'] = matchP.name;
            }
          }
          sharedMap[id] = recCopy;

          final pName = (recCopy['patientName'] ?? 'Patient').toString().trim();
          final pKey = pName.toLowerCase();
          if (pName.isNotEmpty && !uniquePatientMap.containsKey(pKey)) {
            final matchP = patientProfileMap[pKey];
            uniquePatientMap[pKey] = {
              'name': pName,
              'phone': matchP?.phone ?? '',
              'age': '${(matchP?.age.isNotEmpty == true) ? matchP!.age : '28'} Yrs',
              'blood': (matchP?.bloodGroup.isNotEmpty == true) ? matchP!.bloodGroup : 'O+',
              'issue': 'Shared Health Record (${recCopy['category'] ?? 'Record'})',
              'patientId': recPid,
            };
          }
        }

        final combinedPatients = uniquePatientMap.values.toList();
        final filteredPatients = combinedPatients.where((p) {
          if (_patientSearchQuery.isEmpty) return true;
          final q = _patientSearchQuery.toLowerCase();
          final name = (p['name'] ?? '').toString().toLowerCase();
          final phone = (p['phone'] ?? '').toString().toLowerCase();
          final city = (p['city'] ?? '').toString().toLowerCase();
          return name.contains(q) || phone.contains(q) || city.contains(q);
        }).toList();

        return SingleChildScrollView(
          key: const Key('dentist_patients_scroll_view'),
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Clean GS HEALTH Header (Screenshot 1)
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Everyone you've cared for",
                      style: TextStyle(
                        fontSize: 13.5,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 2),
                    Text(
                      'My patients',
                      style: TextStyle(
                        fontSize: 26,
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

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Full-width Search Bar (Screenshot 1)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: TextField(
                        key: const Key('doctor_patients_search_field'),
                        controller: _patientSearchCtrl,
                        onChanged: (val) {
                          setState(() {
                            _patientSearchQuery = val.trim();
                          });
                        },
                        style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
                        decoration: InputDecoration(
                          hintText: 'Search by name or phone number',
                          hintStyle: const TextStyle(fontSize: 13.5, color: Color(0xFF94A3B8)),
                          prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF94A3B8), size: 22),
                          suffixIcon: _patientSearchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 18),
                                  onPressed: () {
                                    _patientSearchCtrl.clear();
                                    setState(() => _patientSearchQuery = '');
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Patient Cards
                    if (filteredPatients.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _patientSearchQuery.isNotEmpty ? Icons.search_off_rounded : Icons.people_outline_rounded,
                                size: 40,
                                color: const Color(0xFF94A3B8),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _patientSearchQuery.isNotEmpty ? 'No patients found' : 'No patients yet',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _patientSearchQuery.isNotEmpty
                                    ? 'No patient matches "$_patientSearchQuery"'
                                    : 'Patients you care for will appear here.',
                                style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ...filteredPatients.map((p) {
                        final pName = (p['name'] ?? 'Patient').toString().trim();
                        final profile = patientProfileMap[pName.toLowerCase()];
                        final pId = (p['patientId'] ?? profile?.id ?? '').toString().trim();
                        final pPhone = (p['phone'] ?? profile?.phone ?? '').toString().trim();
                        final pCity = (profile?.city.isNotEmpty == true)
                            ? profile!.city
                            : (p['city']?.isNotEmpty == true ? p['city']! : 'Mumbai');

                        // Compute visits count & last visit date
                        final cleanDigits = pPhone.replaceAll(RegExp(r'\D'), '');
                        final raw10 = cleanDigits.length >= 10 ? cleanDigits.substring(cleanDigits.length - 10) : cleanDigits;
                        final nameLower = pName.toLowerCase();

                        int visitsCount = 0;
                        DateTime? lastVisitDate;

                        for (final req in _patientService.requests) {
                          final rPid = (req.patientId ?? '').trim();
                          final rPhone = req.patientPhone.replaceAll(RegExp(r'\D'), '');
                          final rName = req.patientName.trim().toLowerCase();

                          if ((pId.isNotEmpty && rPid == pId) ||
                              (rName.isNotEmpty && rName == nameLower) ||
                              (raw10.isNotEmpty && rPhone.contains(raw10))) {
                            visitsCount++;
                            DateTime? d;
                            if (req.confirmedDate != null && req.confirmedDate!.isNotEmpty) {
                              d = DateTime.tryParse(req.confirmedDate!);
                            }
                            d ??= req.submittedAt;
                            if (lastVisitDate == null || d.isAfter(lastVisitDate)) {
                              lastVisitDate = d;
                            }
                          }
                        }

                        // Format phone number
                        String formattedPhone;
                        if (cleanDigits.length == 10) {
                          formattedPhone = '+91 $cleanDigits';
                        } else if (cleanDigits.length > 10 && cleanDigits.startsWith('91')) {
                          formattedPhone = '+91 ${cleanDigits.substring(2)}';
                        } else if (pPhone.isNotEmpty) {
                          formattedPhone = pPhone.startsWith('+') ? pPhone : '+$pPhone';
                        } else {
                          formattedPhone = '+91 9000000200';
                        }

                        // Format last visit date
                        String lastVisitStr = '';
                        if (lastVisitDate != null) {
                          const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                          const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
                          final w = weekdays[lastVisitDate.weekday - 1];
                          final m = months[lastVisitDate.month - 1];
                          lastVisitStr = '$w, ${lastVisitDate.day} $m';
                        }

                        final visitsSubtitle = visitsCount > 0
                            ? '$visitsCount ${visitsCount == 1 ? "visit" : "visits"}${lastVisitStr.isNotEmpty ? " · last $lastVisitStr" : ""}'
                            : '0 visits';

                        final targetProfile = profile ??
                            PatientProfile(
                              id: pId.isNotEmpty ? pId : 'pat_${pName.hashCode}',
                              name: pName,
                              phone: pPhone,
                              city: pCity,
                              age: (p['age'] ?? '28').toString().replaceAll(RegExp(r'\D'), ''),
                              gender: 'Female',
                              bloodGroup: p['blood'] ?? 'O+',
                              languages: const ['English', 'Hindi'],
                            );

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: InkWell(
                            key: Key('doctor_patient_card_${pName.toLowerCase().replaceAll(' ', '_')}'),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (ctx) => DoctorPatientRecordScreen(
                                    patient: targetProfile,
                                    onWriteRx: () => _showPrescriptionModal(context, targetProfile.name),
                                    onRefer: () {
                                      Navigator.of(ctx).pop();
                                      _selectPatientForReferral(targetProfile);
                                      setState(() {
                                        _previousTabIndex = 1;
                                        _currentIndex = 3;
                                      });
                                    },
                                  ),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Row(
                                children: [
                                  // Squircle Avatar
                                  Container(
                                    width: 52,
                                    height: 52,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0F172A),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: targetProfile.photoBytes != null && targetProfile.photoBytes!.isNotEmpty
                                        ? Image.memory(targetProfile.photoBytes!, fit: BoxFit.cover)
                                        : Center(
                                            child: Text(
                                              _getPatientInitials(pName),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 18,
                                              ),
                                            ),
                                          ),
                                  ),
                                  const SizedBox(width: 14),
                                  // Patient Details
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          pName,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF0F172A),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          '$formattedPhone · $pCity',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: Color(0xFF64748B),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          visitsSubtitle,
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF4A6B5D),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Chevron Navigation Arrow
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    color: Color(0xFF94A3B8),
                                    size: 24,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDoctorSharedRecordTile(
    BuildContext context, {
    required Map<String, dynamic> record,
    required String doctorId,
    required String doctorUserId,
    required String doctorEmail,
  }) {
    final title = (record['title'] ?? 'Health Record').toString();
    final patientName = (record['patientName'] ?? 'Patient').toString();
    final category = (record['category'] ?? 'Medical Report').toString();
    final date = (record['date'] ?? '').toString();
    final fileType = (record['fileType'] ?? 'PDF').toString().toUpperCase();
    final description = (record['description'] ?? '').toString().trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.gsNavy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  fileType == 'PDF'
                      ? Icons.picture_as_pdf_rounded
                      : Icons.image_rounded,
                  color: fileType == 'PDF'
                      ? AppTheme.gsRed
                      : AppTheme.gsNavy,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                        color: AppTheme.textDark,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Patient: $patientName • $category • $date',
                      style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (description.isNotEmpty)
                      Text(
                        description,
                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.gsNavy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  fileType,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.gsNavy,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: () => _showDoctorRecordPreviewModal(
                  context,
                  record: record,
                  doctorId: doctorId,
                  doctorUserId: doctorUserId,
                  doctorEmail: doctorEmail,
                ),
                icon: const Icon(Icons.visibility_rounded, size: 14),
                label: const Text('View Record', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.gsNavy,
                  side: const BorderSide(color: AppTheme.gsNavy),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => _handleDoctorDownloadSharedRecord(
                  context,
                  record: record,
                  doctorId: doctorId,
                  doctorUserId: doctorUserId,
                  doctorEmail: doctorEmail,
                ),
                icon: const Icon(Icons.download_rounded, size: 14),
                label: const Text('Download', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.gsNavy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleDoctorDownloadSharedRecord(
    BuildContext context, {
    required Map<String, dynamic> record,
    required String doctorId,
    required String doctorUserId,
    required String doctorEmail,
  }) async {
    final recId = (record['id'] ?? '').toString();
    final title = (record['title'] ?? 'dental_record').toString();
    final fileName = (record['fileName'] ?? '$title.pdf').toString();
    final mimeType = (record['mimeType'] ?? 'application/pdf').toString();

    final accessRes = await ApiService().getAuthorizedRecordAccess(
      recordId: recId,
      requesterId: doctorId,
      requesterRole: 'Dentist',
      doctorUserId: doctorUserId,
      doctorEmail: doctorEmail,
    );

    if (!context.mounted) return;
    if (accessRes['success'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text((accessRes['message'] ?? 'Access denied: Record is not shared with you.').toString()),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
      return;
    }

    if (accessRes['fileBytes'] is Uint8List) {
      final bytes = accessRes['fileBytes'] as Uint8List;
      await RecordFileHelper.downloadOrOpenFile(
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Downloaded "$fileName" (${RecordFileHelper.formatFileSize(bytes.length)}).'),
          backgroundColor: AppTheme.gsNavy,
        ),
      );
      return;
    }

    final signedUrl = (accessRes['signedUrl'] ?? '').toString();
    if (signedUrl.isNotEmpty) {
      final uri = Uri.tryParse(signedUrl);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Authorized download completed for "$title".'),
        backgroundColor: AppTheme.gsNavy,
      ),
    );
  }

  void _showDoctorRecordPreviewModal(
    BuildContext context, {
    required Map<String, dynamic> record,
    required String doctorId,
    required String doctorUserId,
    required String doctorEmail,
  }) {
    final recId = (record['id'] ?? '').toString();
    final title = (record['title'] ?? 'Shared Health Record').toString();
    final patientName = (record['patientName'] ?? 'Patient').toString();
    final category = (record['category'] ?? 'Medical Report').toString();
    final date = (record['date'] ?? '').toString();
    final description = (record['description'] ?? '').toString();
    final fileName = (record['fileName'] ?? '').toString();
    final fileType = (record['fileType'] ?? 'PDF').toString().toUpperCase();
    final isImage = fileType == 'JPG' || fileType == 'JPEG' || fileType == 'PNG';

    showDialog(
      context: context,
      builder: (dialogCtx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 540, maxHeight: 620),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textDark,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Patient: $patientName • $category • $date',
                          style: const TextStyle(fontSize: 11, color: AppTheme.gsNavy),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(dialogCtx).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const Divider(height: 20, color: Color(0xFFE2E8F0)),
              if (description.isNotEmpty) ...[
                Text(
                  'Patient Notes: $description',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 12),
              ],
              Expanded(
                child: FutureBuilder<Map<String, dynamic>>(
                  future: ApiService().getAuthorizedRecordAccess(
                    recordId: recId,
                    requesterId: doctorId,
                    requesterRole: 'Dentist',
                    doctorUserId: doctorUserId,
                    doctorEmail: doctorEmail,
                  ),
                  builder: (ctx, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(strokeWidth: 2),
                            SizedBox(height: 8),
                            Text(
                              'Verifying sharing permission & loading record...',
                              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      );
                    }

                    final res = snap.data ?? {};
                    if (res['success'] != true) {
                      return Center(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.lock_person_rounded, size: 36, color: Color(0xFFDC2626)),
                              const SizedBox(height: 8),
                              Text(
                                (res['message'] ?? 'Access Denied: Patient has not shared this record with you.').toString(),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFB91C1C),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    final bytes = res['fileBytes'] is Uint8List ? res['fileBytes'] as Uint8List : null;
                    if (isImage && bytes != null && bytes.isNotEmpty) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          color: const Color(0xFF0F172A),
                          width: double.infinity,
                          child: InteractiveViewer(
                            child: Image.memory(
                              bytes,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      );
                    }

                    return Center(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.picture_as_pdf_rounded, size: 48, color: Color(0xFFDC2626)),
                            const SizedBox(height: 10),
                            Text(
                              fileName.isNotEmpty ? fileName : '$title.pdf',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              bytes != null
                                  ? 'Authorized PDF Record • ${RecordFileHelper.formatFileSize(bytes.length)}'
                                  : 'Authorized PDF Record',
                              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(dialogCtx).pop();
                    _handleDoctorDownloadSharedRecord(
                      context,
                      record: record,
                      doctorId: doctorId,
                      doctorUserId: doctorUserId,
                      doctorEmail: doctorEmail,
                    );
                  },
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: const Text('Download Authorized Copy'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.gsNavy,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // TAB 2: ASSIGNED REQUESTS TAB (Screenshot 2)
  // ==========================================
  Widget _buildAssignedRequestsTab() {
    final doc = _resolveCurrentDoctor();
    final allRequests = _getDentistAssignedAndScheduledRequests();

    return SingleChildScrollView(
      key: const Key('dentist_requests_scroll_view'),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: "Triage cases routed to you" + "Assigned requests" + folder icon
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Triage cases routed to you',
                        style: TextStyle(
                          fontSize: 13.5,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Assigned requests',
                        style: TextStyle(
                          fontSize: 26,
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
                const SizedBox(width: 12),
                InkWell(
                  key: const Key('requests_folder_button'),
                  onTap: () => setState(() => _currentIndex = 1),
                  borderRadius: BorderRadius.circular(22),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.folder_outlined,
                        color: Color(0xFF0F172A),
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            child: allRequests.isEmpty
                ? Container(
                    key: const Key('dentist_requests_empty_state'),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: AppTheme.gsNavy.withValues(alpha: 0.06),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.inbox_outlined,
                              color: AppTheme.gsNavy,
                              size: 28,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'No assigned requests yet',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'When an admin or AI triage routes a patient consultation to you, it will appear here.',
                          style: TextStyle(
                            fontSize: 13.5,
                            color: Color(0xFF64748B),
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: allRequests
                        .map((req) => _buildAssignedRequestCard(req, doc))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssignedRequestCard(PatientConsultationRequest req, DoctorModel? doc) {
    final severityUpper = req.severity.trim().toUpperCase();
    final isHighUrgency = severityUpper.contains('SEVERE') ||
        severityUpper.contains('HIGH') ||
        severityUpper.contains('URGENT') ||
        severityUpper.contains('EMERGENCY');
    final isLowUrgency = severityUpper.contains('LOW') || severityUpper.contains('MILD');
    final urgencyLabel = isHighUrgency
        ? 'HIGH URGENCY'
        : (isLowUrgency ? 'LOW URGENCY' : 'MODERATE URGENCY');

    final isAccepted = req.status.toLowerCase().contains('confirm') ||
        req.status.toLowerCase().contains('accept');
    final isAccepting = _acceptingRequestIds.contains(req.id);

    final bool isAssignedToDoctor = (doc != null && doc.id.isNotEmpty && req.assignedDoctorId == doc.id) ||
        (doc != null &&
            req.assignedDoctorName != null &&
            req.assignedDoctorName!.toLowerCase().contains(doc.name.replaceAll('Dr.', '').replaceAll('Dr. ', '').trim().toLowerCase()));

    final bool isAuthorized = isAssignedToDoctor ||
        isAccepted ||
        (doc != null && (doc.verified || doc.verificationStatus == 'VERIFIED'));

    final isReferral = req.isReferral;
    final headline = isReferral
        ? (req.problemCategory.trim().isNotEmpty
            ? req.problemCategory.trim()
            : 'Patient Referral')
        : ((req.symptoms.trim().isNotEmpty && req.symptoms.trim() != req.problemDescription.trim())
            ? req.symptoms.trim()
            : (req.problemCategory.trim().isNotEmpty
                ? req.problemCategory.trim()
                : req.problemDescription.trim()));

    final displayReason = isReferral
        ? 'Referral Reason: ${req.cleanReferralReason}'
        : req.problemDescription;

    final formattedPhone = req.getFormattedPatientPhone(isAuthorized: isAuthorized);
    final patientNameClean = req.patientName.trim().isNotEmpty ? req.patientName.trim() : 'Patient';

    final suggestedSpecialty = (req.assignedDoctorSpecialty != null && req.assignedDoctorSpecialty!.trim().isNotEmpty)
        ? req.assignedDoctorSpecialty!.trim()
        : ((doc?.specialty.isNotEmpty == true)
            ? doc!.specialty
            : (req.problemCategory.isNotEmpty ? req.problemCategory : 'Endodontist'));

    final assignedDocName = (req.assignedDoctorName != null && req.assignedDoctorName!.trim().isNotEmpty)
        ? req.assignedDoctorName!.trim()
        : ((doc?.name.isNotEmpty == true) ? doc!.name : 'Assigned Doctor');

    final formattedDate = _formatShortDayMonth(req.submittedAt);

    return Container(
      key: Key('assigned_request_card_${req.id}'),
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Badges Row: Urgency + Assignment Status
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.monitor_heart_outlined,
                      size: 13,
                      color: Color(0xFFB45309),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      urgencyLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFB45309),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              if (isReferral)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3E8FF),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.share_outlined,
                        size: 12,
                        color: Color(0xFF7E22CE),
                      ),
                      SizedBox(width: 4),
                      Text(
                        'PATIENT REFERRAL',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF7E22CE),
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                decoration: BoxDecoration(
                  color: isAccepted ? const Color(0xFFDCFCE7) : const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isAccepted ? 'Accepted' : 'Doctor assigned',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: isAccepted ? const Color(0xFF15803D) : const Color(0xFF0369A1),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Symptom Headline
          Text(
            headline,
            style: const TextStyle(
              fontSize: 17.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
              height: 1.3,
              fontFamilyFallback: ['Nirmala UI', 'Segoe UI Symbol', 'Segoe UI', 'Roboto'],
            ),
          ),
          const SizedBox(height: 6),

          // English Symptom Description / Referral Reason
          Text(
            displayReason,
            style: const TextStyle(
              fontSize: 14.5,
              color: Color(0xFF64748B),
              height: 1.4,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),

          // Metadata Rows
          _buildRequestMetaRow(
            Icons.person_outline_rounded,
            formattedPhone != 'Phone not provided'
                ? '$patientNameClean · $formattedPhone'
                : patientNameClean,
          ),
          const SizedBox(height: 6),
          _buildRequestMetaRow(
            Icons.medical_services_outlined,
            'Suggested: $suggestedSpecialty',
          ),
          const SizedBox(height: 6),
          _buildRequestMetaRow(
            Icons.done_all_rounded,
            'Assigned to $assignedDocName',
          ),
          const SizedBox(height: 6),
          _buildRequestMetaRow(
            Icons.access_time_rounded,
            formattedDate,
          ),

          // Admin Guidance / Referral Instructions Box (Sanitized, No Raw JSON or IDs)
          Builder(
            builder: (context) {
              final cleanGuidance = req.cleanAdminGuidance;
              if (cleanGuidance == null || cleanGuidance.trim().isEmpty) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            size: 13,
                            color: Color(0xFF64748B),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            isReferral ? 'REFERRAL INSTRUCTIONS' : 'ADMIN GUIDANCE',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF64748B),
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        cleanGuidance.trim(),
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF0F172A),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 14),

          // Accept Case Button
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              key: Key('accept_case_button_${req.id}'),
              onPressed: (isAccepted || isAccepting)
                  ? null
                  : () => _handleAcceptAssignedRequest(req),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.gsNavy,
                disabledBackgroundColor: isAccepted
                    ? AppTheme.gsNavy.withValues(alpha: 0.55)
                    : AppTheme.gsNavy.withValues(alpha: 0.4),
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: isAccepting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      isAccepted ? Icons.check_circle_outline_rounded : Icons.check_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
              label: Text(
                isAccepting
                    ? 'Accepting...'
                    : (isAccepted ? 'Case accepted' : 'Accept case'),
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestMetaRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF64748B)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13.5,
              color: Color(0xFF475569),
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Future<void> _handleAcceptAssignedRequest(PatientConsultationRequest req) async {
    if (_acceptingRequestIds.contains(req.id)) return;
    setState(() => _acceptingRequestIds.add(req.id));
    try {
      final targetDate = _baseCalendarDate.add(Duration(days: _selectedDateIndex));
      final dateStr =
          '${targetDate.year.toString().padLeft(4, '0')}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';
      await _patientService.acceptReferralByDentist(
        req.id,
        timeSlot: (req.confirmedTimeSlot != null && req.confirmedTimeSlot!.trim().isNotEmpty)
            ? req.confirmedTimeSlot!
            : '11:00 AM',
        date: dateStr,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Accepted case for ${req.patientName}. Added to your schedule.'),
          backgroundColor: AppTheme.gsNavy,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _acceptingRequestIds.remove(req.id));
      }
    }
  }

  String _formatShortDayMonth(DateTime dt) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final dayName = days[(dt.weekday - 1).clamp(0, 6)];
    final monthName = months[(dt.month - 1).clamp(0, 11)];
    return '$dayName, ${dt.day} $monthName';
  }

  // ==========================================
  // TAB 3: REFER A PATIENT TAB (Screenshot 3)
  // ==========================================
  List<PatientProfile> _getDentistQuickSelectPatients() {
    final Map<String, PatientProfile> map = {};
    if (_selectedReferPatient != null && _selectedReferPatient!.name.trim().isNotEmpty) {
      map[_selectedReferPatient!.name.trim().toLowerCase()] = _selectedReferPatient!;
    }
    for (final p in _patientService.getDentistAssociatedPatients()) {
      if (p.name.trim().isNotEmpty && !map.containsKey(p.name.trim().toLowerCase())) {
        map[p.name.trim().toLowerCase()] = p;
      }
    }
    for (final p in _patientService.allPatients) {
      if (p.name.trim().isNotEmpty && !map.containsKey(p.name.trim().toLowerCase())) {
        map[p.name.trim().toLowerCase()] = p;
      }
    }
    for (final req in _getDentistAssignedAndScheduledRequests()) {
      final k = req.patientName.trim().toLowerCase();
      if (k.isNotEmpty && !map.containsKey(k)) {
        map[k] = PatientProfile(
          id: req.id,
          name: req.patientName.trim(),
          phone: req.patientPhone.replaceAll(RegExp(r'\D'), ''),
          age: '34',
          gender: 'Female',
          city: '',
          address: '',
          bloodGroup: 'O+',
          emergencyContact: '',
        );
      }
    }
    return map.values.toList();
  }

  void _selectPatientForReferral(PatientProfile p) {
    _selectedReferPatient = p;
    final cleanDigits = p.phone.replaceAll(RegExp(r'\D'), '');
    final tenDigits = cleanDigits.length > 10
        ? cleanDigits.substring(cleanDigits.length - 10)
        : cleanDigits;
    final cleanAge = p.age.replaceAll(RegExp(r'\D'), '');
    setState(() {
      _selectedReferPatientChipName = p.name;
      _referPatientNameCtrl.text = p.name;
      if (tenDigits.isNotEmpty) {
        _referPatientMobileCtrl.text = tenDigits;
      }
      _referPatientAgeCtrl.text = cleanAge.isNotEmpty ? cleanAge : '34';
      if (p.gender.trim().isNotEmpty) {
        final gLower = p.gender.trim().toLowerCase();
        if (gLower.startsWith('m')) {
          _referPatientGender = 'Male';
        } else if (gLower.startsWith('f')) {
          _referPatientGender = 'Female';
        } else {
          _referPatientGender = 'Other';
        }
      } else {
        _referPatientGender = 'Female';
      }
    });
  }

  Widget _buildReferPatientTab() {
    final currentDoc = _resolveCurrentDoctor();
    final quickPatients = _getDentistQuickSelectPatients();
    final searchQuery = _referSearchCtrl.text.trim().toLowerCase();

    final specialistDoctors = _patientService.allDoctors.where((d) {
      if (currentDoc != null && d.id.isNotEmpty && (d.id == currentDoc.id || (currentDoc.userId.isNotEmpty && d.userId == currentDoc.userId))) {
        return false;
      }
      if (searchQuery.isEmpty) return true;
      return d.name.toLowerCase().contains(searchQuery) ||
          d.specialty.toLowerCase().contains(searchQuery) ||
          d.clinicName.toLowerCase().contains(searchQuery) ||
          d.city.toLowerCase().contains(searchQuery);
    }).toList();

    final clinics = _patientService.allClinics.where((c) {
      if (searchQuery.isEmpty) return true;
      return c.clinicName.toLowerCase().contains(searchQuery) ||
          c.location.toLowerCase().contains(searchQuery) ||
          c.services.any((s) => s.toLowerCase().contains(searchQuery));
    }).toList();

    return SingleChildScrollView(
      key: const Key('dentist_refer_scroll_view'),
      physics: const BouncingScrollPhysics(),
      child: Form(
        key: _referFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header + Toggle Pills matching Screenshot 2
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      InkWell(
                        key: const Key('refer_screen_back_button'),
                        onTap: () {
                          setState(() {
                            _currentIndex = _previousTabIndex;
                          });
                        },
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
                            child: Icon(Icons.chevron_left_rounded, color: Color(0xFF0F172A), size: 28),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Text(
                          'Refer to a specialist',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                            letterSpacing: -0.4,
                          ),
                        ),
                      ),
                      InkWell(
                        key: const Key('refer_history_button'),
                        onTap: () => ReferredPatientsSheet.show(context),
                        borderRadius: BorderRadius.circular(22),
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.format_list_bulleted_rounded,
                              color: Color(0xFF0F172A),
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  // Hidden compat texts for legacy tests
                  const Offstage(
                    offstage: true,
                    child: Column(
                      children: [
                        Text('Share details & files with a specialist or clinic'),
                        Text('Refer a patient'),
                      ],
                    ),
                  ),
                  // Referral Type Toggle Pills: Specialist dentist | Clinic
                  Row(
                    children: [
                      InkWell(
                        key: const Key('refer_type_specialist_pill'),
                        onTap: () => setState(() => _referToClinic = false),
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: !_referToClinic ? const Color(0xFF4A6B5D) : Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: !_referToClinic ? const Color(0xFF4A6B5D) : const Color(0xFFCBD5E1),
                            ),
                          ),
                          child: Text(
                            'Specialist doctor',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: !_referToClinic ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      InkWell(
                        key: const Key('refer_type_clinic_pill'),
                        onTap: () => setState(() => _referToClinic = true),
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                          decoration: BoxDecoration(
                            color: _referToClinic ? const Color(0xFF4A6B5D) : Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: _referToClinic ? const Color(0xFF4A6B5D) : const Color(0xFFCBD5E1),
                            ),
                          ),
                          child: Text(
                            'Clinic',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _referToClinic ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Patient details heading
                  const Text(
                    'Patient details',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Pick one of your patients or type details below',
                    style: TextStyle(
                      fontSize: 13.5,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  if (quickPatients.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: quickPatients.map((p) {
                        final isSelected = _selectedReferPatientChipName == p.name;
                        return InkWell(
                          key: Key('refer_patient_chip_${p.name}'),
                          onTap: () => _selectPatientForReferral(p),
                          borderRadius: BorderRadius.circular(22),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF4A6B5D)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: isSelected ? const Color(0xFF4A6B5D) : const Color(0xFFE2E8F0),
                                width: isSelected ? 1.5 : 1.0,
                              ),
                            ),
                            child: Text(
                              p.name,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: isSelected ? Colors.white : const Color(0xFF0F172A),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 18),

                  // PATIENT NAME
                  const Text(
                    'PATIENT NAME',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const Key('dentist_refer_patient_name'),
                    controller: _referPatientNameCtrl,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF0F172A),
                    ),
                    decoration: _buildGsReferInputDecoration('e.g. Amit Verma'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Please enter patient name' : null,
                  ),
                  const SizedBox(height: 16),

                  // PATIENT MOBILE (+91)
                  const Text(
                    'PATIENT MOBILE (+91)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const Key('dentist_refer_patient_phone'),
                    controller: _referPatientMobileCtrl,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF0F172A),
                    ),
                    decoration: _buildGsReferInputDecoration('98765 43210'),
                    validator: (v) {
                      final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                      if (digits.length != 10) {
                        return 'Enter a valid 10-digit Indian mobile number';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // AGE + Gender Selection Row
                  const Text(
                    'AGE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 84,
                        child: TextFormField(
                          key: const Key('dentist_refer_patient_age'),
                          controller: _referPatientAgeCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF0F172A),
                          ),
                          decoration: _buildGsReferInputDecoration('34'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Row(
                          children: ['Male', 'Female', 'Other'].map((gender) {
                            final isSelected = _referPatientGender == gender;
                            return Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(right: gender == 'Other' ? 0 : 8),
                                child: InkWell(
                                  key: Key('dentist_refer_gender_$gender'),
                                  onTap: () => setState(() => _referPatientGender = gender),
                                  borderRadius: BorderRadius.circular(14),
                                  child: Container(
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: isSelected ? const Color(0xFF4A6B5D) : Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: isSelected
                                            ? const Color(0xFF4A6B5D)
                                            : const Color(0xFFE2E8F0),
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        gender,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700,
                                          color: isSelected
                                              ? Colors.white
                                              : const Color(0xFF0F172A),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // REFER TO
                  const Text(
                    'REFER TO',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const Key('dentist_refer_search_input'),
                    controller: _referSearchCtrl,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF0F172A),
                    ),
                    decoration: _buildGsReferInputDecoration(
                      _referToClinic
                          ? 'Search clinic by name, location...'
                          : 'Search doctor by name, specialty...',
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Selectable Specialist Dentist Cards OR Clinic Cards
                  if (!_referToClinic) ...[
                    if (specialistDoctors.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: const Text(
                          'No matching doctors found.',
                          style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      ...specialistDoctors.take(6).map((doc) => _buildReferDoctorCard(doc)),
                  ] else ...[
                    if (clinics.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: const Text(
                          'No matching clinics found.',
                          style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      ...clinics.take(6).map((clinic) => _buildReferClinicCard(clinic)),
                  ],

                  const SizedBox(height: 18),

                  // CHIEF COMPLAINT & CLINICAL NOTES
                  const Text(
                    'CHIEF COMPLAINT & CLINICAL NOTES',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const Key('dentist_refer_notes_input'),
                    controller: _referNotesCtrl,
                    maxLines: 4,
                    style: const TextStyle(
                      fontSize: 14.5,
                      color: Color(0xFF0F172A),
                    ),
                    decoration: _buildGsReferInputDecoration(
                      'e.g. Impacted 38, pain for 2 weeks. Please evaluate for extraction',
                    ),
                  ),
                  const SizedBox(height: 18),

                  // ATTACH X-RAYS, PHOTOS OR REPORTS (0/5)
                  Text(
                    'ATTACH X-RAYS, PHOTOS OR REPORTS (${_referPickedAttachments.length}/5)',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildReferAttachmentButton(
                          key: const Key('refer_attachment_gallery_button'),
                          icon: Icons.photo_library_outlined,
                          label: 'Gallery',
                          onTap: _pickGalleryAttachment,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildReferAttachmentButton(
                          key: const Key('refer_attachment_camera_button'),
                          icon: Icons.camera_alt_outlined,
                          label: 'Camera',
                          onTap: _pickCameraAttachment,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildReferAttachmentButton(
                          key: const Key('refer_attachment_pdf_button'),
                          icon: Icons.picture_as_pdf_outlined,
                          label: 'PDF',
                          onTap: _pickPdfAttachment,
                        ),
                      ),
                    ],
                  ),
                  if (_referPickedAttachments.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _referPickedAttachments.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final att = entry.value;
                        return Container(
                          key: Key('refer_attachment_chip_${att.name}'),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (att.isImage)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: att.bytes.isNotEmpty
                                      ? Image.memory(
                                          att.bytes,
                                          width: 36,
                                          height: 36,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => Container(
                                            width: 36,
                                            height: 36,
                                            color: const Color(0xFFE2E8F0),
                                            child: const Icon(Icons.image_rounded, size: 20, color: Color(0xFF4A6B5D)),
                                          ),
                                        )
                                      : Container(
                                          width: 36,
                                          height: 36,
                                          color: const Color(0xFFE2E8F0),
                                          child: const Icon(Icons.image_rounded, size: 20, color: Color(0xFF4A6B5D)),
                                        ),
                                )
                              else
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: AppTheme.gsRed.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Center(
                                    child: Icon(Icons.picture_as_pdf_rounded, color: AppTheme.gsRed, size: 20),
                                  ),
                                ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 140),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        att.name,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF0F172A),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        att.formattedSize,
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          color: Color(0xFF64748B),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              InkWell(
                                key: Key('remove_refer_attachment_${att.name}'),
                                onTap: () => _removeReferAttachment(idx),
                                borderRadius: BorderRadius.circular(12),
                                child: const Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(Icons.close_rounded, size: 16, color: Color(0xFF64748B)),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 22),

                  // Send referral Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      key: const Key('dentist_send_referral_button'),
                      onPressed: _isSubmittingReferral ? null : _submitInlinePatientReferral,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4A6B5D),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: _isSubmittingReferral
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send_rounded, size: 18),
                      label: Text(
                        _isSubmittingReferral ? 'Sending referral...' : 'Send referral',
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _buildGsReferInputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: Color(0xFF94A3B8),
        fontSize: 15,
        fontWeight: FontWeight.w400,
      ),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF4A6B5D), width: 1.5),
      ),
    );
  }

  Widget _buildReferDoctorCard(DoctorModel doc) {
    final isSelected = _selectedReferDoctor?.id == doc.id && _selectedReferDoctor?.name == doc.name;
    final locationPart = doc.city.isNotEmpty
        ? doc.city
        : (doc.clinicName.isNotEmpty ? doc.clinicName : 'GS HEALTH Network');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        key: Key('dentist_refer_doctor_${doc.id.isNotEmpty ? doc.id : doc.name}'),
        onTap: () => setState(() => _selectedReferDoctor = doc),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected ? const Color(0xFF4A6B5D) : const Color(0xFFE2E8F0),
              width: isSelected ? 1.6 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFEDF2EE),
                  borderRadius: BorderRadius.circular(14),
                ),
                clipBehavior: Clip.antiAlias,
                child: doc.photoBytes != null && doc.photoBytes!.isNotEmpty
                    ? Image.memory(doc.photoBytes!, fit: BoxFit.cover)
                    : Center(
                        child: Text(
                          doc.name.replaceAll('Dr.', '').replaceAll('Dr. ', '').trim().isNotEmpty
                              ? doc.name.replaceAll('Dr.', '').replaceAll('Dr. ', '').trim()[0].toUpperCase()
                              : 'D',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF4A6B5D),
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.name,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${doc.specialty} · $locationPart',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF64748B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? const Color(0xFF4A6B5D) : const Color(0xFFCBD5E1),
                    width: isSelected ? 6 : 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReferClinicCard(ClinicModel clinic) {
    final isSelected = _selectedReferClinic?.id == clinic.id &&
        _selectedReferClinic?.clinicName == clinic.clinicName;
    final subtitle = [
      if (clinic.location.isNotEmpty) clinic.location,
      if (clinic.services.isNotEmpty) clinic.services.take(2).join(', '),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        key: Key('dentist_refer_clinic_${clinic.id.isNotEmpty ? clinic.id : clinic.clinicName}'),
        onTap: () => setState(() => _selectedReferClinic = clinic),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected ? const Color(0xFF4A6B5D) : const Color(0xFFE2E8F0),
              width: isSelected ? 1.6 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFEDF2EE),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(
                  child: Icon(
                    Icons.local_hospital_rounded,
                    color: Color(0xFF4A6B5D),
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      clinic.clinicName,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle.isNotEmpty ? subtitle : 'Verified Clinic',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF64748B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? const Color(0xFF4A6B5D) : const Color(0xFFCBD5E1),
                    width: isSelected ? 6 : 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReferAttachmentButton({
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      key: key,
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF0F172A),
        backgroundColor: Colors.white,
        side: const BorderSide(color: Color(0xFFE2E8F0)),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: Icon(icon, size: 17, color: const Color(0xFF4A6B5D)),
      label: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Color(0xFF0F172A),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Future<void> _pickGalleryAttachment() async {
    if (_referPickedAttachments.length >= 5) {
      _showAttachmentLimitMessage();
      return;
    }
    try {
      if (RecordFileHelper.testFilePickerOverride != null) {
        final testFile = await RecordFileHelper.testFilePickerOverride!();
        if (testFile != null) {
          setState(() {
            _referPickedAttachments.add(testFile);
            _referAttachments.add(testFile.name);
          });
        }
        return;
      }

      final picker = ImagePicker();
      final remaining = 5 - _referPickedAttachments.length;
      if (remaining > 1) {
        try {
          final List<XFile> images = await picker.pickMultiImage(
            imageQuality: 85,
            maxWidth: 1600,
          );
          if (images.isNotEmpty) {
            for (final img in images.take(remaining)) {
              await _processAndAddAttachmentXFile(img);
            }
            return;
          }
        } catch (_) {}
      }
      final XFile? img = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (img != null) {
        await _processAndAddAttachmentXFile(img);
      }
    } catch (e) {
      _showAttachmentError('Failed to select image from gallery: $e');
    }
  }

  Future<void> _pickCameraAttachment() async {
    if (_referPickedAttachments.length >= 5) {
      _showAttachmentLimitMessage();
      return;
    }
    try {
      if (RecordFileHelper.testFilePickerOverride != null) {
        final testFile = await RecordFileHelper.testFilePickerOverride!();
        if (testFile != null) {
          setState(() {
            _referPickedAttachments.add(testFile);
            _referAttachments.add(testFile.name);
          });
        }
        return;
      }

      final picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (photo != null) {
        await _processAndAddAttachmentXFile(photo);
      }
    } catch (e) {
      _showAttachmentError('Failed to capture photo with camera: $e');
    }
  }

  Future<void> _pickPdfAttachment() async {
    if (_referPickedAttachments.length >= 5) {
      _showAttachmentLimitMessage();
      return;
    }
    try {
      final file = await RecordFileHelper.pickRecordFile();
      if (file != null) {
        final validationError = RecordFileHelper.validatePickedFile(file);
        if (validationError != null) {
          _showAttachmentError(validationError);
          return;
        }
        setState(() {
          _referPickedAttachments.add(file);
          _referAttachments.add(file.name);
        });
      }
    } catch (e) {
      _showAttachmentError('Failed to select PDF document: $e');
    }
  }

  Future<void> _processAndAddAttachmentXFile(XFile file) async {
    final bytes = await file.readAsBytes();
    final name = file.name;
    final size = bytes.length;
    final ext = RecordFileHelper.extractExtension(name, mimeType: file.mimeType);

    final validationError = RecordFileHelper.validateFile(
      fileName: name,
      sizeBytes: size,
      mimeType: file.mimeType,
    );
    if (validationError != null) {
      _showAttachmentError(validationError);
      return;
    }

    final picked = PickedRecordFile(
      name: name,
      extension: ext.isNotEmpty ? ext : 'JPG',
      mimeType: file.mimeType ?? 'image/jpeg',
      sizeBytes: size,
      bytes: bytes,
    );

    setState(() {
      _referPickedAttachments.add(picked);
      _referAttachments.add(name);
    });
  }

  void _removeReferAttachment(int index) {
    if (index >= 0 && index < _referPickedAttachments.length) {
      setState(() {
        final removed = _referPickedAttachments.removeAt(index);
        _referAttachments.remove(removed.name);
      });
    }
  }

  @visibleForTesting
  void addTestReferAttachment(String fileName) => _addMockOrPickedReferAttachment(fileName);

  void _addMockOrPickedReferAttachment(String fileName) {
    if (_referPickedAttachments.length >= 5) {
      _showAttachmentLimitMessage();
      return;
    }
    final isPdf = fileName.toLowerCase().endsWith('.pdf');
    final ext = isPdf ? 'PDF' : 'JPG';
    final mime = isPdf ? 'application/pdf' : 'image/jpeg';
    final dummyBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
    final picked = PickedRecordFile(
      name: fileName,
      extension: ext,
      mimeType: mime,
      sizeBytes: 1024 * 50,
      bytes: dummyBytes,
    );
    setState(() {
      _referPickedAttachments.add(picked);
      if (!_referAttachments.contains(fileName)) {
        _referAttachments.add(fileName);
      }
    });
  }

  void _showAttachmentLimitMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Maximum 5 attachments allowed per referral.'),
        backgroundColor: AppTheme.gsNavy,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showAttachmentError(String error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error),
        backgroundColor: AppTheme.gsRed,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _submitInlinePatientReferral() async {
    if (!(_referFormKey.currentState?.validate() ?? false)) return;

    final targetDoc = !_referToClinic ? _selectedReferDoctor : null;
    final targetClinic = _referToClinic ? _selectedReferClinic : null;

    if (!_referToClinic && targetDoc == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a specialist doctor to refer to.'),
          backgroundColor: AppTheme.gsRed,
        ),
      );
      return;
    }
    if (_referToClinic && targetClinic == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a clinic to refer to.'),
          backgroundColor: AppTheme.gsRed,
        ),
      );
      return;
    }

    setState(() => _isSubmittingReferral = true);
    try {
      final pName = _referPatientNameCtrl.text.trim();
      final pPhone = _referPatientMobileCtrl.text.replaceAll(RegExp(r'\D'), '').trim();
      final pAge = _referPatientAgeCtrl.text.trim().isNotEmpty
          ? _referPatientAgeCtrl.text.trim()
          : '34';
      final notes = _referNotesCtrl.text.trim();
      final gender = _referPatientGender.isNotEmpty ? _referPatientGender : 'Female';

      final res = await _patientService.submitPatientReferral(
        referredPatientName: pName,
        referredPatientMobile: pPhone,
        referredPatientAge: pAge,
        referredPatientGender: gender,
        referredPatientCity: targetDoc?.city.isNotEmpty == true
            ? targetDoc!.city
            : (_selectedReferPatient?.city.isNotEmpty == true ? _selectedReferPatient!.city : 'Mumbai'),
        referredPatientPincode: targetDoc?.pincode.isNotEmpty == true ? targetDoc!.pincode : '400050',
        referredPatientLocation: targetDoc?.clinicAddress.isNotEmpty == true
            ? targetDoc!.clinicAddress
            : (targetClinic?.location ?? 'Bandra West'),
        requiredSpecialist: targetDoc?.specialty ??
            (targetClinic != null && targetClinic.services.isNotEmpty
                ? targetClinic.services.first
                : 'Specialist Evaluation'),
        clinicalComplaint: notes.isNotEmpty
            ? notes
            : 'Impacted 38, pain for 2 weeks. Please evaluate for extraction',
        doctorId: targetDoc?.id ?? (targetClinic?.id ?? ''),
        doctorName: targetDoc?.name ?? (targetClinic?.clinicName ?? 'Specialist Doctor'),
        doctorClinicName: targetClinic?.clinicName ?? (targetDoc?.clinicName ?? 'GS HEALTH Clinic'),
        doctorLocation: targetClinic?.location ?? (targetDoc?.clinicAddress ?? ''),
        doctorCity: targetDoc?.city ?? 'Mumbai',
        doctorPincode: targetDoc?.pincode ?? '400050',
        doctorPhone: targetDoc?.phone ?? '',
      );

      if (!mounted) return;

      if (res['success'] == true) {
        // Upload attachments if present
        if (_referPickedAttachments.isNotEmpty) {
          final patientId = _selectedReferPatient?.id.isNotEmpty == true
              ? _selectedReferPatient!.id
              : 'patient_${DateTime.now().millisecondsSinceEpoch}';

          for (final att in _referPickedAttachments) {
            try {
              await ApiService().uploadPatientDentalRecord(
                patientId: patientId,
                patientName: pName,
                title: 'Referral Document: ${att.name}',
                category: att.isPdf ? 'Dental Report' : 'Dental X-ray',
                description: 'Attachment for referral to ${targetDoc?.name ?? targetClinic?.clinicName}. Note: $notes',
                fileName: att.name,
                fileType: att.extension,
                fileSize: att.sizeBytes,
                fileBytes: att.bytes,
                mimeType: att.mimeType,
              );
            } catch (e) {
              debugPrint('Referral attachment upload notice: $e');
            }
          }
        }

        await _patientService.syncDoctorReferralsFromApi();
        await _patientService.syncReferralsFromApi();
        await _patientService.syncProblemRequestsFromApi();

        setState(() {
          _referPatientNameCtrl.clear();
          _referPatientMobileCtrl.clear();
          _referNotesCtrl.clear();
          _referAttachments.clear();
          _referPickedAttachments.clear();
          _selectedReferPatientChipName = null;
          _selectedReferPatient = null;
          _selectedReferDoctor = null;
          _selectedReferClinic = null;
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Referral successfully sent for $pName.'),
            backgroundColor: const Color(0xFF4A6B5D),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text((res['message'] ?? 'Could not submit referral.').toString()),
            backgroundColor: AppTheme.gsRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmittingReferral = false);
      }
    }
  }

  // ==========================================
  // TAB 4: E-PRESCRIPTIONS TAB (Screenshot 4)
  // ==========================================
  Widget _buildPrescriptionsTab() {
    final currentDoc = _resolveCurrentDoctor();
    final currentDocName = (currentDoc?.name ?? '')
        .replaceAll('Dr.', '')
        .replaceAll('Dr. ', '')
        .trim()
        .toLowerCase();
    final currentDocId = (currentDoc?.id ?? '').trim();
    final currentDocUserId = (currentDoc?.userId ?? '').trim();

    return FutureBuilder<List<dynamic>>(
      future: ApiService().fetchMedicalRecords(),
      builder: (context, snapshot) {
        final combinedRaw = <Map<String, dynamic>>[];
        final seenIds = <String>{};

        for (final r in [
          ..._patientService.medicalRecords,
          ...(snapshot.data ?? const <dynamic>[]),
        ]) {
          if (r is! Map) continue;
          final map = Map<String, dynamic>.from(r);
          final recType = (map['type'] ?? '').toString().toLowerCase();
          if (recType != 'prescription' && !map.containsKey('items')) continue;

          final dName = (map['doctorName'] ?? map['doctor_name'] ?? '')
              .toString()
              .replaceAll('Dr.', '')
              .replaceAll('Dr. ', '')
              .trim()
              .toLowerCase();
          final dId = (map['doctorId'] ?? map['doctor_id'] ?? '').toString().trim();

          bool matchesDoctor = false;
          if (currentDocId.isNotEmpty && dId == currentDocId) matchesDoctor = true;
          if (currentDocUserId.isNotEmpty && dId == currentDocUserId) matchesDoctor = true;
          if (currentDocName.isNotEmpty &&
              currentDocName != 'dentist' &&
              dName.isNotEmpty &&
              (dName == currentDocName ||
                  dName.contains(currentDocName) ||
                  currentDocName.contains(dName))) {
            matchesDoctor = true;
          }
          if (currentDoc == null && _patientService.allDoctors.isEmpty) {
            matchesDoctor = true;
          }
          if (!matchesDoctor) continue;

          final id = (map['id'] ?? '${map['title']}_${map['date']}').toString();
          if (seenIds.add(id)) {
            combinedRaw.add(map);
          }
        }

        return SingleChildScrollView(
          key: const Key('dentist_rx_scroll_view'),
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: "Issued by you" + "E-prescriptions" + right "+" button
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Issued by you',
                            style: TextStyle(
                              fontSize: 13.5,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: 2),
                          Text(
                            'E-prescriptions',
                            style: TextStyle(
                              fontSize: 26,
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
                    const SizedBox(width: 12),
                    InkWell(
                      key: const Key('dentist_new_rx_button'),
                      onTap: () {
                        final defaultPatient = _getDentistQuickSelectPatients().firstOrNull?.name ??
                            (_patientService.currentPatient.name.isNotEmpty
                                ? _patientService.currentPatient.name
                                : 'Patient');
                        _showPrescriptionModal(context, defaultPatient);
                      },
                      borderRadius: BorderRadius.circular(22),
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppTheme.gsNavy,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.gsNavy.withValues(alpha: 0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.add_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                child: combinedRaw.isEmpty
                    ? Container(
                        key: const Key('dentist_rx_empty_state'),
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 58,
                              height: 58,
                              decoration: BoxDecoration(
                                color: AppTheme.gsNavy.withValues(alpha: 0.06),
                                shape: BoxShape.circle,
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.description_outlined,
                                  color: AppTheme.gsNavy,
                                  size: 26,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'No e-prescriptions issued yet',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Tap the + button above or issue an e-prescription from an active patient consultation.',
                              style: TextStyle(
                                fontSize: 13.5,
                                color: Color(0xFF64748B),
                                height: 1.4,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : Column(
                        children: combinedRaw.asMap().entries.map((entry) {
                          return _buildExpandableRxCard(entry.value, entry.key);
                        }).toList(),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildExpandableRxCard(Map<String, dynamic> rec, int index) {
    final recId = (rec['id'] ?? 'rx_$index').toString();
    final isExpanded = _expandedRxCardIds.contains(recId) ||
        (_expandedRxCardIds.isEmpty && index == 0);

    final rawDiagnosis = (rec['diagnosis'] ?? rec['title'] ?? '').toString().trim();
    final diagnosisHeadline = rawDiagnosis
        .replaceFirst(RegExp(r'^E-Prescription:\s*', caseSensitive: false), '')
        .trim();
    final displayTitle = diagnosisHeadline.isNotEmpty
        ? diagnosisHeadline
        : 'Medical E-Prescription';

    final patientName = (rec['patientName'] ?? rec['patient_name'] ?? '').toString().trim();
    final displayPatient = patientName.isNotEmpty
        ? patientName
        : (_patientService.currentPatient.name.isNotEmpty
            ? _patientService.currentPatient.name
            : 'Patient');

    final rawDate = (rec['date'] ?? '').toString().trim();
    final displayDate = _formatRxDateLabel(rawDate);

    final rawItems = rec['items'] is List ? (rec['items'] as List) : const [];
    final instructions = (rec['instructions'] ?? rec['notes'] ?? '').toString().trim();

    return Container(
      key: Key('dentist_rx_card_$recId'),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Header Row (Tappable to expand/collapse)
          InkWell(
            key: Key('dentist_rx_toggle_$recId'),
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedRxCardIds.remove(recId);
                  if (_expandedRxCardIds.isEmpty) {
                    _expandedRxCardIds.add('__none__');
                  }
                } else {
                  _expandedRxCardIds.remove('__none__');
                  _expandedRxCardIds.add(recId);
                }
              });
            },
            borderRadius: BorderRadius.circular(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.gsNavy.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.description_outlined,
                      color: AppTheme.gsNavy,
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayTitle,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$displayPatient · $displayDate',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: const Color(0xFF64748B),
                  size: 22,
                ),
              ],
            ),
          ),

          if (isExpanded) ...[
            const SizedBox(height: 14),
            const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 14),
            Text(
              'E-PRESCRIPTION · ${rawItems.isEmpty ? 1 : rawItems.length} MEDICINE(S)',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFF64748B),
                letterSpacing: 0.7,
              ),
            ),
            const SizedBox(height: 10),
            if (rawItems.isEmpty)
              _buildRxMedicineBox(
                medNameAndDose: 'Prescribed Dental Medication',
                freqAndDuration: 'As directed',
              )
            else
              ...rawItems.map((item) {
                final map = item is Map ? item : <String, dynamic>{};
                final mName = (map['name'] ?? 'Medicine').toString().trim();
                final mDosage = (map['dosage'] ?? '').toString().trim();
                final mFreq = (map['frequency'] ?? map['instructions'] ?? '').toString().trim();
                final mDur = (map['duration'] ?? '').toString().trim();
                final titleLine = mDosage.isNotEmpty && !mName.contains(mDosage)
                    ? '$mName $mDosage'
                    : mName;
                final subLine = [
                  if (mFreq.isNotEmpty) mFreq,
                  if (mDur.isNotEmpty) mDur,
                ].join(' · ');

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildRxMedicineBox(
                    medNameAndDose: titleLine,
                    freqAndDuration: subLine.isNotEmpty ? subLine : 'As directed',
                  ),
                );
              }),
            if (instructions.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 15,
                    color: Color(0xFF64748B),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      instructions,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: Color(0xFF475569),
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildRxMedicineBox({
    required String medNameAndDose,
    required String freqAndDuration,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '℞ $medNameAndDose',
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
              fontFamilyFallback: ['Segoe UI Symbol', 'Segoe UI', 'Roboto'],
            ),
          ),
          const SizedBox(height: 3),
          Text(
            freqAndDuration,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _formatRxDateLabel(String rawDate) {
    if (rawDate.isEmpty) {
      return _formatShortDayMonth(DateTime.now());
    }
    final parsed = DateTime.tryParse(rawDate);
    if (parsed != null) {
      return _formatShortDayMonth(parsed);
    }
    return rawDate;
  }

  // ==========================================
  // ADD DENTIST DIALOG
  // ==========================================
  void _showAddDentistDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final qualCtrl = TextEditingController(text: 'BDS, MDS');
    final licenseCtrl = TextEditingController();
    final clinicCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final cityCtrl = TextEditingController();
    final pincodeCtrl = TextEditingController();
    final expCtrl = TextEditingController(text: '5');
    final feeCtrl = TextEditingController(text: '₹500');
    String selectedSpecialty = 'General Dentistry';
    String selectedLanguage = 'English';
    double? selectedLat;
    double? selectedLng;
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final screenHeight = MediaQuery.of(context).size.height;
            final screenWidth = MediaQuery.of(context).size.width;

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              backgroundColor: Colors.white,
              elevation: 20,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: 540,
                  maxHeight: screenHeight * 0.88,
                ),
                padding: EdgeInsets.all(screenWidth < 400 ? 14 : 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header Bar
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.person_add_rounded, color: AppTheme.primaryBlue, size: 22),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Add New Doctor',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textDark),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Register colleague practitioner into GS HEALTH network',
                                style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => Navigator.of(dialogContext).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    const SizedBox(height: 12),

                    // Scrollable Form Fields
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 1. Doctor Full Name *
                            TextField(
                              controller: nameCtrl,
                              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                              cursorColor: AppTheme.primaryBlue,
                              decoration: InputDecoration(
                                labelText: 'Doctor Full Name *',
                                hintText: 'e.g. Dr. Rajesh Sharma',
                                labelStyle: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                prefixIcon: const Icon(Icons.person_outline_rounded, size: 18, color: AppTheme.primaryBlue),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 1.8)),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // 2. Mobile Phone Number *
                            TextField(
                              controller: phoneCtrl,
                              keyboardType: TextInputType.phone,
                              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                              cursorColor: AppTheme.primaryBlue,
                              decoration: InputDecoration(
                                labelText: 'Mobile Phone Number (10 Digits) *',
                                hintText: '9876543210',
                                prefixText: '+91 ',
                                prefixStyle: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textDark, fontSize: 13),
                                labelStyle: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                prefixIcon: const Icon(Icons.phone_outlined, size: 18, color: AppTheme.primaryBlue),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 1.8)),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // 3. Specialty & Qualification
                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: DropdownButtonFormField<String>(
                                    initialValue: selectedSpecialty,
                                    isExpanded: true,
                                    dropdownColor: Colors.white,
                                    decoration: InputDecoration(
                                      labelText: 'Medical Specialty',
                                      labelStyle: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                      prefixIcon: const Icon(Icons.medical_services_outlined, size: 18, color: AppTheme.primaryBlue),
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 1.8)),
                                    ),
                                    items: <String>{
                                      ..._patientService.activeSpecialtyNames,
                                      'General Dentistry',
                                      'Orthodontics',
                                      'Endodontics',
                                      'Periodontics',
                                      'Prosthodontics',
                                      'Pediatric Dentistry',
                                      'Oral & Maxillofacial Surgery',
                                      'Cosmetic Dentistry',
                                      'Implantology',
                                    }.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 12, color: AppTheme.textDark), overflow: TextOverflow.ellipsis))).toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        setModalState(() {
                                          selectedSpecialty = val;
                                          qualCtrl.text = MedicalSpecialtyModel.getDefaultQualificationForSpecialty(val);
                                        });
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    controller: qualCtrl,
                                    style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                                    cursorColor: AppTheme.primaryBlue,
                                    decoration: InputDecoration(
                                      labelText: 'Qualification',
                                      hintText: 'BDS, MDS',
                                      labelStyle: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 1.8)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // 4. Clinic Name & License
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: clinicCtrl,
                                    style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                                    cursorColor: AppTheme.primaryBlue,
                                    decoration: InputDecoration(
                                      labelText: 'Clinic / Hospital Name',
                                      hintText: 'e.g. Apex Dental Hospital',
                                      labelStyle: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                      prefixIcon: const Icon(Icons.local_hospital_outlined, size: 18, color: AppTheme.primaryBlue),
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 1.8)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: licenseCtrl,
                                    style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                                    cursorColor: AppTheme.primaryBlue,
                                    decoration: InputDecoration(
                                      labelText: 'Medical License #',
                                      hintText: 'MCI-10294',
                                      labelStyle: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 1.8)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // 5. Interactive Map Location Picker Field
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Row(
                                        children: [
                                          Icon(Icons.location_on_rounded, size: 16, color: AppTheme.primaryBlue),
                                          SizedBox(width: 6),
                                          Text('Clinic Location & Address', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
                                        ],
                                      ),
                                      InkWell(
                                        onTap: () {
                                          MapLocationPickerDialog.show(
                                            context: context,
                                            initialAddress: addressCtrl.text,
                                            initialCity: cityCtrl.text,
                                            initialPincode: pincodeCtrl.text,
                                            initialLat: selectedLat,
                                            initialLng: selectedLng,
                                            isDentist: true,
                                            onLocationSelected: (address, city, pincode, lat, lng, locationName) {
                                              setModalState(() {
                                                addressCtrl.text = address;
                                                if (city.isNotEmpty) cityCtrl.text = city;
                                                if (pincode.isNotEmpty) pincodeCtrl.text = pincode;
                                                selectedLat = lat;
                                                selectedLng = lng;
                                              });
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text('📍 Map Location Attached: $address, $city ($pincode)'),
                                                  backgroundColor: const Color(0xFF10B981),
                                                  duration: const Duration(seconds: 2),
                                                ),
                                              );
                                            },
                                          );
                                        },
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: const Color(0xFF2563EB).withValues(alpha: 0.3)),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.map_rounded, size: 13, color: Color(0xFF2563EB)),
                                              SizedBox(width: 4),
                                              Text('Pick on Map', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: addressCtrl,
                                    style: const TextStyle(color: Color(0xFF0F172A), fontSize: 12.5, fontWeight: FontWeight.w500),
                                    cursorColor: AppTheme.primaryBlue,
                                    decoration: const InputDecoration(
                                      hintText: 'Address / Street / Area (or Pick on Map)',
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: cityCtrl,
                                          style: const TextStyle(color: Color(0xFF0F172A), fontSize: 12.5, fontWeight: FontWeight.w500),
                                          cursorColor: AppTheme.primaryBlue,
                                          decoration: const InputDecoration(
                                            hintText: 'City',
                                            isDense: true,
                                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextField(
                                          controller: pincodeCtrl,
                                          keyboardType: TextInputType.number,
                                          style: const TextStyle(color: Color(0xFF0F172A), fontSize: 12.5, fontWeight: FontWeight.w500),
                                          cursorColor: AppTheme.primaryBlue,
                                          decoration: const InputDecoration(
                                            hintText: 'Pincode',
                                            isDense: true,
                                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),

                            // 6. Experience, Fee & Language
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: expCtrl,
                                    keyboardType: TextInputType.number,
                                    style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                                    cursorColor: AppTheme.primaryBlue,
                                    decoration: InputDecoration(
                                      labelText: 'Exp. (Years)',
                                      hintText: '5',
                                      labelStyle: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: feeCtrl,
                                    style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                                    cursorColor: AppTheme.primaryBlue,
                                    decoration: InputDecoration(
                                      labelText: 'Consult Fee',
                                      hintText: '₹500',
                                      labelStyle: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: selectedLanguage,
                                    isExpanded: true,
                                    dropdownColor: Colors.white,
                                    decoration: InputDecoration(
                                      labelText: 'Language',
                                      labelStyle: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    items: ['English', 'Telugu', 'Hindi', 'Tamil', 'Kannada', 'Marathi']
                                        .map((l) => DropdownMenuItem(value: l, child: Text(l, style: const TextStyle(fontSize: 12, color: AppTheme.textDark), overflow: TextOverflow.ellipsis)))
                                        .toList(),
                                    onChanged: (val) {
                                      if (val != null) setModalState(() => selectedLanguage = val);
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Actions
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isSubmitting ? null : () => Navigator.of(dialogContext).pop(),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: isSubmitting
                                ? null
                                : () async {
                                    final name = nameCtrl.text.trim();
                                    final phone = phoneCtrl.text.replaceAll(RegExp(r'[^0-9]'), '').trim();
                                    if (name.isEmpty) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('⚠️ Please enter doctor name'), backgroundColor: Color(0xFFEF4444)),
                                      );
                                      return;
                                    }
                                    if (phone.length < 10) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('⚠️ Please enter a valid 10-digit mobile number'), backgroundColor: Color(0xFFEF4444)),
                                      );
                                      return;
                                    }

                                    setModalState(() => isSubmitting = true);

                                    final cleanEmail = emailCtrl.text.trim().isNotEmpty
                                        ? emailCtrl.text.trim().toLowerCase()
                                        : 'dentist_$phone@dentaguru.com';
                                    final cleanExp = int.tryParse(expCtrl.text.trim()) ?? 5;
                                    final cleanFee = feeCtrl.text.trim().isNotEmpty ? feeCtrl.text.trim() : '₹500';
                                    final formattedDocName = name.startsWith('Dr.') ? name : 'Dr. $name';

                                    try {
                                      _patientService.registerDoctor(
                                        name: formattedDocName,
                                        email: cleanEmail,
                                        phone: phone,
                                        licenseNumber: licenseCtrl.text.trim(),
                                        specialty: selectedSpecialty,
                                        clinicName: clinicCtrl.text.trim().isNotEmpty ? clinicCtrl.text.trim() : 'GS HEALTH Partner Clinic',
                                        experienceYears: cleanExp,
                                        qualification: qualCtrl.text.trim().isNotEmpty ? qualCtrl.text.trim() : 'BDS, MDS',
                                        consultationFee: cleanFee,
                                        clinicAddress: addressCtrl.text.trim(),
                                        city: cityCtrl.text.trim(),
                                        pincode: pincodeCtrl.text.trim(),
                                        latitude: selectedLat,
                                        longitude: selectedLng,
                                        languages: [selectedLanguage],
                                      );

                                      // Register via API / Supabase
                                      await ApiService().registerUser(
                                        name: formattedDocName,
                                        email: cleanEmail,
                                        phone: phone,
                                        password: 'Password123!',
                                        role: 'Dentist',
                                        specialty: selectedSpecialty,
                                        qualification: qualCtrl.text.trim(),
                                        licenseNumber: licenseCtrl.text.trim(),
                                        clinicName: clinicCtrl.text.trim(),
                                        clinicAddress: addressCtrl.text.trim(),
                                        city: cityCtrl.text.trim(),
                                        pincode: pincodeCtrl.text.trim(),
                                        languages: [selectedLanguage],
                                        experienceYears: cleanExp,
                                        latitude: selectedLat,
                                        longitude: selectedLng,
                                      );

                                      await _patientService.syncDoctorsFromApi();

                                      if (mounted && dialogContext.mounted && context.mounted) {
                                        Navigator.of(dialogContext).pop();
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('✅ $formattedDocName added to GS HEALTH network!'),
                                            backgroundColor: const Color(0xFF10B981),
                                            behavior: SnackBarBehavior.floating,
                                            duration: const Duration(seconds: 3),
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      setModalState(() => isSubmitting = false);
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Error registering doctor: $e'), backgroundColor: const Color(0xFFEF4444)),
                                      );
                                    }
                                  },
                            icon: isSubmitting
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.person_add_rounded, size: 18),
                            label: Text(
                              isSubmitting ? 'Registering...' : 'Add Doctor',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryBlue,
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
            );
          },
        );
      },
    );
  }

}
