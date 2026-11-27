import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/denta_guru_logo.dart';
import '../../../../core/widgets/recent_updates_preview_section.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/session_service.dart';
import '../../../../core/services/firebase_service.dart';
import '../../../../core/utils/record_file_helper.dart';
import '../../../../core/utils/prescription_pdf_generator.dart';
import '../../../../core/models/specialty_clinical_config.dart';
import '../../../../core/constants/booking_rules_config.dart';
import '../../../../core/widgets/whatsapp_chat_modal.dart';
import '../widgets/referred_patients_sheet.dart';
import '../widgets/book_visit_flow_dialog.dart';
import '../widgets/book_consultation_fab.dart';
import '../widgets/appointment_management_dialog.dart';
import '../widgets/gs_health_patient_sponsored_banner.dart';
import '../../../../core/widgets/need_help_card.dart';
import 'find_doctors_screen.dart';
import 'refer_a_friend_screen.dart';
import 'talk_to_dentist_now_screen.dart';
import 'ai_triage_screen.dart';
import 'patient_profile_completion_screen.dart';

class PatientDashboardScreen extends StatefulWidget {
  final int initialTabIndex;
  final String? openBookingDoctorId;
  final String? initialBookingDate;
  final String? initialBookingSlot;
  final String? initialBookingMode;

  const PatientDashboardScreen({
    super.key,
    this.initialTabIndex = 0,
    this.openBookingDoctorId,
    this.initialBookingDate,
    this.initialBookingSlot,
    this.initialBookingMode,
  });

  @override
  State<PatientDashboardScreen> createState() => _PatientDashboardScreenState();
}

class _PatientDashboardScreenState extends State<PatientDashboardScreen> with TickerProviderStateMixin {
  int _currentIndex = 0;
  bool _handledBookingDeepLink = false;
  final PatientProblemService _patientService = PatientProblemService();

