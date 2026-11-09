import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/denta_guru_logo.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/session_service.dart';
import '../../../../core/utils/record_file_helper.dart';
import '../../../../core/widgets/dental_ads_banner.dart';
import '../../../../core/widgets/whatsapp_chat_modal.dart';
import '../widgets/refer_patient_flow_dialog.dart';
import '../widgets/referred_patients_sheet.dart';
import '../widgets/book_visit_flow_dialog.dart';
import '../widgets/appointment_management_dialog.dart';
import '../../../../core/widgets/need_help_card.dart';
import 'find_doctors_screen.dart';

class PatientDashboardScreen extends StatefulWidget {
  const PatientDashboardScreen({super.key});

  @override
  State<PatientDashboardScreen> createState() => _PatientDashboardScreenState();
}

class _PatientDashboardScreenState extends State<PatientDashboardScreen> with TickerProviderStateMixin {
  int _currentIndex = 0;
  final PatientProblemService _patientService = PatientProblemService();

  late AnimationController _entryController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _pulseScaleAnimation;

  @override
  void initState() {
    super.initState();
    _patientService.addListener(_onServiceUpdate);
    _patientService.syncAllDataFromApi();

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
    if (mounted) setState(() {});
  }

  User? get _safeAuthUser {
    try {
      return Supabase.instance.client.auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  String _formatPatientName(String name) {
    if (name.isEmpty) return 'Patient';
    if (name.contains('.')) {
      return name
          .split('.')
          .map((s) => s.isNotEmpty ? '${s[0].toUpperCase()}${s.substring(1)}' : '')
          .join(' ');
    }
    return name[0].toUpperCase() + name.substring(1);
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

  void _openBookVisitFlow(BuildContext context, {DoctorModel? preselectedDoctor}) {
    BookVisitFlowDialog.show(
      context,
      preselectedDoctor: preselectedDoctor,
      onBookingSuccess: () {
        setState(() {
          _currentIndex = 1; // Switch/stay on Appointments tab
        });
      },
    );
  }

  void _showReportProblemDialog(BuildContext context, {DoctorModel? preselectedDoctor}) {
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
                                      : 'Explore doctors and connect with a specialized dentist.',
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
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
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
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E40AF)),
                                    ),
                                    Text(
                                      '${preselectedDoctor.specialty} • ${preselectedDoctor.city.isNotEmpty ? preselectedDoctor.city : "Verified"}',
                                      style: const TextStyle(fontSize: 10.5, color: Color(0xFF3B82F6)),
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
                        value: selectedCategory,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Dental Issue Category',
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
                                            ? const Color(0xFFFEE2E2)
                                            : sev == 'Moderate'
                                                ? const Color(0xFFFFEDD5)
                                                : const Color(0xFFDBEAFE))
                                        : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: selectedSeverity == sev
                                          ? (sev == 'Severe'
                                              ? const Color(0xFFEF4444)
                                              : sev == 'Moderate'
                                                  ? const Color(0xFFF97316)
                                                  : const Color(0xFF3B82F6))
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
                                                ? const Color(0xFFEF4444)
                                                : sev == 'Moderate'
                                                    ? const Color(0xFFF97316)
                                                    : const Color(0xFF3B82F6))
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
                                                  ? const Color(0xFF991B1B)
                                                  : sev == 'Moderate'
                                                      ? const Color(0xFF9A3412)
                                                      : const Color(0xFF1E40AF))
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
                                              : '✅ Dental problem submitted! Admin will recommend a specialist shortly.',
                                        ),
                                        backgroundColor: const Color(0xFF10B981),
                                        duration: const Duration(seconds: 3),
                                      ),
                                    );
                                  }
                                } catch (err) {
                                  setModalState(() => isSubmitting = false);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Error submitting problem: $err'), backgroundColor: Colors.red),
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
    final docId = doctor?.id ?? assignedReq.assignedDoctorId;
    final pName = patient.name.isNotEmpty ? patient.name : (assignedReq.patientName.isNotEmpty ? assignedReq.patientName : 'anusha');

    WhatsAppChatModal.show(
      context,
      patientName: pName,
      doctorName: docName,
      currentUserRole: 'Patient',
      patientId: patient.id.isNotEmpty ? patient.id : null,
      doctorId: docId,
    );
  }

  void _showNotificationsModal(BuildContext context, String role) {
    final patient = _patientService.currentPatient;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        final notifs = _patientService.appNotifications
            .where((n) => n.recipientRole == role || n.recipientId == patient.name || n.recipientId == patient.id)
            .toList();

        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440, maxHeight: 520),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.notifications_active_rounded, color: AppTheme.primaryBlue, size: 22),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Patient Notifications',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(dialogCtx).pop()),
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
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(n.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryBlue)),
                              const SizedBox(height: 2),
                              Text(n.message, style: const TextStyle(fontSize: 11, color: AppTheme.textDark)),
                              const SizedBox(height: 4),
                              Text(
                                '${n.timestamp.hour}:${n.timestamp.minute.toString().padLeft(2, '0')}',
                                style: const TextStyle(fontSize: 9, color: Colors.grey),
                              ),
                            ],
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
  }

  @override
  Widget build(BuildContext context) {
    final patient = _patientService.currentPatient;

    return Scaffold(
      backgroundColor: AppTheme.softBlueBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.05),
        automaticallyImplyLeading: false,
        titleSpacing: 10,
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: DentaGuruLogo(height: 32),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                Builder(
                  builder: (context) {
                    final patientNotifs = _patientService.appNotifications
                        .where((n) => n.recipientRole == 'Patient' || n.recipientId == patient.name || n.recipientId == patient.id)
                        .toList();
                    final unreadCount = patientNotifs.where((n) => !n.isRead).length;

                    return Stack(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.notifications_none_rounded, color: AppTheme.textDark, size: 24),
                          onPressed: () => _showNotificationsModal(context, 'Patient'),
                        ),
                        if (unreadCount > 0)
                          Positioned(
                            right: 6,
                            top: 6,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle),
                              child: Text(
                                '$unreadCount',
                                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(width: 4),
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.primaryBlue, width: 2),
                  ),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.1),
                    backgroundImage: patient.photoBytes != null ? MemoryImage(patient.photoBytes!) : null,
                    child: patient.photoBytes == null
                        ? Text(
                            patient.name.isNotEmpty ? patient.name[0].toUpperCase() : 'P',
                            style: const TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold, fontSize: 13),
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: _buildCurrentTab(),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
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
          selectedItemColor: AppTheme.primaryBlue,
          unselectedItemColor: AppTheme.textMuted,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
          onTap: (index) => setState(() => _currentIndex = index),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home_rounded, color: AppTheme.primaryBlue),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.calendar_today_outlined),
              activeIcon: Icon(Icons.calendar_month_rounded, color: AppTheme.primaryBlue),
              label: 'Appointments',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.folder_outlined),
              activeIcon: Icon(Icons.folder_rounded, color: AppTheme.primaryBlue),
              label: 'Records',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline_rounded),
              activeIcon: Icon(Icons.person_rounded, color: AppTheme.primaryBlue),
              label: 'Profile',
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
        return _buildAppointmentsTab();
      case 2:
        return _buildRecordsTab();
      case 3:
        return _buildProfileTab();
      default:
        return _buildHomeTab();
    }
  }

  // ==========================================
  // TAB 1: HOME TAB (ANIMATED & GOOD LOOKING)
  // ==========================================
  Widget _buildHomeTab() {
    final patient = _patientService.currentPatient;
    final requests = _patientService.requests;
    final formattedName = _formatPatientName(patient.name);

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Patient Greeting & Vitals Header
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hello, $formattedName 👋',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '🩸 ${_resolvePatientBloodGroup(patient)}',
                                style: const TextStyle(fontSize: 11, color: AppTheme.primaryBlue, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '🎂 ${_resolvePatientAge(patient).isNotEmpty ? _resolvePatientAge(patient) : "N/A"} Yrs',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF10B981), fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.primaryBlue, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryBlue.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 26,
                      backgroundColor: AppTheme.softBlueCard,
                      backgroundImage: patient.photoBytes != null ? MemoryImage(patient.photoBytes!) : null,
                      child: patient.photoBytes == null
                          ? Text(
                              patient.name.isNotEmpty ? patient.name[0].toUpperCase() : 'P',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.primaryBlue),
                            )
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 2. Main Hero Problem Banner with Pulsing Icon
              InkWell(
                onTap: () => _showReportProblemDialog(context),
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0284C7), Color(0xFF0052CC)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.3),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      ScaleTransition(
                        scale: _pulseScaleAnimation,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 26),
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Connect to a Doctor',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Explore doctors and connect with a specialized dentist.',
                              style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.3),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 16),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 3. Animated Quick Action Cards
              const Text(
                'Quick Care Services',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark),
              ),
              const SizedBox(height: 10),

              LayoutBuilder(
                builder: (context, constraints) {
                  final myCreatedRefs = _patientService.myCreatedPatientReferrals;
                  final receivedForMeRefs = _patientService.receivedForMePatientReferrals;
                  final totalRefsCount = myCreatedRefs.length + receivedForMeRefs.length;

                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        SizedBox(
                          width: (constraints.maxWidth > 600) ? (constraints.maxWidth - 32) / 5 : 85,
                          child: _AnimatedPatientActionTile(
                            icon: Icons.calendar_month_rounded,
                            title: 'Appointments',
                            color: AppTheme.primaryBlue,
                            onTap: () => setState(() => _currentIndex = 1),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: (constraints.maxWidth > 600) ? (constraints.maxWidth - 32) / 5 : 85,
                          child: _AnimatedPatientActionTile(
                            icon: Icons.person_search_rounded,
                            title: 'Find Doctors',
                            color: const Color(0xFF0284C7),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const FindDoctorsScreen(),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: (constraints.maxWidth > 600) ? (constraints.maxWidth - 32) / 5 : 85,
                          child: _AnimatedPatientActionTile(
                            icon: Icons.person_add_alt_1_rounded,
                            title: 'Refer a Patient',
                            color: const Color(0xFF0D9488),
                            onTap: () => ReferPatientFlowDialog.show(context),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: (constraints.maxWidth > 600) ? (constraints.maxWidth - 32) / 5 : 85,
                          child: _AnimatedPatientActionTile(
                            icon: Icons.groups_rounded,
                            title: 'Referred Patients',
                            color: const Color(0xFF6366F1),
                            badgeCount: totalRefsCount,
                            onTap: () => ReferredPatientsSheet.show(context),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: (constraints.maxWidth > 600) ? (constraints.maxWidth - 32) / 5 : 85,
                          child: _AnimatedPatientActionTile(
                            icon: Icons.receipt_long_rounded,
                            title: 'Prescriptions',
                            color: const Color(0xFF10B981),
                            onTap: () => setState(() => _currentIndex = 2),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),

              // ── REMAINING PRODUCTS ADS SECTION (Auto-rotating one by one above problems) ──
              const DentalAdsBanner(isDentist: false, remainingSlidesOnly: true),
              const SizedBox(height: 18),

              // ── 24/7 SUPPORT & ASSISTANCE (Call Us Now & Chat on WhatsApp) ──
              const NeedHelpCard(),
              const SizedBox(height: 24),

              // 4. Section: Reported Problems & Doctor Suggestions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Reported Problems & Doctor Suggestions',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Builder(
                builder: (context) {
                  final rawFiltered = requests.where((req) {
                    final authUser = _safeAuthUser;
                    final authId = authUser?.id ?? '';
                    final authEmail = authUser?.email?.trim().toLowerCase() ?? '';

                    final reqNameLower = req.patientName.trim().toLowerCase();
                    final patientNameLower = patient.name.trim().toLowerCase();
                    final patientEmailLower = patient.email.trim().toLowerCase();

                    // 1. Direct match by patient profile ID or authId
                    if (authId.isNotEmpty && (req.patientId == authId || req.id.contains(authId) || req.patientPhone.contains(authId))) return true;
                    if (patient.id.isNotEmpty && (req.patientId == patient.id || req.id.contains(patient.id) || req.patientPhone.contains(patient.id))) return true;

                    // 2. Direct match by email
                    if (authEmail.isNotEmpty && (reqNameLower.contains(authEmail.split('@').first) || authEmail.contains(reqNameLower))) return true;
                    if (patientEmailLower.isNotEmpty && (reqNameLower.contains(patientEmailLower.split('@').first) || patientEmailLower.contains(reqNameLower))) return true;

                    // 3. Direct match by patient profile name
                    if (patientNameLower.isNotEmpty && patientNameLower != 'patient') {
                      if (reqNameLower == patientNameLower) return true;
                      if (reqNameLower.contains(patientNameLower) || patientNameLower.contains(reqNameLower)) return true;
                    }

                    // 4. Direct match by phone number
                    if (patient.phone.isNotEmpty && req.patientPhone.trim().isNotEmpty && req.patientPhone.trim() == patient.phone.trim()) return true;

                    // ❌ NO MATCH: Return false so another patient's data NEVER displays!
                    return false;
                  }).toList();

                  // Deduplicate requests by ID or category to prevent duplicate cards
                  final uniqueMap = <String, PatientConsultationRequest>{};
                  for (final req in rawFiltered) {
                    final key = req.id.isNotEmpty ? req.id : '${req.patientName}_${req.problemCategory}';
                    if (!uniqueMap.containsKey(key)) {
                      uniqueMap[key] = req;
                    } else {
                      if (req.status == 'Confirmed' || req.status == 'DENTIST_ACCEPTED' || (req.assignedDoctorName != null && req.assignedDoctorName!.isNotEmpty && req.assignedDoctorName != 'null')) {
                        uniqueMap[key] = req;
                      }
                    }
                  }
                  final myPatientRequests = uniqueMap.values.toList();
                  myPatientRequests.sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
                  final displayRequests = myPatientRequests.take(1).toList();

                  if (displayRequests.isEmpty) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFEEF2F6)),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.check_circle_outline_rounded, color: Color(0xFF10B981), size: 36),
                          SizedBox(height: 8),
                          Text(
                            'No Pending Dental Problems',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Tap the top banner whenever you experience dental pain or need a specialist.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                          ),
                        ],
                      ),
                    );
                  }

                  return Column(
                    children: displayRequests.map((req) {
                      final String rawSt = req.status.toUpperCase().trim();
                      final bool isConfirmed = rawSt == 'CONFIRMED' ||
                        rawSt == 'ACCEPTED' ||
                        rawSt == 'DENTIST_ACCEPTED' ||
                        rawSt == 'COMPLETED' ||
                        (req.confirmedTimeSlot != null && req.confirmedTimeSlot!.isNotEmpty);

                      final bool isDoctorAssigned = isConfirmed ||
                        ((rawSt == 'DENTIST_ASSIGNED' || rawSt == 'DENTIST_SUGGESTED' || rawSt == 'DOCTOR ASSIGNED' || rawSt == 'DOCTOR SUGGESTED') &&
                         req.assignedDoctorName != null &&
                         req.assignedDoctorName!.trim().isNotEmpty &&
                         req.assignedDoctorName != 'null' &&
                         req.assignedDoctorName != 'None');

                      final bool isAdminReviewed = isDoctorAssigned ||
                        (rawSt == 'ADMIN_REVIEWED' ||
                         rawSt == 'ADMIN REVIEW' ||
                         rawSt == 'ADMIN_REVIEW' ||
                         rawSt == 'UNDER_REVIEW');

                    return Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isConfirmed
                              ? const Color(0xFF10B981)
                              : (isDoctorAssigned ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1)),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (isConfirmed ? const Color(0xFF10B981) : const Color(0xFF0284C7)).withValues(alpha: 0.08),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header Row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  req.problemCategory,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isConfirmed
                                      ? const Color(0xFFDCFCE7)
                                      : (isDoctorAssigned
                                          ? const Color(0xFFE0F2FE)
                                          : (isAdminReviewed ? const Color(0xFFFEF3C7) : const Color(0xFFF1F5F9))),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  isConfirmed
                                      ? '🟢 Confirmed & Scheduled'
                                      : (isDoctorAssigned
                                          ? '🔵 Doctor Assigned'
                                          : (isAdminReviewed ? '🟡 Admin Reviewed' : '⏳ Pending Admin Review')),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: isConfirmed
                                        ? const Color(0xFF15803D)
                                        : (isDoctorAssigned
                                            ? const Color(0xFF0369A1)
                                            : (isAdminReviewed ? const Color(0xFFB45309) : const Color(0xFF64748B))),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            req.problemDescription,
                            style: const TextStyle(fontSize: 12, color: AppTheme.textMedium, height: 1.35),
                          ),
                          const SizedBox(height: 12),

                          // 4-Step Progress Tracker for Patient
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  _buildProgressStep(title: 'Submitted', isDone: true),
                                  _buildProgressLine(isDone: isAdminReviewed),
                                  _buildProgressStep(title: 'Admin Review', isDone: isAdminReviewed),
                                  _buildProgressLine(isDone: isDoctorAssigned),
                                  _buildProgressStep(title: 'Doctor Assigned', isDone: isDoctorAssigned),
                                  _buildProgressLine(isDone: isConfirmed),
                                  _buildProgressStep(title: 'Confirmed', isDone: isConfirmed),
                                ],
                              ),
                            ),
                          ),

                          if (isDoctorAssigned) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isConfirmed ? const Color(0xFFF0FDF4) : const Color(0xFFF0F9FF),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isConfirmed ? const Color(0xFF86EFAC) : const Color(0xFFBAE6FD),
                                  width: 1.5,
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
                                          color: isConfirmed ? const Color(0xFFDCFCE7) : const Color(0xFFE0F2FE),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          isConfirmed ? Icons.verified_rounded : Icons.person_search_rounded,
                                          color: isConfirmed ? const Color(0xFF16A34A) : const Color(0xFF0284C7),
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              isConfirmed ? '🎉 Consultation Confirmed & Scheduled' : '👨‍⚕️ Assigned Specialist',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                                color: isConfirmed ? const Color(0xFF14532D) : const Color(0xFF0369A1),
                                              ),
                                            ),
                                            Text(
                                              '${req.displayDoctorName} (${req.displayDoctorSpecialty})',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: isConfirmed ? const Color(0xFF15803D) : AppTheme.textDark,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '🏥 Clinic: ${req.displayDoctorClinic} • 💰 Estimated Fee (${req.problemCategory}): ₹500',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isConfirmed ? const Color(0xFF166534) : const Color(0xFF0369A1),
                                    ),
                                  ),
                                  if (req.confirmedTimeSlot != null && req.confirmedTimeSlot!.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFDCFCE7),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: const Color(0xFF86EFAC)),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.access_time_filled_rounded, size: 15, color: Color(0xFF15803D)),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              'Confirmed Time Slot: ${req.confirmedTimeSlot}',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF15803D)),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ] else ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      '⏳ Waiting for doctor to accept referral and set time slot.',
                                      style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: AppTheme.textMuted),
                                    ),
                                  ],
                                  if (req.adminNotes != null && req.adminNotes!.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: const Color(0xFFBBF7D0)),
                                      ),
                                      child: Text(
                                        'Admin Note: "${req.adminNotes}"',
                                        style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Color(0xFF14532D)),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.calendar_month_rounded, size: 16),
                                    label: Text('Book Consultation with ${req.displayDoctorName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF16A34A),
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size.fromHeight(42),
                                      elevation: 1,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    onPressed: () {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('📅 Appointment booking request sent for ${req.displayDoctorName}!'),
                                          backgroundColor: const Color(0xFF16A34A),
                                          duration: const Duration(seconds: 3),
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.chat_rounded, size: 16),
                                    label: Text('Chat with ${req.displayDoctorName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF0369A1),
                                      side: const BorderSide(color: Color(0xFF0284C7)),
                                      minimumSize: const Size.fromHeight(42),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    onPressed: () {
                                      _showChatModal(context, request: req);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ] else ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFBEB),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFFDE68A), width: 1.5),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFFEF3C7),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.hourglass_top_rounded,
                                      color: Color(0xFFD97706),
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          (req.preferredDoctorName != null && req.preferredDoctorName!.isNotEmpty)
                                              ? 'Referred Doctor: ${req.preferredDoctorName}'
                                              : 'Pending Clinical Triage & Assignment',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: Color(0xFF92400E),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          (req.preferredDoctorName != null && req.preferredDoctorName!.isNotEmpty)
                                              ? 'Your referral recommendation has been submitted. GS HEALTH Admin is currently reviewing and verifying the specialist dispatch.'
                                              : 'Your consultation request has been received. GS HEALTH Admin is matching the best specialist for your care.',
                                          style: const TextStyle(fontSize: 11, color: Color(0xFFB45309), height: 1.35),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                  );
                },
              ),
              const SizedBox(height: 16),

              // 5. Next Visit Card
              _buildNextVisitCard(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressStep({required String title, required bool isDone}) {
    return Row(
      children: [
        Icon(
          isDone ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
          size: 14,
          color: isDone ? const Color(0xFF16A34A) : AppTheme.textMuted,
        ),
        const SizedBox(width: 4),
        Text(
          isDone ? '$title ✓' : title,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isDone ? FontWeight.bold : FontWeight.normal,
            color: isDone ? const Color(0xFF14532D) : AppTheme.textMuted,
          ),
        ),
      ],
    );
  }
  Widget _buildProgressLine({required bool isDone}) {
    return Container(
      width: 14,
      height: 2,
      color: isDone ? const Color(0xFF16A34A) : const Color(0xFFCBD5E1),
    );
  }

  Widget _buildNextVisitCard() {
    final requests = _patientService.requests;
    final patient = _patientService.currentPatient;
    final authUser = _safeAuthUser;
    final authId = authUser?.id ?? '';
    final authEmail = authUser?.email?.trim().toLowerCase() ?? '';

    final myRequests = requests.where((r) {
      if (r.patientId != null && r.patientId!.isNotEmpty) {
        if (r.patientId == authId || r.patientId == patient.id) return true;
      }
      if (patient.name.isNotEmpty && patient.name != 'Patient' && r.patientName.trim().toLowerCase() == patient.name.trim().toLowerCase()) return true;
      if (patient.name.isNotEmpty && patient.name != 'Patient' && (r.patientName.toLowerCase().contains(patient.name.toLowerCase()) || patient.name.toLowerCase().contains(r.patientName.toLowerCase()))) return true;
      if (patient.id.isNotEmpty && r.id.contains(patient.id)) return true;
      if (authEmail.isNotEmpty && r.patientName.toLowerCase().contains(authEmail.split('@').first)) return true;
      if (patient.name.isEmpty || patient.name == 'Patient' || requests.length <= 1) return true;
      return false;
    }).toList();

    final upcomingRequests = myRequests.where((r) {
      final s = r.status.toUpperCase();
      if (s == 'COMPLETED' || s == 'CANCELLED' || s == 'REJECTED') return false;
      final hasDocName = r.assignedDoctorName != null &&
          r.assignedDoctorName!.isNotEmpty &&
          r.assignedDoctorName != 'null' &&
          r.assignedDoctorName != 'None';
      final hasSlot = r.confirmedTimeSlot != null && r.confirmedTimeSlot!.isNotEmpty;
      return hasDocName || hasSlot || s.contains('ASSIGN') || s.contains('CONFIRM') || s.contains('PENDING') || s.contains('RESCHEDULE') || s.contains('ACCEPT');
    }).toList();

    if (upcomingRequests.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Column(
          children: [
            Icon(Icons.calendar_today_rounded, size: 32, color: AppTheme.primaryBlue),
            SizedBox(height: 8),
            Text('No Scheduled Visits', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark)),
            SizedBox(height: 2),
            Text('Submit a dental problem or report symptoms to schedule a visit.', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          ],
        ),
      );
    }

    return Column(
      children: [
        for (int i = 0; i < upcomingRequests.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _buildSingleScheduledVisitCard(upcomingRequests[i], isFirst: i == 0),
        ],
      ],
    );
  }

  Widget _buildSingleScheduledVisitCard(PatientConsultationRequest assignedReq, {required bool isFirst}) {
    final docName = assignedReq.assignedDoctorName ?? 'Attending Specialist';
    final clinicName = assignedReq.assignedDoctorClinic ?? '';
    final statusUpper = assignedReq.status.toUpperCase();
    final isConfirmed = statusUpper == 'CONFIRMED' || statusUpper == 'ACCEPTED' || statusUpper == 'DOCTOR SUGGESTED';
    final isRescheduled = statusUpper == 'RESCHEDULED';

    String dateStr = '';
    if (assignedReq.confirmedDate != null && assignedReq.confirmedDate!.isNotEmpty) {
      final dt = DateTime.tryParse(assignedReq.confirmedDate!);
      if (dt != null) {
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        dateStr = '${weekdays[dt.weekday - 1]}, ${dt.day} ${months[dt.month - 1]} • ';
      }
    }

    final slotDisplay = (assignedReq.confirmedTimeSlot != null && assignedReq.confirmedTimeSlot!.isNotEmpty)
        ? '$dateStr${assignedReq.confirmedTimeSlot!}'
        : 'Slot Pending Confirmation';

    return Container(
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isFirst ? 'Your Next Scheduled Visit' : 'Scheduled Visit',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            slotDisplay,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                assignedReq.problemCategory,
                                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                              ),
                              const SizedBox(width: 4),
                              const Text(
                                '• 💰 Fee: ₹500',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isConfirmed
                            ? AppTheme.statusConfirmedBg
                            : isRescheduled
                                ? const Color(0xFFDBEAFE)
                                : const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        isConfirmed
                            ? 'Confirmed'
                            : isRescheduled
                                ? 'Rescheduled'
                                : 'Pending',
                        style: TextStyle(
                          color: isConfirmed
                              ? AppTheme.statusConfirmedText
                              : isRescheduled
                                  ? const Color(0xFF1D4ED8)
                                  : const Color(0xFFD97706),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person_rounded, color: AppTheme.primaryBlue, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        docName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: AppTheme.textDark),
                      ),
                      if (clinicName.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          clinicName,
                          style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () {
                    AppointmentManagementDialog.show(
                      context,
                      appointment: assignedReq,
                      initialMode: AppointmentManagementMode.details,
                      onUpdated: () => setState(() {}),
                    );
                  },
                  icon: const Icon(Icons.info_outline_rounded, size: 15),
                  label: const Text('Details', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: () {
                    AppointmentManagementDialog.show(
                      context,
                      appointment: assignedReq,
                      initialMode: AppointmentManagementMode.reschedule,
                      onUpdated: () => setState(() {}),
                    );
                  },
                  icon: const Icon(Icons.edit_calendar_rounded, size: 15),
                  label: const Text('Reschedule', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: () {
                    AppointmentManagementDialog.show(
                      context,
                      appointment: assignedReq,
                      initialMode: AppointmentManagementMode.cancel,
                      onUpdated: () => setState(() {}),
                    );
                  },
                  icon: const Icon(Icons.cancel_outlined, size: 15, color: Color(0xFFDC2626)),
                  label: const Text('Cancel', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFDC2626))),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 2: APPOINTMENTS TAB
  // ==========================================
  Widget _buildAppointmentsTab() {
    final requests = _patientService.requests;
    final patient = _patientService.currentPatient;
    final authUser = _safeAuthUser;
    final authId = authUser?.id ?? '';
    final authEmail = authUser?.email?.trim().toLowerCase() ?? '';

    final myRequests = requests.where((r) {
      if (r.patientId != null && r.patientId!.isNotEmpty) {
        if (r.patientId == authId || r.patientId == patient.id) return true;
      }
      if (patient.name.isNotEmpty && patient.name != 'Patient' && r.patientName.trim().toLowerCase() == patient.name.trim().toLowerCase()) return true;
      if (patient.name.isNotEmpty && patient.name != 'Patient' && (r.patientName.toLowerCase().contains(patient.name.toLowerCase()) || patient.name.toLowerCase().contains(r.patientName.toLowerCase()))) return true;
      if (patient.id.isNotEmpty && r.id.contains(patient.id)) return true;
      if (authEmail.isNotEmpty && r.patientName.toLowerCase().contains(authEmail.split('@').first)) return true;
      if (patient.name.isEmpty || patient.name == 'Patient' || requests.length <= 1) return true;
      return false;
    }).toList();

    final pastRequests = myRequests.where((r) {
      final s = r.status.toUpperCase();
      return s == 'COMPLETED' || s == 'CANCELLED' || s == 'REJECTED';
    }).toList();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'My Appointments',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textDark),
          ),
          const SizedBox(height: 4),
          const Text('Track upcoming and past dental visits', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          const SizedBox(height: 14),

          // ── BOOK VISIT ACTION BUTTON ──────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _openBookVisitFlow(context),
              icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
              label: const Text(
                'Book Visit',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 16),

          _buildNextVisitCard(),
          const SizedBox(height: 16),

          const Text('Past Visit History', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
          const SizedBox(height: 10),
          if (pastRequests.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.history_rounded, color: AppTheme.textMuted, size: 22),
                  SizedBox(width: 12),
                  Text('No past dental visits recorded.', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                ],
              ),
            )
          else
            ...pastRequests.map((req) {
              final isCancelled = req.status.toUpperCase() == 'CANCELLED' || req.status.toUpperCase() == 'REJECTED';
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    AppointmentManagementDialog.show(
                      context,
                      appointment: req,
                      initialMode: AppointmentManagementMode.details,
                      onUpdated: () => setState(() {}),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          isCancelled ? Icons.cancel_outlined : Icons.history_rounded,
                          color: isCancelled ? const Color(0xFF94A3B8) : AppTheme.primaryBlue,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isCancelled ? 'Cancelled Visit' : 'Completed Visit',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${req.problemCategory}${req.assignedDoctorName != null ? " • ${req.assignedDoctorName}" : ""}',
                                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isCancelled ? const Color(0xFFF1F5F9) : const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            isCancelled ? 'Cancelled' : 'Completed',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: isCancelled ? const Color(0xFF64748B) : const Color(0xFF15803D),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 3: RECORDS TAB (DYNAMIC FROM BACKEND API & SUPABASE STORAGE)
  // ==========================================
  static const List<String> _recordCategories = [
    'Dental X-ray',
    'Prescription',
    'Dental Report',
    'Lab Report',
    'Treatment Documents',
    'Other',
  ];

  String _selectedRecordCategoryFilter = 'All';

  String _resolveActivePatientId() {
    if (_patientService.currentPatient.id.isNotEmpty) {
      return _patientService.currentPatient.id;
    }
    try {
      return Supabase.instance.client.auth.currentUser?.id ?? '';
    } catch (_) {
      return '';
    }
  }

  Widget _buildRecordsTab() {
    final activePatientId = _resolveActivePatientId();
    return FutureBuilder<List<dynamic>>(
      future: ApiService().fetchMedicalRecords(patientId: activePatientId.isNotEmpty ? activePatientId : null),
      builder: (context, snapshot) {
        final apiRecords = snapshot.data ?? [];
        final localRecords = _patientService.medicalRecords;

        final combinedMap = <String, Map<String, dynamic>>{};
        for (final item in [...localRecords, ...apiRecords]) {
          if (item is! Map) continue;
          final itemMap = Map<String, dynamic>.from(item);
          final recPatientId = (itemMap['patientId'] ?? itemMap['patient_id'] ?? '').toString();
          if (activePatientId.isNotEmpty &&
              recPatientId.isNotEmpty &&
              recPatientId != activePatientId) {
            continue;
          }
          final id = (itemMap['id'] ?? itemMap['title'] ?? UniqueKey().toString()).toString();
          combinedMap[id] = itemMap;
        }

        final allRecords = combinedMap.values.toList()
          ..sort((a, b) {
            final aDate = (a['uploadedAt'] ?? a['date'] ?? '').toString();
            final bDate = (b['uploadedAt'] ?? b['date'] ?? '').toString();
            return bDate.compareTo(aDate);
          });

        final records = _selectedRecordCategoryFilter == 'All'
            ? allRecords
            : allRecords.where((r) {
                final cat = (r['category'] ?? '').toString().toLowerCase();
                return cat == _selectedRecordCategoryFilter.toLowerCase();
              }).toList();

        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with + Add Record & Share buttons
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Dental Health Records',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textDark,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Secure digital prescriptions, X-rays & dental charts',
                          style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Padding(
                      padding: EdgeInsets.only(top: 8, right: 8),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.primaryBlue,
                        ),
                      ),
                    ),
                  ElevatedButton.icon(
                    key: const Key('add_dental_record_button'),
                    onPressed: () => _showUploadOrEditRecordSheet(context),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text(
                      '+ Add Record',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
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
              const SizedBox(height: 12),

              // Quick Action Bar when records exist (Share Multiple with Favourite Doctor + Category Filter)
              if (allRecords.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('share_multiple_records_button'),
                      onPressed: () => _showShareWithDoctorModal(
                        context,
                        allAvailableRecords: allRecords,
                      ),
                      icon: const Icon(Icons.share_rounded, size: 15, color: AppTheme.primaryBlue),
                      label: Text(
                        'Share with Favourite Doctor (${_patientService.myDoctors.length})',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryBlue,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppTheme.primaryBlue),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${allRecords.length} ${allRecords.length == 1 ? 'Record' : 'Records'} Stored Securely',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: ['All', ..._recordCategories].map((cat) {
                      final isSelected = _selectedRecordCategoryFilter == cat;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(
                            cat,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isSelected ? Colors.white : AppTheme.textDark,
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: AppTheme.primaryBlue,
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: isSelected ? AppTheme.primaryBlue : const Color(0xFFE2E8F0),
                            ),
                          ),
                          onSelected: (_) {
                            setState(() {
                              _selectedRecordCategoryFilter = cat;
                            });
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 14),
              ] else
                const SizedBox(height: 4),

              // Empty State or Records List
              if (records.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.folder_open_rounded,
                          size: 36,
                          color: AppTheme.primaryBlue,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        allRecords.isEmpty
                            ? 'No Digital Records Issued Yet'
                            : 'No $_selectedRecordCategoryFilter Records Found',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: AppTheme.textDark,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Upload your Dental X-rays, Prescriptions, Lab Reports, or Treatment Documents (JPG, JPEG, PNG, PDF) and securely share them with your Favourite Doctors.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        key: const Key('empty_state_add_record_button'),
                        onPressed: () => _showUploadOrEditRecordSheet(context),
                        icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                        label: const Text(
                          '+ Add Record',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ...records.map((rec) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildRecordCard(
                      record: rec,
                      allRecords: allRecords,
                    ),
                  );
                }),
            ],
          ),
        );
      },
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
      return const Color(0xFF8B5CF6);
    }
    if (c.contains('prescription')) {
      return const Color(0xFF10B981);
    }
    if (c.contains('lab')) {
      return const Color(0xFF0EA5E9);
    }
    if (c.contains('treatment')) {
      return AppTheme.brandOrange;
    }
    return AppTheme.primaryBlue;
  }

  Widget _buildRecordCard({
    required Map<String, dynamic> record,
    required List<Map<String, dynamic>> allRecords,
  }) {
    final recId = (record['id'] ?? '').toString();
    final type = (record['type'] ?? 'prescription').toString();
    final title = (record['title'] ?? 'Dental Record').toString();
    final category = (record['category'] ?? 'Dental Report').toString();
    final description = (record['description'] ?? '').toString().trim();
    final date = (record['date'] ?? '').toString();
    final fileType = (record['fileType'] ?? 'PDF').toString().toUpperCase();
    final fileSize = record['fileSize'] is int
        ? record['fileSize'] as int
        : int.tryParse((record['fileSize'] ?? '0').toString()) ?? 0;
    final isPatientUpload = record['isPatientUpload'] == true ||
        (record['storageKey'] ?? '').toString().isNotEmpty;

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
                                  ? const Color(0xFFFEE2E2)
                                  : const Color(0xFFE0F2FE),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              fileType,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: fileType == 'PDF'
                                    ? const Color(0xFFDC2626)
                                    : const Color(0xFF0284C7),
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
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.verified_user_rounded, size: 14, color: Color(0xFF16A34A)),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Shared with Favourite Doctor(s):',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF15803D),
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
                          border: Border.all(color: const Color(0xFF86EFAC)),
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
                                        color: Color(0xFFDC2626),
                                      ),
                                    ),
                                    SizedBox(width: 2),
                                    Icon(Icons.close_rounded, size: 13, color: Color(0xFFDC2626)),
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
                color: AppTheme.primaryBlue,
                onTap: () => _showRecordDetailModal(context, record),
              ),
              _buildRecordActionButton(
                icon: Icons.download_rounded,
                label: 'Download',
                color: const Color(0xFF0284C7),
                onTap: () => _handleDownloadRecord(context, record),
              ),
              _buildRecordActionButton(
                icon: Icons.share_rounded,
                label: 'Share with Doctor',
                color: const Color(0xFF10B981),
                onTap: () => _showShareWithDoctorModal(
                  context,
                  preselectedRecord: record,
                  allAvailableRecords: allRecords,
                ),
              ),
              if (isPatientUpload || recId.isNotEmpty)
                _buildRecordActionButton(
                  icon: Icons.edit_rounded,
                  label: 'Edit',
                  color: AppTheme.brandOrange,
                  onTap: () => _showUploadOrEditRecordSheet(
                    context,
                    existingRecord: record,
                  ),
                ),
              if (isPatientUpload || recId.isNotEmpty)
                _buildRecordActionButton(
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete',
                  color: const Color(0xFFDC2626),
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
        ? (existingRecord['category'] ?? 'Dental X-ray').toString()
        : 'Dental X-ray';
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
                            ? 'Dental record "$recordName" updated successfully.'
                            : 'Dental record "$recordName" uploaded securely.',
                      ),
                      backgroundColor: const Color(0xFF10B981),
                    ),
                  );
                }
              } else {
                setModalState(() {
                  isSubmitting = false;
                  errorMessage = (res['message'] ?? 'Failed to save dental record.').toString();
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
                                  isEdit ? 'Edit Dental Record' : 'Upload Dental Health Record',
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
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFECACA)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  errorMessage!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFB91C1C),
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
                                              ? const Color(0xFFDC2626)
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
                                          color: const Color(0xFFFEF2F2),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: const Color(0xFFFECACA)),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.picture_as_pdf_rounded,
                                              color: Color(0xFFDC2626),
                                              size: 22,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'PDF Document Ready (${pickedFile!.formattedSize})',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF991B1B),
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
                                : (isEdit ? 'Save Record Changes' : 'Upload Dental Record'),
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
                    'Share ${selectedRecordIds.length} dental ${selectedRecordIds.length == 1 ? 'record' : 'records'} with ${doc.name} (${doc.specialty})?\n\nYou can revoke this permission at any time from your Records tab.',
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
                        backgroundColor: const Color(0xFF10B981),
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
                      backgroundColor: const Color(0xFF10B981),
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
                            color: const Color(0xFF10B981).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.share_rounded,
                            color: Color(0xFF10B981),
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
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),
                        child: Text(
                          errorMsg!,
                          style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C)),
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
                            if (_patientService.allDoctors.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _patientService.allDoctors.take(4).map((doc) {
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
                                ? const Color(0xFFF0FDF4)
                                : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF10B981)
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
                              color: isSelected ? const Color(0xFF10B981) : AppTheme.textMuted,
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
                      final title = (rec['title'] ?? 'Dental Record').toString();
                      final category = (rec['category'] ?? 'Dental Report').toString();
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
                          backgroundColor: const Color(0xFF10B981),
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
              backgroundColor: const Color(0xFFDC2626),
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
        backgroundColor: res['success'] == true ? const Color(0xFF0F172A) : const Color(0xFFDC2626),
      ),
    );
  }

  Future<void> _confirmDeleteRecord(
    BuildContext context,
    Map<String, dynamic> record,
  ) async {
    final recId = (record['id'] ?? '').toString();
    final title = (record['title'] ?? 'Dental Record').toString();
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Dental Record?',
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
              backgroundColor: const Color(0xFFDC2626),
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
        backgroundColor: res['success'] == true ? const Color(0xFF10B981) : const Color(0xFFDC2626),
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
              backgroundColor: const Color(0xFF10B981),
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
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
        return;
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Downloaded "$title" to device.'),
        backgroundColor: const Color(0xFF10B981),
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
                                color: const Color(0xFFEFF6FF),
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
                                  color: const Color(0xFFFEF2F2),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: const Color(0xFFFECACA)),
                                ),
                                child: Column(
                                  children: [
                                    const Icon(
                                      Icons.picture_as_pdf_rounded,
                                      size: 44,
                                      color: Color(0xFFDC2626),
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
                                          : 'Encrypted PDF Dental Record',
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
                                    const Icon(Icons.medication_rounded, color: Color(0xFF10B981), size: 20),
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
                          foregroundColor: const Color(0xFF10B981),
                          side: const BorderSide(color: Color(0xFF10B981)),
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
  // TAB 4: PROFILE TAB
  // ==========================================
  Widget _buildProfileTab() {
    final patient = _patientService.currentPatient;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.1),
                  child: Text(
                    patient.name.isNotEmpty ? patient.name[0].toUpperCase() : 'P',
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                  ),
                ),
                const SizedBox(height: 12),
                Text(_formatPatientName(patient.name), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('Role: Patient', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
                ),
                const SizedBox(height: 12),
                const Divider(color: Color(0xFFF1F5F9)),
                const SizedBox(height: 8),

                // Detailed Info Rows
                _buildProfileDetailRow('Mobile Number', patient.phone.isNotEmpty ? patient.phone : 'Not provided', Icons.phone_android_rounded),
                _buildProfileDetailRow('Email Address', patient.email.isNotEmpty ? patient.email : 'Not provided', Icons.email_outlined),
                _buildProfileDetailRow('City / Location', patient.city.isNotEmpty ? patient.city : 'Not provided', Icons.location_city_rounded),
                _buildProfileDetailRow('Pincode / Postal Code', patient.pincode.isNotEmpty ? patient.pincode : 'Not provided', Icons.pin_drop_outlined),
                _buildProfileDetailRow('Preferred Language', patient.languages.isNotEmpty ? patient.languages.join(', ') : 'English', Icons.language_rounded),

                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildProfileStat('Blood Group', _resolvePatientBloodGroup(patient)),
                    _buildProfileStat('Age', '${_resolvePatientAge(patient).isNotEmpty ? _resolvePatientAge(patient) : "N/A"} Yrs'),
                    _buildProfileStat('Gender', patient.gender),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Log Out of Patient Account', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () async {
              await SessionService().clearSession();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Logged out of Patient Account.'),
                  duration: Duration(seconds: 2),
                ),
              );
              context.go('/login');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProfileDetailRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.primaryBlue),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: value == 'Not provided' ? AppTheme.textMuted : AppTheme.textDark,
                fontWeight: value == 'Not provided' ? FontWeight.normal : FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileStat(String label, String val) {
    return Column(
      children: [
        Text(val, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryBlue)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
      ],
    );
  }
}

// Custom Stateful Animated Action Card
class _AnimatedPatientActionTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;
  final int badgeCount;

  const _AnimatedPatientActionTile({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
    this.badgeCount = 0,
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
                  if (widget.badgeCount > 0)
                    Positioned(
                      top: -3,
                      right: -5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: widget.color,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white, width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 3,
                            ),
                          ],
                        ),
                        child: Text(
                          widget.badgeCount > 99 ? '99+' : '${widget.badgeCount}',
                          style: const TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
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
