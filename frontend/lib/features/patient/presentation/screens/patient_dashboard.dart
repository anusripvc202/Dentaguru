import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/denta_guru_logo.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/session_service.dart';
import '../../../../core/widgets/dental_ads_banner.dart';
import '../../../../core/widgets/whatsapp_chat_modal.dart';
import '../../../../core/models/referral_model.dart';
import '../widgets/refer_patient_flow_dialog.dart';

class PatientDashboardScreen extends StatefulWidget {
  const PatientDashboardScreen({super.key});

  @override
  State<PatientDashboardScreen> createState() => _PatientDashboardScreenState();
}

class _PatientDashboardScreenState extends State<PatientDashboardScreen> with TickerProviderStateMixin {
  int _currentIndex = 0;
  final PatientProblemService _patientService = PatientProblemService();

  // Doctors Directory & My Doctors state
  final TextEditingController _doctorSearchController = TextEditingController();
  String _doctorSearchQuery = '';
  int _doctorTabFilter = 0; // 0: My Doctors, 1: All Available Doctors
  String _doctorSpecialtyFilter = 'All';

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
    _doctorSearchController.dispose();
    _entryController.dispose();
    _pulseController.dispose();
    _patientService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
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
    try {
      final authUser = Supabase.instance.client.auth.currentUser;
      final metaAge = authUser?.userMetadata?['age']?.toString() ?? authUser?.userMetadata?['patient_age']?.toString();
      if (metaAge != null && metaAge.trim().isNotEmpty && metaAge.trim() != 'null') {
        patient.age = metaAge.trim();
        return metaAge.trim();
      }
    } catch (_) {}
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
                                  preselectedDoctor != null ? 'Book with ${preselectedDoctor.name}' : 'Book a Dentist',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: AppTheme.textDark),
                                ),
                                Text(
                                  preselectedDoctor != null
                                      ? '${preselectedDoctor.specialty} • ${preselectedDoctor.clinicName.isNotEmpty ? preselectedDoctor.clinicName : "DentaGuru Clinic"}'
                                      : 'Submit symptoms & get recommended a specialized Doctor',
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

              // ── HERO ADS SECTION (GSI Implants Featured Partner) ──────
              const DentalAdsBanner(isDentist: false, firstSlideOnly: true),
              const SizedBox(height: 18),

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
                              'Book a Dentist',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Report symptoms & get recommended a specialized Doctor',
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
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        SizedBox(
                          width: (constraints.maxWidth > 600) ? (constraints.maxWidth - 24) / 4 : 85,
                          child: _AnimatedPatientActionTile(
                            icon: Icons.calendar_month_rounded,
                            title: 'Appointments',
                            color: AppTheme.primaryBlue,
                            onTap: () => setState(() => _currentIndex = 1),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: (constraints.maxWidth > 600) ? (constraints.maxWidth - 24) / 4 : 85,
                          child: _AnimatedPatientActionTile(
                            icon: Icons.person_search_rounded,
                            title: 'Find Doctors',
                            color: const Color(0xFF0284C7),
                            onTap: () => setState(() => _doctorTabFilter = 1),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: (constraints.maxWidth > 600) ? (constraints.maxWidth - 24) / 4 : 85,
                          child: _AnimatedPatientActionTile(
                            icon: Icons.person_add_alt_1_rounded,
                            title: 'Refer a Patient',
                            color: const Color(0xFF0D9488),
                            onTap: () => ReferPatientFlowDialog.show(context),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: (constraints.maxWidth > 600) ? (constraints.maxWidth - 24) / 4 : 85,
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
                    final authUser = Supabase.instance.client.auth.currentUser;
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
                                              ? 'Your referral recommendation has been submitted. DentaGuru Admin is currently reviewing and verifying the specialist dispatch.'
                                              : 'Your consultation request has been received. DentaGuru Admin is matching the best specialist for your care.',
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

              // 4a. Section: Dental Specialists & My Doctors Directory
              _buildDoctorsDirectorySection(),
              const SizedBox(height: 20),

              // 4b. Section: My Patient Referrals
              _buildMyPatientReferralsSection(),
              const SizedBox(height: 20),

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
    final authUser = Supabase.instance.client.auth.currentUser;
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
    final assignedReq = myRequests.firstWhere(
      (r) => (r.status == 'Confirmed' || r.status == 'Accepted') && r.confirmedTimeSlot != null && r.confirmedTimeSlot!.isNotEmpty,
      orElse: () => myRequests.firstWhere(
        (r) => r.confirmedTimeSlot != null && r.confirmedTimeSlot!.isNotEmpty,
        orElse: () => myRequests.firstWhere(
          (r) {
            final hasDocName = r.assignedDoctorName != null &&
                r.assignedDoctorName!.isNotEmpty &&
                r.assignedDoctorName != 'null' &&
                r.assignedDoctorName != 'None';
            final statusUpper = r.status.toUpperCase();
            final isAssignedOrConfirmed = statusUpper.contains('ASSIGN') ||
                statusUpper.contains('SUGGEST') ||
                statusUpper.contains('CONFIRM') ||
                statusUpper.contains('ACCEPT');
            return hasDocName || isAssignedOrConfirmed;
          },
          orElse: () => PatientConsultationRequest(id: '', patientName: '', patientPhone: '', problemCategory: '', problemDescription: '', severity: '', submittedAt: DateTime.now(), status: ''),
        ),
      ),
    );

    if (assignedReq.id.isEmpty) {
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

    final docName = assignedReq.assignedDoctorName ?? 'Attending Specialist';
    final clinicName = assignedReq.assignedDoctorClinic ?? '';
    final isConfirmed = assignedReq.status == 'Doctor Suggested' || assignedReq.status == 'Confirmed' || assignedReq.status == 'Accepted';

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
                const Text(
                  'Your Next Scheduled Visit',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textDark),
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
                            (assignedReq.confirmedTimeSlot != null && assignedReq.confirmedTimeSlot!.isNotEmpty)
                                ? assignedReq.confirmedTimeSlot!
                                : 'Slot Pending Confirmation',
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
                        color: isConfirmed ? AppTheme.statusConfirmedBg : const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        isConfirmed ? 'Confirmed' : 'Pending',
                        style: TextStyle(
                          color: isConfirmed ? AppTheme.statusConfirmedText : const Color(0xFFD97706),
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
        ],
      ),
    );
  }

  // ==========================================
  // TAB 2: APPOINTMENTS TAB
  // ==========================================
  Widget _buildAppointmentsTab() {
    final requests = _patientService.requests;
    final pastRequests = requests.where((r) => r.status == 'Completed').toList();

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
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.history_rounded, color: AppTheme.primaryBlue, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Completed Visit', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark)),
                          Text('${req.problemCategory} • Completed', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                        ],
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

  // ==========================================
  // TAB 3: RECORDS TAB
  // ==========================================
  // ==========================================
  // TAB 3: RECORDS TAB (DYNAMIC FROM BACKEND API)
  // ==========================================
  Widget _buildRecordsTab() {
    return FutureBuilder<List<dynamic>>(
      future: ApiService().fetchMedicalRecords(patientId: _patientService.currentPatient.id),
      builder: (context, snapshot) {
        final apiRecords = snapshot.data ?? [];
        final localRecords = _patientService.medicalRecords;
        
        final combinedMap = <String, Map<String, dynamic>>{};
        for (final item in [...localRecords, ...apiRecords]) {
          final id = item['id']?.toString() ?? item['title']?.toString() ?? UniqueKey().toString();
          combinedMap[id] = Map<String, dynamic>.from(item);
        }
        final records = combinedMap.values.toList();

        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dental Health Records',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                      ),
                      SizedBox(height: 4),
                      Text('Secure digital prescriptions, X-rays & dental charts', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                    ],
                  ),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryBlue)),
                ],
              ),
              const SizedBox(height: 16),
              if (records.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.folder_open_rounded, size: 40, color: AppTheme.textMuted),
                      SizedBox(height: 10),
                      Text('No Digital Records Issued Yet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark)),
                      SizedBox(height: 4),
                      Text('Prescriptions and X-rays issued by your attending dentist will appear here live.', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                    ],
                  ),
                )
              else
              ...records.map((rec) {
                final type = rec['type'] ?? 'prescription';
                final title = rec['title'] ?? 'Record Slip';
                final subtitle = rec['subtitle'] ?? 'Tap to view details';
                
                IconData icon;
                Color color;
                if (type == 'xray') {
                  icon = Icons.qr_code_scanner_rounded;
                  color = const Color(0xFF8B5CF6);
                } else if (type == 'chart') {
                  icon = Icons.view_in_ar_rounded;
                  color = AppTheme.brandOrange;
                } else {
                  icon = Icons.receipt_long_rounded;
                  color = const Color(0xFF10B981);
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildRecordCard(
                    title: title,
                    subtitle: subtitle,
                    icon: icon,
                    color: color,
                    onTap: () => _showRecordDetailModal(context, rec),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRecordCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppTheme.textMuted),
          ],
        ),
      ),
    );
  }

  void _showRecordDetailModal(BuildContext context, Map<String, dynamic> record) {
    final type = record['type'] ?? 'prescription';
    final title = record['title'] ?? 'Record Details';
    final doctor = record['doctorName'] ?? 'Attending Specialist';
    final clinic = (record['clinicName'] ?? record['clinic_name'] ?? '').toString();
    final date = record['date'] ?? '2026-08-01';
    final List items = record['items'] is List ? record['items'] : [];

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
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
                          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textDark)),
                          Text('👨‍⚕️ $doctor • 🏥 $clinic', style: const TextStyle(fontSize: 11, color: AppTheme.primaryBlue)),
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
                        Row(
                          children: [
                            const Icon(Icons.calendar_today_rounded, size: 14, color: AppTheme.textMuted),
                            const SizedBox(width: 6),
                            Text('Record Date: $date', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textMuted)),
                          ],
                        ),
                        const SizedBox(height: 14),

                        if (type == 'prescription') ...[
                          const Text('💊 Prescribed Medications List:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark)),
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
                                          Text(item['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark)),
                                          Text('Dosage: ${item['dosage']} • Duration: ${item['duration']}', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(6)),
                                      child: const Text('Active', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF16A34A))),
                                    ),
                                  ],
                                ),
                              )),
                        ] else if (type == 'xray') ...[
                          const Text('📷 DICOM Radiograph Inspection:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark)),
                          const SizedBox(height: 8),
                          Container(
                            height: 140,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFF334155)),
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.qr_code_scanner_rounded, size: 42, color: Color(0xFF38BDF8)),
                                    SizedBox(height: 6),
                                    Text('HD DICOM Panoramic View Enabled', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                    Text('Tap to magnify dental bone density scan', style: TextStyle(color: Colors.white60, fontSize: 10)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          ...items.map((item) => Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item['scanType'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textDark)),
                                    const SizedBox(height: 2),
                                    Text('Format: ${item['format']} • Radiologist Notes: ${item['notes']}', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                                  ],
                                ),
                              )),
                        ] else ...[
                          const Text('🦷 3D Teeth Restoration Timeline:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark)),
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
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(color: AppTheme.brandOrange.withValues(alpha: 0.15), shape: BoxShape.circle),
                                      child: Text('#${item['toothNumber']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppTheme.brandOrange)),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(item['procedure'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textDark)),
                                          Text('Date: ${item['date']}', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(6)),
                                      child: Text(item['status'] ?? 'Checked', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
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
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(dialogCtx).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('📄 Exported $title to patient cloud locker.'),
                        backgroundColor: const Color(0xFF10B981),
                      ),
                    );
                  },
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: Text('Download Official $title Document', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
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


  void _showReferredPatientFlow(BuildContext context) {
    ReferPatientFlowDialog.show(context);
  }

  // ==========================================
  // SECTION: DENTAL SPECIALISTS & MY DOCTORS DIRECTORY
  // ==========================================
  Widget _buildDoctorsDirectorySection() {
    final myDoctors = _patientService.myDoctors;
    final allDoctors = _patientService.allDoctors;

    // Filter doctors based on tab, search query, and specialty filter
    final targetList = _doctorTabFilter == 0 ? myDoctors : allDoctors;
    final query = _doctorSearchQuery.trim().toLowerCase();

    final filteredDoctors = targetList.where((doc) {
      if (_doctorSpecialtyFilter != 'All') {
        final matchesSpecialty = doc.specialty.toLowerCase().contains(_doctorSpecialtyFilter.toLowerCase());
        if (!matchesSpecialty) return false;
      }
      if (query.isEmpty) return true;

      final nameMatch = doc.name.toLowerCase().contains(query);
      final specMatch = doc.specialty.toLowerCase().contains(query);
      final clinicMatch = doc.clinicName.toLowerCase().contains(query);
      final cityMatch = doc.city.toLowerCase().contains(query);
      final pinMatch = doc.pincode.toLowerCase().contains(query);
      return nameMatch || specMatch || clinicMatch || cityMatch || pinMatch;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Dental Specialists & Doctors',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Manage your saved doctors & discover verified dental specialists',
                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Segmented Tab Toggle (⭐ My Doctors vs 🔍 All Doctors)
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _doctorTabFilter = 0),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _doctorTabFilter == 0 ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: _doctorTabFilter == 0
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.star_rounded,
                          size: 16,
                          color: _doctorTabFilter == 0 ? const Color(0xFFD97706) : AppTheme.textMuted,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'My Doctors (${myDoctors.length})',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _doctorTabFilter == 0 ? AppTheme.textDark : AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _doctorTabFilter = 1),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _doctorTabFilter == 1 ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: _doctorTabFilter == 1
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_rounded,
                          size: 16,
                          color: _doctorTabFilter == 1 ? AppTheme.primaryBlue : AppTheme.textMuted,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'All Doctors (${allDoctors.length})',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _doctorTabFilter == 1 ? AppTheme.textDark : AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Live Search Input
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            controller: _doctorSearchController,
            onChanged: (val) => setState(() => _doctorSearchQuery = val),
            style: const TextStyle(fontSize: 13, color: AppTheme.textDark),
            decoration: InputDecoration(
              hintText: 'Search by Doctor, Specialty, Clinic, City, Pincode...',
              hintStyle: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppTheme.primaryBlue),
              suffixIcon: _doctorSearchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18, color: AppTheme.textMuted),
                      onPressed: () {
                        _doctorSearchController.clear();
                        setState(() => _doctorSearchQuery = '');
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: InputBorder.none,
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Specialty Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              'All',
              'Orthodontics',
              'Endodontics',
              'General Dentistry',
              'Oral & Maxillofacial',
              'Pediatric',
              'Periodontics',
              'Prosthodontics',
            ].map((spec) {
              final isSelected = _doctorSpecialtyFilter == spec;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(spec),
                  selected: isSelected,
                  onSelected: (sel) {
                    if (sel) setState(() => _doctorSpecialtyFilter = spec);
                  },
                  labelStyle: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? Colors.white : AppTheme.textDark,
                  ),
                  selectedColor: AppTheme.primaryBlue,
                  backgroundColor: const Color(0xFFF1F5F9),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  side: BorderSide(
                    color: isSelected ? AppTheme.primaryBlue : const Color(0xFFE2E8F0),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),

        // List of Doctors or Empty State
        if (filteredDoctors.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (_doctorTabFilter == 0 ? const Color(0xFFD97706) : AppTheme.primaryBlue).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _doctorTabFilter == 0 ? Icons.star_border_rounded : Icons.person_search_rounded,
                    color: _doctorTabFilter == 0 ? const Color(0xFFD97706) : AppTheme.primaryBlue,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _doctorSearchQuery.isNotEmpty
                      ? 'No doctors matching "$_doctorSearchQuery"'
                      : (_doctorTabFilter == 0
                          ? 'No doctors added to "My Doctors" yet'
                          : 'No dental specialists found'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                ),
                const SizedBox(height: 4),
                Text(
                  _doctorSearchQuery.isNotEmpty
                      ? 'Try searching with another name, specialty, city, or pincode.'
                      : (_doctorTabFilter == 0
                          ? 'Browse all verified platform doctors and add them to your favorites for quick booking.'
                          : 'Our medical network is constantly expanding with verified dental experts.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, height: 1.35),
                ),
                if (_doctorTabFilter == 0 && _doctorSearchQuery.isEmpty) ...[
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => setState(() => _doctorTabFilter = 1),
                    icon: const Icon(Icons.search_rounded, size: 15),
                    label: const Text('Browse All Available Doctors', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                  ),
                ],
                if (_doctorSearchQuery.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () {
                      _doctorSearchController.clear();
                      setState(() {
                        _doctorSearchQuery = '';
                        _doctorSpecialtyFilter = 'All';
                      });
                    },
                    child: const Text('Reset All Filters', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
                  ),
                ],
              ],
            ),
          )
        else
          ...filteredDoctors.map((doc) => _buildDoctorCard(doc)),
      ],
    );
  }

  Widget _buildDoctorCard(DoctorModel doc) {
    final isAdded = _patientService.isDoctorAdded(doc.id) ||
                    (doc.userId.isNotEmpty && _patientService.isDoctorAdded(doc.userId)) ||
                    (doc.email.isNotEmpty && _patientService.isDoctorAdded(doc.email));

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAdded ? const Color(0xFFBAE6FD) : const Color(0xFFE2E8F0),
          width: isAdded ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Profile Photo, Name, Specialty, Experience/Rating
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Profile Photo / Initials Avatar
              Stack(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: const Color(0xFFE0F2FE),
                    backgroundImage: doc.photoBytes != null ? MemoryImage(doc.photoBytes!) : null,
                    child: doc.photoBytes == null
                        ? Text(
                            doc.name.isNotEmpty
                                ? (doc.name.replaceAll('Dr.', '').replaceAll('Dr. ', '').trim().isNotEmpty
                                    ? doc.name.replaceAll('Dr.', '').replaceAll('Dr. ', '').trim()[0].toUpperCase()
                                    : 'D')
                                : 'D',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryBlue,
                            ),
                          )
                        : null,
                  ),
                  if (doc.verificationStatus == 'VERIFIED' || doc.rating >= 4.5)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.verified_rounded, size: 14, color: Color(0xFF0284C7)),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),

              // Name, Specialty, Rating
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            doc.name.startsWith('Dr.') ? doc.name : 'Dr. ${doc.name}',
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textDark,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isAdded)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFBFDBFE)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.star_rounded, size: 12, color: Color(0xFF2563EB)),
                                SizedBox(width: 3),
                                Text(
                                  'My Doctor',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1D4ED8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFBBF7D0)),
                          ),
                          child: Text(
                            doc.specialty.isNotEmpty ? doc.specialty : 'General Dentistry',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF15803D),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (doc.experienceYears > 0 || doc.rating > 0)
                          Text(
                            '${doc.experienceYears > 0 ? "${doc.experienceYears}+ Yrs • " : ""}${doc.rating} ⭐',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 8),

          // Clinic Name
          Row(
            children: [
              const Icon(Icons.local_hospital_outlined, size: 14, color: AppTheme.primaryBlue),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  doc.clinicName.isNotEmpty ? doc.clinicName : 'DentaGuru Partner Dental Clinic',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // City & Pincode
          Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 14, color: Color(0xFF0D9488)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  [
                    if (doc.clinicAddress.isNotEmpty) doc.clinicAddress,
                    if (doc.city.isNotEmpty) doc.city,
                    if (doc.pincode.isNotEmpty) 'PIN: ${doc.pincode}',
                  ].where((s) => s.isNotEmpty).isNotEmpty
                      ? [
                          if (doc.clinicAddress.isNotEmpty) doc.clinicAddress,
                          if (doc.city.isNotEmpty) doc.city,
                          if (doc.pincode.isNotEmpty) 'PIN: ${doc.pincode}',
                        ].where((s) => s.isNotEmpty).join(' • ')
                      : 'Location verified on DentaGuru network',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF0F766E), fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Action Buttons: Add/Remove Doctor & Book & WhatsApp
          Row(
            children: [
              // Add / Remove Toggle Button
              Expanded(
                flex: 5,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    if (isAdded) {
                      await _patientService.removeDoctorFromMyDoctors(doc);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Removed ${doc.name} from My Doctors'),
                            backgroundColor: const Color(0xFFEF4444),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    } else {
                      await _patientService.addDoctorToMyDoctors(doc);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('⭐ Added ${doc.name} to My Doctors!'),
                            backgroundColor: const Color(0xFF10B981),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    }
                  },
                  icon: Icon(
                    isAdded ? Icons.remove_circle_outline_rounded : Icons.person_add_alt_1_rounded,
                    size: 14,
                    color: isAdded ? const Color(0xFFDC2626) : Colors.white,
                  ),
                  label: Text(
                    isAdded ? 'Remove Doctor' : 'Add Doctor',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: isAdded ? const Color(0xFFDC2626) : Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isAdded ? const Color(0xFFFEF2F2) : AppTheme.primaryBlue,
                    foregroundColor: isAdded ? const Color(0xFFDC2626) : Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: isAdded ? const Color(0xFFFCA5A5) : Colors.transparent,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Book Appointment Button
              Expanded(
                flex: 4,
                child: OutlinedButton.icon(
                  onPressed: () => _showReportProblemDialog(context, preselectedDoctor: doc),
                  icon: const Icon(Icons.calendar_month_rounded, size: 14, color: AppTheme.primaryBlue),
                  label: const Text(
                    'Book Visit',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    side: const BorderSide(color: AppTheme.primaryBlue),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),

              // WhatsApp Contact Button
              if (doc.phone.isNotEmpty) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: () async {
                    String rawPhone = doc.phone.replaceAll(RegExp(r'[^0-9]'), '');
                    if (rawPhone.startsWith('0') && rawPhone.length == 11) {
                      rawPhone = '91${rawPhone.substring(1)}';
                    } else if (rawPhone.length == 10) {
                      rawPhone = '91$rawPhone';
                    }
                    final msg = 'Hello ${doc.name}, I found your profile on DentaGuru and would like to schedule a dental consultation at ${doc.clinicName.isNotEmpty ? doc.clinicName : "your clinic"}.';
                    final waUrl = Uri.parse('https://wa.me/$rawPhone?text=${Uri.encodeComponent(msg)}');
                    try {
                      await launchUrl(waUrl, mode: LaunchMode.externalApplication);
                    } catch (_) {}
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF25D366).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF86EFAC)),
                    ),
                    child: const Icon(Icons.chat_rounded, size: 16, color: Color(0xFF16A34A)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMyPatientReferralsSection() {
    final myCreatedRefs = _patientService.myCreatedPatientReferrals;
    final receivedForMeRefs = _patientService.receivedForMePatientReferrals;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'My Patient Referrals',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Patients you referred to specialized doctors',
                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () => _showReferredPatientFlow(context),
              icon: const Icon(Icons.add_rounded, size: 16, color: Color(0xFF0D9488)),
              label: const Text(
                'Refer Patient',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0D9488)),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                backgroundColor: const Color(0xFF0D9488).withOpacity(0.08),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (myCreatedRefs.isEmpty && receivedForMeRefs.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFEEF2F6)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D9488).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF0D9488), size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'No patient referrals yet',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Know someone who needs dental care? Refer them to our verified doctors in just a few clicks.',
                        style: TextStyle(fontSize: 11, color: AppTheme.textMuted, height: 1.3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else ...[
          // List of referrals created by logged-in patient
          ...myCreatedRefs.map((ref) {
            final isAccepted = ref.status == 'Accepted';
            final isRejected = ref.status == 'Rejected';

            final statusColor = isAccepted
                ? const Color(0xFF10B981)
                : (isRejected ? const Color(0xFFEF4444) : const Color(0xFFF59E0B));
            final statusBg = isAccepted
                ? const Color(0xFFDCFCE7)
                : (isRejected ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7));
            final statusText = isAccepted
                ? '🟢 Accepted by Doctor'
                : (isRejected ? '🔴 Referral Declined' : '🟡 Doctor Reviewing');

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isAccepted ? const Color(0xFF86EFAC) : const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
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
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: const Color(0xFF0284C7).withOpacity(0.12),
                              child: Text(
                                ref.referredPatientName.isNotEmpty ? ref.referredPatientName[0].toUpperCase() : 'P',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    ref.referredPatientName,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    [
                                      '+91 ${ref.referredPatientMobile}',
                                      if (ref.referredPatientAge.isNotEmpty) '${ref.referredPatientAge} Yrs',
                                      if (ref.referredPatientGender.isNotEmpty) ref.referredPatientGender,
                                    ].join(' • '),
                                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (ref.referredPatientLocation.isNotEmpty || ref.referredPatientCity.isNotEmpty || ref.referredPatientPincode.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        const Icon(Icons.location_on_outlined, size: 12, color: Color(0xFF0284C7)),
                                        const SizedBox(width: 3),
                                        Expanded(
                                          child: Text(
                                            [
                                              if (ref.referredPatientLocation.isNotEmpty) ref.referredPatientLocation,
                                              if (ref.referredPatientCity.isNotEmpty) ref.referredPatientCity,
                                              if (ref.referredPatientPincode.isNotEmpty) '(${ref.referredPatientPincode})',
                                            ].join(', '),
                                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: Color(0xFF0369A1)),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          statusText,
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
                  const SizedBox(height: 8),

                  Row(
                    children: [
                      const Icon(Icons.medical_services_outlined, size: 14, color: Color(0xFF0D9488)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${ref.doctorName} • ${ref.requiredSpecialist}',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.local_hospital_outlined, size: 14, color: Colors.black45),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          [
                            ref.doctorClinicName.isNotEmpty ? ref.doctorClinicName : 'DentaGuru Partner Clinic',
                            if (ref.doctorLocation.isNotEmpty || ref.doctorCity.isNotEmpty || ref.doctorPincode.isNotEmpty)
                              [
                                if (ref.doctorLocation.isNotEmpty) ref.doctorLocation,
                                if (ref.doctorCity.isNotEmpty) ref.doctorCity,
                                if (ref.doctorPincode.isNotEmpty) ref.doctorPincode,
                              ].join(', ')
                          ].join(' • '),
                          style: const TextStyle(fontSize: 11, color: AppTheme.textMedium),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),

                  if (ref.clinicalComplaint.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Reason: ${ref.clinicalComplaint}',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, fontStyle: FontStyle.italic),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],

                  if (isRejected && ref.rejectionReason != null && ref.rejectionReason!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Reason: ${ref.rejectionReason}',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF991B1B), fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],

                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.chat_rounded, size: 13, color: Colors.white),
                        label: Text(
                          'WhatsApp ${ref.referredPatientName}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF25D366),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                        onPressed: () async {
                          String rawPhone = ref.referredPatientMobile.replaceAll(RegExp(r'[^0-9]'), '');
                          if (rawPhone.startsWith('0') && rawPhone.length == 11) {
                            rawPhone = '91${rawPhone.substring(1)}';
                          } else if (rawPhone.length == 10) {
                            rawPhone = '91$rawPhone';
                          }
                          final msg = _buildReferralWhatsAppMessage(ref);
                          final waUrl = Uri.parse(rawPhone.isNotEmpty
                              ? 'https://wa.me/$rawPhone?text=${Uri.encodeComponent(msg)}'
                              : 'https://wa.me/?text=${Uri.encodeComponent(msg)}');
                          try {
                            await launchUrl(waUrl, mode: LaunchMode.externalApplication);
                          } catch (_) {}
                        },
                      ),
                      Text(
                        '${ref.referralDate.day}/${ref.referralDate.month}/${ref.referralDate.year}',
                        style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),

          // List of referrals received by logged-in patient (Section 20)
          if (receivedForMeRefs.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Referrals For You',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textDark),
            ),
            const SizedBox(height: 6),
            ...receivedForMeRefs.map((ref) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF86EFAC)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'Referred by: ${ref.referrerPatientName}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF14532D)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              ref.status,
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF16A34A)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Doctor: ${ref.doctorName} (${ref.requiredSpecialist})',
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF166534)),
                      ),
                      if (ref.doctorClinicName.isNotEmpty || ref.doctorCity.isNotEmpty || ref.doctorPincode.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined, size: 12, color: Color(0xFF15803D)),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                [
                                  if (ref.doctorClinicName.isNotEmpty) ref.doctorClinicName,
                                  if (ref.doctorLocation.isNotEmpty) ref.doctorLocation,
                                  if (ref.doctorCity.isNotEmpty) ref.doctorCity,
                                  if (ref.doctorPincode.isNotEmpty) '(${ref.doctorPincode})',
                                ].join(', '),
                                style: const TextStyle(fontSize: 10.5, color: Color(0xFF15803D)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (ref.clinicalComplaint.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Complaint: ${ref.clinicalComplaint}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF14532D)),
                        ),
                      ],
                    ],
                  ),
                )),
          ],
        ],
      ],
    );
  }

  String _buildReferralWhatsAppMessage(PatientReferral ref) {
    // Find doctor in platform directory if available
    DoctorModel? doc;
    for (final d in _patientService.allDoctors) {
      if (ref.doctorId.isNotEmpty && (d.id == ref.doctorId || d.userId == ref.doctorId)) {
        doc = d;
        break;
      }
      final cleanRefDoc = ref.doctorName.replaceAll('Dr.', '').replaceAll('Dr. ', '').trim().toLowerCase();
      final cleanD = d.name.replaceAll('Dr.', '').replaceAll('Dr. ', '').trim().toLowerCase();
      if (cleanRefDoc.isNotEmpty && (cleanD.contains(cleanRefDoc) || cleanRefDoc.contains(cleanD))) {
        doc = d;
        break;
      }
    }

    final docName = ref.doctorName.isNotEmpty
        ? (ref.doctorName.startsWith('Dr.') ? ref.doctorName : 'Dr. ${ref.doctorName}')
        : (doc != null ? (doc.name.startsWith('Dr.') ? doc.name : 'Dr. ${doc.name}') : 'Doctor');
    final specialty = ref.requiredSpecialist.isNotEmpty ? ref.requiredSpecialist : (doc?.specialty ?? 'Dental Specialist');
    final qual = (doc?.qualification.isNotEmpty == true && doc!.qualification != 'BDS, MDS') ? ' (${doc.qualification})' : '';
    final clinic = ref.doctorClinicName.isNotEmpty ? ref.doctorClinicName : (doc?.clinicName.isNotEmpty == true ? doc!.clinicName : '');

    final locationParts = [
      if (ref.doctorLocation.isNotEmpty) ref.doctorLocation else if (doc?.clinicAddress.isNotEmpty == true) doc!.clinicAddress,
      if (ref.doctorCity.isNotEmpty) ref.doctorCity else if (doc?.city.isNotEmpty == true) doc!.city,
      if (ref.doctorPincode.isNotEmpty) 'PIN: ${ref.doctorPincode}' else if (doc?.pincode.isNotEmpty == true) 'PIN: ${doc!.pincode}',
    ].where((s) => s.trim().isNotEmpty).toList();

    final docPhone = (doc?.phone.isNotEmpty == true) ? doc!.phone : '';

    final buffer = StringBuffer();
    buffer.writeln('Hi ${ref.referredPatientName},');
    buffer.writeln();
    buffer.writeln('I have referred you to *$docName*$qual on DentaGuru for your dental care.');
    buffer.writeln();
    buffer.writeln('👨‍⚕️ *Doctor & Clinic Details:*');
    buffer.writeln('• *Doctor:* $docName');
    buffer.writeln('• *Specialty:* $specialty');
    if (clinic.isNotEmpty) buffer.writeln('• *Clinic:* $clinic');
    if (docPhone.isNotEmpty) buffer.writeln('• *Doctor Mobile:* +91 $docPhone');
    if (locationParts.isNotEmpty) buffer.writeln('• *Address:* ${locationParts.join(", ")}');
    if (doc != null && doc.experienceYears > 0) buffer.writeln('• *Experience:* ${doc.experienceYears}+ Years (${doc.rating} ⭐)');
    if (ref.clinicalComplaint.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('📋 *Clinical Reason:* ${ref.clinicalComplaint}');
    }
    buffer.writeln();
    buffer.writeln('You can reach out directly to the clinic or doctor to schedule your appointment. Wishing you the best dental care!');

    return buffer.toString();
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
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: _isHovered ? 0.22 : 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(widget.icon, color: widget.color, size: 20),
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