  late AnimationController _entryController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _pulseScaleAnimation;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTabIndex.clamp(0, 3);
    _patientService.addListener(_onServiceUpdate);
    _patientService.syncAllDataFromApi();
    _patientService.syncAppointmentsFromApi();
    _patientService.syncDoctorsFromApi(includeUnavailable: true);
    _patientService.syncReferralsFromApi();
    _patientService.syncNotificationsFromApi(role: 'Patient');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (FirebaseService.consumePendingNotificationNavigation()) return;
      _maybeOpenDeepLinkedBooking();
    });

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
    ));

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _pulseScaleAnimation = Tween<double>(begin: 0.94, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _entryController.forward();
  }

  @override
  void dispose() {
    _entryController.dispose();
    _pulseController.dispose();
    _patientService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) {
      setState(() {});
      _maybeOpenDeepLinkedBooking();
    }
  }

  void _maybeOpenDeepLinkedBooking() {
    if (_handledBookingDeepLink || !mounted) return;
    final targetDocId = (widget.openBookingDoctorId ?? '').trim();
    if (targetDocId.isEmpty) return;

    final matchedDoc = _patientService.allDoctors
        .where((d) => d.id == targetDocId || d.userId == targetDocId)
        .firstOrNull;
    if (matchedDoc == null) return;

    _handledBookingDeepLink = true;
    final parsedDate = (widget.initialBookingDate != null && widget.initialBookingDate!.trim().isNotEmpty)
        ? DateTime.tryParse(widget.initialBookingDate!.trim())
        : null;
    BookVisitFlowDialog.show(
      context,
      preselectedDoctor: matchedDoc,
      initialConsultationMode: (widget.initialBookingMode ?? 'In-Person').trim().isNotEmpty
          ? widget.initialBookingMode!.trim()
          : 'In-Person',
      initialDate: parsedDate,
      initialTimeSlot: widget.initialBookingSlot,
    );
  }

  User? get _safeAuthUser {
    try {
      return Supabase.instance.client.auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Good morning';
    } else if (hour < 17) {
      return 'Good afternoon';
    } else {
      return 'Good evening';
    }
  }

  String _formatPatientName(String name) {
    String candidate = name.trim();
    if (candidate.isEmpty || candidate.toLowerCase() == 'patient') {
      final sessName = SessionService().currentSession?.name?.trim();
      final authMetaName = _safeAuthUser?.userMetadata?['name']?.toString().trim() ??
          _safeAuthUser?.userMetadata?['full_name']?.toString().trim();
      if (sessName != null && sessName.isNotEmpty && sessName.toLowerCase() != 'patient') {
        candidate = sessName;
      } else if (authMetaName != null && authMetaName.isNotEmpty && authMetaName.toLowerCase() != 'patient') {
        candidate = authMetaName;
      } else {
        candidate = 'Patient';
      }
    }
    if (candidate.contains('.')) {
      return candidate
          .split('.')
          .map((s) => s.isNotEmpty ? '${s[0].toUpperCase()}${s.substring(1)}' : '')
          .join(' ');
    }
    return candidate[0].toUpperCase() + candidate.substring(1);
  }

  String _resolvePatientAge(PatientProfile patient) {
    if (patient.age.trim().isNotEmpty && patient.age.trim() != 'null') {
      return patient.age.trim();
    }
    final authUser = _safeAuthUser;
    final metaAge = authUser?.userMetadata?['age']?.toString() ?? authUser?.userMetadata?['patient_age']?.toString();
    if (metaAge != null && metaAge.trim().isNotEmpty && metaAge.trim() != 'null') {
      patient.age = metaAge.trim();
      return metaAge.trim();
    }
    final match = _patientService.allPatients.firstWhere(
      (p) => (p.email.isNotEmpty && p.email.toLowerCase() == patient.email.toLowerCase()) ||
          (p.phone.isNotEmpty && p.phone == patient.phone) ||
          (p.name.isNotEmpty && p.name.toLowerCase() == patient.name.toLowerCase()),
      orElse: () => PatientProfile(),
    );
    if (match.age.trim().isNotEmpty && match.age.trim() != 'null') {
      patient.age = match.age.trim();
      return match.age.trim();
    }
    return '';
  }

  String _resolvePatientBloodGroup(PatientProfile patient) {
    if (patient.bloodGroup.trim().isNotEmpty && patient.bloodGroup.trim() != 'null' && patient.bloodGroup != 'O Positive (O+)') {
      return patient.bloodGroup.trim();
    }
    final match = _patientService.allPatients.firstWhere(
      (p) => (p.email.isNotEmpty && p.email.toLowerCase() == patient.email.toLowerCase()) ||
          (p.phone.isNotEmpty && p.phone == patient.phone) ||
          (p.name.isNotEmpty && p.name.toLowerCase() == patient.name.toLowerCase()),
      orElse: () => PatientProfile(),
    );
    if (match.bloodGroup.trim().isNotEmpty && match.bloodGroup.trim() != 'null') {
      patient.bloodGroup = match.bloodGroup.trim();
      return match.bloodGroup.trim();
    }
    return patient.bloodGroup.isNotEmpty ? patient.bloodGroup : 'O Positive (O+)';
  }

  /// Ensures Patients complete required profile fields (image, pincode, age, gender)
  /// before opening any service or service-related action, then continues to the selected service.
  Future<void> _guardServiceAccess(
    BuildContext context, {
    required String serviceTitle,
    required VoidCallback onAllowed,
  }) async {
    if (_patientService.currentPatient.isProfileComplete) {
      onAllowed();
      return;
    }
    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PatientProfileCompletionScreen(
          serviceTitle: serviceTitle,
        ),
      ),
    );
    if (!mounted || completed != true) return;
    if (_patientService.currentPatient.isProfileComplete) {
      setState(() {});
      onAllowed();
    }
  }

  void _openBookVisitFlow(BuildContext context, {DoctorModel? preselectedDoctor}) {
    _guardServiceAccess(
      context,
      serviceTitle: 'Book a Visit',
      onAllowed: () {
        BookVisitFlowDialog.show(
          context,
          preselectedDoctor: preselectedDoctor,
          onBookingSuccess: () {
            _patientService.syncAppointmentsFromApi();
            _patientService.syncNotificationsFromApi(role: 'Patient');
            setState(() {
              _currentIndex = 2; // Switch/stay on Visits (Appointments) tab
            });
          },
        );
      },
    );
  }

  void showReportProblemDialog(BuildContext context, {DoctorModel? preselectedDoctor}) {
    final descriptionController = TextEditingController();
    String selectedCategory = 'Toothache & Cold Sensitivity';
    String selectedSeverity = 'Moderate';

    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 440),
                padding: const EdgeInsets.all(22),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryBlue.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.health_and_safety_rounded, color: AppTheme.primaryBlue, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  preselectedDoctor != null ? 'Book with ${preselectedDoctor.name}' : 'Connect to a Doctor',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: AppTheme.textDark),
                                ),
                                Text(
                                  preselectedDoctor != null
                                      ? '${preselectedDoctor.specialty} • ${preselectedDoctor.clinicName.isNotEmpty ? preselectedDoctor.clinicName : "GS HEALTH Clinic"}'
                                      : 'Explore doctors and connect with a specialized doctor.',
                                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      if (preselectedDoctor != null) ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0x14012A58),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0x40012A58)),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.15),
                                child: Text(
                                  preselectedDoctor.name.isNotEmpty
                                      ? preselectedDoctor.name.replaceAll('Dr.', '').replaceAll('Dr. ', '').trim()[0].toUpperCase()
                                      : 'D',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue, fontSize: 12),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Preferred Doctor: ${preselectedDoctor.name}',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF012A58)),
                                    ),
                                    Text(
                                      '${preselectedDoctor.specialty} • ${preselectedDoctor.city.isNotEmpty ? preselectedDoctor.city : "Verified"}',
                                      style: const TextStyle(fontSize: 10.5, color: Color(0xFFFE3434)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Problem Category Dropdown
                      DropdownButtonFormField<String>(
                        initialValue: selectedCategory,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Health Concern Category',
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        items: [
                          'Toothache & Cold Sensitivity',
                          'Bleeding Gums & Swelling',
                          'Wisdom Tooth Pain',
                          'Aligners & Braces Adjustment',
                          'Tooth Decay / Cavity',
                          'Teeth Cleaning & Whitening',
                        ].map((cat) => DropdownMenuItem(value: cat, child: Text(cat, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis))).toList(),
                        onChanged: (val) => setModalState(() => selectedCategory = val ?? selectedCategory),
                      ),
                      const SizedBox(height: 12),

                      // Symptom Description
                      TextField(
                        controller: descriptionController,
                        maxLines: 3,
                        style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13.5, fontWeight: FontWeight.w500),
                        cursorColor: AppTheme.primaryBlue,
                        decoration: InputDecoration(
                          labelText: 'Describe Symptoms & Duration',
                          hintText: 'e.g. Sharp throbbing pain in lower molar when drinking cold liquids...',
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Pain Severity Segmented Buttons (Single Line)
                      const Text('Pain Severity Level:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppTheme.textMuted)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          for (final sev in ['Mild', 'Moderate', 'Severe']) ...[
                            if (sev != 'Mild') const SizedBox(width: 8),
                            Expanded(
                              child: InkWell(
                                onTap: () => setModalState(() => selectedSeverity = sev),
                                borderRadius: BorderRadius.circular(10),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: selectedSeverity == sev
                                        ? (sev == 'Severe'
                                            ? const Color(0x14FE3434)
                                            : sev == 'Moderate'
                                                ? const Color(0x14FE3434)
                                                : const Color(0x14012A58))
                                        : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: selectedSeverity == sev
                                          ? (sev == 'Severe'
                                              ? const Color(0xFFFE3434)
                                              : sev == 'Moderate'
                                                  ? const Color(0xFFFE3434)
                                                  : const Color(0xFFFE3434))
                                          : const Color(0xFFE2E8F0),
                                      width: selectedSeverity == sev ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        sev == 'Severe'
                                            ? Icons.warning_amber_rounded
                                            : sev == 'Moderate'
                                                ? Icons.error_outline_rounded
                                                : Icons.check_circle_outline_rounded,
                                        size: 14,
                                        color: selectedSeverity == sev
                                            ? (sev == 'Severe'
                                                ? const Color(0xFFFE3434)
                                                : sev == 'Moderate'
                                                    ? const Color(0xFFFE3434)
                                                    : const Color(0xFFFE3434))
                                            : AppTheme.textMuted,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        sev,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: selectedSeverity == sev
                                              ? (sev == 'Severe'
                                                  ? const Color(0xFFFE3434)
                                                  : sev == 'Moderate'
                                                      ? const Color(0xFFFE3434)
                                                      : const Color(0xFF012A58))
                                              : AppTheme.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Submit Button
                      ElevatedButton.icon(
                        icon: isSubmitting
                            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.send_rounded, size: 18),
                        label: Text(
                          isSubmitting
                              ? 'Submitting...'
                              : (preselectedDoctor != null ? 'Request Visit with ${preselectedDoctor.name}' : 'Submit Symptoms to Admin'),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                if (descriptionController.text.trim().isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Please describe your symptoms.')),
                                  );
                                  return;
                                }
                                setModalState(() => isSubmitting = true);
                                try {
                                  await _patientService.submitProblem(
                                    problemCategory: selectedCategory,
                                    problemDescription: descriptionController.text.trim(),
                                    severity: selectedSeverity,
                                    preferredDoctorId: preselectedDoctor?.id.isNotEmpty == true ? preselectedDoctor!.id : preselectedDoctor?.userId,
                                    preferredDoctorName: preselectedDoctor?.name,
                                    preferredDoctorClinic: preselectedDoctor?.clinicName,
                                  );

                                  if (dialogContext.mounted) {
                                    Navigator.of(dialogContext).pop();
                                  }
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          preselectedDoctor != null
                                              ? '✅ Appointment requested with ${preselectedDoctor.name}!'
                                              : '✅ Health concern submitted! Admin will recommend a specialist shortly.',
                                        ),
                                        backgroundColor: const Color(0xFF012A58),
                                        duration: const Duration(seconds: 3),
                                      ),
                                    );
                                  }
                                } catch (err) {
                                  setModalState(() => isSubmitting = false);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Error submitting problem: $err'), backgroundColor: const Color(0xFFFE3434)),
                                    );
                                  }
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

  void _showChatModal(BuildContext context, {PatientConsultationRequest? request, DoctorModel? doctor}) {
    final patient = _patientService.currentPatient;
    final requests = _patientService.requests;
    
    final assignedReq = request ?? requests.firstWhere(
      (r) => (r.assignedDoctorName != null && r.assignedDoctorName!.isNotEmpty) || (r.displayDoctorName.isNotEmpty),
      orElse: () => requests.isNotEmpty ? requests.first : PatientConsultationRequest(
        id: '', patientName: patient.name, patientPhone: patient.phone, problemCategory: '', problemDescription: '', severity: '', submittedAt: DateTime.now()
      ),
    );

    final docName = doctor?.name ?? (assignedReq.displayDoctorName.isNotEmpty ? assignedReq.displayDoctorName : (assignedReq.assignedDoctorName?.isNotEmpty == true ? assignedReq.assignedDoctorName! : 'Doctor'));
    String? docId = doctor?.id ?? assignedReq.assignedDoctorId ?? assignedReq.preferredDoctorId;
    if ((docId == null || docId.trim().isEmpty) && docName.trim().isNotEmpty) {
      final cleanTarget = docName.replaceAll(RegExp(r'^Dr\.?\s*', caseSensitive: false), '').trim().toLowerCase();
      final matchedDoc = _patientService.allDoctors.where((d) {
        final cleanD = d.name.replaceAll(RegExp(r'^Dr\.?\s*', caseSensitive: false), '').trim().toLowerCase();
        return cleanD.isNotEmpty && (cleanD == cleanTarget || cleanD.contains(cleanTarget) || cleanTarget.contains(cleanD));
      }).firstOrNull;
      if (matchedDoc != null) {
        docId = matchedDoc.userId.trim().isNotEmpty ? matchedDoc.userId.trim() : matchedDoc.id.trim();
      }
    }
    final pName = (patient.name.trim().isNotEmpty && patient.name.trim().toLowerCase() != 'patient')
        ? patient.name
        : (assignedReq.patientName.trim().isNotEmpty
            ? assignedReq.patientName
            : _resolveProfileDisplayName(patient));
    final resolvedPatientId = patient.id.trim().isNotEmpty
        ? patient.id.trim()
        : ((assignedReq.patientId != null && assignedReq.patientId!.trim().isNotEmpty)
            ? assignedReq.patientId!.trim()
            : SessionService().currentSession?.canonicalUserId);

    WhatsAppChatModal.show(
      context,
      patientName: pName,
      doctorName: docName,
      currentUserRole: 'Patient',
      patientId: (resolvedPatientId != null && resolvedPatientId.isNotEmpty) ? resolvedPatientId : null,
      doctorId: docId,
    );
  }

  void _showNotificationsModal(BuildContext context, String role) {
    _patientService.syncNotificationsFromApi(role: role);

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final notifs = _patientService.getNotificationsForRole(role);
            final unreadCount = notifs.where((n) => !n.isRead).length;

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 440, maxHeight: 540),
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
                              const Icon(Icons.notifications_active_rounded, color: AppTheme.primaryBlue, size: 22),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Patient Notifications',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (unreadCount > 0)
                                Container(
                                  margin: const EdgeInsets.only(left: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.gsRed.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '$unreadCount unread',
                                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppTheme.gsRed),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (unreadCount > 0)
                          TextButton(
                            key: const Key('patient_mark_all_notifications_read'),
                            onPressed: () async {
                              await _patientService.markAllNotificationsRead(role);
                              if (dialogCtx.mounted) setModalState(() {});
                            },
                            child: const Text(
                              'Mark all read',
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                            ),
                          ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(dialogCtx).pop(),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    if (notifs.isEmpty)
                      const Expanded(
                        child: Center(
                          child: Text('No new notifications.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.builder(
                          itemCount: notifs.length,
                          itemBuilder: (ctx, idx) {
                            final n = notifs[idx];
                            final isUnread = !n.isRead;
                            return InkWell(
                              key: Key('patient_notification_item_${n.id}'),
                              onTap: () async {
                                if (isUnread) {
                                  await _patientService.markNotificationRead(n.id);
                                  if (dialogCtx.mounted) setModalState(() {});
                                }
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isUnread ? const Color(0x14FE3434) : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isUnread ? const Color(0x40FE3434) : const Color(0xFFE2E8F0),
                                    width: isUnread ? 1.4 : 1.0,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            n.title,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                              color: isUnread ? AppTheme.primaryBlue : AppTheme.textDark,
                                            ),
                                          ),
                                        ),
                                        if (isUnread)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppTheme.primaryBlue,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Text(
                                              'NEW',
                                              style: TextStyle(fontSize: 8.5, color: Colors.white, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(n.message, style: const TextStyle(fontSize: 11.5, color: AppTheme.textDark, height: 1.35)),
                                    const SizedBox(height: 5),
                                    Text(
                                      '${n.timestamp.day}/${n.timestamp.month}/${n.timestamp.year} • ${n.timestamp.hour.toString().padLeft(2, '0')}:${n.timestamp.minute.toString().padLeft(2, '0')}',
                                      style: const TextStyle(fontSize: 9.5, color: Colors.grey),
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
    final patient = _patientService.currentPatient;
    final formattedName = _resolveProfileDisplayName(patient);

    return Scaffold(
      backgroundColor: AppTheme.softBlueBg,
      appBar: (_currentIndex == 1 ||
              _currentIndex == 2 ||
              _currentIndex == 3 ||
              _currentIndex == 4)
          ? null
          : PreferredSize(
              preferredSize: Size.fromHeight(MediaQuery.of(context).padding.top + 96),
              child: Container(
                color: Colors.white,
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 4,
                  left: 18,
                  right: 18,
                  bottom: 4,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const GsHealthLogo(
                            height: 26,
                            alignment: Alignment.centerLeft,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _getGreeting(),
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.textMedium,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            formattedName,
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textDark,
                              height: 1.15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Builder(
                      builder: (context) {
                        final patientNotifs = _patientService.getNotificationsForRole('Patient');
                        final unreadCount = patientNotifs.where((n) => !n.isRead).length;

                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            IconButton(
                              key: const Key('patient_notifications_bell_button'),
                              icon: const Icon(Icons.notifications_none_rounded, color: AppTheme.textDark, size: 24),
                              onPressed: () => _showNotificationsModal(context, 'Patient'),
                              tooltip: 'Notifications',
                              visualDensity: VisualDensity.compact,
                            ),
                            if (unreadCount > 0)
                              Positioned(
                                right: 6,
                                top: 6,
                                child: IgnorePointer(
                                  child: Container(
                                    key: const Key('patient_unread_notifications_badge'),
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(color: AppTheme.gsRed, shape: BoxShape.circle),
                                    child: Text(
                                      '$unreadCount',
                                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      key: const Key('dashboard_profile_avatar_button'),
                      onTap: () {
                        _patientService.syncPatientsFromApi();
                        setState(() => _currentIndex = 4);
                      },
                      borderRadius: BorderRadius.circular(30),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppTheme.gsNavy.withValues(alpha: 0.35),
                            width: 1.4,
                          ),
                          color: Colors.white,
                        ),
                        child: Center(
                          child: patient.photoBytes != null
                              ? ClipOval(
                                  child: Image.memory(
                                    patient.photoBytes!,
                                    width: 40,
                                    height: 40,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : (patient.profileImageUrl != null &&
                                      patient.profileImageUrl!.trim().isNotEmpty)
                                  ? ClipOval(
                                      child: Image.network(
                                        patient.profileImageUrl!,
                                        width: 40,
                                        height: 40,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => const Icon(
                                          Icons.person_outline_rounded,
                                          color: AppTheme.gsNavy,
                                          size: 24,
                                        ),
                                      ),
                                    )
                                  : const Icon(
                                      Icons.person_outline_rounded,
                                      color: AppTheme.gsNavy,
                                      size: 24,
                                    ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: _buildCurrentTab(),
      ),
      floatingActionButton: (_currentIndex == 0 || _currentIndex == 2)
          ? BookConsultationFab(
              onPressed: () => _openBookVisitFlow(context),
            )
          : null,
      bottomNavigationBar: _currentIndex == 4
          ? null
          : Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(
            top: BorderSide(color: Color(0xFFF1F5F9), width: 1),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex > 3 ? 0 : _currentIndex,
          backgroundColor: Colors.white,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: AppTheme.gsNavy,
          unselectedItemColor: const Color(0xFF94A3B8),
          selectedFontSize: 12,
          unselectedFontSize: 12,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
          onTap: (index) {
            if (index == 0) {
              setState(() => _currentIndex = 0);
              _patientService.syncAppointmentsFromApi();
              _patientService.syncProblemRequestsFromApi();
              _patientService.syncReferralsFromApi();
              _patientService.syncNotificationsFromApi(role: 'Patient');
              return;
            }
            final String serviceName = index == 1
                ? 'Find Doctors'
                : (index == 2 ? 'My Visits' : 'Health Locker');
            _guardServiceAccess(
              context,
              serviceTitle: serviceName,
              onAllowed: () {
                setState(() => _currentIndex = index);
                if (index == 1) {
                  _patientService.syncDoctorsFromApi(includeUnavailable: true);
                } else if (index == 2) {
                  _patientService.syncAppointmentsFromApi();
                  _patientService.syncProblemRequestsFromApi();
                  _patientService.syncReferralsFromApi();
                  _patientService.syncNotificationsFromApi(role: 'Patient');
                } else if (index == 3) {
                  _patientService.syncMedicalRecordsFromApi();
                }
              },
            );
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home_rounded, color: AppTheme.gsNavy),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.search_rounded),
              activeIcon: Icon(Icons.search_rounded, color: AppTheme.gsNavy),
              label: 'Find',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.calendar_month_outlined),
              activeIcon: Icon(Icons.calendar_month_rounded, color: AppTheme.gsNavy),
              label: 'Visits',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.folder_outlined),
              activeIcon: Icon(Icons.folder_rounded, color: AppTheme.gsNavy),
              label: 'Locker',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentTab() {
    switch (_currentIndex) {
      case 0:
        return _buildHomeTab();
      case 1:
        return FindDoctorsScreen(onBack: () => setState(() => _currentIndex = 0));
      case 2:
        return _buildAppointmentsTab();
      case 3:
        return _buildRecordsTab();
      case 4:
        return _buildProfileTab();
      default:
        return _buildHomeTab();
    }
  }

  // ==========================================
  // TAB 1: REDESIGNED GS HEALTH HOME TAB
  // ==========================================
  bool _isUpcomingAppointmentStatus(String status) {
    final s = status.trim().toUpperCase();
    return s != 'COMPLETED' &&
        s != 'CANCELLED' &&
        s != 'CANCELED' &&
        s != 'REJECTED' &&
        s != 'NO_SHOW' &&
        s != 'NO SHOW' &&
        s != 'CLOSED' &&
        s != 'EXPIRED' &&
        s != 'DECLINED';
  }

  DateTime _resolveAppointmentStartDateTime(PatientConsultationRequest req) {
    DateTime baseDate = _resolveAppointmentDateTime(req);
    final rawDate = (req.confirmedDate ?? '').trim();
    if (rawDate.isNotEmpty) {
      final parsedIso = DateTime.tryParse(rawDate);
      if (parsedIso != null) {
        baseDate = parsedIso.isUtc ? parsedIso.toLocal() : parsedIso;
      } else {
        final dmy = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$').firstMatch(rawDate);
        if (dmy != null) {
          final day = int.tryParse(dmy.group(1) ?? '');
          final month = int.tryParse(dmy.group(2) ?? '');
          final year = int.tryParse(dmy.group(3) ?? '');
          if (day != null && month != null && year != null) {
            baseDate = DateTime(year, month, day);
          }
        }
      }
    }

    final slot = (req.confirmedTimeSlot ?? '').trim();
    if (slot.isNotEmpty) {
      final timeMatch = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)?', caseSensitive: false).firstMatch(slot);
      if (timeMatch != null) {
        var hour = int.tryParse(timeMatch.group(1) ?? '') ?? 0;
        final minute = int.tryParse(timeMatch.group(2) ?? '') ?? 0;
        final period = (timeMatch.group(3) ?? '').toUpperCase();
        if (period == 'PM' && hour < 12) {
          hour += 12;
        } else if (period == 'AM' && hour == 12) {
          hour = 0;
        }
        return DateTime(baseDate.year, baseDate.month, baseDate.day, hour, minute);
      }
    }
    return baseDate;
  }

  PatientConsultationRequest? _selectNextUpcomingVisit(
    List<PatientConsultationRequest> patientRequests,
  ) {
    final activeRequests = patientRequests
        .where((r) => _isUpcomingAppointmentStatus(r.status))
        .toList();
    if (activeRequests.isEmpty) return null;

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    final futureUpcoming = <PatientConsultationRequest>[];
    final earlierActive = <PatientConsultationRequest>[];

    for (final req in activeRequests) {
      final startDt = _resolveAppointmentStartDateTime(req);
      final hasSlot = (req.confirmedTimeSlot ?? '').trim().isNotEmpty;
      final isUpcoming = hasSlot
          ? !startDt.isBefore(now)
          : !DateTime(startDt.year, startDt.month, startDt.day).isBefore(todayStart);
      if (isUpcoming) {
        futureUpcoming.add(req);
      } else {
        earlierActive.add(req);
      }
    }

    if (futureUpcoming.isNotEmpty) {
      futureUpcoming.sort((a, b) {
        final cmp = _resolveAppointmentStartDateTime(a)
            .compareTo(_resolveAppointmentStartDateTime(b));
        if (cmp != 0) return cmp;
        return a.submittedAt.compareTo(b.submittedAt);
      });
      return futureUpcoming.first;
    }

    earlierActive.sort((a, b) {
      final cmp = _resolveAppointmentStartDateTime(b)
          .compareTo(_resolveAppointmentStartDateTime(a));
      if (cmp != 0) return cmp;
      return b.submittedAt.compareTo(a.submittedAt);
    });
    return earlierActive.first;
  }

  String _resolveHeroDoctorName(PatientConsultationRequest visit) {
    final raw = visit.displayDoctorName.trim();
    final lower = raw.toLowerCase();
    if (raw.isEmpty ||
        lower == 'null' ||
        lower == 'dr. specialist' ||
        lower == 'selected doctor' ||
        lower == 'doctor') {
      return '';
    }
    if (lower.startsWith('dr.') || lower.startsWith('dr ')) {
      return raw;
    }
    return 'Dr. $raw';
  }

  String _formatHeroAppointmentStatusLine(PatientConsultationRequest visit) {
    final rawStatus = visit.status.trim();
    final upper = rawStatus.toUpperCase();
    String statusLabel;
    if (upper == 'CONFIRMED' ||
        upper == 'ACCEPTED' ||
        upper == 'BOOKED' ||
        upper == 'APPROVED' ||
        upper == 'DOCTOR ASSIGNED') {
      statusLabel = 'Confirmed';
    } else if (upper == 'RESCHEDULED') {
      statusLabel = 'Rescheduled';
    } else if (upper == 'SCHEDULED') {
      statusLabel = 'Scheduled';
    } else if (upper == 'IN_PROGRESS' || upper == 'IN PROGRESS' || upper == 'ONGOING') {
      statusLabel = 'In Progress';
    } else if (upper.contains('PENDING') || upper == 'REQUESTED') {
      statusLabel = 'Pending';
    } else if (rawStatus.isNotEmpty) {
      statusLabel = rawStatus[0].toUpperCase() + rawStatus.substring(1).toLowerCase();
    } else {
      statusLabel = 'Scheduled';
    }

    final slot = (visit.confirmedTimeSlot ?? '').trim();
    final hasValidSlot = slot.isNotEmpty &&
        slot.toLowerCase() != 'null' &&
        slot.toLowerCase() != 'pending review';
    if (hasValidSlot) {
      return '$statusLabel for $slot';
    }
    if (statusLabel == 'Confirmed') {
      return 'Confirmed appointment';
    }
    return '$statusLabel confirmation';
  }

  Widget _buildHomeTab() {
    final myRequests = _getPatientRequests();
    final nextVisit = _selectNextUpcomingVisit(myRequests);
    final hasUpcoming = nextVisit != null;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16, 16, 16, 36 + MediaQuery.of(context).padding.bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Compact Hero Summary: Next Upcoming Visit + Open Visits CTA
              _buildHeroUpcomingVisitsBanner(
                hasUpcoming: hasUpcoming,
                nextVisit: nextVisit,
                totalVisitsCount: myRequests.length,
              ),
              const SizedBox(height: 16),

              // 1a. Online & Offline Consultation Selection Section
              _buildConsultationModeSelectionSection(),
              const SizedBox(height: 16),

              // 1b. Upcoming Appointments Preview (Max 2 + View All)
              _buildPatientUpcomingAppointmentsPreviewSection(myRequests),
              const SizedBox(height: 16),

              // 2. AI Dental Triage Card ("Something hurting?")
              _buildAiTriageCard(),
              const SizedBox(height: 14),

              // 3. Talk to a Dentist Card ("Talk to a dentist now")
              _buildTalkToDentistCard(),
              const SizedBox(height: 16),

              // 4. Sponsored Banner (Dynamic GS HEALTH multi-specialty healthcare ads)
              _buildSponsoredBanner(),
              const SizedBox(height: 20),

              // 5. My Favourite Dentists Section
              _buildFavouriteDentistsSection(),
              const SizedBox(height: 16),

              // 5b. Recent Consultations Preview (Max 2 + View All)
              _buildPatientRecentConsultationsPreviewSection(myRequests),
              const SizedBox(height: 16),

              // 6. Refer a Friend Section
              _buildReferAFriendSection(),
              const SizedBox(height: 16),

              // 6b. Patient Referrals (Received for Patient & Sent Referrals — Max 2 + View All)
              _buildPatientReferralsSummarySection(),

              // 7. Prescriptions, Diagnostics & Recent/Previous Visits Overview
              _buildPatientHealthOverviewSection(myRequests),
              const SizedBox(height: 16),

              // 8. 24/7 Support Card (WhatsApp only — Call Us Now removed from Patient Dashboard)
              const NeedHelpCard(showCallAction: false),
              const SizedBox(height: 36),
            ],
          ),
        ),
      ),
    );
  }

  String _selectedHomeConsultationMode = 'Online';

  void _openConsultationModeDoctors(String mode) {
    setState(() {
      _selectedHomeConsultationMode = mode;
    });
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FindDoctorsScreen(
          initialConsultationMode: mode,
        ),
      ),
    );
  }

  Widget _buildConsultationModeSelectionSection() {
    final isOnlineSelected = _selectedHomeConsultationMode == 'Online';
    final isOfflineSelected = _selectedHomeConsultationMode == 'Offline';

    return Container(
      key: const Key('patient_consultation_mode_selector_section'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.gsNavy.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.gsNavy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.medical_services_rounded, size: 18, color: AppTheme.gsNavy),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Choose Consultation Mode',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textDark,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Select your preferred consultation mode to find eligible doctors',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  key: const Key('patient_select_online_consultation_card'),
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _openConsultationModeDoctors('Online'),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isOnlineSelected ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isOnlineSelected ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1),
                        width: isOnlineSelected ? 1.8 : 1.1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0284C7).withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.videocam_rounded, color: Color(0xFF0284C7), size: 20),
                            ),
                            const Spacer(),
                            Icon(
                              isOnlineSelected ? Icons.check_circle_rounded : Icons.arrow_forward_ios_rounded,
                              size: isOnlineSelected ? 18 : 13,
                              color: isOnlineSelected ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Online Consultation',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textDark,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Video & tele-consult with online-enabled doctors',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF475569),
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  key: const Key('patient_select_offline_consultation_card'),
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _openConsultationModeDoctors('Offline'),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isOfflineSelected ? const Color(0xFFECFDF5) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isOfflineSelected ? const Color(0xFF059669) : const Color(0xFFCBD5E1),
                        width: isOfflineSelected ? 1.8 : 1.1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF059669).withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.local_hospital_rounded, color: Color(0xFF059669), size: 20),
                            ),
                            const Spacer(),
                            Icon(
                              isOfflineSelected ? Icons.check_circle_rounded : Icons.arrow_forward_ios_rounded,
                              size: isOfflineSelected ? 18 : 13,
                              color: isOfflineSelected ? const Color(0xFF059669) : const Color(0xFF64748B),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Offline Consultation (Visit Clinic)',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textDark,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'In-person visit at a clinic with directions & slots',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF475569),
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroUpcomingVisitsBanner({
    required bool hasUpcoming,
    PatientConsultationRequest? nextVisit,
    int totalVisitsCount = 0,
  }) {
    return InkWell(
      onTap: () {
        if (hasUpcoming || totalVisitsCount > 0) {
          _guardServiceAccess(
            context,
            serviceTitle: 'My Visits',
            onAllowed: () {
              _patientService.syncAppointmentsFromApi();
              setState(() {
                _visitsSubTabIndex = 0;
                _showAllVisits = false;
                _expandedVisitsLimit = _visitsExpandedPageSize;
                _currentIndex = 2;
              });
            },
          );
        } else {
          _openBookVisitFlow(context);
        }
      },
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 195),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  'assets/healthcare_hero_banner.jpg',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF0F172A), AppTheme.gsNavy],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.25),
                        Colors.black.withValues(alpha: 0.8),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.gsRed.withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'YOUR SMILE, CARED FOR',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      hasUpcoming
                          ? ((nextVisit?.problemCategory.trim().isNotEmpty ?? false)
                              ? nextVisit!.problemCategory.trim()
                              : 'Scheduled Visit')
                          : 'No upcoming visits',
                      key: const Key('hero_appointment_title'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (hasUpcoming && nextVisit != null) ...[
                      Builder(
                        builder: (context) {
                          final doctorName = _resolveHeroDoctorName(nextVisit);
                          if (doctorName.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              doctorName,
                              key: const Key('hero_appointment_doctor_name'),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.96),
                                fontSize: 15,
                                height: 1.25,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.1,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        },
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      hasUpcoming && nextVisit != null
                          ? _formatHeroAppointmentStatusLine(nextVisit)
                          : 'Book a verified doctor near you in under a minute.',
                      key: const Key('hero_appointment_status_time'),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 12.5,
                        height: 1.3,
                        fontWeight: FontWeight.w400,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (hasUpcoming || totalVisitsCount > 0) ...[
                      const SizedBox(height: 12),
                      InkWell(
                        key: const Key('home_open_visits_button'),
                        onTap: () => _guardServiceAccess(
                          context,
                          serviceTitle: 'My Visits',
                          onAllowed: () {
                            _patientService.syncAppointmentsFromApi();
                            setState(() {
                              _visitsSubTabIndex = 0;
                              _showAllVisits = false;
                              _expandedVisitsLimit = _visitsExpandedPageSize;
                              _currentIndex = 2;
                            });
                          },
                        ),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.94),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.calendar_month_rounded,
                                size: 14,
                                color: AppTheme.gsNavy,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  totalVisitsCount > 1
                                      ? 'Open Visits ($totalVisitsCount)'
                                      : 'Open Visits',
                                  style: const TextStyle(
                                    color: AppTheme.gsNavy,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.arrow_forward_rounded,
                                size: 14,
                                color: AppTheme.gsNavy,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAiTriageCard() {
    return InkWell(
      key: const Key('patient_ai_triage_card'),
      onTap: () {
        _guardServiceAccess(
          context,
          serviceTitle: 'AI Health Triage',
          onAllowed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const AiTriageScreen(),
              ),
            );
          },
        );
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppTheme.gsNavy,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppTheme.gsNavy.withValues(alpha: 0.28),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Center(
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Something hurting?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Describe it and our AI tells you how urgent it is and who to see.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11.5,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.arrow_forward_rounded,
              color: Colors.white,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTalkToDentistCard() {
    return InkWell(
      key: const Key('talk_to_dentist_now_card'),
      onTap: () {
        _guardServiceAccess(
          context,
          serviceTitle: 'Talk to a Doctor',
          onAllowed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const TalkToDentistNowScreen(),
              ),
            );
          },
        );
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppTheme.gsRed.withValues(alpha: 0.35),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _pulseScaleAnimation,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: const Color(0xFF012A58),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF012A58).withValues(alpha: 0.4),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Talk to a doctor now',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Get matched with an online doctor who speaks your language.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textMedium,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppTheme.gsRed.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Icon(
                  Icons.bolt_rounded,
                  color: AppTheme.gsRed,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSponsoredBanner() {
    return GsHealthPatientSponsoredBanner(
      activeSpecialties: _patientService.activeSpecialties,
      availableDoctors: _patientService.availableDoctors,
      onAdTap: (ad) {
        _guardServiceAccess(
          context,
          serviceTitle: ad.title,
          onAllowed: () {
            if (ad.destination == GsSponsoredDestination.aiTriage) {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AiTriageScreen()),
              );
              return;
            }
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => FindDoctorsScreen(
                  initialSpecialty: ad.destination == GsSponsoredDestination.findDoctorsSpecialty
                      ? (ad.targetSpecialty ?? 'All')
                      : 'All',
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFavouriteDentistsSection() {
    final myDocs = _patientService.myDoctors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'My favourite doctors',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () {
                _guardServiceAccess(
                  context,
                  serviceTitle: 'Favourite Doctors',
                  onAllowed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const FindDoctorsScreen(initialTabFilter: 1),
                      ),
                    );
                  },
                );
              },
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(50, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'See all',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.gsNavy,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (myDocs.isEmpty)
          InkWell(
            onTap: () {
              _guardServiceAccess(
                context,
                serviceTitle: 'Find Doctors',
                onAllowed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const FindDoctorsScreen(),
                    ),
                  );
                },
              );
            },
            borderRadius: BorderRadius.circular(18),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFF1F5F9), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppTheme.gsRed.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.favorite_rounded,
                        color: AppTheme.gsRed,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'No favourites yet',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textDark,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Tap ❤️ on a doctor\'s profile to save them here and refer friends to them.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppTheme.textMedium,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Color(0xFF94A3B8),
                    size: 16,
                  ),
                ],
              ),
            ),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: myDocs.take(kDashboardRecentPreviewLimit).map((doc) {
                return Container(
                  width: 220,
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFF1F5F9), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: AppTheme.gsNavy.withValues(alpha: 0.1),
                            child: Text(
                              doc.name.isNotEmpty ? doc.name[0].toUpperCase() : 'D',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.gsNavy),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  doc.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  doc.specialty,
                                  style: const TextStyle(fontSize: 11, color: AppTheme.textMedium),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => _openBookVisitFlow(context, preselectedDoctor: doc),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.gsNavy,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('Book Visit', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildReferAFriendSection() {
    return InkWell(
      onTap: () {
        _guardServiceAccess(
          context,
          serviceTitle: 'Refer a Friend',
          onAllowed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ReferAFriendScreen(),
              ),
            );
          },
        );
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFF1F5F9), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppTheme.gsNavy.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Icon(
                  Icons.card_giftcard_rounded,
                  color: AppTheme.gsNavy,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Refer a friend',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Share a doctor you trust and track the referral.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textMedium,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () {
                _guardServiceAccess(
                  context,
                  serviceTitle: 'My Referrals',
                  onAllowed: () => ReferredPatientsSheet.show(context),
                );
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: const Size(50, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'My referrals',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.gsNavy,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildPatientUpcomingAppointmentsPreviewSection(
    List<PatientConsultationRequest> myRequests,
  ) {
    final upcomingAll = myRequests.where((r) {
      final st = r.status.trim().toUpperCase();
      return st != 'COMPLETED' && st != 'CANCELLED' && st != 'REJECTED';
    }).toList();
    final latestTwoUpcoming = takeLatestPreviewRecords<PatientConsultationRequest>(
      upcomingAll,
      limit: kDashboardRecentPreviewLimit,
      compareDesc: (a, b) => b.submittedAt.compareTo(a.submittedAt),
    );

    void openAllUpcoming() {
      _guardServiceAccess(
        context,
        serviceTitle: 'My Visits',
        onAllowed: () {
          _patientService.syncAppointmentsFromApi();
          setState(() {
            _visitsSubTabIndex = 0;
            _showAllVisits = true;
            _expandedVisitsLimit = _visitsExpandedPageSize;
            _currentIndex = 2;
          });
        },
      );
    }

    return RecentUpdatesPreviewSection(
      sectionKey: const Key('patient_upcoming_appointments_section'),
      viewAllKey: const Key('patient_view_all_upcoming_appointments_btn'),
      emptyStateKey: const Key('patient_upcoming_appointments_empty'),
      title: 'Upcoming Appointments',
      totalCount: upcomingAll.length,
      icon: Icons.calendar_today_outlined,
      onViewAll: openAllUpcoming,
      emptyIcon: Icons.event_available_outlined,
      emptyTitle: 'No upcoming appointments yet.',
      emptySubtitle: 'Book a consultation to see your upcoming appointments here.',
      previewChildren: latestTwoUpcoming.asMap().entries.map((entry) {
        final idx = entry.key;
        final req = entry.value;
        final docName = req.displayDoctorName.trim().isNotEmpty
            ? req.displayDoctorName.trim()
            : (req.assignedDoctorName?.trim().isNotEmpty == true
                ? req.assignedDoctorName!.trim()
                : 'Doctor Pending Assignment');
        final dtLabel = (req.confirmedDate != null && req.confirmedDate!.trim().isNotEmpty)
            ? req.confirmedDate!.split('T').first
            : '${req.submittedAt.toLocal().day}/${req.submittedAt.toLocal().month}/${req.submittedAt.toLocal().year}';
        final slotLabel = (req.confirmedTimeSlot != null && req.confirmedTimeSlot!.trim().isNotEmpty)
            ? ' • ${req.confirmedTimeSlot}'
            : '';
        return RecentUpdatePreviewCard(
          cardKey: Key('patient_upcoming_appointment_card_$idx'),
          leadingIcon: Icons.medical_services_outlined,
          title: docName,
          subtitle: req.problemCategory.trim().isNotEmpty ? req.problemCategory.trim() : 'Scheduled Visit',
          metaLine: '$dtLabel$slotLabel',
          statusLabel: req.status.trim().isNotEmpty ? req.status.trim() : 'Scheduled',
          onTap: openAllUpcoming,
        );
      }).toList(),
    );
  }

  Widget _buildPatientRecentConsultationsPreviewSection(
    List<PatientConsultationRequest> myRequests,
  ) {
    final latestTwoConsultations = takeLatestPreviewRecords<PatientConsultationRequest>(
      myRequests,
      limit: kDashboardRecentPreviewLimit,
      compareDesc: (a, b) => b.submittedAt.compareTo(a.submittedAt),
    );

    void openAllConsultations() {
      _guardServiceAccess(
        context,
        serviceTitle: 'My Visits',
        onAllowed: () {
          _patientService.syncAppointmentsFromApi();
          setState(() {
            _visitsSubTabIndex = 0;
            _showAllVisits = true;
            _expandedVisitsLimit = _visitsExpandedPageSize;
            _currentIndex = 2;
          });
        },
      );
    }

    return RecentUpdatesPreviewSection(
      sectionKey: const Key('patient_recent_consultations_section'),
      viewAllKey: const Key('patient_view_all_consultations_btn'),
      emptyStateKey: const Key('patient_recent_consultations_empty'),
      title: 'Recent Consultations',
      totalCount: myRequests.length,
      icon: Icons.history_rounded,
      onViewAll: openAllConsultations,
      emptyIcon: Icons.history_rounded,
      emptyTitle: 'No recent consultations yet.',
      emptySubtitle: 'Your recent and past consultations will appear here.',
      previewChildren: latestTwoConsultations.asMap().entries.map((entry) {
        final idx = entry.key;
        final req = entry.value;
        final docName = req.displayDoctorName.trim().isNotEmpty
            ? req.displayDoctorName.trim()
            : (req.assignedDoctorName?.trim().isNotEmpty == true
                ? req.assignedDoctorName!.trim()
                : 'Consultation Request');
        final dtLabel = (req.confirmedDate != null && req.confirmedDate!.trim().isNotEmpty)
            ? req.confirmedDate!.split('T').first
            : '${req.submittedAt.toLocal().day}/${req.submittedAt.toLocal().month}/${req.submittedAt.toLocal().year}';
        return RecentUpdatePreviewCard(
          cardKey: Key('patient_recent_consultation_card_$idx'),
          leadingIcon: Icons.assignment_outlined,
          title: req.problemCategory.trim().isNotEmpty ? req.problemCategory.trim() : 'Consultation',
          subtitle: docName,
          metaLine: dtLabel,
          statusLabel: req.status.trim().isNotEmpty ? req.status.trim() : 'Submitted',
          onTap: openAllConsultations,
        );
      }).toList(),
    );
  }

  Widget _buildPatientReferralsSummarySection() {
    final received = _patientService.receivedForMePatientReferrals;
    final sent = _patientService.myCreatedPatientReferrals;
    final seenIds = <String>{};
    final combined = <dynamic>[];
    for (final r in [...received, ...sent]) {
      final key = r.id.isNotEmpty ? r.id : '${r.referredPatientMobile}_${r.doctorId}';
      if (seenIds.add(key)) combined.add(r);
    }
    combined.sort((a, b) => (b.referralDate as DateTime).compareTo(a.referralDate as DateTime));

    final receivedKeys = received.map((r) => r.id.isNotEmpty ? r.id : '${r.referredPatientMobile}_${r.doctorId}').toSet();

    return Container(
      key: const Key('patient_dashboard_referrals_section'),
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.gsNavy.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.assignment_ind_outlined, color: AppTheme.gsNavy, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Recent Referrals (${combined.length})',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.textDark),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                key: const Key('patient_view_all_referrals_btn'),
                onPressed: () {
                  _guardServiceAccess(
                    context,
                    serviceTitle: 'My Referrals',
                    onAllowed: () => ReferredPatientsSheet.show(context),
                  );
                },
                child: const Text('View All', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (combined.isEmpty)
            Container(
              key: const Key('patient_recent_referrals_empty'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Text(
                'No referrals yet.',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.textMuted),
              ),
            )
          else
            ...combined.take(kDashboardRecentPreviewLimit).map((ref) {
            final key = ref.id.isNotEmpty ? ref.id : '${ref.referredPatientMobile}_${ref.doctorId}';
            final isReceivedForMe = receivedKeys.contains(key);
            final rawStatus = ref.status.toString().trim();
            final statusLower = rawStatus.toLowerCase();
            final isAccepted = statusLower == 'accepted';
            final isRejected = statusLower == 'rejected' || statusLower == 'declined';
            final isCompleted = statusLower == 'completed';
            final isContacted = statusLower == 'contacted';
            final statusLabel = isAccepted
                ? 'Accepted'
                : (isRejected
                    ? 'Rejected'
                    : (isCompleted ? 'Completed' : (isContacted ? 'Contacted' : 'Pending')));
            final statusHint = isAccepted
                ? 'Doctor accepted the referral'
                : (isRejected
                    ? 'Doctor rejected the referral'
                    : (isCompleted
                        ? 'Referral process completed'
                        : (isContacted
                            ? 'Doctor contacted the patient'
                            : 'Waiting for doctor response')));
            final statusColor = isAccepted || isCompleted
                ? const Color(0xFF047857)
                : (isContacted
                    ? const Color(0xFF0369A1)
                    : (isRejected ? const Color(0xFFFE3434) : const Color(0xFFB45309)));
            final statusBg = isAccepted || isCompleted
                ? const Color(0x14047857)
                : (isContacted
                    ? const Color(0x140369A1)
                    : (isRejected ? const Color(0x14FE3434) : const Color(0x1AF59E0B)));
            final refDate = ref.referralDate;
            final formattedDate = '${refDate.day}/${refDate.month}/${refDate.year}';

            return Container(
              key: Key('patient_referral_card_${ref.id}'),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isReceivedForMe
                              ? 'Referred to ${ref.doctorName}'
                              : '${ref.referredPatientName} -> ${ref.doctorName}',
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppTheme.textDark),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          isReceivedForMe
                              ? '${ref.requiredSpecialist} • Referred by ${ref.referrerPatientName}'
                              : '${ref.requiredSpecialist} • ${ref.referredPatientMobile} • $formattedDate',
                          style: const TextStyle(fontSize: 11.5, color: AppTheme.textMedium),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          statusHint,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (ref.clinicalComplaint.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            ref.clinicalComplaint,
                            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    key: Key('patient_referral_status_badge_${ref.id}'),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: statusColor),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildPatientHealthOverviewSection(
    List<PatientConsultationRequest> myRequests,
  ) {
    final activePatientId = _patientService.currentPatient.id.trim();
    final currentPatientName =
        _patientService.currentPatient.name.trim().toLowerCase();
    final scopedRecords = _patientService.medicalRecords.where((itemMap) {
      final recPatientId =
          (itemMap['patientId'] ?? itemMap['patient_id'] ?? '').toString();
      if (activePatientId.isNotEmpty &&
          recPatientId.isNotEmpty &&
          recPatientId != activePatientId &&
          (currentPatientName.isEmpty ||
              recPatientId.trim().toLowerCase() != currentPatientName)) {
        return false;
      }
      return true;
    }).toList();

    final prescriptionsCount = scopedRecords.where(_isPrescriptionRecord).length;
    final diagnosticsCount = scopedRecords.where((r) {
      final isPatientUpload = r['isPatientUpload'] == true ||
          (r['storageKey'] ?? '').toString().isNotEmpty ||
          r['fileBytes'] != null;
      if (isPatientUpload) return true;
      return !_isPrescriptionRecord(r);
    }).length;

    final previousVisits = myRequests
        .where((r) => r.status.trim().toUpperCase() == 'COMPLETED')
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Records & visit history',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: AppTheme.textDark,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: InkWell(
                key: const Key('dashboard_prescriptions_quick_card'),
                onTap: () => _guardServiceAccess(
                  context,
                  serviceTitle: 'Prescriptions',
                  onAllowed: () {
                    _patientService.syncMedicalRecordsFromApi();
                    setState(() {
                      _lockerSubTabIndex = 0;
                      _currentIndex = 3;
                    });
                  },
                ),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppTheme.gsNavy.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Icon(
                          Icons.description_outlined,
                          size: 20,
                          color: AppTheme.gsNavy,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Prescriptions',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textDark,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              prescriptionsCount == 0
                                  ? 'None yet'
                                  : '$prescriptionsCount saved',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF64748B),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                key: const Key('dashboard_diagnostics_quick_card'),
                onTap: () => _guardServiceAccess(
                  context,
                  serviceTitle: 'Diagnostics',
                  onAllowed: () {
                    _patientService.syncMedicalRecordsFromApi();
                    setState(() {
                      _lockerSubTabIndex = 3;
                      _currentIndex = 3;
                    });
                  },
                ),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppTheme.gsRed.withValues(alpha: 0.09),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Icon(
                          Icons.biotech_outlined,
                          size: 20,
                          color: AppTheme.gsRed,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Diagnostics',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textDark,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              diagnosticsCount == 0
                                  ? 'No reports yet'
                                  : '$diagnosticsCount ${diagnosticsCount == 1 ? "report" : "reports"}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF64748B),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        InkWell(
          key: const Key('dashboard_previous_visits_card'),
          onTap: () => _guardServiceAccess(
            context,
            serviceTitle: 'Previous Visits',
            onAllowed: () {
              _patientService.syncAppointmentsFromApi();
              setState(() {
                _visitsSubTabIndex = 2; // Previous Visits tab
                _showAllVisits = false;
                _expandedVisitsLimit = _visitsExpandedPageSize;
                _currentIndex = 2;
              });
            },
          ),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppTheme.gsNavy.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.history_rounded,
                    size: 20,
                    color: AppTheme.gsNavy,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Recent & previous visits',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textDark,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        previousVisits.isEmpty
                            ? 'No previous visits yet'
                            : '${previousVisits.length} completed ${previousVisits.length == 1 ? "visit" : "visits"} • Latest: ${previousVisits.first.displayDoctorName.isNotEmpty ? previousVisits.first.displayDoctorName : previousVisits.first.problemCategory}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF64748B),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: Color(0xFF94A3B8),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // TAB 2: MY VISITS TAB (GS HEALTH REDESIGN)
  // ==========================================
  static const int _defaultVisitsPreviewCount = 3;
  static const int _visitsExpandedPageSize = 20;
  int _visitsSubTabIndex = 0; // 0 = All Visits, 1 = Upcoming Visits, 2 = Previous Visits, 3 = Cancelled Visits
  bool _showAllVisits = false;
  int _expandedVisitsLimit = _visitsExpandedPageSize;
  final Set<String> _cancellingVisitIds = {};

  List<PatientConsultationRequest> _getPatientRequests() {
    final requests = _patientService.requests;
    final patient = _patientService.currentPatient;
    final authUser = _safeAuthUser;
    final authId = authUser?.id.trim() ?? '';
    final authEmail = authUser?.email?.trim().toLowerCase() ?? '';
    final sessUserId = SessionService().currentSession?.userId.trim() ?? '';
    final myPatientIds = <String>{
      if (authId.isNotEmpty) authId,
      if (patient.id.trim().isNotEmpty) patient.id.trim(),
      if (sessUserId.isNotEmpty) sessUserId,
    };

    final seenIds = <String>{};
    final result = <PatientConsultationRequest>[];

    for (final r in requests) {
      final reqPatientId = (r.patientId ?? '').trim();
      bool belongsToPatient = false;
      if (reqPatientId.isNotEmpty) {
        if (myPatientIds.contains(reqPatientId)) {
          belongsToPatient = true;
        } else if (myPatientIds.isNotEmpty) {
          belongsToPatient = false;
        }
      } else if (patient.name.isNotEmpty &&
          patient.name != 'Patient' &&
          r.patientName.trim().toLowerCase() == patient.name.trim().toLowerCase()) {
        belongsToPatient = true;
      } else if (patient.name.isNotEmpty &&
          patient.name != 'Patient' &&
          (r.patientName.toLowerCase().contains(patient.name.toLowerCase()) ||
              patient.name.toLowerCase().contains(r.patientName.toLowerCase()))) {
        belongsToPatient = true;
      } else if (patient.id.isNotEmpty && r.id.contains(patient.id)) {
        belongsToPatient = true;
      } else if (authEmail.isNotEmpty &&
          r.patientName.toLowerCase().contains(authEmail.split('@').first)) {
        belongsToPatient = true;
      } else if (myPatientIds.isEmpty &&
          (patient.name.isEmpty || patient.name == 'Patient' || requests.length <= 1)) {
        belongsToPatient = true;
      }

      if (!belongsToPatient) continue;

      final normalizedId = r.id.trim();
      final dedupKey = normalizedId.isNotEmpty
          ? 'id:$normalizedId'
          : 'sig:${(r.assignedDoctorId ?? r.assignedDoctorName ?? '').trim().toLowerCase()}|${(r.confirmedDate ?? '').trim()}|${(r.confirmedTimeSlot ?? '').trim()}|${r.status.trim().toUpperCase()}';
      if (seenIds.contains(dedupKey)) continue;
      seenIds.add(dedupKey);
      result.add(r);
    }

    return result;
  }

  List<PatientConsultationRequest> _sortVisitsByRelevance(
    List<PatientConsultationRequest> visits,
  ) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final sorted = List<PatientConsultationRequest>.from(visits);

    int bucketOf(PatientConsultationRequest r) {
      final s = r.status.trim().toUpperCase();
      if (s == 'CANCELLED' || s == 'REJECTED') return 3;
      if (s == 'COMPLETED') return 2;
      final startDt = _resolveAppointmentStartDateTime(r);
      final hasSlot = (r.confirmedTimeSlot ?? '').trim().isNotEmpty;
      final isFutureOrToday = hasSlot
          ? !startDt.isBefore(now)
          : !DateTime(startDt.year, startDt.month, startDt.day).isBefore(todayStart);
      return isFutureOrToday ? 0 : 1;
    }

    sorted.sort((a, b) {
      final ba = bucketOf(a);
      final bb = bucketOf(b);
      if (ba != bb) return ba.compareTo(bb);

      final da = _resolveAppointmentStartDateTime(a);
      final db = _resolveAppointmentStartDateTime(b);
      if (ba == 0) {
        // Upcoming visits: soonest first
        final cmp = da.compareTo(db);
        if (cmp != 0) return cmp;
        return b.submittedAt.compareTo(a.submittedAt);
      }
      // Recent active-past, completed, and cancelled history: most recent first
      final cmp = db.compareTo(da);
      if (cmp != 0) return cmp;
      return b.submittedAt.compareTo(a.submittedAt);
    });

    return sorted;
  }

  Widget _buildAppointmentsTab() {
    final myRequests = _getPatientRequests();

    final upcomingVisits = myRequests.where((r) {
      final s = r.status.trim().toUpperCase();
      return s != 'COMPLETED' && s != 'CANCELLED' && s != 'REJECTED';
    }).toList();

    final previousVisits = myRequests.where((r) {
      final s = r.status.trim().toUpperCase();
      return s == 'COMPLETED';
    }).toList();

    final cancelledVisits = myRequests.where((r) {
      final s = r.status.trim().toUpperCase();
      return s == 'CANCELLED' || s == 'REJECTED';
    }).toList();

    final rawSelectedVisits = _visitsSubTabIndex == 0
        ? myRequests
        : (_visitsSubTabIndex == 1
            ? upcomingVisits
            : (_visitsSubTabIndex == 2 ? previousVisits : cancelledVisits));

    final displayedVisits = _sortVisitsByRelevance(rawSelectedVisits);
    final hasMoreThanDefault = displayedVisits.length > _defaultVisitsPreviewCount;
    final visibleVisits = _showAllVisits
        ? displayedVisits.take(_expandedVisitsLimit).toList()
        : displayedVisits.take(_defaultVisitsPreviewCount).toList();
    final remainingAfterPage = displayedVisits.length - visibleVisits.length;

    void selectSubTab(int index) {
      setState(() {
        _visitsSubTabIndex = index;
        _showAllVisits = false;
        _expandedVisitsLimit = _visitsExpandedPageSize;
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top Header with "My visits" and Selectable Tabs
        Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
            ),
          ),
          padding: EdgeInsets.fromLTRB(
            20,
            MediaQuery.of(context).padding.top + 18,
            20,
            16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'My visits',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textDark,
                        letterSpacing: -0.5,
                        height: 1.15,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (hasMoreThanDefault)
                    TextButton(
                      key: Key(_showAllVisits
                          ? 'visits_show_less_header_button'
                          : 'visits_view_all_header_button'),
                      onPressed: () {
                        setState(() {
                          _showAllVisits = !_showAllVisits;
                          _expandedVisitsLimit = _visitsExpandedPageSize;
                        });
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.gsNavy,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: const Size(0, 32),
                      ),
                      child: Text(
                        _showAllVisits ? 'Show Less' : 'View All',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    _buildGsPillTab(
                      key: const Key('visits_tab_all'),
                      label: 'All Visits',
                      badgeText: myRequests.isNotEmpty ? '(${myRequests.length})' : null,
                      isSelected: _visitsSubTabIndex == 0,
                      onTap: () => selectSubTab(0),
                    ),
                    const SizedBox(width: 10),
                    _buildGsPillTab(
                      key: const Key('visits_tab_upcoming'),
                      label: 'Upcoming Visits',
                      badgeText: upcomingVisits.isNotEmpty ? '(${upcomingVisits.length})' : null,
                      isSelected: _visitsSubTabIndex == 1,
                      onTap: () => selectSubTab(1),
                    ),
                    const SizedBox(width: 10),
                    _buildGsPillTab(
                      key: const Key('visits_tab_previous'),
                      label: 'Previous Visits',
                      badgeText: previousVisits.isNotEmpty ? '(${previousVisits.length})' : null,
                      isSelected: _visitsSubTabIndex == 2,
                      onTap: () => selectSubTab(2),
                    ),
                    const SizedBox(width: 10),
                    _buildGsPillTab(
                      key: const Key('visits_tab_cancelled'),
                      label: 'Cancelled Visits',
                      badgeText: cancelledVisits.isNotEmpty ? '(${cancelledVisits.length})' : null,
                      isSelected: _visitsSubTabIndex == 3,
                      onTap: () => selectSubTab(3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Scrollable Appointment Cards List with Latest-3 Default, View All / Show Less & Pagination
        Expanded(
          child: RefreshIndicator(
            color: AppTheme.gsNavy,
            onRefresh: () async {
              await Future.wait([
                _patientService.syncAppointmentsFromApi(),
                _patientService.syncProblemRequestsFromApi(),
              ]);
              if (mounted) setState(() {});
            },
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                36 + MediaQuery.of(context).padding.bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                if (displayedVisits.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _showAllVisits
                                ? 'Showing ${visibleVisits.length} of ${displayedVisits.length} ${displayedVisits.length == 1 ? 'visit' : 'visits'}'
                                : (hasMoreThanDefault
                                    ? 'Showing latest ${visibleVisits.length} of ${displayedVisits.length} visits'
                                    : 'Showing ${displayedVisits.length} ${displayedVisits.length == 1 ? 'visit' : 'visits'}'),
                            key: const Key('visits_count_summary'),
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (visibleVisits.isEmpty)
                  _buildVisitsEmptyState(tabIndex: _visitsSubTabIndex)
                else ...[
                  ...visibleVisits.map(
                    (req) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _buildGsVisitCard(req),
                    ),
                  ),
                  if (hasMoreThanDefault && !_showAllVisits)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          key: const Key('visits_view_all_button'),
                          onPressed: () {
                            setState(() {
                              _showAllVisits = true;
                              _expandedVisitsLimit = _visitsExpandedPageSize;
                            });
                          },
                          icon: const Icon(Icons.unfold_more_rounded, size: 18),
                          label: Text(
                            'View All (${displayedVisits.length} Visits)',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.gsNavy,
                            side: const BorderSide(color: AppTheme.gsNavy, width: 1.4),
                            backgroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_showAllVisits && remainingAfterPage > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 10),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          key: const Key('visits_load_more_button'),
                          onPressed: () {
                            setState(() {
                              _expandedVisitsLimit += _visitsExpandedPageSize;
                            });
                          },
                          icon: const Icon(Icons.expand_more_rounded, size: 18),
                          label: Text(
                            'Load More Visits ($remainingAfterPage remaining)',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.gsNavy,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_showAllVisits && hasMoreThanDefault)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          key: const Key('visits_show_less_button'),
                          onPressed: () {
                            setState(() {
                              _showAllVisits = false;
                              _expandedVisitsLimit = _visitsExpandedPageSize;
                            });
                          },
                          icon: const Icon(Icons.unfold_less_rounded, size: 18),
                          label: const Text(
                            'Show Less',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.gsNavy,
                            side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.3),
                            backgroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGsPillTab({
    Key? key,
    required String label,
    String? badgeText,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(26),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.gsNavy : Colors.white,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: isSelected ? AppTheme.gsNavy : const Color(0xFFCBD5E1),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected ? Colors.white : AppTheme.textDark,
              ),
            ),
            if (badgeText != null && badgeText.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(
                badgeText,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected ? Colors.white : AppTheme.textDark,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVisitsEmptyState({required int tabIndex}) {
    final isAll = tabIndex == 0;
    final isUpcoming = tabIndex == 1;
    final isCancelled = tabIndex == 3;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppTheme.gsNavy.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              (isAll || isUpcoming)
                  ? Icons.calendar_today_rounded
                  : (isCancelled ? Icons.cancel_outlined : Icons.history_rounded),
              color: AppTheme.gsNavy,
              size: 26,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            isAll
                ? 'No visits yet.'
                : (isUpcoming
                    ? 'No upcoming visits yet.'
                    : (isCancelled ? 'No cancelled visits.' : 'No previous visits yet.')),
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppTheme.textDark,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            (isAll || isUpcoming)
                ? 'Book a verified doctor near you in under a minute.'
                : (isCancelled
                    ? 'Any cancelled or declined consultations will appear here.'
                    : 'Your completed medical consultations will appear here.'),
            style: const TextStyle(
              fontSize: 13.5,
              color: Color(0xFF64748B),
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          if (isAll || isUpcoming) ...[
            const SizedBox(height: 18),
            ElevatedButton.icon(
              key: const Key('book_visit_empty_button'),
              onPressed: () => _openBookVisitFlow(context),
              icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
              label: const Text(
                'Book Visit',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.gsNavy,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  DateTime _resolveAppointmentDateTime(PatientConsultationRequest req) {
    if (req.confirmedDate != null && req.confirmedDate!.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(req.confirmedDate!.trim());
      if (parsed != null) return parsed;
    }
    return req.submittedAt;
  }

  String _formatDayAbbreviation(DateTime dt) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return weekdays[(dt.weekday - 1).clamp(0, 6)];
  }

  String _formatShortDate(DateTime dt) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sept',
      'Oct',
      'Nov',
      'Dec'
    ];
    final dayName = weekdays[(dt.weekday - 1).clamp(0, 6)];
    final monthName = months[(dt.month - 1).clamp(0, 11)];
    return '$dayName, ${dt.day} $monthName';
  }

  String _formatPanelTime(String? rawSlot, DateTime dt) {
    if (rawSlot != null && rawSlot.trim().isNotEmpty) {
      final cleaned = rawSlot
          .trim()
          .replaceAll(RegExp(r'\s*(AM|PM)$', caseSensitive: false), '')
          .trim();
      if (cleaned.isNotEmpty) return cleaned;
    }
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _formatBookingTimestamp(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final local = dt.toLocal();
    final month = months[(local.month - 1).clamp(0, 11)];
    final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final amPm = local.hour >= 12 ? 'PM' : 'AM';
    final minStr = local.minute.toString().padLeft(2, '0');
    return '${local.day} $month ${local.year}, $hour12:$minStr $amPm';
  }

  DoctorModel? _resolveDoctorForRequest(PatientConsultationRequest req, String doctorName) {
    final docId = (req.assignedDoctorId ?? req.preferredDoctorId ?? '').trim();
    if (docId.isNotEmpty) {
      final byId = _patientService.allDoctors
          .where((d) => d.id == docId || (d.userId.isNotEmpty && d.userId == docId))
          .firstOrNull;
      if (byId != null) return byId;
    }
    final cleanTarget = doctorName.replaceAll(RegExp(r'^Dr\.?\s*', caseSensitive: false), '').trim().toLowerCase();
    if (cleanTarget.isNotEmpty) {
      return _patientService.allDoctors
          .where((d) => d.name.replaceAll(RegExp(r'^Dr\.?\s*', caseSensitive: false), '').trim().toLowerCase() == cleanTarget)
          .firstOrNull;
    }
    return null;
  }

  Widget _buildGsVisitCard(PatientConsultationRequest req) {
    final dt = _resolveAppointmentDateTime(req);
    final dayAbbr = _formatDayAbbreviation(dt);
    final shortDate = _formatShortDate(dt);
    final panelTime = _formatPanelTime(req.confirmedTimeSlot, dt);
    final fullTimeSlot = (req.confirmedTimeSlot != null && req.confirmedTimeSlot!.trim().isNotEmpty)
        ? req.confirmedTimeSlot!.trim()
        : panelTime;
    final bookedAtFormatted = _formatBookingTimestamp(req.submittedAt);

    final doctorName = req.displayDoctorName.isNotEmpty
        ? req.displayDoctorName
        : (req.assignedDoctorName?.trim().isNotEmpty == true
            ? req.assignedDoctorName!.trim()
            : (req.preferredDoctorName?.trim().isNotEmpty == true
                ? req.preferredDoctorName!.trim()
                : 'Assigned Doctor'));

    final matchedDoctor = _resolveDoctorForRequest(req, doctorName);
    final Uint8List? doctorPhotoBytes = matchedDoctor?.photoBytes;
    final String? doctorPhotoUrl = matchedDoctor?.profileImageUrl;

    final specialty = req.displayDoctorSpecialty.isNotEmpty
        ? req.displayDoctorSpecialty
        : (req.assignedDoctorSpecialty?.trim().isNotEmpty == true
            ? req.assignedDoctorSpecialty!.trim()
            : (matchedDoctor?.specialty.trim().isNotEmpty == true
                ? matchedDoctor!.specialty.trim()
                : (req.problemCategory.trim().isNotEmpty
                    ? req.problemCategory.trim()
                    : 'Medical Consultation')));

    final clinicLocation = req.displayDoctorClinic.isNotEmpty
        ? req.displayDoctorClinic
        : (req.assignedDoctorClinic?.trim().isNotEmpty == true
            ? req.assignedDoctorClinic!.trim()
            : (req.preferredDoctorClinic?.trim().isNotEmpty == true
                ? req.preferredDoctorClinic!.trim()
                : (matchedDoctor?.clinicName.trim().isNotEmpty == true
                    ? matchedDoctor!.clinicName.trim()
                    : req.preferredLocation.trim())));

    final realFeeDisplay = BookingRulesConfig.formatRealFee(
      req.assignedDoctorFee ?? matchedDoctor?.consultationFee,
      emptyFallback: '',
    );

    final combinedTypeCheck =
        '${req.preferredLocation} ${req.problemDescription} ${req.problemCategory}'
            .toLowerCase();
    final isOnline = combinedTypeCheck.contains('online') ||
        combinedTypeCheck.contains('video') ||
        combinedTypeCheck.contains('tele');
    final visitTypeLabel = isOnline ? 'ONLINE' : 'IN-CLINIC';

    final statusUpper = req.status.trim().toUpperCase();
    final canCancel = statusUpper != 'COMPLETED' &&
        statusUpper != 'CANCELLED' &&
        statusUpper != 'REJECTED';

    String statusDisplay;
    Color statusBgColor;
    Color statusTextColor;

    if (statusUpper == 'CONFIRMED' ||
        statusUpper == 'ACCEPTED' ||
        statusUpper == 'SCHEDULED') {
      statusDisplay = 'Confirmed';
      statusBgColor = AppTheme.gsNavy.withValues(alpha: 0.1);
      statusTextColor = AppTheme.gsNavy;
    } else if (statusUpper == 'COMPLETED') {
      statusDisplay = 'Completed';
      statusBgColor = const Color(0x14012A58);
      statusTextColor = const Color(0xFF012A58);
    } else if (statusUpper == 'CANCELLED') {
      statusDisplay = 'Cancelled';
      statusBgColor = AppTheme.gsRed.withValues(alpha: 0.12);
      statusTextColor = const Color(0xFFFE3434);
    } else if (statusUpper == 'REJECTED') {
      statusDisplay = 'Rejected';
      statusBgColor = AppTheme.gsRed.withValues(alpha: 0.12);
      statusTextColor = const Color(0xFFFE3434);
    } else if (statusUpper == 'RESCHEDULED') {
      statusDisplay = 'Rescheduled';
      statusBgColor = const Color(0x14012A58);
      statusTextColor = const Color(0xFF012A58);
    } else {
      statusDisplay = 'Pending';
      statusBgColor = const Color(0x14FE3434);
      statusTextColor = const Color(0xFFFE3434);
    }

    final noteText = req.problemDescription.trim();
    final isCancelling = _cancellingVisitIds.contains(req.id);

    return Container(
      key: Key('visit_card_${req.id}'),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left Date and Time Panel
              Container(
                width: 72,
                constraints: const BoxConstraints(minHeight: 108),
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
                decoration: BoxDecoration(
                  color: AppTheme.gsNavy.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      dayAbbr,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF475569),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      panelTime,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.gsNavy,
                        letterSpacing: -0.3,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),

              // Right Appointment Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Dentist Avatar + Name + Status Badge
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppTheme.gsNavy.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: doctorPhotoBytes != null && doctorPhotoBytes.isNotEmpty
                              ? ClipOval(
                                  child: Image.memory(
                                    doctorPhotoBytes,
                                    width: 40,
                                    height: 40,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.medical_services_rounded,
                                      size: 20,
                                      color: AppTheme.gsNavy,
                                    ),
                                  ),
                                )
                              : (doctorPhotoUrl != null && doctorPhotoUrl.trim().isNotEmpty)
                                  ? ClipOval(
                                      child: Image.network(
                                        doctorPhotoUrl.trim(),
                                        width: 40,
                                        height: 40,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Center(
                                          child: Text(
                                            doctorName.replaceAll(RegExp(r'^Dr\.?\s*', caseSensitive: false), '').trim().isNotEmpty
                                                ? doctorName.replaceAll(RegExp(r'^Dr\.?\s*', caseSensitive: false), '').trim()[0].toUpperCase()
                                                : 'D',
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w800,
                                              color: AppTheme.gsNavy,
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                  : Center(
                                      child: Text(
                                        doctorName.replaceAll(RegExp(r'^Dr\.?\s*', caseSensitive: false), '').trim().isNotEmpty
                                            ? doctorName.replaceAll(RegExp(r'^Dr\.?\s*', caseSensitive: false), '').trim()[0].toUpperCase()
                                            : 'D',
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          color: AppTheme.gsNavy,
                                        ),
                                      ),
                                    ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                doctorName,
                                style: const TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textDark,
                                  height: 1.2,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                specialty,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppTheme.primaryBlue,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: statusBgColor,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            statusDisplay,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: statusTextColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Appointment Date & Time
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 14,
                          color: Color(0xFF64748B),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            '$shortDate · $fullTimeSlot',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF334155),
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Clinic Location with Location Icon
                    if (clinicLocation.isNotEmpty) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 1.5),
                            child: Icon(
                              Icons.location_on_outlined,
                              size: 16,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              clinicLocation,
                              style: const TextStyle(
                                fontSize: 13.5,
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],

                    // Booking Date & Time + Appointment ID
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Text(
                          'Booked: $bookedAtFormatted',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          'ID: ${req.id}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF94A3B8),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Appointment Type Badge (IN-CLINIC / ONLINE) + Real Consultation Fee
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isOnline
                                    ? Icons.videocam_outlined
                                    : Icons.apartment_rounded,
                                size: 14,
                                color: const Color(0xFF475569),
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  visitTypeLabel,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF475569),
                                    letterSpacing: 0.4,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (realFeeDisplay.isNotEmpty)
                          Container(
                            key: Key('visit_fee_badge_${req.id}'),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: AppTheme.gsNavy.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Fee: $realFeeDisplay',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.gsNavy,
                              ),
                            ),
                          ),
                      ],
                    ),

                    // Appointment Notes (if available)
                    if (noteText.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        '“$noteText”',
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: Color(0xFF475569),
                          height: 1.35,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          // Visit Card Actions: Chat, Details, Reschedule, Cancel (where applicable)
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (statusUpper != 'CANCELLED' && statusUpper != 'REJECTED')
                OutlinedButton.icon(
                  key: Key('chat_visit_button_${req.id}'),
                  onPressed: () => _guardServiceAccess(
                    context,
                    serviceTitle: 'Doctor Chat',
                    onAllowed: () => _showChatModal(context, request: req),
                  ),
                  icon: Icon(
                    isOnline ? Icons.videocam_rounded : Icons.chat_bubble_outline_rounded,
                    size: 15,
                  ),
                  label: Text(
                    isOnline && canCancel ? 'Join / Chat' : 'Chat',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.gsNavy,
                    backgroundColor: AppTheme.gsNavy.withValues(alpha: 0.06),
                    side: BorderSide(color: AppTheme.gsNavy.withValues(alpha: 0.25)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              OutlinedButton.icon(
                key: Key('details_visit_button_${req.id}'),
                onPressed: () => _guardServiceAccess(
                  context,
                  serviceTitle: 'Visit Details',
                  onAllowed: () => AppointmentManagementDialog.show(
                    context,
                    appointment: req,
                    initialMode: AppointmentManagementMode.details,
                    onUpdated: () => setState(() {}),
                  ),
                ),
                icon: const Icon(Icons.info_outline_rounded, size: 15),
                label: const Text(
                  'Details',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textDark,
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              if (canCancel) ...[
                OutlinedButton.icon(
                  key: Key('reschedule_visit_button_${req.id}'),
                  onPressed: () => _guardServiceAccess(
                    context,
                    serviceTitle: 'Reschedule Visit',
                    onAllowed: () => AppointmentManagementDialog.show(
                      context,
                      appointment: req,
                      initialMode: AppointmentManagementMode.reschedule,
                      onUpdated: () => setState(() {}),
                    ),
                  ),
                  icon: const Icon(Icons.edit_calendar_outlined, size: 15),
                  label: const Text(
                    'Reschedule',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.gsNavy,
                    side: const BorderSide(color: AppTheme.gsNavy),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                InkWell(
                  key: Key('cancel_visit_button_${req.id}'),
                  onTap: isCancelling
                      ? null
                      : () => _guardServiceAccess(
                            context,
                            serviceTitle: 'Cancel Visit',
                            onAllowed: () => _confirmAndCancelVisit(context, req, doctorName),
                          ),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.gsRed.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isCancelling) ...[
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFFFE3434),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Cancelling...',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFFE3434),
                            ),
                          ),
                        ] else
                          const Text(
                            'Cancel visit',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFFE3434),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndCancelVisit(
    BuildContext context,
    PatientConsultationRequest req,
    String doctorName,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Cancel visit?',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppTheme.textDark,
            ),
          ),
          content: Text(
            'Are you sure you want to cancel your visit with $doctorName?',
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF475569),
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text(
                'Keep visit',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.gsNavy,
                ),
              ),
            ),
            ElevatedButton(
              key: const Key('confirm_cancel_visit_button'),
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.gsRed,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Yes, cancel visit',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _cancellingVisitIds.add(req.id);
    });

    try {
      final res = await _patientService.cancelAppointment(req.id);
      if (!mounted || !context.mounted) return;
      setState(() {
        _cancellingVisitIds.remove(req.id);
      });

      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Visit cancelled successfully.'),
            backgroundColor: AppTheme.gsNavy,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              (res['message'] ?? 'Could not cancel visit. Please try again.')
                  .toString(),
            ),
            backgroundColor: AppTheme.gsRed,
          ),
        );
      }
    } catch (e) {
      if (!mounted || !context.mounted) return;
      setState(() {
        _cancellingVisitIds.remove(req.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error cancelling visit: $e'),
          backgroundColor: AppTheme.gsRed,
        ),
      );
    }
  }

  // ==========================================
  // TAB 3: HEALTH LOCKER TAB (GS HEALTH REDESIGN)
  // ==========================================
  static const List<String> _recordCategories = [
    'Prescription',
    'Lab Report',
    'X-Ray / Scan',
    'Clinical Document',
    'Dental X-ray',
    'Dental Report',
    'Treatment Documents',
    'Other',
  ];

  int _lockerSubTabIndex = 0; // 0 = Prescriptions, 1 = Health Records, 2 = X-rays & reports
  final Set<String> _expandedPrescriptionIds = {};
  bool _didAutoExpandFirstRx = false;

  String _resolveActivePatientId() {
    if (_patientService.currentPatient.id.isNotEmpty) {
      return _patientService.currentPatient.id;
    }
    return _safeAuthUser?.id ?? '';
  }

  bool _isPrescriptionRecord(Map<String, dynamic> rec) {
    final type = (rec['type'] ?? '').toString().toLowerCase();
    final cat = (rec['category'] ?? '').toString().toLowerCase();
    final hasMedItems = rec['items'] is List && (rec['items'] as List).isNotEmpty;
    return type == 'prescription' || cat.contains('prescription') || hasMedItems;
  }

  bool _isDiagnosticRecord(Map<String, dynamic> rec) {
    if (_isPrescriptionRecord(rec)) return false;
    final type = (rec['type'] ?? '').toString().toLowerCase();
    final cat = (rec['category'] ?? '').toString().toLowerCase();
    return type == 'diagnostic' ||
        type == 'lab_report' ||
        type == 'xray' ||
        cat.contains('diagnostic') ||
        cat.contains('lab') ||
        cat.contains('scan') ||
        cat.contains('x-ray') ||
        cat.contains('xray') ||
        cat.contains('pathology') ||
        cat.contains('radiology');
  }

  bool _isToothChartRecord(Map<String, dynamic> rec) {
    final type = (rec['type'] ?? '').toString().toLowerCase();
    final cat = (rec['category'] ?? '').toString().toLowerCase();
    return type == 'tooth' ||
        type == 'dental_chart' ||
        type == 'clinical_document' ||
        cat.contains('tooth') ||
        cat.contains('teeth') ||
        cat.contains('clinical') ||
        cat.contains('health record') ||
        cat.contains('medical history') ||
        cat == 'treatment documents' ||
        cat.contains('chart');
  }

  String _formatLockerRecordDate(String rawDate) {
    if (rawDate.trim().isEmpty) return 'Recent';
    final parsed = DateTime.tryParse(rawDate.trim());
    if (parsed != null) {
      return _formatShortDate(parsed);
    }
    return rawDate.trim();
  }

  Widget _buildRecordsTab() {
    final activePatientId = _resolveActivePatientId();
    return FutureBuilder<List<dynamic>>(
      future: ApiService().fetchMedicalRecords(
        patientId: activePatientId.isNotEmpty ? activePatientId : null,
      ),
      builder: (context, snapshot) {
        final apiRecords = snapshot.data ?? [];
        final localRecords = _patientService.medicalRecords;

        final combinedMap = <String, Map<String, dynamic>>{};
        for (final item in [...localRecords, ...apiRecords]) {
          if (item is! Map) continue;
          final itemMap = Map<String, dynamic>.from(item);
          final recPatientId =
              (itemMap['patientId'] ?? itemMap['patient_id'] ?? '').toString();
          final currentPatientName =
              _patientService.currentPatient.name.trim().toLowerCase();
          if (activePatientId.isNotEmpty &&
              recPatientId.isNotEmpty &&
              recPatientId != activePatientId &&
              (currentPatientName.isEmpty ||
                  recPatientId.trim().toLowerCase() != currentPatientName)) {
            continue;
          }
          final id = (itemMap['id'] ??
                  itemMap['title'] ??
                  UniqueKey().toString())
              .toString();
          combinedMap[id] = itemMap;
        }

        final allRecords = combinedMap.values.toList()
          ..sort((a, b) {
            final aDate = (a['uploadedAt'] ?? a['date'] ?? '').toString();
            final bDate = (b['uploadedAt'] ?? b['date'] ?? '').toString();
            return bDate.compareTo(aDate);
          });

        final prescriptionRecords =
            allRecords.where(_isPrescriptionRecord).toList();

        if (!_didAutoExpandFirstRx && prescriptionRecords.isNotEmpty) {
          final firstId = (prescriptionRecords.first['id'] ?? 'rx_0').toString();
          _expandedPrescriptionIds.add(firstId);
          _didAutoExpandFirstRx = true;
        }

        final toothRecords = allRecords.where(_isToothChartRecord).toList();
        final myConsultations = _getPatientRequests();

        final xrayAndReportRecords = allRecords.where((r) {
          final isPatientUpload = r['isPatientUpload'] == true ||
              (r['storageKey'] ?? '').toString().isNotEmpty ||
              r['fileBytes'] != null;
          if (isPatientUpload) return true;
          return !_isPrescriptionRecord(r);
        }).toList();

        final diagnosticRecords = allRecords.where(_isDiagnosticRecord).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Health Locker Header + Category Tabs
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
                ),
              ),
              padding: EdgeInsets.fromLTRB(
                20,
                MediaQuery.of(context).padding.top + 14,
                20,
                16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your medical & health records',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Health locker',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textDark,
                      letterSpacing: -0.5,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        _buildGsPillTab(
                          key: const Key('locker_tab_prescriptions'),
                          label: 'Prescriptions',
                          badgeText: prescriptionRecords.isNotEmpty
                              ? '(${prescriptionRecords.length})'
                              : null,
                          isSelected: _lockerSubTabIndex == 0,
                          onTap: () => setState(() => _lockerSubTabIndex = 0),
                        ),
                        const SizedBox(width: 10),
                        _buildGsPillTab(
                          key: const Key('locker_tab_my_teeth'),
                          label: 'Health Records',
                          isSelected: _lockerSubTabIndex == 1,
                          onTap: () => setState(() => _lockerSubTabIndex = 1),
                        ),
                        const SizedBox(width: 10),
                        _buildGsPillTab(
                          key: const Key('locker_tab_xrays_reports'),
                          label: 'X-rays & reports',
                          isSelected: _lockerSubTabIndex == 2,
                          onTap: () => setState(() => _lockerSubTabIndex = 2),
                        ),
                        const SizedBox(width: 10),
                        _buildGsPillTab(
                          key: const Key('locker_tab_diagnostics'),
                          label: 'Diagnostics',
                          isSelected: _lockerSubTabIndex == 3,
                          onTap: () => setState(() => _lockerSubTabIndex = 3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Body Content based on Selected Category Tab
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  16,
                  18,
                  16,
                  36 + MediaQuery.of(context).padding.bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_lockerSubTabIndex == 0)
                      _buildPrescriptionsCategoryContent(
                        prescriptionRecords: prescriptionRecords,
                        allRecords: allRecords,
                      )
                    else if (_lockerSubTabIndex == 1)
                      _buildMyTeethCategoryContent(
                        toothRecords: toothRecords,
                        consultations: myConsultations,
                        allRecords: allRecords,
                      )
                    else if (_lockerSubTabIndex == 2)
                      _buildXraysAndReportsCategoryContent(
                        xrayRecords: xrayAndReportRecords,
                        allRecords: allRecords,
                        isLoading: snapshot.connectionState ==
                            ConnectionState.waiting,
                      )
                    else
                      _buildDiagnosticsCategoryContent(
                        diagnosticRecords: diagnosticRecords,
                        allRecords: allRecords,
                        isLoading: snapshot.connectionState ==
                            ConnectionState.waiting,
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPrescriptionsCategoryContent({
    required List<Map<String, dynamic>> prescriptionRecords,
    required List<Map<String, dynamic>> allRecords,
  }) {
    if (prescriptionRecords.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppTheme.gsNavy.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.description_outlined,
                color: AppTheme.gsNavy,
                size: 26,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'No prescriptions yet',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.textDark,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            const Text(
              'Digital e-prescriptions issued by your doctor after a visit will appear here.',
              style: TextStyle(
                fontSize: 13.5,
                color: Color(0xFF64748B),
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      children: prescriptionRecords.asMap().entries.map((entry) {
        final index = entry.key;
        final rec = entry.value;
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _buildExpandablePrescriptionCard(
            record: rec,
            fallbackIndex: index,
            allRecords: allRecords,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildExpandablePrescriptionCard({
    required Map<String, dynamic> record,
    required int fallbackIndex,
    required List<Map<String, dynamic>> allRecords,
  }) {
    final recId = (record['id'] ?? 'rx_$fallbackIndex').toString();
    final isExpanded = _expandedPrescriptionIds.contains(recId);

    // Resolve diagnosis or prescription title
    String diagnosisTitle = (record['diagnosis'] ?? '').toString().trim();
    if (diagnosisTitle.isEmpty) {
      final rawSubtitle = (record['subtitle'] ?? '').toString().trim();
      if (rawSubtitle.toLowerCase().startsWith('diagnosis:')) {
        diagnosisTitle = rawSubtitle.substring('diagnosis:'.length).trim();
      } else if (rawSubtitle.isNotEmpty) {
        diagnosisTitle = rawSubtitle;
      }
    }
    if (diagnosisTitle.isEmpty) {
      diagnosisTitle = (record['title'] ?? 'Medical Prescription').toString().trim();
    }

    final doctorName = (record['doctorName'] ??
            record['doctor_name'] ??
            record['doctor'] ??
            'Attending Doctor')
        .toString()
        .trim();
    final clinicName = (record['clinicName'] ??
            record['clinic_name'] ??
            record['clinic'] ??
            '')
        .toString()
        .trim();
    final rawDate =
        (record['date'] ?? record['uploadedAt'] ?? '').toString().trim();
    final formattedDate = _formatLockerRecordDate(rawDate);

    final List<Map<String, dynamic>> medItems = [];
    final rawItemsList = record['items'] ?? record['medicines'];
    if (rawItemsList is List) {
      for (final item in rawItemsList) {
        if (item is Map) {
          medItems.add(Map<String, dynamic>.from(item));
        }
      }
    }

    String instructions = (record['instructions'] ??
            record['advice'] ??
            record['notes'] ??
            record['description'] ??
            '')
        .toString()
        .trim();
    if (instructions.isEmpty && medItems.isNotEmpty) {
      instructions = (medItems.first['instructions'] ?? '').toString().trim();
    }

    final hasUploadedFile = record['isPatientUpload'] == true ||
        (record['storageKey'] ?? '').toString().isNotEmpty ||
        record['fileBytes'] != null;

    return Container(
      key: Key('prescription_card_$recId'),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
          // Expandable Header
          InkWell(
            key: Key('prescription_header_$recId'),
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedPrescriptionIds.remove(recId);
                } else {
                  _expandedPrescriptionIds.add(recId);
                }
              });
            },
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppTheme.gsNavy.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.description_outlined,
                      color: AppTheme.gsNavy,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          diagnosisTitle,
                          style: const TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textDark,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$doctorName · $formattedDate',
                          style: const TextStyle(
                            fontSize: 13.5,
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
                    color: const Color(0xFF475569),
                    size: 24,
                  ),
                ],
              ),
            ),
          ),

          // Expanded Prescription Details
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'E-PRESCRIPTION',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF64748B),
                          letterSpacing: 0.8,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          ' · ${medItems.isNotEmpty ? medItems.length : 1} MEDICINE(S)',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF64748B),
                            letterSpacing: 0.8,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if ((record['specialty'] ?? '').toString().trim().isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.gsNavy.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            record['specialty'].toString().trim(),
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.gsNavy,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (medItems.isNotEmpty)
                    ...medItems.map((med) {
                      final medName =
                          (med['name'] ?? 'Prescribed Medicine').toString().trim();
                      final dosage = (med['dosage'] ?? '').toString().trim();
                      final frequency =
                          (med['frequency'] ?? '1-0-1').toString().trim();
                      final duration =
                          (med['duration'] ?? '3 days').toString().trim();

                      final displayMedTitle = dosage.isNotEmpty &&
                              !medName.toLowerCase().contains(dosage.toLowerCase())
                          ? '$medName $dosage'
                          : medName;

                      return Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '℞ $displayMedTitle',
                              style: const TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textDark,
                                fontFamilyFallback: [
                                  'Segoe UI Symbol',
                                  'Arial Unicode MS',
                                  'serif',
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$frequency · $duration',
                              style: const TextStyle(
                                fontSize: 13.5,
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      );
                    })
                  else
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        '℞ $diagnosisTitle',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textDark,
                        ),
                      ),
                    ),
                  if (instructions.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.chat_outlined,
                            size: 16,
                            color: Color(0xFF64748B),
                          ),
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
                  if (record['clinicalSections'] is Map && (record['clinicalSections'] as Map).isNotEmpty) ...[
                    const SizedBox(height: 6),
                    ...SpecialtyClinicalConfig.forSpecialty((record['specialty'] ?? '').toString())
                        .prescriptionSchema
                        .sections
                        .where((sec) => ((record['clinicalSections'] as Map)[sec.key] ?? '').toString().trim().isNotEmpty)
                        .map((sec) {
                      final val = (record['clinicalSections'] as Map)[sec.key].toString().trim();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '${sec.label}: $val',
                          style: const TextStyle(fontSize: 12.5, color: Color(0xFF334155), height: 1.35),
                        ),
                      );
                    }),
                  ],
                  if ((record['followUpDate'] ?? '').toString().trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Follow-up Date: ${record['followUpDate']}',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.gsRed),
                    ),
                  ],
                  if (clinicName.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 1.5),
                          child: Icon(
                            Icons.location_on_outlined,
                            size: 16,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            clinicName,
                            style: const TextStyle(
                              fontSize: 13.5,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (!hasUploadedFile) ...[
                    const SizedBox(height: 10),
                    _buildRecordActionButton(
                      icon: Icons.picture_as_pdf_outlined,
                      label: 'Prescription PDF',
                      color: AppTheme.gsNavy,
                      onTap: () => PrescriptionPdfGenerator.showPreviewDialog(context, record: record),
                    ),
                  ],
                  if (hasUploadedFile) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _buildRecordActionButton(
                          icon: Icons.visibility_rounded,
                          label: 'View file',
                          color: AppTheme.gsNavy,
                          onTap: () => _showRecordDetailModal(context, record),
                        ),
                        _buildRecordActionButton(
                          icon: Icons.download_rounded,
                          label: 'Download',
                          color: AppTheme.gsNavy,
                          onTap: () => _handleDownloadRecord(context, record),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMyTeethCategoryContent({
    required List<Map<String, dynamic>> toothRecords,
    required List<PatientConsultationRequest> consultations,
    required List<Map<String, dynamic>> allRecords,
  }) {
    if (toothRecords.isEmpty && consultations.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppTheme.gsNavy.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.medical_information_outlined,
                color: AppTheme.gsNavy,
                size: 26,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'No health records yet',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.textDark,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            const Text(
              'Clinical evaluations, medical history, consultations, and medical/treatment records from your visits will appear here.',
              style: TextStyle(
                fontSize: 13.5,
                color: Color(0xFF64748B),
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...toothRecords.map(
          (rec) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildRecordCard(record: rec, allRecords: allRecords),
          ),
        ),
        ...consultations.map((req) {
          final dt = _resolveAppointmentDateTime(req);
          final shortDate = _formatShortDate(dt);
          final docName = req.displayDoctorName.isNotEmpty
              ? req.displayDoctorName
              : (req.assignedDoctorName ?? 'Medical Evaluation');
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.gsNavy.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.healing_rounded,
                    color: AppTheme.gsNavy,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        req.problemCategory,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$docName · $shortDate',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (req.problemDescription.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          req.problemDescription.trim(),
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF475569),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildXraysAndReportsCategoryContent({
    required List<Map<String, dynamic>> xrayRecords,
    required List<Map<String, dynamic>> allRecords,
    required bool isLoading,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top Action Bar (+ Add Record & Share with Doctor)
        Row(
          children: [
            Expanded(
              child: Text(
                xrayRecords.isEmpty
                    ? 'X-rays, scans & lab reports'
                    : '${xrayRecords.length} ${xrayRecords.length == 1 ? 'document' : 'documents'} saved',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isLoading)
              const Padding(
                padding: EdgeInsets.only(right: 10),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.gsNavy,
                  ),
                ),
              ),
            ElevatedButton.icon(
              key: const Key('add_dental_record_button'),
              onPressed: () => _guardServiceAccess(
                context,
                serviceTitle: 'Health Locker',
                onAllowed: () => _showUploadOrEditRecordSheet(context),
              ),
              icon: const Icon(Icons.cloud_upload_outlined, size: 17),
              label: const Text(
                '+ Add Record',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.gsNavy,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        if (allRecords.isNotEmpty) ...[
          const SizedBox(height: 10),
            OutlinedButton.icon(
            key: const Key('share_multiple_records_button'),
            onPressed: () => _guardServiceAccess(
              context,
              serviceTitle: 'Health Locker',
              onAllowed: () => _showShareWithDoctorModal(
                context,
                allAvailableRecords: allRecords,
              ),
            ),
            icon: const Icon(
              Icons.share_rounded,
              size: 15,
              color: AppTheme.gsNavy,
            ),
            label: Text(
              'Share with Favourite Doctor (${_patientService.myDoctors.length})',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.gsNavy,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppTheme.gsNavy),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
        const SizedBox(height: 14),

        if (xrayRecords.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppTheme.gsNavy.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.folder_open_rounded,
                    size: 28,
                    color: AppTheme.gsNavy,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'No X-rays or reports yet',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    color: AppTheme.textDark,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Upload your X-rays, lab reports, scans or clinical documents (JPG, PNG, PDF) and securely share them with your doctor.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: Color(0xFF64748B),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  key: const Key('empty_state_add_record_button'),
                  onPressed: () => _guardServiceAccess(
                    context,
                    serviceTitle: 'Health Locker',
                    onAllowed: () => _showUploadOrEditRecordSheet(context),
                  ),
                  icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                  label: const Text(
                    '+ Add Record',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.gsNavy,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          ...xrayRecords.map((rec) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildRecordCard(
                record: rec,
                allRecords: allRecords,
              ),
            );
          }),
      ],
    );
  }

  Widget _buildDiagnosticsCategoryContent({
    required List<Map<String, dynamic>> diagnosticRecords,
    required List<Map<String, dynamic>> allRecords,
    required bool isLoading,
  }) {
    if (diagnosticRecords.isEmpty) {
      return Container(
        key: const Key('diagnostics_empty_state'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppTheme.gsNavy.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.biotech_rounded,
                color: AppTheme.gsNavy,
                size: 26,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'No diagnostic reports yet.',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.textDark,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            const Text(
              'Your lab tests, blood work, and radiology scans will appear here with referring doctor and lab status details.',
              style: TextStyle(
                fontSize: 13.5,
                color: Color(0xFF64748B),
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              key: const Key('diagnostics_empty_upload_button'),
              onPressed: () => _guardServiceAccess(
                context,
                serviceTitle: 'Diagnostics',
                onAllowed: () => _showUploadOrEditRecordSheet(context),
              ),
              icon: const Icon(Icons.cloud_upload_rounded, size: 18),
              label: const Text('+ Upload Diagnostic Report', style: TextStyle(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.gsNavy,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isLoading)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: LinearProgressIndicator(color: AppTheme.gsNavy),
          ),
        ...diagnosticRecords.map((rec) {
          final recId = (rec['id'] ?? '').toString();
          final testName = (rec['testName'] ?? rec['title'] ?? 'Diagnostic Test').toString().trim();
          final rawDate = (rec['date'] ?? rec['uploadedAt'] ?? '').toString().trim();
          final dateLabel = _formatLockerRecordDate(rawDate);
          final referringDoctor = (rec['referringDoctor'] ??
                  rec['doctorName'] ??
                  rec['doctor_name'] ??
                  '')
              .toString()
              .trim();
          final labDetails = (rec['labName'] ??
                  rec['labDetails'] ??
                  rec['clinicName'] ??
                  rec['clinic_name'] ??
                  '')
              .toString()
              .trim();
          final reportStatus = (rec['reportStatus'] ?? rec['status'] ?? 'Available').toString().trim();

          return Container(
            key: Key('diagnostic_card_$recId'),
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.gsNavy.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.biotech_rounded, color: AppTheme.gsNavy, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            testName,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textDark,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Date: $dateLabel',
                            style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.gsNavy.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        reportStatus,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.gsNavy,
                        ),
                      ),
                    ),
                  ],
                ),
                if (referringDoctor.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Referring Doctor: $referringDoctor',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF334155)),
                  ),
                ],
                if (labDetails.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Lab: $labDetails',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _buildRecordActionButton(
                      icon: Icons.visibility_rounded,
                      label: 'View',
                      color: AppTheme.gsNavy,
                      onTap: () => _showRecordDetailModal(context, rec),
                    ),
                    _buildRecordActionButton(
                      icon: Icons.download_rounded,
                      label: 'Download',
                      color: AppTheme.gsNavy,
                      onTap: () => _handleDownloadRecord(context, rec),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  IconData _iconForCategory(String category, String type, String fileType) {
    final c = category.toLowerCase();
    if (c.contains('x-ray') || c.contains('xray') || type == 'xray') {
      return Icons.qr_code_scanner_rounded;
    }
    if (c.contains('prescription')) {
      return Icons.medication_rounded;
    }
    if (c.contains('lab')) {
      return Icons.biotech_rounded;
    }
    if (c.contains('treatment')) {
      return Icons.medical_information_rounded;
    }
    if (fileType.toUpperCase() == 'PDF') {
      return Icons.picture_as_pdf_rounded;
    }
    return Icons.description_rounded;
  }

  Color _colorForCategory(String category, String type) {
    final c = category.toLowerCase();
    if (c.contains('x-ray') || c.contains('xray') || type == 'xray') {
      return AppTheme.gsNavy;
    }
    if (c.contains('prescription')) {
      return AppTheme.gsNavy;
    }
    if (c.contains('lab')) {
      return AppTheme.gsRed;
    }
    if (c.contains('treatment')) {
      return AppTheme.gsRed;
    }
    return AppTheme.gsNavy;
  }

  Widget _buildRecordCard({
    required Map<String, dynamic> record,
    required List<Map<String, dynamic>> allRecords,
  }) {
    final recId = (record['id'] ?? '').toString();
    final type = (record['type'] ?? 'prescription').toString();
    final title = (record['title'] ?? 'Health Record').toString();
    final category = (record['category'] ?? 'Medical Report').toString();
    final description = (record['description'] ?? '').toString().trim();
    final date = (record['date'] ?? '').toString();
    final fileType = (record['fileType'] ?? 'PDF').toString().toUpperCase();
    final fileSize = record['fileSize'] is int
        ? record['fileSize'] as int
        : int.tryParse((record['fileSize'] ?? '0').toString()) ?? 0;
    final isPatientUpload = record['isPatientUpload'] == true ||
        (record['storageKey'] ?? '').toString().isNotEmpty;
    final Uint8List? fileBytes =
        record['fileBytes'] is Uint8List ? record['fileBytes'] as Uint8List : null;

    final List<Map<String, dynamic>> sharedWith = [];
    if (record['sharedWith'] is List) {
      for (final item in (record['sharedWith'] as List)) {
        if (item is Map) {
          sharedWith.add(Map<String, dynamic>.from(item));
        }
      }
    }

    final icon = _iconForCategory(category, type, fileType);
    final color = _colorForCategory(category, type);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          InkWell(
            onTap: () => _showRecordDetailModal(context, record),
            borderRadius: BorderRadius.circular(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (fileBytes != null && fileBytes.isNotEmpty && fileType != 'PDF')
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Image.memory(
                        fileBytes,
                        fit: BoxFit.cover,
                        errorBuilder: (ctx, err, stack) => Container(
                          color: color.withValues(alpha: 0.1),
                          child: Icon(icon, color: color, size: 24),
                        ),
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: AppTheme.textDark,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: fileType == 'PDF'
                                  ? const Color(0x14FE3434)
                                  : const Color(0x14FE3434),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              fileType,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: fileType == 'PDF'
                                    ? const Color(0xFFFE3434)
                                    : const Color(0xFFFE3434),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              category,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: color,
                              ),
                            ),
                          ),
                          if (date.isNotEmpty)
                            Text(
                              'Uploaded: $date',
                              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                            ),
                          if (fileSize > 0)
                            Text(
                              '• ${RecordFileHelper.formatFileSize(fileSize)}',
                              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                            ),
                        ],
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          description,
                          style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Shared with Doctor status badges + one-tap Revoke
          const SizedBox(height: 10),
          if (sharedWith.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.gsNavy.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppTheme.gsNavy.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.verified_user_rounded,
                        size: 14,
                        color: AppTheme.gsNavy,
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Shared with Favourite Doctor(s):',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.gsNavy,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: sharedWith.map((s) {
                      final docId = (s['doctorId'] ?? '').toString();
                      final docName = (s['doctorName'] ?? 'Doctor').toString();
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppTheme.gsNavy.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                docName,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textDark,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () => _confirmRevokeShare(
                                context,
                                recordId: recId,
                                recordTitle: title,
                                doctorId: docId,
                                doctorName: docName,
                              ),
                              child: const Tooltip(
                                message: 'Revoke access',
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Revoke',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFFE3434),
                                      ),
                                    ),
                                    SizedBox(width: 2),
                                    Icon(Icons.close_rounded, size: 13, color: Color(0xFFFE3434)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            )
          else
            const Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 13, color: AppTheme.textMuted),
                SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Private — Only visible to you until shared with a doctor',
                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

          const Divider(height: 18, color: Color(0xFFE2E8F0)),

          // Action Buttons: View, Download, Share with Doctor, Edit, Delete
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildRecordActionButton(
                icon: Icons.visibility_rounded,
                label: 'View',
                color: AppTheme.gsNavy,
                onTap: () => _showRecordDetailModal(context, record),
              ),
              _buildRecordActionButton(
                icon: Icons.download_rounded,
                label: 'Download',
                color: AppTheme.gsNavy,
                onTap: () => _handleDownloadRecord(context, record),
              ),
              _buildRecordActionButton(
                icon: Icons.share_rounded,
                label: 'Share with Doctor',
                color: AppTheme.gsNavy,
                onTap: () => _guardServiceAccess(
                  context,
                  serviceTitle: 'Health Locker',
                  onAllowed: () => _showShareWithDoctorModal(
                    context,
                    preselectedRecord: record,
                    allAvailableRecords: allRecords,
                  ),
                ),
              ),
              if (isPatientUpload || recId.isNotEmpty)
                _buildRecordActionButton(
                  icon: Icons.edit_rounded,
                  label: 'Edit',
                  color: AppTheme.gsRed,
                  onTap: () => _guardServiceAccess(
                    context,
                    serviceTitle: 'Health Locker',
                    onAllowed: () => _showUploadOrEditRecordSheet(
                      context,
                      existingRecord: record,
                    ),
                  ),
                ),
              if (isPatientUpload || recId.isNotEmpty)
                _buildRecordActionButton(
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete',
                  color: AppTheme.gsRed,
                  onTap: () => _confirmDeleteRecord(context, record),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecordActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // UPLOAD / EDIT DENTAL RECORD MODAL SHEET
  // ==========================================
  void _showUploadOrEditRecordSheet(
    BuildContext context, {
    Map<String, dynamic>? existingRecord,
  }) {
    final isEdit = existingRecord != null;
    final nameController = TextEditingController(
      text: isEdit ? (existingRecord['title'] ?? '').toString() : '',
    );
    final descController = TextEditingController(
      text: isEdit ? (existingRecord['description'] ?? '').toString() : '',
    );
    String selectedCategory = isEdit
        ? (existingRecord['category'] ?? 'Medical X-ray').toString()
        : 'Medical X-ray';
    if (!_recordCategories.contains(selectedCategory)) {
      selectedCategory = 'Other';
    }

    PickedRecordFile? pickedFile;
    bool isSubmitting = false;
    double uploadProgress = 0.0;
    String? errorMessage;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Future<void> handlePickFile() async {
              setModalState(() {
                errorMessage = null;
              });
              final file = await RecordFileHelper.pickRecordFile();
              if (file == null) return;

              final validationError = RecordFileHelper.validatePickedFile(file);
              if (validationError != null) {
                setModalState(() {
                  errorMessage = validationError;
                });
                return;
              }
              setModalState(() {
                pickedFile = file;
                if (nameController.text.trim().isEmpty) {
                  final dotIndex = file.name.lastIndexOf('.');
                  nameController.text = dotIndex > 0 ? file.name.substring(0, dotIndex) : file.name;
                }
              });
            }

            Future<void> handleSubmit() async {
              final recordName = nameController.text.trim();
              final description = descController.text.trim();

              if (recordName.isEmpty) {
                setModalState(() {
                  errorMessage = 'Please enter a Record Name.';
                });
                return;
              }
              if (!isEdit && pickedFile == null) {
                setModalState(() {
                  errorMessage = 'Please select a file to upload (JPG, JPEG, PNG, or PDF).';
                });
                return;
              }

              setModalState(() {
                isSubmitting = true;
                uploadProgress = 0.05;
                errorMessage = null;
              });

              Map<String, dynamic> res;
              if (isEdit) {
                res = await _patientService.updateDentalRecord(
                  recordId: (existingRecord['id'] ?? '').toString(),
                  recordName: recordName,
                  category: selectedCategory,
                  description: description,
                  newFileBytes: pickedFile?.bytes,
                  newFileName: pickedFile?.name,
                  onProgress: (p) {
                    if (ctx.mounted) {
                      setModalState(() => uploadProgress = p);
                    }
                  },
                );
              } else {
                res = await _patientService.uploadDentalRecord(
                  recordName: recordName,
                  category: selectedCategory,
                  description: description,
                  fileBytes: pickedFile!.bytes,
                  fileName: pickedFile!.name,
                  onProgress: (p) {
                    if (ctx.mounted) {
                      setModalState(() => uploadProgress = p);
                    }
                  },
                );
              }

              if (!ctx.mounted) return;
              if (res['success'] == true) {
                Navigator.of(sheetCtx).pop();
                if (mounted) {
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isEdit
                            ? 'Health record "$recordName" updated successfully.'
                            : 'Health record "$recordName" uploaded securely.',
                      ),
                      backgroundColor: const Color(0xFF012A58),
                    ),
                  );
                }
              } else {
                setModalState(() {
                  isSubmitting = false;
                  errorMessage = (res['message'] ?? 'Failed to save health record.').toString();
                });
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.88,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: const EdgeInsets.all(20),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              isEdit ? Icons.edit_document : Icons.cloud_upload_rounded,
                              color: AppTheme.primaryBlue,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isEdit ? 'Edit Health Record' : 'Upload Health Record',
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textDark,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const Text(
                                  'Supported formats: JPG, JPEG, PNG, PDF (Max 20 MB)',
                                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: isSubmitting ? null : () => Navigator.of(sheetCtx).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const Divider(height: 24, color: Color(0xFFE2E8F0)),

                      if (errorMessage != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: const Color(0x14FE3434),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0x40FE3434)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: Color(0xFFFE3434), size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  errorMessage!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFFE3434),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // 1. Record Name
                      const Text(
                        'Record Name *',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        key: const Key('record_name_field'),
                        controller: nameController,
                        enabled: !isSubmitting,
                        decoration: InputDecoration(
                          hintText: 'e.g., Upper Molar Panoramic X-Ray',
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // 2. Record Category
                      const Text(
                        'Record Category *',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        key: const Key('record_category_dropdown'),
                        initialValue: selectedCategory,
                        items: _recordCategories
                            .map((cat) => DropdownMenuItem(
                                  value: cat,
                                  child: Text(cat, style: const TextStyle(fontSize: 13)),
                                ))
                            .toList(),
                        onChanged: isSubmitting
                            ? null
                            : (val) {
                                if (val != null) {
                                  setModalState(() => selectedCategory = val);
                                }
                              },
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // 3. Description (optional)
                      const Text(
                        'Description (Optional)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        key: const Key('record_description_field'),
                        controller: descController,
                        enabled: !isSubmitting,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: 'Add notes about tooth position, clinic, or symptoms...',
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // 4. Upload File Picker & Preview
                      Text(
                        isEdit ? 'Replace File (Optional)' : 'Upload File *',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 6),
                      InkWell(
                        key: const Key('select_record_file_button'),
                        onTap: isSubmitting ? null : handlePickFile,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: pickedFile != null
                                  ? AppTheme.primaryBlue
                                  : const Color(0xFFCBD5E1),
                            ),
                          ),
                          child: pickedFile == null
                              ? Column(
                                  children: [
                                    const Icon(
                                      Icons.upload_file_rounded,
                                      size: 32,
                                      color: AppTheme.primaryBlue,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      isEdit
                                          ? 'Current file: ${(existingRecord['fileName'] ?? existingRecord['title'] ?? 'Attached document')} (Tap to replace)'
                                          : 'Tap to select JPG, JPEG, PNG or PDF file',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.textDark,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    const Text(
                                      'Encrypted & stored in private patient vault',
                                      style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                    ),
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          pickedFile!.isPdf
                                              ? Icons.picture_as_pdf_rounded
                                              : Icons.image_rounded,
                                          color: pickedFile!.isPdf
                                              ? const Color(0xFFFE3434)
                                              : AppTheme.primaryBlue,
                                          size: 28,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                pickedFile!.name,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppTheme.textDark,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              Text(
                                                '${pickedFile!.extension.toUpperCase()} • ${pickedFile!.formattedSize}',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: AppTheme.textMuted,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: isSubmitting ? null : handlePickFile,
                                          child: const Text('Change', style: TextStyle(fontSize: 12)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    if (pickedFile!.isImage)
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: Image.memory(
                                          pickedFile!.bytes,
                                          height: 150,
                                          width: double.infinity,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => Container(
                                            height: 80,
                                            alignment: Alignment.center,
                                            color: const Color(0xFFE2E8F0),
                                            child: const Text(
                                              'Image selected & ready for upload',
                                              style: TextStyle(fontSize: 12),
                                            ),
                                          ),
                                        ),
                                      )
                                    else if (pickedFile!.isPdf)
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: const Color(0x14FE3434),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: const Color(0x40FE3434)),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.picture_as_pdf_rounded,
                                              color: Color(0xFFFE3434),
                                              size: 22,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'PDF Document Ready (${pickedFile!.formattedSize})',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFFFE3434),
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                        ),
                      ),

                      if (isSubmitting) ...[
                        const SizedBox(height: 16),
                        LinearProgressIndicator(
                          value: uploadProgress > 0 && uploadProgress <= 1.0 ? uploadProgress : null,
                          backgroundColor: const Color(0xFFE2E8F0),
                          color: AppTheme.primaryBlue,
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Uploading & encrypting document... ${(uploadProgress * 100).clamp(5, 100).toInt()}%',
                          style: const TextStyle(fontSize: 11, color: AppTheme.primaryBlue),
                        ),
                      ],

                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          key: const Key('submit_dental_record_button'),
                          onPressed: isSubmitting ? null : handleSubmit,
                          icon: isSubmitting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(isEdit ? Icons.save_rounded : Icons.cloud_done_rounded, size: 18),
                          label: Text(
                            isSubmitting
                                ? 'Saving Record...'
                                : (isEdit ? 'Save Record Changes' : 'Upload Health Record'),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
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

  // ==========================================
  // SHARE RECORDS WITH FAVOURITE DOCTOR MODAL
  // ==========================================
  void _showShareWithDoctorModal(
    BuildContext context, {
    Map<String, dynamic>? preselectedRecord,
    required List<Map<String, dynamic>> allAvailableRecords,
  }) {
    final favDoctors = _patientService.myDoctors;
    final selectedRecordIds = <String>{};
    if (preselectedRecord != null) {
      final preId = (preselectedRecord['id'] ?? '').toString();
      if (preId.isNotEmpty) selectedRecordIds.add(preId);
    } else if (allAvailableRecords.length == 1) {
      final onlyId = (allAvailableRecords.first['id'] ?? '').toString();
      if (onlyId.isNotEmpty) selectedRecordIds.add(onlyId);
    }

    DoctorModel? selectedDoctor = favDoctors.isNotEmpty ? favDoctors.first : null;
    bool isSharing = false;
    String? errorMsg;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final currentFavDoctors = _patientService.myDoctors;
            if (selectedDoctor == null && currentFavDoctors.isNotEmpty) {
              selectedDoctor = currentFavDoctors.first;
            }

            Future<void> confirmAndShare() async {
              if (selectedDoctor == null) {
                setModalState(() => errorMsg = 'Please select a Favourite Doctor.');
                return;
              }
              if (selectedRecordIds.isEmpty) {
                setModalState(() => errorMsg = 'Please select at least one record to share.');
                return;
              }

              final doc = selectedDoctor!;
              final confirmed = await showDialog<bool>(
                context: ctx,
                builder: (dCtx) => AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: const Text(
                    'Confirm Record Sharing',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  content: Text(
                    'Share ${selectedRecordIds.length} health ${selectedRecordIds.length == 1 ? 'record' : 'records'} with ${doc.name} (${doc.specialty})?\n\nYou can revoke this permission at any time from your Records tab.',
                    style: const TextStyle(fontSize: 13, color: AppTheme.textDark),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dCtx).pop(false),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      key: const Key('confirm_share_dialog_button'),
                      onPressed: () => Navigator.of(dCtx).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF012A58),
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Confirm & Share'),
                    ),
                  ],
                ),
              );

              if (confirmed != true || !ctx.mounted) return;

              setModalState(() {
                isSharing = true;
                errorMsg = null;
              });

              final res = await _patientService.shareDentalRecordsWithDoctor(
                recordIds: selectedRecordIds.toList(),
                doctor: doc,
              );

              if (!ctx.mounted) return;
              if (res['success'] == true) {
                Navigator.of(sheetCtx).pop();
                if (mounted) {
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        (res['message'] ?? 'Shared records with ${doc.name}.').toString(),
                      ),
                      backgroundColor: const Color(0xFF012A58),
                    ),
                  );
                }
              } else {
                setModalState(() {
                  isSharing = false;
                  errorMsg = (res['message'] ?? 'Failed to share records.').toString();
                });
              }
            }

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.85,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF012A58).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.share_rounded,
                            color: Color(0xFF012A58),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Share with Favourite Doctor',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textDark,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Grant secure view & download access to your selected specialist',
                                style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: isSharing ? null : () => Navigator.of(sheetCtx).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const Divider(height: 24, color: Color(0xFFE2E8F0)),

                    if (errorMsg != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: const Color(0x14FE3434),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0x40FE3434)),
                        ),
                        child: Text(
                          errorMsg!,
                          style: const TextStyle(fontSize: 12, color: Color(0xFFFE3434)),
                        ),
                      ),
                    ],

                    // Step 1: Select Favourite Doctor
                    const Text(
                      '1. Select Favourite Doctor ("My Favourite Doctors")',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 8),

                    if (currentFavDoctors.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.person_add_alt_1_rounded, size: 28, color: AppTheme.primaryBlue),
                            const SizedBox(height: 8),
                            const Text(
                              'No Favourite Doctors Added Yet',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Add a doctor to "My Favourite Doctors" on the Home tab first, or quick-add from available specialists below:',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                            ),
                            if (_patientService.availableDoctors.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _patientService.availableDoctors.take(4).map((doc) {
                                  return ActionChip(
                                    avatar: const Icon(Icons.favorite_border_rounded, size: 14, color: AppTheme.primaryBlue),
                                    label: Text(
                                      '+ Add ${doc.name}',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                    ),
                                    onPressed: () async {
                                      await _patientService.addDoctorToMyDoctors(doc);
                                      if (ctx.mounted) {
                                        setModalState(() {
                                          selectedDoctor = doc;
                                        });
                                      }
                                    },
                                  );
                                }).toList(),
                              ),
                            ],
                          ],
                        ),
                      )
                    else
                      ...currentFavDoctors.map((doc) {
                        final isSelected = selectedDoctor?.id == doc.id &&
                            selectedDoctor?.email == doc.email;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0x14012A58)
                                : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF012A58)
                                  : const Color(0xFFE2E8F0),
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: ListTile(
                            onTap: isSharing
                                ? null
                                : () => setModalState(() => selectedDoctor = doc),
                            leading: Icon(
                              isSelected
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_off_rounded,
                              color: isSelected ? const Color(0xFF012A58) : AppTheme.textMuted,
                            ),
                            title: Text(
                              doc.name,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textDark,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${doc.specialty}${doc.clinicName.isNotEmpty ? ' • ${doc.clinicName}' : ''}',
                              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                              overflow: TextOverflow.ellipsis,
                            ),
                            dense: true,
                          ),
                        );
                      }),

                    const SizedBox(height: 14),

                    // Step 2: Select One or Multiple Records
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            '2. Select Record(s) to Share',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textDark,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton(
                          onPressed: isSharing
                              ? null
                              : () {
                                  setModalState(() {
                                    if (selectedRecordIds.length == allAvailableRecords.length) {
                                      selectedRecordIds.clear();
                                    } else {
                                      for (final r in allAvailableRecords) {
                                        final id = (r['id'] ?? '').toString();
                                        if (id.isNotEmpty) selectedRecordIds.add(id);
                                      }
                                    }
                                  });
                                },
                          child: Text(
                            selectedRecordIds.length == allAvailableRecords.length
                                ? 'Deselect All'
                                : 'Select All (${allAvailableRecords.length})',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    ...allAvailableRecords.map((rec) {
                      final id = (rec['id'] ?? '').toString();
                      final title = (rec['title'] ?? 'Health Record').toString();
                      final category = (rec['category'] ?? 'Medical Report').toString();
                      final date = (rec['date'] ?? '').toString();
                      final isChecked = selectedRecordIds.contains(id);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isChecked
                              ? AppTheme.primaryBlue.withValues(alpha: 0.05)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isChecked
                                ? AppTheme.primaryBlue
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: CheckboxListTile(
                          value: isChecked,
                          activeColor: AppTheme.primaryBlue,
                          dense: true,
                          onChanged: isSharing || id.isEmpty
                              ? null
                              : (val) {
                                  setModalState(() {
                                    if (val == true) {
                                      selectedRecordIds.add(id);
                                    } else {
                                      selectedRecordIds.remove(id);
                                    }
                                  });
                                },
                          title: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textDark,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '$category • $date',
                            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      );
                    }),

                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        key: const Key('submit_share_records_button'),
                        onPressed: (isSharing || currentFavDoctors.isEmpty)
                            ? null
                            : confirmAndShare,
                        icon: isSharing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.verified_user_rounded, size: 18),
                        label: Text(
                          isSharing
                              ? 'Sharing Records...'
                              : 'Share Selected (${selectedRecordIds.length}) with Doctor',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF012A58),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
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

  Future<void> _confirmRevokeShare(
    BuildContext context, {
    required String recordId,
    required String recordTitle,
    required String doctorId,
    required String doctorName,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Revoke Doctor Access?',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Remove $doctorName\'s access to "$recordTitle"? They will immediately lose permission to view or download this record.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            key: const Key('confirm_revoke_share_button'),
            onPressed: () => Navigator.of(dCtx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFE3434),
              foregroundColor: Colors.white,
            ),
            child: const Text('Revoke Access'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final res = await _patientService.revokeDentalRecordShare(
      recordId: recordId,
      doctorId: doctorId,
    );

    if (!mounted) return;
    setState(() {});
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          (res['message'] ?? 'Revoked $doctorName\'s access to "$recordTitle".').toString(),
        ),
        backgroundColor: res['success'] == true ? const Color(0xFF0F172A) : const Color(0xFFFE3434),
      ),
    );
  }

  Future<void> _confirmDeleteRecord(
    BuildContext context,
    Map<String, dynamic> record,
  ) async {
    final recId = (record['id'] ?? '').toString();
    final title = (record['title'] ?? 'Health Record').toString();
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Health Record?',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to permanently delete "$title"? Any doctors this record was shared with will also lose access.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            key: const Key('confirm_delete_record_button'),
            onPressed: () => Navigator.of(dCtx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFE3434),
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final res = await _patientService.deleteDentalRecord(recordId: recId);
    if (!mounted) return;
    setState(() {});
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          (res['message'] ?? 'Deleted "$title".').toString(),
        ),
        backgroundColor: res['success'] == true ? const Color(0xFF012A58) : const Color(0xFFFE3434),
      ),
    );
  }

  Future<void> _handleDownloadRecord(
    BuildContext context,
    Map<String, dynamic> record,
  ) async {
    final title = (record['title'] ?? 'dental_record').toString();
    final recId = (record['id'] ?? '').toString();
    final storageKey = (record['storageKey'] ?? '').toString();
    final fileName = (record['fileName'] ?? '$title.pdf').toString();
    final mimeType = (record['mimeType'] ?? 'application/pdf').toString();

    if (storageKey.isNotEmpty && recId.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Verifying authorization & downloading "$title"...'),
          duration: const Duration(seconds: 2),
        ),
      );
      final accessRes = await ApiService().getAuthorizedRecordAccess(
        recordId: recId,
        requesterId: _resolveActivePatientId(),
        requesterRole: 'Patient',
      );
      if (!context.mounted) return;

      if (accessRes['success'] == true) {
        if (accessRes['fileBytes'] is Uint8List) {
          final bytes = accessRes['fileBytes'] as Uint8List;
          final saved = await RecordFileHelper.downloadOrOpenFile(
            bytes: bytes,
            fileName: fileName,
            mimeType: mimeType,
          );
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                saved
                    ? 'Downloaded "$fileName" (${RecordFileHelper.formatFileSize(bytes.length)}).'
                    : 'Prepared "$fileName" (${RecordFileHelper.formatFileSize(bytes.length)}) for offline access.',
              ),
              backgroundColor: const Color(0xFF012A58),
            ),
          );
          return;
        } else if ((accessRes['signedUrl'] ?? '').toString().isNotEmpty) {
          final uri = Uri.tryParse(accessRes['signedUrl'].toString());
          if (uri != null) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
            return;
          }
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text((accessRes['message'] ?? 'Access denied.').toString()),
            backgroundColor: const Color(0xFFFE3434),
          ),
        );
        return;
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Downloaded "$title" to device.'),
        backgroundColor: const Color(0xFF012A58),
      ),
    );
  }

  void _showRecordDetailModal(BuildContext context, Map<String, dynamic> record) {
    final recId = (record['id'] ?? '').toString();
    final type = (record['type'] ?? 'prescription').toString();
    final title = (record['title'] ?? 'Record Details').toString();
    final category = (record['category'] ?? 'Dental Report').toString();
    final description = (record['description'] ?? '').toString();
    final doctor = (record['doctorName'] ?? 'Patient Uploaded Record').toString();
    final clinic = (record['clinicName'] ?? record['clinic_name'] ?? 'Private Health Vault').toString();
    final date = (record['date'] ?? '').toString();
    final fileName = (record['fileName'] ?? '').toString();
    final fileType = (record['fileType'] ?? 'PDF').toString().toUpperCase();
    final storageKey = (record['storageKey'] ?? '').toString();
    final List items = record['items'] is List ? record['items'] : [];
    final isImageFile = fileType == 'JPG' || fileType == 'JPEG' || fileType == 'PNG';

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 540, maxHeight: 640),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: AppTheme.textDark,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$category • $doctor • $clinic',
                            style: const TextStyle(fontSize: 11, color: AppTheme.primaryBlue),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => Navigator.of(dialogCtx).pop(),
                    ),
                  ],
                ),
                const Divider(height: 20, color: Color(0xFFE2E8F0)),

                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 10,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.calendar_today_rounded, size: 14, color: AppTheme.textMuted),
                                const SizedBox(width: 6),
                                Text(
                                  'Date: $date',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0x14012A58),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '$category ($fileType)',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primaryBlue,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Clinical / Patient Notes:',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textDark,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  description,
                                  style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),

                        // Secure Document Preview (Image or PDF) when backed by Supabase Storage
                        if (storageKey.isNotEmpty && recId.isNotEmpty)
                          FutureBuilder<Map<String, dynamic>>(
                            future: ApiService().getAuthorizedRecordAccess(
                              recordId: recId,
                              requesterId: _resolveActivePatientId(),
                              requesterRole: 'Patient',
                            ),
                            builder: (ctx, snap) {
                              if (snap.connectionState == ConnectionState.waiting) {
                                return Container(
                                  height: 180,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      CircularProgressIndicator(strokeWidth: 2),
                                      SizedBox(height: 8),
                                      Text(
                                        'Decrypting & loading secure document preview...',
                                        style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                      ),
                                    ],
                                  ),
                                );
                              }

                              final res = snap.data ?? {};
                              final bytes = res['fileBytes'] is Uint8List
                                  ? res['fileBytes'] as Uint8List
                                  : null;
                              final signedUrl = (res['signedUrl'] ?? '').toString();

                              if (isImageFile) {
                                if (bytes != null && bytes.isNotEmpty) {
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Image Preview (Pinch/Scroll to Zoom):',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.textDark,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(14),
                                        child: Container(
                                          height: 260,
                                          width: double.infinity,
                                          color: const Color(0xFF0F172A),
                                          child: InteractiveViewer(
                                            child: Image.memory(
                                              bytes,
                                              fit: BoxFit.contain,
                                              errorBuilder: (_, __, ___) => const Center(
                                                child: Text(
                                                  'Image preview loaded',
                                                  style: TextStyle(color: Colors.white),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                } else if (signedUrl.isNotEmpty) {
                                  return ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: Image.network(
                                      signedUrl,
                                      height: 240,
                                      width: double.infinity,
                                      fit: BoxFit.contain,
                                    ),
                                  );
                                }
                              }

                              // PDF Preview Card
                              return Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0x14FE3434),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: const Color(0x40FE3434)),
                                ),
                                child: Column(
                                  children: [
                                    const Icon(
                                      Icons.picture_as_pdf_rounded,
                                      size: 44,
                                      color: Color(0xFFFE3434),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      fileName.isNotEmpty ? fileName : '$title.pdf',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: AppTheme.textDark,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      bytes != null
                                          ? 'Verified PDF Document • ${RecordFileHelper.formatFileSize(bytes.length)}'
                                          : 'Encrypted PDF Health Record',
                                      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                    ),
                                  ],
                                ),
                              );
                            },
                          )
                        else if (type == 'prescription' && items.isNotEmpty) ...[
                          const Text(
                            'Prescribed Medications List:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: AppTheme.textDark,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...items.map((item) => Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.medication_rounded, color: Color(0xFF012A58), size: 20),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            (item['name'] ?? '').toString(),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                              color: AppTheme.textDark,
                                            ),
                                          ),
                                          Text(
                                            'Dosage: ${item['dosage']} • Duration: ${item['duration']}',
                                            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(dialogCtx).pop();
                          _showShareWithDoctorModal(
                            context,
                            preselectedRecord: record,
                            allAvailableRecords: [record],
                          );
                        },
                        icon: const Icon(Icons.share_rounded, size: 16),
                        label: const Text('Share', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF012A58),
                          side: const BorderSide(color: Color(0xFF012A58)),
                          minimumSize: const Size.fromHeight(44),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(dialogCtx).pop();
                          _handleDownloadRecord(context, record);
                        },
                        icon: const Icon(Icons.download_rounded, size: 16),
                        label: const Text(
                          'Download Document',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryBlue,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(44),
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
  }

  // ==========================================
  // TAB 4: PROFILE TAB (GS HEALTH CONTINUOUS SCROLL REDESIGN)
  // ==========================================
  static const List<String> _profileLanguageOptions = [
    'English',
    'Hindi',
    'Marathi',
    'Tamil',
    'Telugu',
    'Kannada',
    'Malayalam',
    'Bengali',
    'Gujarati',
    'Punjabi',
    'Urdu',
    'Odia',
  ];

  String _resolveProfileDisplayName(PatientProfile patient) {
    final raw = patient.name.trim();
    if (raw.isNotEmpty &&
        raw.toLowerCase() != 'patient' &&
        !raw.toLowerCase().startsWith('user_')) {
      return _formatPatientName(raw);
    }
    final sessName = SessionService().currentSession?.name?.trim();
    if (sessName != null &&
        sessName.isNotEmpty &&
        sessName.toLowerCase() != 'patient' &&
        !sessName.toLowerCase().startsWith('user_')) {
      return _formatPatientName(sessName);
    }
    final authMetaName = _safeAuthUser?.userMetadata?['name']?.toString().trim() ??
        _safeAuthUser?.userMetadata?['full_name']?.toString().trim();
    if (authMetaName != null &&
        authMetaName.isNotEmpty &&
        authMetaName.toLowerCase() != 'patient' &&
        !authMetaName.toLowerCase().startsWith('user_')) {
      return _formatPatientName(authMetaName);
    }
    return (raw.isNotEmpty && !raw.toLowerCase().startsWith('user_'))
        ? _formatPatientName(raw)
        : 'Patient';
  }

  String _resolveProfilePhone(PatientProfile patient) {
    String raw = patient.phone.trim();
    if (raw.isEmpty) {
      raw = SessionService().currentSession?.phone?.trim() ?? '';
    }
    if (raw.isEmpty) {
      raw = _safeAuthUser?.phone?.trim() ??
          _safeAuthUser?.userMetadata?['phone']?.toString().trim() ??
          '';
    }
    if (raw.isEmpty) {
      return 'Mobile not provided';
    }
    final digitsOnly = raw.replaceAll(RegExp(r'\D'), '');
    if (!raw.startsWith('+') && digitsOnly.length == 10) {
      return '+91$digitsOnly';
    }
    return raw;
  }

  String _resolveProfileCity(PatientProfile patient) {
    if (patient.city.trim().isNotEmpty && patient.city.trim().toLowerCase() != 'null') {
      return patient.city.trim();
    }
    if (patient.address.trim().isNotEmpty && patient.address.trim().toLowerCase() != 'null') {
      return patient.address.trim();
    }
    final metaCity = _safeAuthUser?.userMetadata?['city']?.toString().trim();
    if (metaCity != null && metaCity.isNotEmpty && metaCity.toLowerCase() != 'null') {
      return metaCity;
    }
    return 'India';
  }

  String _getPatientInitials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'P';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Future<void> _togglePreferredLanguage(String language) async {
    final current = List<String>.from(_patientService.currentPatient.languages);
    final existingIdx = current.indexWhere(
      (l) => l.trim().toLowerCase() == language.trim().toLowerCase(),
    );

    if (existingIdx != -1) {
      if (current.length > 1) {
        current.removeAt(existingIdx);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('At least one preferred language must remain selected.'),
            backgroundColor: AppTheme.gsNavy,
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }
    } else {
      current.add(language);
    }

    await _patientService.updatePatientLanguages(current);
    if (mounted) {
      setState(() {});
    }
  }

  Widget _buildProfileTab() {
    final patient = _patientService.currentPatient;
    final displayName = _resolveProfileDisplayName(patient);
    final displayPhone = _resolveProfilePhone(patient);
    final displayCity = _resolveProfileCity(patient);
    final selectedLanguages = patient.languages.isNotEmpty
        ? patient.languages
        : const <String>['English'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Profile Page Header
        Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
            ),
          ),
          padding: EdgeInsets.fromLTRB(
            18,
            MediaQuery.of(context).padding.top + 12,
            18,
            14,
          ),
          child: Row(
            children: [
              InkWell(
                key: const Key('profile_back_button'),
                onTap: () => setState(() => _currentIndex = 0),
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFE2E8F0),
                      width: 1.2,
                    ),
                  ),
                  child: const Icon(
                    Icons.chevron_left_rounded,
                    color: AppTheme.textDark,
                    size: 26,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'Profile',
                  style: TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),

        // Continuous Scrollable Body containing all Profile cards & actions
        Expanded(
          child: SingleChildScrollView(
            key: const Key('profile_scroll_view'),
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              16,
              18,
              16,
              36 + MediaQuery.of(context).padding.bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 2. Patient Profile Card
                Container(
                  key: const Key('patient_profile_card'),
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
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
                    children: [
                      // Centered Avatar
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          color: AppTheme.gsNavy,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.gsNavy.withValues(alpha: 0.18),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: patient.photoBytes != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(28),
                                child: Image.memory(
                                  patient.photoBytes!,
                                  width: 84,
                                  height: 84,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : Center(
                                child: Text(
                                  _getPatientInitials(displayName),
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(height: 16),

                      // Patient Full Name (Explicitly horizontally centered)
                      SizedBox(
                        width: double.infinity,
                        child: Center(
                          child: Text(
                            displayName,
                            key: const Key('profile_patient_display_name'),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textDark,
                              letterSpacing: -0.3,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Role Badge: Patient (Centered for balanced header alignment)
                      Align(
                        alignment: Alignment.center,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.gsRed.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppTheme.gsRed.withValues(alpha: 0.22),
                            ),
                          ),
                          child: const Text(
                            'Patient',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.gsRed,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Registered Mobile Number with Phone Icon
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.call_outlined,
                            size: 16,
                            color: Color(0xFF64748B),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              displayPhone,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF475569),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // City / Location with Location Icon
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 16,
                            color: Color(0xFF64748B),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              displayCity,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF475569),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Edit Profile Button
                      InkWell(
                        key: const Key('edit_profile_button'),
                        onTap: () => _showEditPatientProfileSheet(context),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.gsNavy.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppTheme.gsNavy.withValues(alpha: 0.16),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.edit_outlined,
                                size: 17,
                                color: AppTheme.gsNavy,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Edit profile',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.gsNavy,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // 3. Preferred Languages Card
                Container(
                  key: const Key('preferred_languages_card'),
                  padding: const EdgeInsets.all(20),
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
                      const Text(
                        'PREFERRED LANGUAGES',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 10,
                        children: _profileLanguageOptions.map((lang) {
                          final isSelected = selectedLanguages.any(
                            (l) =>
                                l.trim().toLowerCase() ==
                                lang.trim().toLowerCase(),
                          );
                          return InkWell(
                            key: Key('profile_lang_chip_$lang'),
                            onTap: () => _togglePreferredLanguage(lang),
                            borderRadius: BorderRadius.circular(24),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 9,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppTheme.gsNavy
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: isSelected
                                      ? AppTheme.gsNavy
                                      : const Color(0xFFCBD5E1),
                                  width: 1.2,
                                ),
                              ),
                              child: Text(
                                lang,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  color: isSelected
                                      ? Colors.white
                                      : AppTheme.textDark,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'AI triage replies in your preferred language, and healthcare professionals who speak it are easy to find.',
                        style: TextStyle(
                          fontSize: 13.5,
                          color: Color(0xFF64748B),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // 4. Referrals Section Card
                Container(
                  key: const Key('profile_referrals_card'),
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
                    children: [
                      InkWell(
                        key: const Key('profile_referrals_row'),
                        onTap: () {
                          _guardServiceAccess(
                            context,
                            serviceTitle: 'My Referrals',
                            onAllowed: () => ReferredPatientsSheet.show(context),
                          );
                        },
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 18,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.medical_services_outlined,
                                color: AppTheme.gsNavy,
                                size: 22,
                              ),
                              SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  'Referrals',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textDark,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: Color(0xFF64748B),
                                size: 24,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Divider(
                        height: 1,
                        thickness: 1,
                        indent: 20,
                        endIndent: 20,
                        color: Color(0xFFF1F5F9),
                      ),
                      InkWell(
                        key: const Key('profile_refer_friend_row'),
                        onTap: () {
                          _guardServiceAccess(
                            context,
                            serviceTitle: 'Refer a Friend',
                            onAllowed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const ReferAFriendScreen(),
                                ),
                              );
                            },
                          );
                        },
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(24),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 18,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.person_add_alt_1_outlined,
                                color: AppTheme.gsNavy,
                                size: 22,
                              ),
                              SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  'Refer a friend',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textDark,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: Color(0xFF64748B),
                                size: 24,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // 5. Need Help Card
                InkWell(
                  key: const Key('profile_need_help_card'),
                  onTap: () => _showProfileHelplineDialog(context),
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    padding: const EdgeInsets.all(20),
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
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'NEED HELP?',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Call our 24/7 clinical care helpline for medical emergencies, appointments and consultations.',
                          style: TextStyle(
                            fontSize: 15,
                            color: Color(0xFF475569),
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 6. Log Out Button
                InkWell(
                  key: const Key('profile_logout_button'),
                  onTap: () => _confirmAndLogoutPatient(context),
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x14FE3434),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: AppTheme.gsRed.withValues(alpha: 0.25),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.logout_rounded,
                          color: Color(0xFFFE3434),
                          size: 20,
                        ),
                        SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            'Log out',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFFE3434),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // 7. Terms of Use Button
                _buildProfileActionCardButton(
                  key: const Key('profile_terms_button'),
                  icon: Icons.description_outlined,
                  label: 'Terms of Use',
                  onTap: () => _showProfileTermsDialog(context),
                ),
                const SizedBox(height: 12),

                // 8. Privacy Policy Button
                _buildProfileActionCardButton(
                  key: const Key('profile_privacy_button'),
                  icon: Icons.verified_user_outlined,
                  label: 'Privacy Policy',
                  onTap: () => _showProfilePrivacyDialog(context),
                ),
                const SizedBox(height: 12),

                // 9. Delete My Account Button
                _buildProfileActionCardButton(
                  key: const Key('profile_delete_account_button'),
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete my account',
                  onTap: () => _confirmAndDeletePatientAccount(context),
                ),
                const SizedBox(height: 28),

                // 10. Centered GS HEALTH Logo
                const Center(
                  child: GsHealthLogo(
                    key: Key('profile_bottom_gs_health_logo'),
                    height: 38,
                    alignment: Alignment.center,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileActionCardButton({
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppTheme.textDark, size: 20),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textDark,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditPatientProfileSheet(BuildContext context) {
    final patient = _patientService.currentPatient;
    final nameCtrl = TextEditingController(
      text: patient.name.trim() == 'Patient' ? '' : patient.name.trim(),
    );
    final phoneCtrl = TextEditingController(text: patient.phone.trim());
    final emailCtrl = TextEditingController(text: patient.email.trim());
    final cityCtrl = TextEditingController(text: patient.city.trim());
    final pincodeCtrl = TextEditingController(text: patient.pincode.trim());
    final ageCtrl = TextEditingController(text: _resolvePatientAge(patient));
    final emergencyCtrl = TextEditingController(
      text: patient.emergencyContact.trim(),
    );
    String selectedGender = patient.hasValidGender ? patient.gender.trim() : '';
    String selectedBloodGroup = _resolvePatientBloodGroup(patient);
    String? errorMsg;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.88,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: const EdgeInsets.all(20),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.gsNavy.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.person_outline_rounded,
                              color: AppTheme.gsNavy,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Edit Profile',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textDark,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(sheetCtx).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const Divider(height: 24, color: Color(0xFFE2E8F0)),
                      if (errorMsg != null) ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: const Color(0x14FE3434),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0x40FE3434)),
                          ),
                          child: Text(
                            errorMsg!,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFFE3434),
                            ),
                          ),
                        ),
                      ],
                      TextField(
                        key: const Key('edit_profile_name_field'),
                        controller: nameCtrl,
                        decoration: InputDecoration(
                          labelText: 'Full Name *',
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('edit_profile_phone_field'),
                        controller: phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: 'Mobile Number *',
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('edit_profile_city_field'),
                        controller: cityCtrl,
                        decoration: InputDecoration(
                          labelText: 'City / Location',
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: const Key('edit_profile_pincode_field'),
                              controller: pincodeCtrl,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Pincode',
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              key: const Key('edit_profile_age_field'),
                              controller: ageCtrl,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Age',
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('edit_profile_email_field'),
                        controller: emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: 'Email Address',
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      ElevatedButton(
                        key: const Key('save_profile_changes_button'),
                        onPressed: () {
                          final newName = nameCtrl.text.trim();
                          final newPhone = phoneCtrl.text.trim();
                          if (newName.isEmpty) {
                            setModalState(() {
                              errorMsg = 'Please enter your full name.';
                            });
                            return;
                          }
                          _patientService.updatePatientProfile(
                            id: patient.id,
                            name: newName,
                            email: emailCtrl.text.trim().isNotEmpty
                                ? emailCtrl.text.trim()
                                : patient.email,
                            phone: newPhone.isNotEmpty ? newPhone : patient.phone,
                            age: ageCtrl.text.trim(),
                            gender: selectedGender,
                            bloodGroup: selectedBloodGroup,
                            emergencyContact: emergencyCtrl.text.trim().isNotEmpty
                                ? emergencyCtrl.text.trim()
                                : newPhone,
                            address: patient.address,
                            city: cityCtrl.text.trim(),
                            pincode: pincodeCtrl.text.trim(),
                            state: patient.state,
                            languages: patient.languages,
                            photoBytes: patient.photoBytes,
                          );
                          Navigator.of(sheetCtx).pop();
                          if (mounted) {
                            setState(() {});
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Profile updated successfully.'),
                                backgroundColor: AppTheme.gsNavy,
                              ),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.gsNavy,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Save profile',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
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

  void _showProfileHelplineDialog(BuildContext context) {
    const helpCard = NeedHelpCard();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.support_agent_rounded, color: AppTheme.gsNavy, size: 24),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'GS HEALTH 24/7 Helpline',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Call our 24/7 clinical care helpline for medical emergencies, appointments and consultations:',
              style: TextStyle(fontSize: 13.5, color: Color(0xFF475569)),
            ),
            const SizedBox(height: 12),
            SelectableText(
              helpCard.displayHelplineNumber,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.gsNavy,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text(
              'Close',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ElevatedButton.icon(
            key: const Key('call_helpline_confirm_button'),
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              final uri = Uri(scheme: 'tel', path: helpCard.helplineNumber);
              try {
                await launchUrl(uri);
              } catch (_) {}
            },
            icon: const Icon(Icons.call_rounded, size: 16),
            label: const Text('Call Now'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.gsNavy,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndLogoutPatient(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Log out?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppTheme.textDark,
          ),
        ),
        content: const Text(
          'Are you sure you want to log out of your GS HEALTH account?',
          style: TextStyle(fontSize: 14, color: Color(0xFF475569), height: 1.4),
        ),
        actions: [
          TextButton(
            key: const Key('cancel_logout_dialog_button'),
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppTheme.gsNavy,
              ),
            ),
          ),
          ElevatedButton(
            key: const Key('confirm_logout_dialog_button'),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.gsRed,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Log out',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await SessionService().clearSession();
    if (!mounted || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Logged out of Patient Account.'),
        duration: Duration(seconds: 2),
      ),
    );
    try {
      context.go('/login');
    } catch (_) {}
  }

  void _showProfileTermsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Terms of Use',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: AppTheme.gsNavy,
          ),
        ),
        content: const SingleChildScrollView(
          child: Text(
            'Welcome to GS HEALTH.\n\n'
            '1. Acceptance of Terms: By signing in and using our healthcare platform, you agree to comply with these Terms of Use.\n\n'
            '2. Medical Disclaimer: AI triage provides preliminary guidance only and does not replace an in-person clinical evaluation by a licensed doctor or specialist.\n\n'
            '3. Appointments & Records: Patients are responsible for providing accurate health history and arriving on time for scheduled consultations.',
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: Color(0xFF334155),
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('close_terms_dialog_button'),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Close',
              style: TextStyle(
                color: AppTheme.gsNavy,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showProfilePrivacyDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Privacy Policy',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: AppTheme.gsNavy,
          ),
        ),
        content: const SingleChildScrollView(
          child: Text(
            'GS HEALTH Privacy Policy\n\n'
            '1. Data Protection: Your mobile number, clinical records, prescriptions, scans, and consultation history are encrypted and stored securely.\n\n'
            '2. Authentication: We use your mobile number solely to send one-time verification codes (OTP) and appointment updates.\n\n'
            '3. Record Sharing: Your medical records are only shared with verified doctors and clinics you explicitly consult or authorize.',
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: Color(0xFF334155),
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('close_privacy_dialog_button'),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Close',
              style: TextStyle(
                color: AppTheme.gsNavy,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndDeletePatientAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Delete my account?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppTheme.textDark,
          ),
        ),
        content: const Text(
          'Are you sure you want to permanently delete your GS HEALTH account and associated profile data? This action cannot be undone.',
          style: TextStyle(fontSize: 14, color: Color(0xFF475569), height: 1.4),
        ),
        actions: [
          TextButton(
            key: const Key('cancel_delete_account_button'),
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppTheme.gsNavy,
              ),
            ),
          ),
          ElevatedButton(
            key: const Key('confirm_delete_account_button'),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.gsRed,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Delete account',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await _patientService.deleteCurrentPatientAccount();
    await SessionService().clearSession();
    if (!mounted || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Your account has been deleted.'),
        backgroundColor: AppTheme.gsNavy,
      ),
    );
    try {
      context.go('/login');
    } catch (_) {}
  }
}

// Custom Stateful Animated Action Card
class _AnimatedPatientActionTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  const _AnimatedPatientActionTile({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });

  @override
  State<_AnimatedPatientActionTile> createState() => _AnimatedPatientActionTileState();
}

class _AnimatedPatientActionTileState extends State<_AnimatedPatientActionTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isHovered = true),
        onTapUp: (_) {
          setState(() => _isHovered = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          height: 92,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: _isHovered ? widget.color.withValues(alpha: 0.04) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isHovered ? widget.color : const Color(0xFFE2E8F0),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: _isHovered ? widget.color.withValues(alpha: 0.18) : Colors.black.withValues(alpha: 0.03),
                blurRadius: _isHovered ? 12 : 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: _isHovered ? 0.22 : 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(widget.icon, color: widget.color, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                    color: _isHovered ? widget.color : AppTheme.textDark,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
