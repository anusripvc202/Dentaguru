import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/denta_guru_logo.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/session_service.dart';
import '../../../../core/constants/booking_rules_config.dart';
import '../../../../core/constants/permissions.dart';
import '../../../../core/models/referral_model.dart';
import '../../../../core/models/medical_specialty_model.dart';
import 'patient_details_screen.dart';
import '../widgets/admin_global_visits_calendar.dart';
import '../widgets/admin_doctor_activity_calendar.dart';
import '../widgets/admin_clinic_management_panel.dart';
import '../widgets/doctor_slot_management_dialog.dart';
import '../widgets/gs_health_admin_overview.dart';
import '../widgets/gs_health_district_management_panel.dart';
import '../widgets/gs_health_patient_assignment_panel.dart';
import '../widgets/gs_health_district_reports_panel.dart';
import '../widgets/gs_health_sub_admin_district_dialog.dart';
import '../../../patient/presentation/screens/find_doctors_screen.dart';
import '../../../patient/presentation/screens/doctor_profile_screen.dart';
import '../../../clinic/presentation/screens/clinic_dashboard.dart';
import 'admin_profile_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  final int initialTab;
  const AdminDashboardScreen({super.key, this.initialTab = 0});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> with TickerProviderStateMixin {
  late int _selectedNavIndex = widget.initialTab; // 0: Overview, 1: Clinics, 2: Dentists, 3: Patients, 4: Appointments, 5: Revenue, 6: Reports, 7: Reviews, 8: Settings, 9: Sub-Admins, 13: Requests
  final PatientProblemService _problemService = PatientProblemService();

  bool _isOverviewLoading = false;
  String? _overviewError;
  List<AdminAppointmentItem> _overviewAppointments = const [];
  List<Map<String, dynamic>> _liveDoctorSchedules = const [];
  List<Map<String, dynamic>> _pendingRescheduleRequests = const [];
  bool _showPendingVerificationOnly = false;
  String _adminApptSearchQuery = '';
  String _adminApptStatusFilter = 'All';
  String _adminApptSpecialtyFilter = 'All';
  String _adminApptDoctorFilter = 'All';
  String _adminApptDateFilter = '';
  final Set<String> _expandedAppointmentIds = {};
  final Set<String> _togglingSubAdminIds = {};

  Timer? _autoSyncTimer;
  RealtimeChannel? _realtimeChannel;
  bool _isBackgroundSyncing = false;

  late AnimationController _entryController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _pulseScaleAnimation;

  @override
  void initState() {
    super.initState();
    _problemService.addListener(_onServiceUpdate);
    _problemService.setAdminMode(true);
    _refreshOverviewData();

    // ⏱️ Auto-sync timer: polls cleanly without overlapping in-flight requests
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (!mounted || _isBackgroundSyncing) return;
      _isBackgroundSyncing = true;
      try {
        await Future.wait([
          _problemService.syncProblemRequestsFromApi(),
          _problemService.syncAdminReferralsFromApi(),
          _problemService.syncNotificationsFromApi(role: 'Admin'),
        ]);
      } finally {
        _isBackgroundSyncing = false;
      }
    });

    // ⚡ Supabase Realtime Postgres Changes listener for instant multi-device sync
    try {
      _realtimeChannel = Supabase.instance.client
          .channel('admin_problem_requests_realtime')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'patient_problem_requests',
            callback: (payload) {
              debugPrint('⚡ Realtime update on patient_problem_requests: ${payload.eventType}');
              if (mounted) _problemService.syncProblemRequestsFromApi();
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'referrals',
            callback: (payload) {
              debugPrint('⚡ Realtime update on referrals: ${payload.eventType}');
              if (mounted) _problemService.syncAdminReferralsFromApi();
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('Admin Realtime Channel Subscription Notice: $e');
    }

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
    _autoSyncTimer?.cancel();
    if (_realtimeChannel != null) {
      try {
        Supabase.instance.client.removeChannel(_realtimeChannel!);
      } catch (_) {}
    }
    _entryController.dispose();
    _pulseController.dispose();
    _problemService.setAdminMode(false);
    _problemService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  void _showAssignDoctorDialog(BuildContext context, PatientConsultationRequest req, {DoctorModel? preSelectedDoctor}) {
    // 🌐 Automatically mark request as Admin Reviewed in Database & Backend API
    _problemService.markAdminReviewed(req.id);

    int currentStep = 1; // 1: Patient Problem, 2: Select Doctor, 3: Review & Send
    DoctorModel? initialDoc = preSelectedDoctor;
    if (initialDoc == null && req.preferredDoctorName != null && req.preferredDoctorName!.isNotEmpty) {
      final pName = req.preferredDoctorName!.toLowerCase();
      try {
        initialDoc = _problemService.allDoctors.firstWhere(
          (d) => d.name.toLowerCase().contains(pName) || pName.contains(d.name.toLowerCase()),
        );
      } catch (_) {}
    }
    DoctorModel? selectedDoctor = initialDoc ?? (_problemService.allDoctors.isNotEmpty ? _problemService.allDoctors.first : null);
    String searchKeyword = '';
    String selectedSpecialtyFilter = 'All';
    String selectedAvailabilityFilter = 'All';
    final stateFilterController = TextEditingController();
    final cityFilterController = TextEditingController();
    final pincodeFilterController = TextEditingController();
    List<DoctorModel>? remoteFilteredDoctors;
    bool isFilteringApi = false;
    final defaultNote = (req.preferredDoctorName != null && req.preferredDoctorName!.isNotEmpty)
        ? 'Patient-referred specialist request to ${req.preferredDoctorName} reviewed and clinically approved for consultation.'
        : 'Recommended for specialized clinical evaluation and care.';
    final adminNotesController = TextEditingController(text: defaultNote);

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final sourceDoctors = remoteFilteredDoctors ?? _problemService.allDoctors;
            final searchTrim = searchKeyword.trim().toLowerCase();

            // 1. Filter doctors matching Search (name, specialty, clinic, city, pincode, state, address) + filters
            final exactFilteredDoctors = sourceDoctors.where((doc) {
              final matchesSearch = searchTrim.isEmpty ||
                  doc.name.toLowerCase().contains(searchTrim) ||
                  doc.specialty.toLowerCase().contains(searchTrim) ||
                  doc.clinicName.toLowerCase().contains(searchTrim) ||
                  doc.city.toLowerCase().contains(searchTrim) ||
                  doc.pincode.contains(searchTrim) ||
                  doc.state.toLowerCase().contains(searchTrim) ||
                  doc.clinicAddress.toLowerCase().contains(searchTrim);
              final matchesSpecialty = MedicalSpecialtyModel.matchesSpecialtyFilter(doc.specialty, selectedSpecialtyFilter);
              final matchesAvailability = selectedAvailabilityFilter == 'All' ||
                  doc.status.toLowerCase() == selectedAvailabilityFilter.toLowerCase();
              final matchesState = stateFilterController.text.trim().isEmpty ||
                  doc.state.toLowerCase().contains(stateFilterController.text.trim().toLowerCase());
              final matchesCity = cityFilterController.text.trim().isEmpty ||
                  doc.city.toLowerCase().contains(cityFilterController.text.trim().toLowerCase()) ||
                  doc.clinicAddress.toLowerCase().contains(cityFilterController.text.trim().toLowerCase());
              final matchesPincode = pincodeFilterController.text.trim().isEmpty ||
                  doc.pincode.contains(pincodeFilterController.text.trim());
              return matchesSearch && matchesSpecialty && matchesAvailability && matchesState && matchesCity && matchesPincode;
            }).toList();

            bool isShowingNearestFallback = false;
            List<DoctorModel> filteredDoctors;

            if (exactFilteredDoctors.isNotEmpty) {
              filteredDoctors = exactFilteredDoctors;
            } else if (sourceDoctors.isNotEmpty) {
              // 2. FALLBACK: No doctor found in searched City/Pincode. Show nearest available doctors!
              isShowingNearestFallback = true;
              filteredDoctors = sourceDoctors.where((doc) {
                final matchesSpecialty = MedicalSpecialtyModel.matchesSpecialtyFilter(doc.specialty, selectedSpecialtyFilter);
                final matchesAvailability = selectedAvailabilityFilter == 'All' ||
                    doc.status.toLowerCase() == selectedAvailabilityFilter.toLowerCase();
                return matchesSpecialty && matchesAvailability;
              }).toList();
            } else {
              filteredDoctors = [];
            }

            // Target location for priority ranking (prefer searched city/pincode or patient location)
            final targetCity = (searchTrim.isNotEmpty && RegExp(r'^[a-zA-Z\s]+$').hasMatch(searchTrim))
                ? searchTrim
                : (cityFilterController.text.trim().isNotEmpty ? cityFilterController.text.trim() : req.city);
            final targetPincode = (searchTrim.isNotEmpty && RegExp(r'^\d+$').hasMatch(searchTrim))
                ? searchTrim
                : (pincodeFilterController.text.trim().isNotEmpty ? pincodeFilterController.text.trim() : req.pincode);
            final targetState = stateFilterController.text.trim().isNotEmpty ? stateFilterController.text.trim() : req.state;

            // Priority Location Sorting: Same Pincode (Tier 1) -> Nearby Pincode (Tier 2) -> Same City (Tier 3) -> Same State (Tier 5) -> Rating
            filteredDoctors.sort((a, b) {
              final tierA = a.getLocationMatchTier(targetState, targetCity, targetPincode);
              final tierB = b.getLocationMatchTier(targetState, targetCity, targetPincode);
              if (tierA != tierB) return tierA.compareTo(tierB);
              return b.rating.compareTo(a.rating);
            });

            if (selectedDoctor == null && filteredDoctors.isNotEmpty) {
              selectedDoctor = filteredDoctors.first;
            }

            final clinicAddr = (selectedDoctor?.clinicAddress != null && selectedDoctor!.clinicAddress.trim().isNotEmpty)
                ? selectedDoctor!.clinicAddress.trim()
                : 'Address not specified';
            final doctorPhone = (selectedDoctor?.phone != null && selectedDoctor!.phone.trim().isNotEmpty)
                ? selectedDoctor!.phone.trim()
                : 'Not provided';
            final rawFee = selectedDoctor?.getFeeForCategory(req.problemCategory).trim() ?? '';
            final caseFee = rawFee.isNotEmpty ? rawFee : 'Standard consultation fee';
            final waText = "🏥 *GS HEALTH Clinical Recommendation*\n\n"
                "Dear *${req.patientName}*,\n\n"
                "Our Clinical Admin team has reviewed your reported symptoms:\n"
                "📌 *Issue*: ${req.problemCategory} (${req.severity} Severity)\n\n"
                "👨‍⚕️ *Recommended Doctor*: *${selectedDoctor?.name}*\n"
                "🎓 *Specialty*: ${selectedDoctor?.specialty}\n"
                "💳 *Estimated Fee*: $caseFee\n"
                "🏥 *Clinic*: ${selectedDoctor?.clinicName}\n"
                "📍 *Address*: $clinicAddr\n"
                "📞 *Doctor Contact*: $doctorPhone\n\n"
                "💬 *Admin Guidance*: ${adminNotesController.text.trim().isEmpty ? 'Recommended for specialized clinical evaluation and care.' : adminNotesController.text.trim()}\n\n"
                "Please open your GS HEALTH App to confirm your consultation slot.";

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              backgroundColor: Colors.white,
              elevation: 20,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              child: Container(
                constraints: BoxConstraints(maxWidth: 580, maxHeight: MediaQuery.of(context).size.height * 0.88),
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Modal Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.person_add_alt_1_rounded, color: AppTheme.primaryBlue, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Doctor Assignment Wizard • ${req.patientName}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                              Text(
                                'Ticket ${req.id} • ${req.problemCategory}',
                                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted, size: 20),
                          onPressed: () => Navigator.of(dialogContext).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // RESPONSIVE STEP INDICATOR PIPELINE (GUARANTEED SINGLE LINE & NO OVERFLOW)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: LayoutBuilder(
                        builder: (context, stepConstraints) {
                          final isSmallScreen = stepConstraints.maxWidth < 420;

                          return Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: _buildStepBadge(1, isSmallScreen ? 'Patient' : 'Patient Problem', currentStep == 1, currentStep > 1),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 2),
                                child: Icon(Icons.chevron_right_rounded, size: 14, color: Color(0xFF94A3B8)),
                              ),
                              Expanded(
                                flex: 3,
                                child: _buildStepBadge(2, isSmallScreen ? 'Doctor' : 'Select Doctor', currentStep == 2, currentStep > 2),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 2),
                                child: Icon(Icons.chevron_right_rounded, size: 14, color: Color(0xFF94A3B8)),
                              ),
                              Expanded(
                                flex: 3,
                                child: _buildStepBadge(3, 'Dispatch', currentStep == 3, false),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),

                    // STEP 1: PATIENT PROBLEM DETAILS
                    if (currentStep == 1)
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(14),
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
                                            '👤 Patient: ${req.patientName}',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: req.severity == 'Severe' ? const Color(0x14FE3434) : const Color(0x14FE3434),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            'Severity: ${req.severity}',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: req.severity == 'Severe' ? const Color(0xFFFE3434) : const Color(0xFFFE3434),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 4,
                                      children: [
                                        Text('📞 Contact: ${req.patientPhone}', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                                        Text('📍 Location: ${req.getDisplayCity(_problemService.allPatients)}${req.getDisplayPincode(_problemService.allPatients).isNotEmpty ? " (PIN: ${req.getDisplayPincode(_problemService.allPatients)})" : ""}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textDark)),
                                        Text('📌 Category: ${req.problemCategory}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryBlue)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              if (req.preferredDoctorName != null && req.preferredDoctorName!.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: const Color(0x14FE3434),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0x40FE3434)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.recommend_rounded, color: Color(0xFFFE3434), size: 20),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '⭐ Patient Referral Preference: ${req.preferredDoctorName}',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFFFE3434)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              const SizedBox(height: 14),
                              const Text('Patient Reported Symptoms & Notes:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textDark)),
                              const SizedBox(height: 6),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFCBD5E1)),
                                ),
                                child: Text(
                                  req.problemDescription,
                                  style: const TextStyle(fontSize: 12, color: AppTheme.textMedium, height: 1.4),
                                ),
                              ),
                              const SizedBox(height: 16),

                              ElevatedButton.icon(
                                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                                label: const Text(
                                  'Step 2: Choose Doctor from Master List',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primaryBlue,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size.fromHeight(46),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: () => setModalState(() => currentStep = 2),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // STEP 2: SELECT DOCTOR FROM ALL DOCTORS DIRECTORY (LOCATION-BASED PRIORITY MATCHING)
                    if (currentStep == 2)
                      Expanded(
                        child: Column(
                          children: [
                            // Patient Location Context Banner
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0x14012A58),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0x40012A58)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.my_location_rounded, size: 18, color: AppTheme.primaryBlue),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('Patient Location', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textMuted)),
                                        Text(
                                           '📍 ${req.getDisplayCity(_problemService.allPatients)}${req.getDisplayPincode(_problemService.allPatients).isNotEmpty ? " • 📌 Pincode: ${req.getDisplayPincode(_problemService.allPatients)}" : ""}${req.state.isNotEmpty ? " • ${req.state}" : ""}',
                                           style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                                           overflow: TextOverflow.ellipsis,
                                         ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0x14012A58),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text('Priority Ranked', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF012A58))),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Search & Location Filter Bar (Responsive)
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final isMobile = constraints.maxWidth < 520;
                                final searchField = TextField(
                                  onChanged: (val) => setModalState(() => searchKeyword = val),
                                  style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                                  cursorColor: AppTheme.primaryBlue,
                                  decoration: InputDecoration(
                                    hintText: 'Search doctor / clinic...',
                                    prefixIcon: const Icon(Icons.search_rounded, size: 16, color: AppTheme.textMuted),
                                    filled: true,
                                    fillColor: const Color(0xFFF8FAFC),
                                    contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                                  ),
                                );

                                final locationFieldsRow = Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: stateFilterController,
                                        style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                                        cursorColor: AppTheme.primaryBlue,
                                        decoration: InputDecoration(
                                          hintText: 'State...',
                                          prefixIcon: const Icon(Icons.map_rounded, size: 15, color: AppTheme.textMuted),
                                          filled: true,
                                          fillColor: const Color(0xFFF8FAFC),
                                          contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: TextField(
                                        controller: cityFilterController,
                                        style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                                        cursorColor: AppTheme.primaryBlue,
                                        decoration: InputDecoration(
                                          hintText: 'City...',
                                          prefixIcon: const Icon(Icons.location_city_rounded, size: 15, color: AppTheme.textMuted),
                                          filled: true,
                                          fillColor: const Color(0xFFF8FAFC),
                                          contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: TextField(
                                        controller: pincodeFilterController,
                                        keyboardType: TextInputType.number,
                                        style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                                        cursorColor: AppTheme.primaryBlue,
                                        decoration: InputDecoration(
                                          hintText: 'Pincode...',
                                          prefixIcon: const Icon(Icons.pin_drop_rounded, size: 15, color: AppTheme.textMuted),
                                          filled: true,
                                          fillColor: const Color(0xFFF8FAFC),
                                          contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    ElevatedButton(
                                      onPressed: isFilteringApi
                                          ? null
                                          : () async {
                                              setModalState(() => isFilteringApi = true);
                                              final stVal = stateFilterController.text.trim();
                                              final cityVal = cityFilterController.text.trim();
                                              final pinVal = pincodeFilterController.text.trim();
                                              if (stVal.isEmpty && cityVal.isEmpty && pinVal.isEmpty) {
                                                setModalState(() {
                                                  remoteFilteredDoctors = null;
                                                  isFilteringApi = false;
                                                });
                                              } else {
                                                final res = await _problemService.fetchDoctorsFiltered(
                                                  state: stVal.isNotEmpty ? stVal : null,
                                                  city: cityVal.isNotEmpty ? cityVal : null,
                                                  pincode: pinVal.isNotEmpty ? pinVal : null,
                                                );
                                                setModalState(() {
                                                  remoteFilteredDoctors = res;
                                                  isFilteringApi = false;
                                                });
                                              }
                                            },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppTheme.primaryBlue,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      child: isFilteringApi
                                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                          : const Icon(Icons.filter_alt_rounded, size: 16),
                                    ),
                                    if (stateFilterController.text.isNotEmpty || cityFilterController.text.isNotEmpty || pincodeFilterController.text.isNotEmpty || remoteFilteredDoctors != null) ...[
                                      const SizedBox(width: 2),
                                      IconButton(
                                        icon: const Icon(Icons.clear_rounded, size: 18, color: Color(0xFFFE3434)),
                                        tooltip: 'Reset Filters',
                                        onPressed: () => setModalState(() {
                                          stateFilterController.clear();
                                          cityFilterController.clear();
                                          pincodeFilterController.clear();
                                          remoteFilteredDoctors = null;
                                        }),
                                      ),
                                    ],
                                  ],
                                );

                                if (isMobile) {
                                  return Column(
                                    children: [
                                      searchField,
                                      const SizedBox(height: 6),
                                      locationFieldsRow,
                                    ],
                                  );
                                }

                                return Row(
                                  children: [
                                    Expanded(flex: 2, child: searchField),
                                    const SizedBox(width: 4),
                                    Expanded(flex: 3, child: locationFieldsRow),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 8),

                            // Specialty & Availability Chips
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  // Specialty Chips
                                  ...<String>{
                                    'All',
                                    ..._problemService.activeSpecialtyNames,
                                    'Orthodontics',
                                    'Endodontics',
                                    'Periodontics',
                                  }.map((spec) {
                                    final isSel = selectedSpecialtyFilter == spec;
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 4),
                                      child: ChoiceChip(
                                        label: Text(spec, style: TextStyle(fontSize: 10, fontWeight: isSel ? FontWeight.bold : FontWeight.normal)),
                                        selected: isSel,
                                        selectedColor: AppTheme.primaryBlue.withValues(alpha: 0.15),
                                        labelStyle: TextStyle(color: isSel ? AppTheme.primaryBlue : AppTheme.textDark),
                                        onSelected: (val) {
                                          if (val) setModalState(() => selectedSpecialtyFilter = spec);
                                        },
                                      ),
                                    );
                                  }),
                                  const SizedBox(width: 6),
                                  // Availability Filter Chips
                                  ...['All Status', 'Available', 'In Consultation'].map((avail) {
                                    final key = avail == 'All Status' ? 'All' : avail;
                                    final isSel = selectedAvailabilityFilter == key;
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 4),
                                      child: ChoiceChip(
                                        label: Text(avail, style: TextStyle(fontSize: 10, fontWeight: isSel ? FontWeight.bold : FontWeight.normal)),
                                        selected: isSel,
                                        selectedColor: const Color(0xFF012A58).withValues(alpha: 0.2),
                                        labelStyle: TextStyle(color: isSel ? const Color(0xFF012A58) : AppTheme.textDark),
                                        onSelected: (val) {
                                          if (val) setModalState(() => selectedAvailabilityFilter = key);
                                        },
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Doctors List with Location Priority Hierarchy
                            Expanded(
                              child: filteredDoctors.isEmpty
                                  ? Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const Icon(Icons.person_search_rounded, size: 40, color: AppTheme.textMuted),
                                            const SizedBox(height: 8),
                                            const Text(
                                              'No Doctors Found in Location Range',
                                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              (cityFilterController.text.isNotEmpty || pincodeFilterController.text.isNotEmpty || stateFilterController.text.isNotEmpty)
                                                  ? 'No doctor matches state "${stateFilterController.text}", city "${cityFilterController.text}", or pincode "${pincodeFilterController.text}".'
                                                  : 'No doctor matches your location or filter criteria.',
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                            ),
                                            const SizedBox(height: 12),
                                            ElevatedButton.icon(
                                              onPressed: () {
                                                Navigator.of(dialogContext).pop();
                                                _showRegisterDoctorModal(context);
                                              },
                                              icon: const Icon(Icons.person_add_rounded, size: 16),
                                              label: const Text('Register Doctor in Location', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: AppTheme.primaryBlue,
                                                foregroundColor: Colors.white,
                                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                   : Column(
                                       children: [
                                         if (isShowingNearestFallback) ...[
                                           Container(
                                             margin: const EdgeInsets.only(bottom: 8),
                                             padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                             decoration: BoxDecoration(
                                               color: const Color(0x14FE3434),
                                               borderRadius: BorderRadius.circular(10),
                                               border: Border.all(color: const Color(0x40FE3434)),
                                             ),
                                             child: Row(
                                               children: [
                                                 const Icon(Icons.location_off_rounded, color: Color(0xFFFE3434), size: 16),
                                                 const SizedBox(width: 8),
                                                 Expanded(
                                                   child: Text(
                                                     'No doctor found directly in "${searchKeyword.isNotEmpty ? searchKeyword : cityFilterController.text.isNotEmpty ? cityFilterController.text : pincodeFilterController.text}". Showing nearest available doctors:',
                                                     style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFFFE3434)),
                                                   ),
                                                 ),
                                               ],
                                             ),
                                           ),
                                         ],
                                         Expanded(
                                           child: ListView.builder(
                                             itemCount: filteredDoctors.length,
                                             itemBuilder: (context, idx) {
                                               final doc = filteredDoctors[idx];
                                               final isSelected = selectedDoctor?.id == doc.id;
                                               final isSpecialtyMatch = req.problemCategory.toLowerCase().contains(doc.specialty.toLowerCase().split(' ').first);
                                               final tier = doc.getLocationMatchTier(req.state, req.city, req.pincode);
                                               final badgeLabel = doc.getLocationBadgeText(req.state, req.city, req.pincode);

                                               Color badgeBg = const Color(0xFFF1F5F9);
                                               Color badgeFg = const Color(0xFF475569);
                                               if (tier == 1) {
                                                 badgeBg = const Color(0x14012A58); // Emerald green for Same Pincode
                                                 badgeFg = const Color(0xFF012A58);
                                               } else if (tier == 2) {
                                                 badgeBg = const Color(0x14012A58); // Teal for Nearby Pincode
                                                 badgeFg = const Color(0xFF012A58);
                                               } else if (tier == 3) {
                                                 badgeBg = const Color(0x14012A58); // Blue for Same City
                                                 badgeFg = const Color(0xFF012A58);
                                               } else if (tier == 5) {
                                                 badgeBg = const Color(0x14FE3434); // Indigo for Same State
                                                 badgeFg = const Color(0xFF012A58);
                                               }

                                               return GestureDetector(
                                                 onTap: () => setModalState(() => selectedDoctor = doc),
                                                 child: Container(
                                                   margin: const EdgeInsets.only(bottom: 8),
                                                   padding: const EdgeInsets.all(10),
                                                   decoration: BoxDecoration(
                                                     color: isSelected ? const Color(0x14012A58) : Colors.white,
                                                     borderRadius: BorderRadius.circular(12),
                                                     border: Border.all(
                                                       color: isSelected ? AppTheme.primaryBlue : const Color(0xFFE2E8F0),
                                                       width: isSelected ? 2 : 1,
                                                     ),
                                                   ),
                                                   child: Row(
                                                     children: [
                                                       Radio<String>(
                                                         value: doc.id,
                                                         groupValue: selectedDoctor?.id,
                                                         activeColor: AppTheme.primaryBlue,
                                                         onChanged: (val) => setModalState(() => selectedDoctor = doc),
                                                       ),
                                                       Expanded(
                                                          child: Column(
                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                            children: [
                                                              // 1. DOCTOR NAME & STATUS ROW
                                                              Row(
                                                                children: [
                                                                  const Icon(Icons.medical_services_rounded, size: 15, color: AppTheme.primaryBlue),
                                                                  const SizedBox(width: 5),
                                                                  Expanded(
                                                                    child: Text(
                                                                      doc.name.isNotEmpty ? doc.name : (doc.clinicName.isNotEmpty ? 'Dr. ${doc.clinicName}' : 'Dr. Specialist'),
                                                                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, color: AppTheme.textDark),
                                                                      overflow: TextOverflow.ellipsis,
                                                                      maxLines: 1,
                                                                    ),
                                                                  ),
                                                                  const SizedBox(width: 4),
                                                                  Container(
                                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                                    decoration: BoxDecoration(
                                                                      color: doc.status == 'Available' ? const Color(0x14012A58) : const Color(0x14FE3434),
                                                                      borderRadius: BorderRadius.circular(6),
                                                                    ),
                                                                    child: Text(
                                                                      doc.status,
                                                                      style: TextStyle(
                                                                        fontSize: 9.5,
                                                                        fontWeight: FontWeight.bold,
                                                                        color: doc.status == 'Available' ? const Color(0xFF012A58) : const Color(0xFFFE3434),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                              const SizedBox(height: 4),

                                                              // 2. SPECIALTY & LOCATION MATCH BADGES WRAP
                                                              Wrap(
                                                                spacing: 5,
                                                                runSpacing: 4,
                                                                crossAxisAlignment: WrapCrossAlignment.center,
                                                                children: [
                                                                  Container(
                                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                                    decoration: BoxDecoration(
                                                                      color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                                                                      borderRadius: BorderRadius.circular(6),
                                                                    ),
                                                                    child: Text(
                                                                      '${doc.specialty} • ${doc.qualification}',
                                                                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                                                                    ),
                                                                  ),
                                                                  Container(
                                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                                    decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(6)),
                                                                    child: Text(badgeLabel, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: badgeFg)),
                                                                  ),
                                                                  if (isSpecialtyMatch)
                                                                    Container(
                                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                                      decoration: BoxDecoration(
                                                                        color: const Color(0x14FE3434),
                                                                        borderRadius: BorderRadius.circular(6),
                                                                        border: Border.all(color: const Color(0x40FE3434)),
                                                                      ),
                                                                      child: const Text('Matched Specialty', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFFFE3434))),
                                                                    ),
                                                                ],
                                                              ),
                                                              const SizedBox(height: 4),

                                                              // 3. CLINIC, PHONE, PINCODE & LOCATION
                                                              Text(
                                                                '${doc.clinicName.isNotEmpty ? "🏥 ${doc.clinicName} • " : ""}📞 ${doc.phone.isNotEmpty ? doc.phone : "No phone"}${doc.city.isNotEmpty ? " • 📍 ${doc.city}" : ""}${doc.pincode.isNotEmpty ? " (${doc.pincode})" : ""}',
                                                                style: const TextStyle(fontSize: 10.5, color: AppTheme.textMedium, fontWeight: FontWeight.w500),
                                                                overflow: TextOverflow.ellipsis,
                                                                maxLines: 1,
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
                            const SizedBox(height: 10),

                            Row(
                              children: [
                                OutlinedButton(
                                  onPressed: () => setModalState(() => currentStep = 1),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: const Text('Back'),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                                    label: const Text(
                                      'Step 3: Review & Dispatch',
                                      style: TextStyle(fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.primaryBlue,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    onPressed: () {
                                      if (selectedDoctor == null) {
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a doctor.')));
                                        return;
                                      }
                                      setModalState(() => currentStep = 3);
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                    // STEP 3: CONFIRMATION & DISPATCH
                    if (currentStep == 3)
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Doctor summary card
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0x14012A58),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppTheme.primaryBlue.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  children: [
                                    const CircleAvatar(
                                      backgroundColor: AppTheme.primaryBlue,
                                      child: Icon(Icons.medical_services_rounded, color: Colors.white, size: 20),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            selectedDoctor?.name ?? '',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                          Text(
                                            '${selectedDoctor?.specialty}',
                                            style: const TextStyle(fontSize: 11, color: AppTheme.primaryBlue),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                          Text(
                                            '🏥 ${selectedDoctor?.clinicName} • 📍 ${selectedDoctor?.clinicAddress} • 📞 ${selectedDoctor?.phone}',
                                            style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),

                              const Text('Admin Clinical Guidance / Recommendation Note:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textDark)),
                              const SizedBox(height: 6),
                              TextField(
                                controller: adminNotesController,
                                maxLines: 2,
                                style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                                cursorColor: AppTheme.primaryBlue,
                                onChanged: (val) => setModalState(() {}),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: const Color(0xFFF8FAFC),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  contentPadding: const EdgeInsets.all(12),
                                ),
                              ),
                              const SizedBox(height: 14),

                              // WhatsApp Preview Card
                              Container(
                                decoration: BoxDecoration(
                                  color: const Color(0x14012A58).withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: const Color(0x40012A58)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF012A58),
                                        borderRadius: BorderRadius.only(
                                          topLeft: Radius.circular(13),
                                          topRight: Radius.circular(13),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 15),
                                          const SizedBox(width: 8),
                                          const Expanded(
                                            child: Text(
                                              'WhatsApp Message Preview',
                                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                                            ),
                                          ),
                                          InkWell(
                                            onTap: () {
                                              Clipboard.setData(ClipboardData(text: waText));
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Message preview copied to clipboard!'), duration: Duration(seconds: 2)),
                                              );
                                            },
                                            child: const Row(
                                              children: [
                                                Icon(Icons.copy_rounded, color: Colors.white, size: 12),
                                                SizedBox(width: 4),
                                                Text('Copy', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Text(
                                        waText,
                                        style: const TextStyle(fontSize: 11.5, color: Color(0xFF012A58), height: 1.45),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Action buttons: Back, WhatsApp, SMS
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          icon: const Icon(Icons.chat_rounded, size: 16),
                                          label: const Text(
                                            'Send WhatsApp',
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF012A58),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 12),
                                            elevation: 2,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                          onPressed: () async {
                                            if (selectedDoctor == null) return;
                                            await _problemService.assignDoctorToRequest(
                                              requestId: req.id,
                                              doctor: selectedDoctor!,
                                              adminNotes: adminNotesController.text.trim(),
                                            );

                                            String rawPhone = req.patientPhone.replaceAll(RegExp(r'[^0-9]'), '');
                                            if (rawPhone.startsWith('0') && rawPhone.length == 11) {
                                              rawPhone = '91${rawPhone.substring(1)}';
                                            } else if (rawPhone.length == 10) {
                                              rawPhone = '91$rawPhone';
                                            }

                                            final waUrl = Uri.parse(rawPhone.isNotEmpty
                                                ? "https://wa.me/$rawPhone?text=${Uri.encodeComponent(waText)}"
                                                : "https://wa.me/?text=${Uri.encodeComponent(waText)}");
                                            try {
                                              await launchUrl(waUrl, mode: LaunchMode.externalApplication);
                                            } catch (e) {
                                              debugPrint('WhatsApp launcher info: $e');
                                            }

                                            if (!context.mounted) return;
                                            Navigator.of(dialogContext).pop();
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text('📱 Recommendation sent via WhatsApp to ${req.patientName}!'),
                                                backgroundColor: const Color(0xFF012A58),
                                                duration: const Duration(seconds: 3),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          icon: const Icon(Icons.sms_rounded, size: 16),
                                          label: const Text(
                                            'Send via SMS',
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF012A58),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 12),
                                            elevation: 2,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                          onPressed: () async {
                                            if (selectedDoctor == null) return;
                                            await _problemService.assignDoctorToRequest(
                                              requestId: req.id,
                                              doctor: selectedDoctor!,
                                              adminNotes: adminNotesController.text.trim(),
                                            );

                                            String rawPhone = req.patientPhone.replaceAll(RegExp(r'[^0-9]'), '');
                                            if (rawPhone.startsWith('0') && rawPhone.length == 11) {
                                              rawPhone = '91${rawPhone.substring(1)}';
                                            } else if (rawPhone.length == 10) {
                                              rawPhone = '91$rawPhone';
                                            }

                                            final smsUrl = Uri.parse(rawPhone.isNotEmpty
                                                ? "sms:$rawPhone?body=${Uri.encodeComponent(waText)}"
                                                : "sms:?body=${Uri.encodeComponent(waText)}");
                                            try {
                                              await launchUrl(smsUrl, mode: LaunchMode.externalApplication);
                                            } catch (e) {
                                              debugPrint('SMS launcher info: $e');
                                            }

                                            if (!context.mounted) return;
                                            Navigator.of(dialogContext).pop();
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text('✉️ Recommendation opened in SMS for ${req.patientName}!'),
                                                backgroundColor: const Color(0xFF012A58),
                                                duration: const Duration(seconds: 3),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton(
                                          onPressed: () => setModalState(() => currentStep = 2),
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(vertical: 10),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                          child: const Text('Back'),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextButton.icon(
                                          icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                                          label: const Text('Assign Only (No Message)', style: TextStyle(fontSize: 11.5)),
                                          style: TextButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(vertical: 10),
                                          ),
                                          onPressed: () async {
                                            if (selectedDoctor == null) return;
                                            await _problemService.assignDoctorToRequest(
                                              requestId: req.id,
                                              doctor: selectedDoctor!,
                                              adminNotes: adminNotesController.text.trim(),
                                            );
                                            if (!context.mounted) return;
                                            Navigator.of(dialogContext).pop();
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text('✅ Doctor ${selectedDoctor?.name} assigned to ${req.patientName}!'),
                                                backgroundColor: const Color(0xFF012A58),
                                                duration: const Duration(seconds: 3),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
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

  Widget _buildStepBadge(int stepNum, String title, bool isActive, bool isDone) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: isActive
            ? AppTheme.primaryBlue.withValues(alpha: 0.1)
            : (isDone ? const Color(0x14012A58) : Colors.transparent),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: isDone
                  ? const Color(0xFF012A58)
                  : isActive
                      ? AppTheme.primaryBlue
                      : const Color(0xFFCBD5E1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: isDone
                  ? const Icon(Icons.check_rounded, color: Colors.white, size: 12)
                  : Text('$stepNum', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive || isDone ? FontWeight.bold : FontWeight.w500,
                color: isActive ? AppTheme.primaryBlue : (isDone ? const Color(0xFF012A58) : AppTheme.textMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Use container width constraints to strictly determine Desktop side-by-side mode (requires >= 950px width!)
        final isDesktop = constraints.maxWidth >= 950;

        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          appBar: null,
          drawer: isDesktop ? null : Drawer(child: _buildSidebarContent()),
          body: Row(
            children: [
              // Sidebar Menu with Accordion Dropdowns ONLY when container width >= 950px
              if (isDesktop)
                Container(
                  width: 250,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(right: BorderSide(color: Color(0xFFE2E8F0))),
                  ),
                  child: _buildSidebarContent(),
                ),

              // Main Content Panel Area
              Expanded(
                child: Column(
                  children: [
                    // Sticky GS HEALTH Header on Mobile / Sub-Desktop
                    if (!isDesktop) _buildMobileGsHeader(context),
                    // Desktop Header Bar
                    if (isDesktop)
                      Container(
                        height: 64,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _getNavTitle(),
                                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const Text(
                                    'GS HEALTH Clinical Admin Portal',
                                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                Builder(
                                  builder: (context) {
                                    final adminNotifs = _problemService.getNotificationsForRole('Admin');
                                    final unreadCount = adminNotifs.where((n) => !n.isRead).length;

                                    return Stack(
                                      children: [
                                        IconButton(
                                          key: const Key('admin_desktop_notifications_button'),
                                          icon: const Icon(Icons.notifications_none_rounded, color: AppTheme.textDark, size: 22),
                                          onPressed: () => _showNotificationsModal(context, 'Admin'),
                                        ),
                                        if (unreadCount > 0)
                                          Positioned(
                                            right: 6,
                                            top: 6,
                                            child: IgnorePointer(
                                              child: Container(
                                                key: const Key('admin_desktop_unread_notifications_badge'),
                                                padding: const EdgeInsets.all(4),
                                                decoration: const BoxDecoration(color: Color(0xFFFE3434), shape: BoxShape.circle),
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
                                const SizedBox(width: 8),
                                ScaleTransition(
                                  scale: _pulseScaleAnimation,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0x14012A58),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text('Admin Mode', style: TextStyle(color: Color(0xFFFE3434), fontWeight: FontWeight.bold, fontSize: 11)),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                IconButton(
                                  icon: const Icon(Icons.logout_rounded, color: AppTheme.statusCancelText, size: 20),
                                  tooltip: 'Log Out',
                                  onPressed: () async {
                                    await SessionService().clearSession();
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Logged out of Admin Dashboard.'),
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                    context.go('/login');
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                    // Mobile Horizontal Navigation Bar Pills when viewing secondary console sections
                    if (!isDesktop && _selectedNavIndex != 0)
                      _buildMobileSectionPillsBar(),

                    // Active Panel View
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        child: _buildSelectedPanel(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: isDesktop
              ? null
              : BottomNavigationBar(
                  type: BottomNavigationBarType.fixed,
                  backgroundColor: Colors.white,
                  currentIndex: _getBottomNavIndex(),
                  selectedItemColor: AppTheme.gsNavy,
                  unselectedItemColor: AppTheme.textMuted,
                  selectedFontSize: 11,
                  unselectedFontSize: 11,
                  selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
                  onTap: (index) {
                    var target = _selectedNavIndex;
                    if (index == 0) target = 0; // Overview
                    if (index == 1) target = 13; // Requests
                    if (index == 2) target = 2; // Dentists
                    if (index == 3) target = 3; // Patients
                    _selectAdminNavSection(target);
                  },
                  items: const [
                    BottomNavigationBarItem(
                      icon: Icon(Icons.grid_view_outlined),
                      activeIcon: Icon(Icons.grid_view_rounded),
                      label: 'Overview',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.inbox_outlined),
                      activeIcon: Icon(Icons.inbox_rounded),
                      label: 'Requests',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.medical_services_outlined),
                      activeIcon: Icon(Icons.medical_services_rounded),
                      label: 'Doctors',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.people_outline_rounded),
                      activeIcon: Icon(Icons.people_alt_rounded),
                      label: 'Patients',
                    ),
                  ],
                ),
        );
      },
    );
  }

  void _selectAdminNavSection(int index, {bool showPendingOnly = false}) {
    setState(() {
      _showPendingVerificationOnly = showPendingOnly;
      if (index == 2) {
        _adminDoctorSpecialtyFilter = 'All';
      }
      _selectedNavIndex = index;
    });
    if (index == 2) {
      _problemService.syncDoctorsFromApi(includeUnavailable: true);
    }
  }

  Widget _buildMobileNavPill(int index, String label, IconData icon, {int badgeCount = 0}) {
    final isSelected = _selectedNavIndex == index;
    return GestureDetector(
      onTap: () => _selectAdminNavSection(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryBlue : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: isSelected ? Colors.white : AppTheme.textMedium),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: isSelected ? Colors.white : AppTheme.textDark,
              ),
            ),
            if (badgeCount > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : const Color(0xFFFE3434),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$badgeCount',
                  style: TextStyle(
                    color: isSelected ? AppTheme.primaryBlue : Colors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<DoctorModel> get _uniqueDoctors {
    final seenIds = <String>{};
    final seenUserIds = <String>{};
    final seenPhones = <String>{};
    final result = <DoctorModel>[];
    for (final d in _problemService.allDoctors) {
      final id = d.id.trim();
      final uid = d.userId.trim();
      final digits = d.phone.replaceAll(RegExp(r'\D'), '');
      final p10 = digits.length >= 10 ? digits.substring(digits.length - 10) : digits;
      if (id.isNotEmpty && !seenIds.add(id)) continue;
      if (uid.isNotEmpty && !seenUserIds.add(uid)) continue;
      if (p10.length >= 10 && !seenPhones.add(p10)) continue;
      result.add(d);
    }
    return result;
  }

  List<PatientProfile> get _uniquePatients {
    final seenIds = <String>{};
    final seenEmails = <String>{};
    final seenPhones = <String>{};
    final docIds = _problemService.allDoctors
        .expand((d) => [d.id.trim(), d.userId.trim()])
        .where((e) => e.isNotEmpty)
        .toSet();
    final result = <PatientProfile>[];
    for (final p in _problemService.allPatients) {
      final id = p.id.trim();
      final email = p.email.trim().toLowerCase();
      final digits = p.phone.replaceAll(RegExp(r'\D'), '');
      final p10 = digits.length >= 10 ? digits.substring(digits.length - 10) : digits;
      if (id.isNotEmpty && docIds.contains(id)) continue;
      if (email.contains('admin') && !email.contains('patient')) continue;
      if (id.isNotEmpty && !seenIds.add(id)) continue;
      if (email.isNotEmpty && !seenEmails.add(email)) continue;
      if (p10.length >= 10 && !seenPhones.add(p10)) continue;
      result.add(p);
    }
    return result;
  }

  List<ClinicModel> get _uniqueClinics {
    final seenIds = <String>{};
    final seenNames = <String>{};
    final result = <ClinicModel>[];
    for (final c in _problemService.allClinics) {
      final id = c.id.trim();
      final key = '${c.clinicName.trim().toLowerCase()}|${c.location.trim().toLowerCase()}';
      if (id.isNotEmpty && !seenIds.add(id)) continue;
      if (c.clinicName.trim().isNotEmpty && !seenNames.add(key)) continue;
      result.add(c);
    }
    return result;
  }

  List<Map<String, dynamic>> get _uniqueSubAdmins {
    final seenIds = <String>{};
    final seenEmails = <String>{};
    final result = <Map<String, dynamic>>[];
    for (final s in _problemService.subAdmins) {
      final id = (s['id'] ?? '').toString().trim();
      final email = (s['email'] ?? '').toString().trim().toLowerCase();
      if (id.isNotEmpty && !seenIds.add(id)) continue;
      if (email.isNotEmpty && !seenEmails.add(email)) continue;
      result.add(s);
    }
    return result;
  }

  List<Map<String, dynamic>> get _uniqueDistricts {
    final seenIds = <String>{};
    final seenNames = <String>{};
    final result = <Map<String, dynamic>>[];
    for (final d in _problemService.districts) {
      final id = (d['id'] ?? '').toString().trim();
      final name = (d['name'] ?? d['district_name'] ?? '').toString().trim().toLowerCase();
      if (id.isNotEmpty && !seenIds.add(id)) continue;
      if (name.isNotEmpty && !seenNames.add(name)) continue;
      result.add(d);
    }
    return result;
  }

  List<Map<String, dynamic>> get _uniqueAssignmentHistory {
    final seenIds = <String>{};
    final result = <Map<String, dynamic>>[];
    for (final h in _problemService.assignmentHistory) {
      final id = (h['id'] ?? '').toString().trim();
      if (id.isNotEmpty && !seenIds.add(id)) continue;
      result.add(h);
    }
    return result;
  }

  Future<void> _refreshOverviewData() async {
    if (mounted) {
      setState(() {
        _isOverviewLoading = true;
        _overviewError = null;
      });
    }
    try {
      final apptFuture = ApiService().fetchAllAppointmentsForAdmin();
      final liveSchedFuture = ApiService().fetchLiveSchedulingStatus();
      final rulesFuture = ApiService().fetchSchedulingRules();
      final syncFuture = _problemService.syncAllDataFromApi();

      // Apply appointments immediately as soon as they arrive
      final rows = await apptFuture;
      final liveSchedRes = await liveSchedFuture;
      await rulesFuture;
      if (mounted) {
        final earlyItems = deduplicateAdminAppointments(
          rows
              .whereType<Map>()
              .map(
                (r) => AdminAppointmentItem.fromRow(
                  r,
                  patients: _uniquePatients,
                  doctors: _uniqueDoctors,
                ),
              )
              .toList(),
        );
        setState(() {
          _overviewAppointments = earlyItems;
        });
      }

      await syncFuture;
      final items = deduplicateAdminAppointments(
        rows
            .whereType<Map>()
            .map(
              (r) => AdminAppointmentItem.fromRow(
                r,
                patients: _uniquePatients,
                doctors: _uniqueDoctors,
              ),
            )
            .toList(),
      );
      if (!mounted) return;
      setState(() {
        _overviewAppointments = items;
        if (liveSchedRes['doctors'] is List) {
          _liveDoctorSchedules = (liveSchedRes['doctors'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
        if (liveSchedRes['pendingRescheduleRequests'] is List) {
          _pendingRescheduleRequests = (liveSchedRes['pendingRescheduleRequests'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
        _isOverviewLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _overviewError = e.toString().replaceFirst('Exception: ', '');
        _isOverviewLoading = false;
      });
    }
  }

  Widget _buildMobileGsHeader(BuildContext context) {
    final adminNotifs = _problemService.getNotificationsForRole('Admin');
    final unreadCount = adminNotifs.where((n) => !n.isRead).length;
    return GsHealthAdminHeader(
      subtitle: 'Admin console',
      title: 'GS HEALTH',
      unreadCount: unreadCount,
      onNotifications: () => _showNotificationsModal(context, 'Admin'),
      onProfile: () => _openAdminProfile(context),
    );
  }

  void _openAdminProfile(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AdminProfileScreen()),
    );
  }

  Widget _buildMobileSectionPillsBar({bool embedded = false}) {
    final referralBadge = _problemService.adminPatientReferrals.where((r) => r.status == 'Pending').length;
    final row = Row(
      children: [
        _buildMobileNavPill(0, 'Overview', Icons.grid_view_rounded),
        _buildMobileNavPill(13, 'Requests', Icons.inbox_rounded),
        _buildMobileNavPill(11, 'Referrals', Icons.group_add_rounded, badgeCount: referralBadge),
        _buildMobileNavPill(3, 'Patients', Icons.people_outline_rounded),
        _buildMobileNavPill(1, 'Clinics', Icons.local_hospital_outlined),
        _buildMobileNavPill(12, 'Specialties', Icons.category_outlined),
        _buildMobileNavPill(2, 'Doctors', Icons.medical_services_outlined),
        _buildMobileNavPill(16, 'Doctor Calendar', Icons.calendar_month_rounded),
        _buildMobileNavPill(4, 'Appointments', Icons.calendar_month_outlined),
        _buildMobileNavPill(10, 'Chats', Icons.forum_outlined),
        _buildMobileNavPill(6, 'Reports', Icons.bar_chart_rounded),
        _buildMobileNavPill(9, 'Sub-Admins', Icons.supervisor_account_outlined),
        _buildMobileNavPill(14, 'Districts', Icons.map_outlined),
        _buildMobileNavPill(15, 'Assignments', Icons.assignment_ind_outlined),
      ],
    );
    if (embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Console sections',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.textMedium,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: row),
        ],
      );
    }
    return Container(
      height: 48,
      color: Colors.white,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: row,
      ),
    );
  }

  int _getBottomNavIndex() {
    if (_selectedNavIndex == 13) return 1;
    if (_selectedNavIndex == 2) return 2;
    if (_selectedNavIndex == 3) return 3;
    return 0;
  }

  String _getNavTitle() {
    switch (_selectedNavIndex) {
      case 0:
        return 'Overview';
      case 13:
        return 'Requests & Assignments';
      case 1:
        return 'Clinics Directory';
      case 2:
        return 'Doctors & Specialists Directory';
      case 3:
        return 'Patients Directory';
      case 4:
        return 'Appointments Schedule';
      case 6:
        return 'Reports & Specialty Analytics';
      case 7:
        return 'Patient Reviews';
      case 8:
        return 'System Settings';
      case 9:
        return 'Sub-Admin Management';
      case 10:
        return 'Patient-Doctor Chats';
      case 11:
        return 'Referral Management & Growth';
      case 12:
        return 'Medical Specialties Management';
      case 14:
        return 'District Management';
      case 15:
        return 'Patient Assignment Audit';
      case 16:
        return 'Doctor Calendar';
      default:
        return 'Admin Dashboard';
    }
  }

  // ==========================================
  // SIDEBAR WITH ACCORDION DROPDOWN CATEGORIES
  // ==========================================
  Widget _buildSidebarContent() {
    final pendingCount = _problemService.requests.where((r) => r.status == "Pending Admin Review").length;

    return Column(
      children: [
        const SizedBox(height: 18),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: DentaGuruLogo(height: 36),
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            children: [
              // CATEGORY 1: OVERVIEW & CONSULTATIONS DROPDOWN
              _buildSidebarDropdownCategory(
                categoryTitle: 'Overview & Care',
                categoryIcon: Icons.dashboard_customize_rounded,
                initiallyExpanded: true,
                children: [
                  _buildSubNavItem(0, Icons.grid_view_rounded, 'Dashboard Overview'),
                  _buildSubNavItem(0, Icons.mark_chat_read_rounded, 'Patient Problems', badgeCount: pendingCount),
                  _buildSubNavItem(10, Icons.forum_rounded, 'Patient-Doctor Chats'),
                ],
              ),

              const SizedBox(height: 8),

              // CATEGORY 2: CLINICAL MANAGEMENT DROPDOWN
              _buildSidebarDropdownCategory(
                categoryTitle: 'Clinical Operations',
                categoryIcon: Icons.local_hospital_rounded,
                initiallyExpanded: true,
                children: [
                  _buildSubNavItem(12, Icons.category_rounded, 'Medical Specialties', badgeCount: _problemService.activeSpecialties.length),
                  _buildSubNavItem(1, Icons.domain_rounded, 'Clinics Directory'),
                  _buildSubNavItem(2, Icons.medical_services_rounded, 'Doctors & Specialists'),
                  _buildSubNavItem(16, Icons.calendar_month_rounded, 'Doctor Calendar'),
                ],
              ),
              const SizedBox(height: 8),

              // CATEGORY 3: PATIENT CARE DROPDOWN
              _buildSidebarDropdownCategory(
                categoryTitle: 'Patient Operations',
                categoryIcon: Icons.people_alt_rounded,
                initiallyExpanded: false,
                children: [
                  _buildSubNavItem(3, Icons.person_search_rounded, 'Patients Directory'),
                  _buildSubNavItem(4, Icons.calendar_month_rounded, 'Appointments'),
                  _buildSubNavItem(11, Icons.group_add_rounded, 'Referral Management'),
                  _buildSubNavItem(7, Icons.star_rounded, 'Patient Reviews'),
                ],
              ),
              const SizedBox(height: 8),

              // CATEGORY 4: REPORTS & ANALYTICS DROPDOWN
              _buildSidebarDropdownCategory(
                categoryTitle: 'Reports & Analytics',
                categoryIcon: Icons.bar_chart_rounded,
                initiallyExpanded: false,
                children: [
                  _buildSubNavItem(6, Icons.bar_chart_rounded, 'Reports & Analytics'),
                  _buildSubNavItem(5, Icons.category_rounded, 'Specialty Reporting'),
                ],
              ),
              const SizedBox(height: 8),

              // CATEGORY 5: SYSTEM ADMIN DROPDOWN
              _buildSidebarDropdownCategory(
                categoryTitle: 'System Settings',
                categoryIcon: Icons.admin_panel_settings_rounded,
                initiallyExpanded: false,
                children: [
                  _buildSubNavItem(8, Icons.settings_rounded, 'General Settings'),
                  _buildSubNavItem(8, Icons.security_rounded, 'Role & Permissions'),
                  _buildSubNavItem(9, Icons.supervisor_account_rounded, 'Sub-Admins', badgeCount: _uniqueSubAdmins.length),
                  _buildSubNavItem(14, Icons.map_rounded, 'Districts', badgeCount: _problemService.districts.length),
                  _buildSubNavItem(15, Icons.assignment_ind_rounded, 'Assignments & Audit', badgeCount: _problemService.assignmentHistory.length),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSidebarDropdownCategory({
    required String categoryTitle,
    required IconData categoryIcon,
    required List<Widget> children,
    bool initiallyExpanded = false,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Material(
        color: const Color(0xFFF8FAFC),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          childrenPadding: const EdgeInsets.only(bottom: 6),
          leading: Icon(categoryIcon, size: 18, color: AppTheme.primaryBlue),
          title: Text(
            categoryTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
          children: children,
        ),
      ),
    );
  }

  Widget _buildSubNavItem(int index, IconData icon, String title, {int badgeCount = 0}) {
    final isSelected = _selectedNavIndex == index;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: isSelected ? AppTheme.primaryBlue : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        leading: Icon(
          icon,
          size: 16,
          color: isSelected ? Colors.white : AppTheme.textMedium,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.white : AppTheme.textMedium,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 12,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        trailing: badgeCount > 0
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : const Color(0xFFFE3434),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$badgeCount',
                  style: TextStyle(
                    color: isSelected ? AppTheme.primaryBlue : Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : null,
        onTap: () => _selectAdminNavSection(index),
        ),
      ),
    );
  }

  Widget _buildAppointmentsSchedulePanel() {
    final allDoctors = _uniqueDoctors;
    final List<AdminAppointmentItem> sourceAppointments = deduplicateAdminAppointments(_overviewAppointments);

    final filteredAppointments = sourceAppointments.where((a) {
      if (_adminApptStatusFilter != 'All') {
        final st = a.status.trim().toLowerCase();
        final target = _adminApptStatusFilter.toLowerCase();
        if (!st.contains(target)) return false;
      }
      if (_adminApptSpecialtyFilter != 'All') {
        if (a.doctorSpecialty.trim().toLowerCase() !=
            _adminApptSpecialtyFilter.toLowerCase()) {
          return false;
        }
      }
      if (_adminApptDoctorFilter != 'All') {
        if (a.dentistName.trim().toLowerCase() !=
            _adminApptDoctorFilter.toLowerCase()) {
          return false;
        }
      }
      if (_adminApptDateFilter.trim().isNotEmpty) {
        if (!a.dateRaw.contains(_adminApptDateFilter.trim())) {
          return false;
        }
      }
      final q = _adminApptSearchQuery.trim().toLowerCase();
      if (q.isEmpty) return true;
      return a.patientName.toLowerCase().contains(q) ||
          a.phone.toLowerCase().contains(q) ||
          a.dentistName.toLowerCase().contains(q) ||
          a.doctorSpecialty.toLowerCase().contains(q) ||
          a.clinicName.toLowerCase().contains(q) ||
          a.treatment.toLowerCase().contains(q);
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final bool isWideDesktop = width >= 980;
        final bool isCompactMobile = width < 600;
        final double hPad = isCompactMobile ? 14 : 24;

        return RefreshIndicator(
          color: AppTheme.gsNavy,
          onRefresh: _refreshOverviewData,
          child: SingleChildScrollView(
            key: const Key('admin_appointments_panel_scroll'),
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            padding: EdgeInsets.all(hPad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Responsive Top Banner Card
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(isCompactMobile ? 16 : 20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryBlue.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Booked Appointments & Doctor Schedule',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: isCompactMobile ? 16 : 18,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Verified patient bookings showing exact selected doctor, clinic, slot, and schedule controls',
                                  style: TextStyle(color: Colors.white70, fontSize: 12),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () => DoctorSlotManagementDialog.show(context),
                            icon: const Icon(Icons.tune_rounded, size: 16),
                            label: const Text('Manage Doctor Slots', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryBlue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          ElevatedButton.icon(
                            key: const Key('admin_configure_hybrid_rules_btn'),
                            onPressed: _showHybridRulesConfigDialog,
                            icon: const Icon(Icons.timer_outlined, size: 16),
                            label: const Text('Hybrid Rules & Buffers', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F766E),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _isOverviewLoading ? null : _refreshOverviewData,
                            icon: const Icon(Icons.refresh_rounded, size: 16, color: Colors.white),
                            label: const Text('Refresh Bookings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5)),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),

                // 1b. Live Hybrid Doctor Monitor & Pending Reschedule Requests
                _buildHybridSchedulingMonitorSection(sourceAppointments, allDoctors),
                const SizedBox(height: 22),

                // 2. Booked Appointments Header + Search & Filters
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Patient Booked Appointments',
                        style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: AppTheme.textDark),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0x14012A58),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${filteredAppointments.length} Total',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.gsNavy),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Search & Status Filter Bar
                TextField(
                  key: const Key('admin_appointments_search_field'),
                  onChanged: (val) => setState(() => _adminApptSearchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Search patient, mobile, selected doctor, specialty, or clinic...',
                    hintStyle: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppTheme.gsNavy),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['All', 'Pending', 'Confirmed', 'Completed', 'Cancelled'].map((statusOpt) {
                      final selected = _adminApptStatusFilter == statusOpt;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(statusOpt),
                          selected: selected,
                          selectedColor: AppTheme.gsNavy,
                          backgroundColor: Colors.white,
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                          labelStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: selected ? Colors.white : AppTheme.textDark,
                          ),
                          onSelected: (_) => setState(() => _adminApptStatusFilter = statusOpt),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 10),
                Builder(
                  builder: (_) {
                    final specOptions = <String>{
                      'All',
                      ...sourceAppointments
                          .map((a) => a.doctorSpecialty.trim())
                          .where((s) => s.isNotEmpty),
                    }.toList();
                    final docOptions = <String>{
                      'All',
                      ...sourceAppointments
                          .map((a) => a.dentistName.trim())
                          .where((d) => d.isNotEmpty),
                    }.toList();
                    final safeSpec = specOptions.contains(_adminApptSpecialtyFilter)
                        ? _adminApptSpecialtyFilter
                        : 'All';
                    final safeDoc = docOptions.contains(_adminApptDoctorFilter)
                        ? _adminApptDoctorFilter
                        : 'All';
                    return Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 165),
                          child: DropdownButton<String>(
                            key: const Key('admin_appt_specialty_filter'),
                            value: safeSpec,
                            isExpanded: true,
                            underline: const SizedBox.shrink(),
                            items: specOptions
                                .map((s) => DropdownMenuItem(
                                      value: s,
                                      child: Text(
                                        s == 'All' ? 'All Specialties' : s,
                                        style: const TextStyle(fontSize: 12),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ))
                                .toList(),
                            onChanged: (v) => setState(() => _adminApptSpecialtyFilter = v ?? 'All'),
                          ),
                        ),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 165),
                          child: DropdownButton<String>(
                            key: const Key('admin_appt_doctor_filter'),
                            value: safeDoc,
                            isExpanded: true,
                            underline: const SizedBox.shrink(),
                            items: docOptions
                                .map((d) => DropdownMenuItem(
                                      value: d,
                                      child: Text(
                                        d == 'All' ? 'All Doctors' : d,
                                        style: const TextStyle(fontSize: 12),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ))
                                .toList(),
                            onChanged: (v) => setState(() => _adminApptDoctorFilter = v ?? 'All'),
                          ),
                        ),
                        OutlinedButton.icon(
                          key: const Key('admin_appt_date_filter_btn'),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime(2024),
                              lastDate: DateTime(2030),
                            );
                            if (picked != null && mounted) {
                              final ymd =
                                  '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                              setState(() => _adminApptDateFilter = ymd);
                            }
                          },
                          icon: const Icon(Icons.date_range_outlined, size: 15),
                          label: Text(
                            _adminApptDateFilter.isEmpty ? 'Date' : _adminApptDateFilter,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        if (_adminApptSpecialtyFilter != 'All' ||
                            _adminApptDoctorFilter != 'All' ||
                            _adminApptDateFilter.isNotEmpty)
                          TextButton(
                            key: const Key('admin_appt_clear_filters_btn'),
                            onPressed: () => setState(() {
                              _adminApptSpecialtyFilter = 'All';
                              _adminApptDoctorFilter = 'All';
                              _adminApptDateFilter = '';
                            }),
                            child: const Text('Clear filters', style: TextStyle(fontSize: 12)),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),

                if (_isOverviewLoading && sourceAppointments.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(28),
                      child: CircularProgressIndicator(color: AppTheme.gsNavy),
                    ),
                  )
                else if (filteredAppointments.isEmpty)
                  Container(
                    key: const Key('admin_appointments_schedule_empty'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.event_busy_rounded, color: AppTheme.textMuted, size: 24),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'No matching patient appointments found.',
                            style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (isWideDesktop)
                  _buildDesktopAppointmentsTable(filteredAppointments)
                else
                  Column(
                    children: filteredAppointments
                        .map((item) => _buildResponsiveAppointmentCard(item))
                        .toList(),
                  ),

                const SizedBox(height: 26),

                // 2b. Admin Global Visits & Hospitals Monthly Calendar
                AdminGlobalVisitsCalendarSection(
                  appointments: sourceAppointments,
                  clinics: _uniqueClinics,
                  doctors: allDoctors,
                  patients: _uniquePatients,
                  referrals: _problemService.adminPatientReferrals,
                ),

                // 3. Doctor Working Hours & Availability Roster
                const Text(
                  'Doctor Working Hours & Availability Roster',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                ),
                const SizedBox(height: 12),

                if (allDoctors.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Center(
                      child: Text(
                        'No registered platform doctors available yet.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.textMuted),
                      ),
                    ),
                  )
                else
                  ...allDoctors.map((doc) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2)),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AdminDoctorAvatar(
                                doctorName: doc.name,
                                photoBytes: doc.photoBytes,
                                radius: 22,
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
                                            doc.name,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: doc.isAvailable ? const Color(0x14012A58) : const Color(0xFFF1F5F9),
                                            borderRadius: BorderRadius.circular(999),
                                          ),
                                          child: Text(
                                            doc.isAvailable ? 'ON' : 'OFF',
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w800,
                                              color: doc.isAvailable ? const Color(0xFF012A58) : const Color(0xFF64748B),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${doc.specialty} • ${doc.clinicName.isNotEmpty ? doc.clinicName : "Clinic Not Listed"}',
                                      style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              if (!isCompactMobile) ...[
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  onPressed: () => DoctorSlotManagementDialog.show(context, initialDoctor: doc),
                                  icon: const Icon(Icons.edit_calendar_rounded, size: 15),
                                  label: const Text('Configure Slots', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0F172A),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: doc.nextAvailableSlots.isEmpty
                                ? [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'No slots configured',
                                        style: TextStyle(fontSize: 10.5, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                  ]
                                : doc.nextAvailableSlots.take(3).map((s) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(s, style: const TextStyle(fontSize: 10.5, color: Color(0xFF475569), fontWeight: FontWeight.w600)),
                                    );
                                  }).toList(),
                          ),
                          if (isCompactMobile) ...[
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () => DoctorSlotManagementDialog.show(context, initialDoctor: doc),
                                icon: const Icon(Icons.edit_calendar_rounded, size: 15),
                                label: const Text('Configure Slots', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0F172A),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHybridSchedulingMonitorSection(
    List<AdminAppointmentItem> appointments,
    List<dynamic> doctors,
  ) {
    List<Map<String, dynamic>> activeLive = _liveDoctorSchedules;
    List<Map<String, dynamic>> pendingReschedules = _pendingRescheduleRequests;

    if (activeLive.isEmpty && appointments.isNotEmpty) {
      final byDoc = <String, List<AdminAppointmentItem>>{};
      for (final a in appointments) {
        final s = a.status.toUpperCase();
        if (s == 'CANCELLED' || s == 'REJECTED' || s == 'NO_SHOW') continue;
        final key = a.dentistId.trim().isNotEmpty ? a.dentistId.trim() : a.dentistName.trim();
        if (key.isEmpty) continue;
        byDoc.putIfAbsent(key, () => []).add(a);
      }
      final synthesized = <Map<String, dynamic>>[];
      byDoc.forEach((key, docAppts) {
        final current = docAppts.first;
        final next = docAppts.length > 1 ? docAppts[1] : null;
        final st = current.status.toUpperCase();
        final isOnline = current.mode.toUpperCase().contains('ONLINE') ||
            current.treatment.toUpperCase().contains('ONLINE');
        final consultType = isOnline ? 'Online' : 'In-Person';
        String avail = 'Available';
        if (st == 'DELAYED' || current.delayMinutes > 0) {
          avail = 'Delayed';
        } else if (st == 'IN_PROGRESS') {
          avail = isOnline ? 'Busy – Online Consultation' : 'Busy – In-Person Consultation';
        }
        synthesized.add({
          'doctorId': current.dentistId,
          'doctorName': current.dentistName,
          'currentAvailability': avail,
          'delayDurationMinutes': current.delayMinutes,
          'currentAppointment': {
            'id': current.id,
            'patientName': current.patientName,
            'consultationType': consultType,
            'scheduledStartTime': current.timeSlot,
            'scheduledEndTime': current.scheduledEndTime.isNotEmpty ? current.scheduledEndTime : null,
            'actualStartAt': current.actualStartAt.isNotEmpty ? current.actualStartAt : null,
            'actualEndAt': current.actualEndAt.isNotEmpty ? current.actualEndAt : null,
            'delayMinutes': current.delayMinutes,
          },
          if (next != null)
            'nextAppointment': {
              'id': next.id,
              'patientName': next.patientName,
              'consultationType': (next.mode.toUpperCase().contains('ONLINE') ||
                      next.treatment.toUpperCase().contains('ONLINE'))
                  ? 'Online'
                  : 'In-Person',
              'scheduledStartTime': next.timeSlot,
              'scheduledEndTime': next.scheduledEndTime.isNotEmpty ? next.scheduledEndTime : null,
              'estimatedStartTime': next.estimatedStartTime.isNotEmpty ? next.estimatedStartTime : null,
            },
        });
      });
      activeLive = synthesized;
    }

    if (pendingReschedules.isEmpty && appointments.isNotEmpty) {
      pendingReschedules = appointments
          .where((a) => a.rescheduleRequestStatus.toUpperCase() == 'PENDING')
          .map((a) => {
                'appointmentId': a.id,
                'patientName': a.patientName,
                'doctorName': a.dentistName,
                'requestedDate': a.rescheduleRequestedDate,
                'requestedTimeSlot': a.rescheduleRequestedSlot,
                'reason': a.rescheduleRequestReason,
              })
          .toList();
    }

    return Container(
      key: const Key('admin_hybrid_scheduling_monitor'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hub_outlined, size: 18, color: Color(0xFF0F766E)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Live Hybrid Doctor Calendar & Delay Monitor',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (pendingReschedules.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${pendingReschedules.length} Reschedule Req',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF92400E),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _hybridRuleBadge('In-Person: ${BookingRulesConfig.inPersonDurationMinutes}m + ${BookingRulesConfig.inPersonBufferMinutes}m buf'),
              _hybridRuleBadge('Online: ${BookingRulesConfig.onlineDurationMinutes}m + ${BookingRulesConfig.onlineBufferMinutes}m buf'),
              _hybridRuleBadge('Interval: ${BookingRulesConfig.defaultSlotIntervalMinutes}m'),
              _hybridRuleBadge('Delay Alert: ${BookingRulesConfig.adminDelayAlertThresholdMinutes}m'),
            ],
          ),
          const SizedBox(height: 12),
          if (activeLive.isEmpty)
            const Text(
              'No live doctor consultations active right now.',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
            )
          else
            Column(
              children: activeLive.map((doc) {
                final docName = (doc['doctorName'] ?? doc['name'] ?? 'Doctor').toString();
                final availability = (doc['currentAvailability'] ?? 'Available').toString();
                final delayMin = int.tryParse('${doc['delayDurationMinutes'] ?? 0}') ?? 0;
                final currentAppt = doc['currentAppointment'] as Map<String, dynamic>?;
                final nextAppt = doc['nextAppointment'] as Map<String, dynamic>?;
                final isDelayed = delayMin > 0 || availability.toLowerCase().contains('delay');

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDelayed ? const Color(0xFFFFFBEB) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDelayed ? const Color(0xFFFCD34D) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              docName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                                color: Color(0xFF0F172A),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isDelayed
                                  ? const Color(0xFFFEE2E2)
                                  : availability.startsWith('Busy')
                                      ? const Color(0xFFDBEAFE)
                                      : const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              availability,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isDelayed
                                    ? const Color(0xFF991B1B)
                                    : availability.startsWith('Busy')
                                        ? const Color(0xFF1E40AF)
                                        : const Color(0xFF166534),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (currentAppt != null)
                        Builder(
                          builder: (_) {
                            final startStr = (currentAppt['scheduledStartTime'] ??
                                    currentAppt['scheduledStart'] ??
                                    currentAppt['timeSlot'] ??
                                    '')
                                .toString();
                            final endStr = (currentAppt['scheduledEndTime'] ??
                                    currentAppt['scheduledEnd'] ??
                                    '')
                                .toString();
                            final cType = (currentAppt['consultationMode'] ??
                                    currentAppt['consultationType'] ??
                                    'In-Person')
                                .toString();
                            final pName = (currentAppt['patientName'] ?? '').toString().trim();
                            return Text(
                              'Current: ${pName.isNotEmpty ? '$pName • ' : ''}$cType'
                              ' • $startStr'
                              '${endStr.isNotEmpty ? '–$endStr' : ''}'
                              '${currentAppt['actualStartAt'] != null ? ' (Started)' : ''}'
                              '${currentAppt['actualEndAt'] != null ? ' (Completed)' : ''}'
                              '${delayMin > 0 ? ' • Delayed +${delayMin}m' : ''}',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF334155)),
                            );
                          },
                        ),
                      if (nextAppt != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Builder(
                            builder: (_) {
                              final nextStart = (nextAppt['scheduledStartTime'] ??
                                      nextAppt['scheduledStart'] ??
                                      nextAppt['timeSlot'] ??
                                      '')
                                  .toString();
                              final nextEnd = (nextAppt['scheduledEndTime'] ??
                                      nextAppt['scheduledEnd'] ??
                                      '')
                                  .toString();
                              final nextType = (nextAppt['consultationMode'] ??
                                      nextAppt['consultationType'] ??
                                      'In-Person')
                                  .toString();
                              final estStart = (nextAppt['estimatedStartTime'] ?? '').toString();
                              return Text(
                                'Next: ${nextAppt['patientName'] ?? 'Patient'} • $nextType at $nextStart'
                                '${nextEnd.isNotEmpty ? '–$nextEnd' : ''}'
                                '${estStart.isNotEmpty ? ' (Est: $estStart)' : ''}',
                                style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569)),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                );
              }).toList(),
            ),
          if (pendingReschedules.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              'Pending Reschedule Requests',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF92400E)),
            ),
            const SizedBox(height: 6),
            ...pendingReschedules.map((req) {
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEFCE8),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFDE047)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.schedule_send_outlined, size: 16, color: Color(0xFFA16207)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${req['patientName'] ?? 'Patient'} with ${req['doctorName'] ?? 'Doctor'}'
                        ' • Requested ${req['requestedDate'] ?? ''} ${req['requestedTimeSlot'] ?? ''}'
                        '${(req['reason'] ?? '').toString().isNotEmpty ? ' (${req['reason']})' : ''}',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF713F12)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _hybridRuleBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
      ),
    );
  }

  Future<void> _showHybridRulesConfigDialog() async {
    final inPersonDurCtrl = TextEditingController(text: '${BookingRulesConfig.inPersonDurationMinutes}');
    final onlineDurCtrl = TextEditingController(text: '${BookingRulesConfig.onlineDurationMinutes}');
    final inPersonBufCtrl = TextEditingController(text: '${BookingRulesConfig.inPersonBufferMinutes}');
    final onlineBufCtrl = TextEditingController(text: '${BookingRulesConfig.onlineBufferMinutes}');
    final intervalCtrl = TextEditingController(text: '${BookingRulesConfig.defaultSlotIntervalMinutes}');
    final minAdvanceCtrl = TextEditingController(text: '${BookingRulesConfig.minAdvanceBookingMinutes}');
    final maxWindowCtrl = TextEditingController(text: '${BookingRulesConfig.maxAdvanceBookingDays}');
    final delayThreshCtrl = TextEditingController(text: '${BookingRulesConfig.adminDelayAlertThresholdMinutes}');
    bool saving = false;
    String? errorMsg;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Configure Hybrid Scheduling Rules'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      key: const Key('rule_inperson_duration_input'),
                      controller: inPersonDurCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'In-Person Consultation Duration (min)'),
                    ),
                    TextField(
                      key: const Key('rule_online_duration_input'),
                      controller: onlineDurCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Online Consultation Duration (min)'),
                    ),
                    TextField(
                      key: const Key('rule_inperson_buffer_input'),
                      controller: inPersonBufCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'In-Person Buffer Time (min)'),
                    ),
                    TextField(
                      key: const Key('rule_online_buffer_input'),
                      controller: onlineBufCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Online Buffer Time (min)'),
                    ),
                    TextField(
                      key: const Key('rule_slot_interval_input'),
                      controller: intervalCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Slot Interval (min)'),
                    ),
                    TextField(
                      key: const Key('rule_min_advance_input'),
                      controller: minAdvanceCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Minimum Advance Booking (min)'),
                    ),
                    TextField(
                      key: const Key('rule_max_window_input'),
                      controller: maxWindowCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Maximum Advance Booking Window (days)'),
                    ),
                    TextField(
                      key: const Key('rule_delay_threshold_input'),
                      controller: delayThreshCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Admin Delay Alert Threshold (min)'),
                    ),
                    if (errorMsg != null) ...[
                      const SizedBox(height: 8),
                      Text(errorMsg!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                key: const Key('save_hybrid_rules_btn'),
                onPressed: saving
                    ? null
                    : () async {
                        setDialogState(() {
                          saving = true;
                          errorMsg = null;
                        });
                        final payload = <String, dynamic>{
                          'inPersonDurationMinutes': int.tryParse(inPersonDurCtrl.text.trim()) ?? BookingRulesConfig.inPersonDurationMinutes,
                          'onlineDurationMinutes': int.tryParse(onlineDurCtrl.text.trim()) ?? BookingRulesConfig.onlineDurationMinutes,
                          'inPersonBufferMinutes': int.tryParse(inPersonBufCtrl.text.trim()) ?? BookingRulesConfig.inPersonBufferMinutes,
                          'onlineBufferMinutes': int.tryParse(onlineBufCtrl.text.trim()) ?? BookingRulesConfig.onlineBufferMinutes,
                          'defaultSlotIntervalMinutes': int.tryParse(intervalCtrl.text.trim()) ?? BookingRulesConfig.defaultSlotIntervalMinutes,
                          'minAdvanceBookingMinutes': int.tryParse(minAdvanceCtrl.text.trim()) ?? BookingRulesConfig.minAdvanceBookingMinutes,
                          'maxAdvanceBookingDays': int.tryParse(maxWindowCtrl.text.trim()) ?? BookingRulesConfig.maxAdvanceBookingDays,
                          'adminDelayAlertThresholdMinutes': int.tryParse(delayThreshCtrl.text.trim()) ?? BookingRulesConfig.adminDelayAlertThresholdMinutes,
                        };
                        final res = await PatientProblemService().updateSchedulingRules(payload);
                        if (!ctx.mounted) return;
                        if (res['success'] == true) {
                          BookingRulesConfig.applyFromJson(payload);
                          Navigator.of(ctx).pop();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Hybrid scheduling rules saved.')),
                            );
                            await _refreshOverviewData();
                          }
                        } else {
                          setDialogState(() {
                            saving = false;
                            errorMsg = (res['message'] ?? 'Failed to save scheduling rules').toString();
                          });
                        }
                      },
                child: saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save Rules'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDesktopAppointmentsTable(List<AdminAppointmentItem> appointments) {
    return Container(
      key: const Key('admin_appointments_desktop_table'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          showCheckboxColumn: false,
          columnSpacing: 18,
          dataRowMinHeight: 62,
          dataRowMaxHeight: 78,
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
          columns: const [
            DataColumn(label: Text('Patient', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
            DataColumn(label: Text('Selected Doctor', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
            DataColumn(label: Text('Clinic', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
            DataColumn(label: Text('Appt. Date & Time', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
            DataColumn(label: Text('Booked On', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
            DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
            DataColumn(label: Text('Action', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
          ],
          rows: appointments.map((item) {
            final statusColors = adminStatusColors(item.status);
            final displayDoc = item.dentistName.isNotEmpty ? item.dentistName : 'Doctor Unavailable';
            final displaySpec = item.doctorSpecialty.isNotEmpty ? item.doctorSpecialty : 'Specialty Not Listed';
            final displayClinic = item.clinicName.isNotEmpty ? item.clinicName : 'Clinic Not Listed';
            return DataRow(
              onSelectChanged: (_) => showAdminAppointmentDetailsSheet(context, item, canViewPhone: true),
              cells: [
                DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 165),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.patientName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppTheme.textDark),
                        ),
                        Text(
                          item.phone.isNotEmpty ? item.phone : 'No mobile',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                ),
                DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 215),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AdminDoctorAvatar(
                          doctorName: displayDoc,
                          photoBytes: item.doctorPhotoBytes,
                          photoUrl: item.doctorPhotoUrl,
                          radius: 16,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayDoc,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppTheme.gsNavy),
                              ),
                              Text(
                                displaySpec,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: Text(
                      displayClinic,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppTheme.textDark, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 155),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          formatAdminAppointmentDate(item.dateRaw),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppTheme.textDark),
                        ),
                        Text(
                          item.timeSlot.isNotEmpty ? item.timeSlot : 'Time not set',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppTheme.primaryBlue),
                        ),
                      ],
                    ),
                  ),
                ),
                DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 145),
                    child: Text(
                      formatAdminCreatedDateTime(item.createdAtRaw),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                    ),
                  ),
                ),
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColors.bg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      adminStatusLabel(item.status),
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: statusColors.fg),
                    ),
                  ),
                ),
                DataCell(
                  TextButton(
                    onPressed: () => showAdminAppointmentDetailsSheet(context, item, canViewPhone: true),
                    child: const Text('Details', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildResponsiveAppointmentCard(AdminAppointmentItem item) {
    final statusColors = adminStatusColors(item.status);
    final isExpanded = _expandedAppointmentIds.contains(item.id);
    final displayDoc = item.dentistName.isNotEmpty ? item.dentistName : 'Doctor Unavailable';
    final displaySpec = item.doctorSpecialty.isNotEmpty ? item.doctorSpecialty : 'Specialty Not Listed';
    final displayClinic = item.clinicName.isNotEmpty ? item.clinicName : 'Clinic Not Listed';

    return Container(
      key: Key('admin_schedule_appointment_card_${item.id}'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.025), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Patient Name + Status Badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.patientName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.textDark),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.phone.isNotEmpty ? item.phone : 'Mobile not provided',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: AppTheme.textMedium),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColors.bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  adminStatusLabel(item.status),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: statusColors.fg),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Selected Doctor Tile (Photo + Name + Specialization + Clinic)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                AdminDoctorAvatar(
                  doctorName: displayDoc,
                  photoBytes: item.doctorPhotoBytes,
                  photoUrl: item.doctorPhotoUrl,
                  radius: 19,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayDoc,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppTheme.gsNavy),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        displaySpec,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: AppTheme.textMedium, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        displayClinic,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Appointment Date & Time + Booking Created Time
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0x14012A58),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${formatAdminAppointmentDate(item.dateRaw)} • ${item.timeSlot.isNotEmpty ? item.timeSlot : "Time not set"}',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppTheme.primaryBlue),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Booked: ${formatAdminCreatedDateTime(item.createdAtRaw)}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                ),
              ),
            ],
          ),

          if (isExpanded) ...[
            const Divider(height: 18, color: Color(0xFFE2E8F0)),
            if (item.treatment.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Treatment: ${item.treatment}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textDark, fontWeight: FontWeight.w600),
                ),
              ),
            if (item.notes.isNotEmpty)
              Text(
                'Notes: ${item.notes}',
                style: const TextStyle(fontSize: 12, color: AppTheme.textMedium),
              ),
          ],
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    if (isExpanded) {
                      _expandedAppointmentIds.remove(item.id);
                    } else {
                      _expandedAppointmentIds.add(item.id);
                    }
                  });
                },
                icon: Icon(isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18),
                label: Text(isExpanded ? 'Less' : 'More', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              TextButton(
                onPressed: () => showAdminAppointmentDetailsSheet(context, item, canViewPhone: true),
                child: const Text('Full Details', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.gsNavy)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedPanel() {
    switch (_selectedNavIndex) {
      case 0:
        return _buildAdminOverviewPanel();
      case 1:
        return _buildClinicsPanel();
      case 2:
        return _buildDentistsPanel();
      case 3:
        return _buildPatientsPanel();
      case 4:
        return _buildAppointmentsSchedulePanel();
      case 5:
        return _buildSpecialtyReportingPanel();
      case 6:
        return GsHealthDistrictReportsPanel(problemService: _problemService, onRefresh: _refreshOverviewData);
      case 8:
      case 9:
        return _buildSubAdminsPanel();
      case 10:
        return _buildPatientDoctorChatsPanel();
      case 11:
        return _buildReferralManagementPanel();
      case 12:
        return _buildMedicalSpecialtiesPanel();
      case 13:
        return _buildDashboardPanel();
      case 14:
        return GsHealthDistrictManagementPanel(problemService: _problemService, onRefresh: _refreshOverviewData);
      case 15:
        return GsHealthPatientAssignmentPanel(problemService: _problemService, onRefresh: _refreshOverviewData);
      case 16:
        return AdminDoctorActivityCalendarSection(problemService: _problemService);
      default:
        return _buildAdminOverviewPanel();
    }
  }

  Widget _buildAdminOverviewPanel() {
    final waiting = waitingConsultationRequests(_problemService.requests);
    final doctors = _uniqueDoctors;
    final patients = _uniquePatients;
    final clinics = _uniqueClinics;
    final subAdmins = _uniqueSubAdmins;
    final districts = _uniqueDistricts;
    final assignments = _uniqueAssignmentHistory;
    final pendingDocs = doctors.where(isPendingVerificationDoctor).toList();
    final ads = sponsoredAdsForOverview();
    final appointments = deduplicateAdminAppointments(_overviewAppointments);
    final appointmentCount = appointments.length;
    final pendingAppointmentsCount = appointments.where((a) {
      final st = a.status.trim().toLowerCase();
      return st == 'pending' || st.contains('review') || st.contains('requested');
    }).length;
    final completedAppointmentsCount = appointments.where((a) => a.status.trim().toLowerCase() == 'completed').length;
    final cancelledAppointmentsCount = appointments.where((a) {
      final st = a.status.trim().toLowerCase();
      return st == 'cancelled' || st == 'rejected';
    }).length;
    final allReferrals = _problemService.adminPatientReferrals;
    final pendingReferralsCount = allReferrals.where((r) => r.status.trim().toLowerCase() == 'pending').length;
    final activeCoordinatorsCount = subAdmins.where((s) => (s['status'] ?? 'Active').toString().toLowerCase() == 'active').length;
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    return GsHealthAdminOverview(
      isLoading: _isOverviewLoading,
      errorMessage: _overviewError,
      onRetry: _refreshOverviewData,
      onRefresh: _refreshOverviewData,
      waitingCount: waiting.length,
      onAssign: () {
        if (waiting.length == 1) {
          _showAssignDoctorDialog(context, waiting.first);
        } else {
          setState(() => _selectedNavIndex = 13);
        }
      },
      stats: [
        AdminStatCardData(
          id: 'waiting',
          label: 'Requests awaiting a doctor',
          value: waiting.length,
          icon: Icons.hourglass_bottom_rounded,
          accentRed: true,
          onTap: () => setState(() => _selectedNavIndex = 13),
        ),
        AdminStatCardData(
          id: 'pending_doctors',
          label: 'Doctors pending verification',
          value: pendingDocs.length,
          icon: Icons.verified_user_outlined,
          accentRed: pendingDocs.isNotEmpty,
          onTap: () => _selectAdminNavSection(2, showPendingOnly: true),
        ),
        AdminStatCardData(
          id: 'patients',
          label: 'Patients',
          value: patients.length,
          icon: Icons.people_outline_rounded,
          onTap: () => setState(() => _selectedNavIndex = 3),
        ),
        AdminStatCardData(
          id: 'dentists',
          label: 'Doctors',
          value: doctors.length,
          icon: Icons.medical_services_outlined,
          onTap: () => _selectAdminNavSection(2),
        ),
        AdminStatCardData(
          id: 'clinics',
          label: 'Clinics',
          value: clinics.length,
          icon: Icons.local_hospital_outlined,
          accentRed: true,
          onTap: () => setState(() => _selectedNavIndex = 1),
        ),
        AdminStatCardData(
          id: 'appointments',
          label: 'Total Appointments',
          value: appointmentCount,
          icon: Icons.calendar_today_outlined,
          onTap: () => setState(() => _selectedNavIndex = 4),
        ),
        AdminStatCardData(
          id: 'pending_appointments',
          label: 'Pending Appointments',
          value: pendingAppointmentsCount,
          icon: Icons.schedule_outlined,
          accentRed: pendingAppointmentsCount > 0,
          onTap: () {
            setState(() {
              _adminApptStatusFilter = 'Pending';
              _selectedNavIndex = 4;
            });
          },
        ),
        AdminStatCardData(
          id: 'completed_appointments',
          label: 'Completed Appointments',
          value: completedAppointmentsCount,
          icon: Icons.task_alt_rounded,
          onTap: () {
            setState(() {
              _adminApptStatusFilter = 'Completed';
              _selectedNavIndex = 4;
            });
          },
        ),
        AdminStatCardData(
          id: 'cancelled_appointments',
          label: 'Cancelled Appointments',
          value: cancelledAppointmentsCount,
          icon: Icons.cancel_outlined,
          accentRed: cancelledAppointmentsCount > 0,
          onTap: () {
            setState(() {
              _adminApptStatusFilter = 'Cancelled';
              _selectedNavIndex = 4;
            });
          },
        ),
        AdminStatCardData(
          id: 'total_referrals',
          label: 'Total Referrals',
          value: allReferrals.length,
          icon: Icons.share_outlined,
          onTap: () => setState(() => _selectedNavIndex = 11),
        ),
        AdminStatCardData(
          id: 'pending_referrals',
          label: 'Pending Referrals',
          value: pendingReferralsCount,
          icon: Icons.pending_actions_outlined,
          accentRed: pendingReferralsCount > 0,
          onTap: () => setState(() => _selectedNavIndex = 11),
        ),
        AdminStatCardData(
          id: 'sub_admins',
          label: 'Active Coordinators / Sub-Admins',
          value: activeCoordinatorsCount,
          icon: Icons.supervisor_account_rounded,
          onTap: () => setState(() => _selectedNavIndex = 9),
        ),
        AdminStatCardData(
          id: 'districts',
          label: 'Districts',
          value: districts.length,
          icon: Icons.map_rounded,
          onTap: () => setState(() => _selectedNavIndex = 14),
        ),
        AdminStatCardData(
          id: 'assignments',
          label: 'Assignments & Audit',
          value: assignments.length,
          icon: Icons.assignment_ind_rounded,
          onTap: () => setState(() => _selectedNavIndex = 15),
        ),
      ],
      clinicsAction: AdminQuickActionData(
        id: 'clinics_owners',
        label: 'Clinics & owners',
        icon: Icons.star_border_rounded,
        onTap: () => setState(() => _selectedNavIndex = 1),
      ),
      referralsAction: AdminQuickActionData(
        id: 'referrals',
        label: 'Referrals',
        icon: Icons.medical_information_outlined,
        onTap: () => setState(() => _selectedNavIndex = 11),
      ),
      sponsoredAction: AdminQuickActionData(
        id: 'sponsored_ads',
        label: 'Sponsored ads',
        icon: Icons.campaign_outlined,
        onTap: () => showAdminSponsoredAdsSheet(context, ads),
      ),
      smsAction: AdminQuickActionData(
        id: 'sms_login',
        label: 'SMS login',
        icon: Icons.chat_bubble_outline_rounded,
        onTap: () => showAdminSmsLoginSheet(context),
      ),
      ads: ads,
      appointments: appointments,
      canViewPhone: true,
      onAppointmentTap: (item) => showAdminAppointmentDetailsSheet(
        context,
        item,
        canViewPhone: true,
        onOpenSchedule: () => setState(() => _selectedNavIndex = 4),
      ),
      footer: isDesktop ? null : _buildMobileSectionPillsBar(embedded: true),
    );
  }

  // ==========================================
  // PANEL: PATIENT-DOCTOR CHATS & AUDIT (Main Admin Exclusive)
  // ==========================================
  String _chatSearchQuery = '';
  List<dynamic> _adminConversations = [];
  bool _isLoadingConversations = false;
  bool _hasLoadedConversationsOnce = false;

  Future<void> _fetchAdminConversations() async {
    if (!mounted) return;
    setState(() => _isLoadingConversations = true);
    final convs = await ApiService().fetchConversations();
    if (mounted) {
      setState(() {
        _adminConversations = convs;
        _isLoadingConversations = false;
        _hasLoadedConversationsOnce = true;
      });
    }
  }

  void _showAdminChatInspectionModal(BuildContext context, String roomId, String patientName, String doctorName) {
    final replyCtrl = TextEditingController();
    bool isSendingReply = false;
    bool didMarkRead = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            if (!didMarkRead) {
              didMarkRead = true;
              ApiService().markChatRoomRead(roomId: roomId).then((_) {
                _fetchAdminConversations();
              });
            }
            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Modal Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    decoration: const BoxDecoration(
                      color: Color(0xFF0F172A),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.security_rounded, color: AppTheme.primaryBlue, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'Patient: $patientName',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  ),
                                  const Icon(Icons.swap_horiz_rounded, color: Color(0xFF94A3B8), size: 16),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFE3434).withValues(alpha: 0.25),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFFFE3434), width: 0.8),
                                    ),
                                    child: Text(
                                      'Doctor: $doctorName',
                                      style: const TextStyle(color: Color(0xFFFE3434), fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF012A58).withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFF012A58), width: 0.8),
                                    ),
                                    child: const Text('AUDIT LOGGED', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text('Room ID: $roomId • Consulting Doctor: $doctorName', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11), overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 19),
                          tooltip: 'Refresh Messages',
                          onPressed: () => setModalState(() {}),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFE3434), size: 20),
                          tooltip: 'Clear Chat History',
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (dCtx) => AlertDialog(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                title: const Text('Clear Chat History?'),
                                content: const Text('This will permanently delete this conversation. Are you sure?'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancel')),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFE3434)),
                                    onPressed: () => Navigator.pop(dCtx, true),
                                    child: const Text('Clear', style: TextStyle(color: Colors.white)),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await ApiService().clearChatMessages(roomId: roomId);
                              setModalState(() {});
                              _fetchAdminConversations();
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),

                  // Messages Stream
                  Expanded(
                    child: Container(
                      color: const Color(0xFFF1F5F9),
                      child: FutureBuilder<List<dynamic>>(
                        future: ApiService().fetchChatMessages(roomId: roomId, markRead: true),
                        builder: (ctx, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final messages = snapshot.data ?? [];
                          if (messages.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.chat_bubble_outline_rounded, size: 48, color: Colors.grey[400]),
                                  const SizedBox(height: 10),
                                  Text('No messages found in this room.', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                                ],
                              ),
                            );
                          }

                          return ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            itemCount: messages.length,
                            itemBuilder: (context, i) {
                              final msg = messages[i];
                              final text = (msg['message'] ?? '').toString();
                              final type = (msg['type'] ?? 'text').toString();
                              final sender = msg['sender'];
                              final senderRoleStr = (sender is Map ? (sender['role'] ?? type) : type).toString().toLowerCase();
                              final isAdminMsg = type == 'admin' || senderRoleStr.contains('admin');
                              final isDoc = !isAdminMsg && (senderRoleStr.contains('dentist') || senderRoleStr.contains('doctor') || type == 'doctor');

                              String fromName = sender is Map ? (sender['name'] ?? (isAdminMsg ? 'GS HEALTH Admin' : (isDoc ? doctorName : patientName))) : (isAdminMsg ? 'GS HEALTH Admin' : (isDoc ? doctorName : patientName));
                              if (isDoc && !fromName.toLowerCase().startsWith('dr')) {
                                fromName = 'Dr. $fromName';
                              }
                              final String fromRole = isAdminMsg ? 'Admin' : (isDoc ? 'Doctor' : 'Patient');
                              final String toName = isAdminMsg ? '$patientName & $doctorName' : (isDoc ? patientName : doctorName);
                              final String toRole = isAdminMsg ? 'Thread' : (isDoc ? 'Patient' : 'Doctor');

                              final time = msg['created_at'] != null ? DateTime.tryParse(msg['created_at'].toString())?.toLocal() : null;
                              final timeStr = time != null
                                  ? '${time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour)}:${time.minute.toString().padLeft(2, '0')} ${time.hour >= 12 ? 'PM' : 'AM'}'
                                  : '';

                              return Align(
                                alignment: (isDoc || isAdminMsg) ? Alignment.centerRight : Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
                                  decoration: BoxDecoration(
                                    color: isAdminMsg
                                        ? const Color(0xFF012A58).withValues(alpha: 0.12)
                                        : (isDoc ? const Color(0x14FE3434) : Colors.white),
                                    borderRadius: BorderRadius.circular(14).copyWith(
                                      topRight: (isDoc || isAdminMsg) ? const Radius.circular(2) : const Radius.circular(14),
                                      topLeft: (isDoc || isAdminMsg) ? const Radius.circular(14) : const Radius.circular(2),
                                    ),
                                    border: Border.all(
                                      color: isAdminMsg
                                          ? const Color(0xFF012A58).withValues(alpha: 0.35)
                                          : (isDoc ? const Color(0x40FE3434) : const Color(0xFFE2E8F0)),
                                    ),
                                    boxShadow: [
                                      BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 2)),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        spacing: 4,
                                        runSpacing: 2,
                                        children: [
                                          Icon(
                                            isAdminMsg
                                                ? Icons.admin_panel_settings_rounded
                                                : (isDoc ? Icons.medical_services_rounded : Icons.person_rounded),
                                            size: 13,
                                            color: isAdminMsg ? const Color(0xFF012A58) : const Color(0xFFFE3434),
                                          ),
                                          Text(
                                            '$fromName ($fromRole)',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: isAdminMsg ? const Color(0xFF012A58) : const Color(0xFFFE3434),
                                            ),
                                          ),
                                          const Icon(Icons.arrow_forward_rounded, size: 11, color: Color(0xFF94A3B8)),
                                          Text(
                                            'To: $toName ($toRole)',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF012A58),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(text, style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B), height: 1.3)),
                                      if (timeStr.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Align(
                                          alignment: Alignment.bottomRight,
                                          child: Text(timeStr, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),

                  // Admin Message Reply Input Bar
                  Container(
                    padding: EdgeInsets.only(
                      left: 14,
                      right: 14,
                      top: 10,
                      bottom: MediaQuery.of(context).viewInsets.bottom + 12,
                    ),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: replyCtrl,
                            style: const TextStyle(fontSize: 13.5, color: Color(0xFF0F172A)),
                            decoration: InputDecoration(
                              hintText: 'Send an administrative message to this thread...',
                              hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          icon: isSendingReply
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Icon(Icons.send_rounded, size: 16),
                          label: const Text('Send', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF012A58),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                          onPressed: isSendingReply
                              ? null
                              : () async {
                                  final txt = replyCtrl.text.trim();
                                  if (txt.isEmpty) return;
                                  setModalState(() => isSendingReply = true);
                                  final adminId = SessionService().currentSession?.userId ?? 'ADMIN';
                                  final res = await ApiService().sendMessage(
                                    senderId: adminId,
                                    message: txt,
                                    roomId: roomId,
                                    type: 'admin',
                                    senderRole: 'Admin',
                                  );
                                  if (res['success'] == true) {
                                    replyCtrl.clear();
                                    setModalState(() => isSendingReply = false);
                                    _fetchAdminConversations();
                                  } else {
                                    setModalState(() => isSendingReply = false);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(res['message']?.toString() ?? 'Failed to send message.'),
                                          backgroundColor: const Color(0xFFFE3434),
                                        ),
                                      );
                                    }
                                  }
                                },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showAdminAuditLogsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.8,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: const BoxDecoration(
                  color: Color(0xFF0F172A),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.history_rounded, color: AppTheme.primaryBlue, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Admin Chat Access & Privacy Audit Trail',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: FutureBuilder<List<dynamic>>(
                  future: ApiService().fetchChatAuditLogs(),
                  builder: (ctx, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final logs = snapshot.data ?? [];
                    if (logs.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.shield_outlined, size: 48, color: Colors.grey[400]),
                            const SizedBox(height: 10),
                            Text('No admin chat audit logs recorded yet.', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.all(14),
                      itemCount: logs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final log = logs[i];
                        final action = log['action'] ?? 'ACCESS';
                        final target = log['target_resource'] ?? 'ROOM';
                        final email = log['user_email'] ?? 'admin@gshealth.com';
                        final ip = log['ip_address'] ?? '127.0.0.1';
                        final time = log['created_at'] != null ? DateTime.tryParse(log['created_at'].toString()) : null;
                        final dateStr = time != null ? '${time.day}/${time.month}/${time.year} ${time.hour}:${time.minute.toString().padLeft(2, '0')}' : '';

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFE3434).withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.security_rounded, size: 18, color: Color(0xFFFE3434)),
                          ),
                          title: Text(
                            action.toString().replaceAll('_', ' '),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          subtitle: Text(
                            'Admin: $email • Target: $target\nIP: $ip • $dateStr',
                            style: TextStyle(fontSize: 11, color: Colors.grey[600], height: 1.3),
                          ),
                          isThreeLine: true,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPatientDoctorChatsPanel() {
    if (!_hasLoadedConversationsOnce && !_isLoadingConversations) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_hasLoadedConversationsOnce && !_isLoadingConversations) {
          _fetchAdminConversations();
        }
      });
    }

    final filtered = _adminConversations.where((c) {
      final pName = (c['patientName'] ?? '').toString().toLowerCase();
      final dName = (c['doctorName'] ?? '').toString().toLowerCase();
      final rId = (c['roomId'] ?? '').toString().toLowerCase();
      final lastMsg = (c['lastMessage'] ?? '').toString().toLowerCase();
      final q = _chatSearchQuery.toLowerCase();
      return q.isEmpty || pName.contains(q) || dName.contains(q) || rId.contains(q) || lastMsg.contains(q);
    }).toList();

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 650;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isNarrow) ...[
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryBlue.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.forum_rounded, color: AppTheme.primaryBlue, size: 20),
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Patient–Doctor Chat Oversight',
                                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
                                tooltip: 'Refresh Conversations',
                                onPressed: _fetchAdminConversations,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Main Admin Exclusive • Real-time conversation monitoring & compliance audit trail',
                            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.history_rounded, size: 16),
                              label: const Text('Audit Trail', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFE3434),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: () => _showAdminAuditLogsModal(context),
                            ),
                          ),
                        ] else ...[
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryBlue.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.forum_rounded, color: AppTheme.primaryBlue, size: 22),
                              ),
                              const SizedBox(width: 14),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Patient–Doctor Chat Oversight',
                                      style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    SizedBox(height: 3),
                                    Text(
                                      'Main Admin Exclusive • Real-time conversation monitoring & compliance audit trail',
                                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.history_rounded, size: 16),
                                label: const Text('Audit Trail', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFE3434),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: () => _showAdminAuditLogsModal(context),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                                tooltip: 'Refresh Conversations',
                                onPressed: _fetchAdminConversations,
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF012A58).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF012A58), width: 0.8),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.shield_rounded, color: Color(0xFF012A58), size: 14),
                                  SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      'Sub-Admins Strictly Restricted (403 Forbidden)',
                                      style: TextStyle(color: Color(0xFF012A58), fontSize: 11, fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${_adminConversations.length} Active Threads',
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 18),

              // Search Bar
              TextField(
                style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13.5, fontWeight: FontWeight.w500),
                cursorColor: AppTheme.primaryBlue,
                decoration: InputDecoration(
                  hintText: 'Search conversations by patient, doctor, or keyword...',
                  hintStyle: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
                  prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppTheme.primaryBlue),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                onChanged: (val) => setState(() => _chatSearchQuery = val),
              ),
              const SizedBox(height: 16),

              // Conversation Cards List
              if (_isLoadingConversations)
                const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
              else if (filtered.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_outline_rounded, size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      const Text('No Active Patient–Doctor Conversations Found', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark)),
                      const SizedBox(height: 4),
                      Text(
                        _chatSearchQuery.isNotEmpty ? 'No conversations match your search query.' : 'When patients and doctors exchange messages, they will appear here.',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final conv = filtered[i];
                    final roomId = (conv['roomId'] ?? 'GENERAL-CHAT').toString();
                    final patientName = (conv['patientName'] ?? 'Patient').toString();
                    final doctorName = (conv['doctorName'] ?? 'Attending Doctor').toString();
                    final lastMsg = (conv['lastMessage'] ?? '').toString();
                    final totalMsgs = conv['totalMessages'] ?? 0;
                    final unreadMsgs = int.tryParse((conv['unreadCount'] ?? '0').toString()) ?? 0;
                    final time = conv['lastMessageTime'] != null ? DateTime.tryParse(conv['lastMessageTime'].toString())?.toLocal() : null;
                    final timeStr = time != null ? '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}' : '';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: unreadMsgs > 0 ? const Color(0xFFFE3434).withValues(alpha: 0.45) : const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2)),
                        ],
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.primaryBlue.withOpacity(0.12),
                          child: const Icon(Icons.forum_rounded, color: AppTheme.primaryBlue, size: 20),
                        ),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                '$patientName ↔ $doctorName',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text('$totalMsgs msgs', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                            ),
                            if (unreadMsgs > 0) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFE3434),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$unreadMsgs unread',
                                  style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                lastMsg.isNotEmpty ? lastMsg : 'No message preview',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                              ),
                              const SizedBox(height: 4),
                              Text('Room: $roomId • $timeStr', style: TextStyle(fontSize: 10.5, color: Colors.grey[500])),
                            ],
                          ),
                        ),
                        trailing: ElevatedButton.icon(
                          icon: const Icon(Icons.visibility_rounded, size: 14),
                          label: const Text('Inspect', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () => _showAdminChatInspectionModal(context, roomId, patientName, doctorName),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }


  // ==========================================
  // PANEL: SUB-ADMIN MANAGEMENT
  // ==========================================
  String _subAdminSearch = '';
  String _subAdminStatusFilter = 'All'; // 'All', 'Active', 'Inactive'

  Widget _buildSubAdminsPanel() {
    final rawList = _uniqueSubAdmins;
    final subAdminList = rawList.where((sa) {
      final name = (sa['name'] ?? '').toString().toLowerCase();
      final email = (sa['email'] ?? '').toString().toLowerCase();
      final phone = (sa['phone'] ?? '').toString().toLowerCase();
      final status = (sa['status'] ?? 'ACTIVE').toString().toUpperCase();

      final matchesSearch = _subAdminSearch.isEmpty ||
          name.contains(_subAdminSearch.toLowerCase()) ||
          email.contains(_subAdminSearch.toLowerCase()) ||
          phone.contains(_subAdminSearch.toLowerCase());

      final matchesStatus = _subAdminStatusFilter == 'All' ||
          (_subAdminStatusFilter == 'Active' && status == 'ACTIVE') ||
          (_subAdminStatusFilter == 'Inactive' && status != 'ACTIVE');

      return matchesSearch && matchesStatus;
    }).toList();

    final activeCount = rawList.where((s) => (s['status'] ?? 'ACTIVE').toString().toUpperCase() == 'ACTIVE').length;
    final inactiveCount = rawList.length - activeCount;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFE3434), Color(0xFFFE3434)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.shield_outlined, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '🛡️ Sub-Admin & Role-Based Access Control',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${rawList.length} Sub-Admin${rawList.length == 1 ? '' : 's'} ($activeCount Active • $inactiveCount Deactivated)',
                            style: const TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Search & Status Filter Bar
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => _subAdminSearch = v),
                      style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13.5, fontWeight: FontWeight.w500),
                      cursorColor: AppTheme.primaryBlue,
                      decoration: InputDecoration(
                        hintText: 'Search sub-admins by name, email, phone...',
                        hintStyle: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
                        prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppTheme.primaryBlue),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.person_add_rounded, size: 16),
                    label: const Text('+ Add Sub-Admin', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFE3434),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => _showRegisterSubAdminModal(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Filter Chips
              Row(
                children: [
                  _buildSubAdminFilterChip('All (${rawList.length})', 'All'),
                  const SizedBox(width: 8),
                  _buildSubAdminFilterChip('Active ($activeCount)', 'Active'),
                  const SizedBox(width: 8),
                  _buildSubAdminFilterChip('Inactive ($inactiveCount)', 'Inactive'),
                ],
              ),
              const SizedBox(height: 16),

              // Sub-Admin List or Empty State
              if (subAdminList.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFE3434).withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.supervisor_account_outlined, size: 40, color: Color(0xFFFE3434)),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        rawList.isEmpty ? 'No Sub-Admins Created Yet' : 'No Sub-Admins Match Filter',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Create sub-admins and assign granular permissions for patients, doctors, specialist assignments, appointments, problems, and reports.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: AppTheme.textMuted, height: 1.5),
                      ),
                      if (rawList.isEmpty) ...[
                        const SizedBox(height: 18),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.person_add_rounded, size: 16),
                          label: const Text('Create First Sub-Admin', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFE3434),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () => _showRegisterSubAdminModal(context),
                        ),
                      ],
                    ],
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: subAdminList.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final sa = subAdminList[index];
                    final String saId = (sa['id'] ?? '').toString();
                    final String name = (sa['name'] ?? 'Sub-Admin').toString();
                    final String email = (sa['email'] ?? '').toString();
                    final String phone = (sa['phone'] ?? '').toString();
                    final String status = (sa['status'] ?? 'ACTIVE').toString().toUpperCase();
                    final bool isActive = status == 'ACTIVE';

                    final assignedDistricts = sa['assignedDistricts'] is List ? (sa['assignedDistricts'] as List) : [];
                    final int assignedPatientsCount = (sa['assignedPatientsCount'] is int)
                        ? sa['assignedPatientsCount']
                        : int.tryParse(sa['assignedPatientsCount']?.toString() ?? '0') ?? 0;

                    List<String> permissions = [];
                    if (sa['permissions'] is List) {
                      for (final p in sa['permissions']) {
                        if (p != null && p.toString().trim().isNotEmpty) {
                          permissions.add(p.toString().trim().toUpperCase());
                        }
                      }
                    }

                    final initials = name
                        .trim()
                        .split(' ')
                        .where((w) => w.isNotEmpty)
                        .take(2)
                        .map((w) => w[0].toUpperCase())
                        .join();

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: isActive ? const Color(0xFFE2E8F0) : const Color(0x40FE3434)),
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
                          // Top Row: Avatar, Info, Status & Toggle
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: isActive ? const Color(0xFFFE3434) : const Color(0xFF94A3B8),
                                child: Text(
                                  initials.isNotEmpty ? initials : 'SA',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            name,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: isActive ? const Color(0x14012A58) : const Color(0x14FE3434),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            isActive ? '✓ Active' : '⛔ Deactivated',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: isActive ? const Color(0xFFFE3434) : const Color(0xFFFE3434),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Mobile: ${phone.isNotEmpty ? phone : "Not provided"} • City: ${(sa['city'] != null && sa['city'].toString().trim().isNotEmpty) ? sa['city'].toString().trim() : "Not provided"} • PIN: ${(sa['pincode'] != null && sa['pincode'].toString().trim().isNotEmpty) ? sa['pincode'].toString().trim() : "Not provided"} • Languages: ${(sa['languages'] != null && sa['languages'] is List && (sa['languages'] as List).isNotEmpty) ? (sa['languages'] as List).join(", ") : "English"} • Email: ${email.isNotEmpty ? email : "Not provided"}',
                                      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_togglingSubAdminIds.contains(saId))
                                    const Padding(
                                      padding: EdgeInsets.only(right: 6),
                                      child: SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF012A58)),
                                      ),
                                    ),
                                  Switch(
                                    value: isActive,
                                    activeThumbColor: const Color(0xFF012A58),
                                    onChanged: _togglingSubAdminIds.contains(saId)
                                        ? null
                                        : (val) async {
                                            final previousStatus = status;
                                            final newStatus = val ? 'ACTIVE' : 'INACTIVE';
                                            setState(() => _togglingSubAdminIds.add(saId));
                                            _problemService.updateSubAdminStatusLocally(saId, newStatus);

                                            try {
                                              final api = ApiService();
                                              final ok = await api.toggleSubAdminStatus(saId, status: newStatus);
                                              if (!ok) {
                                                _problemService.updateSubAdminStatusLocally(saId, previousStatus);
                                                final errMsg = api.lastSubAdminToggleError;
                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        errMsg != null && errMsg.isNotEmpty
                                                            ? '❌ Failed to update "$name" status: $errMsg'
                                                            : '❌ Failed to update "$name" status. Please check permissions/connection.',
                                                      ),
                                                      backgroundColor: const Color(0xFFFE3434),
                                                      duration: const Duration(seconds: 3),
                                                    ),
                                                  );
                                                }
                                                return;
                                              }
                                              final confirmedStatus = api.lastSubAdminConfirmedStatus ?? newStatus;
                                              _problemService.updateSubAdminStatusLocally(saId, confirmedStatus);
                                              await _problemService.syncSubAdminsFromApi();

                                              if (context.mounted) {
                                                final confirmedActive = confirmedStatus == 'ACTIVE';
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text(confirmedActive ? '✓ Sub-Admin "$name" activated.' : '⛔ Sub-Admin "$name" deactivated.'),
                                                    backgroundColor: confirmedActive ? const Color(0xFF012A58) : const Color(0xFFFE3434),
                                                    duration: const Duration(seconds: 2),
                                                  ),
                                                );
                                              }
                                            } finally {
                                              if (mounted) {
                                                setState(() => _togglingSubAdminIds.remove(saId));
                                              }
                                            }
                                          },
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Divider(height: 1, color: Color(0xFFF1F5F9)),
                          const SizedBox(height: 10),

                          // Assigned Permissions Chips
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Roles:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: permissions.isEmpty
                                    ? const Text('None assigned (Restricted)', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Color(0xFFFE3434)))
                                    : Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: permissions.map((p) {
                                          return Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: const Color(0x14FE3434),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: const Color(0x40FE3434)),
                                            ),
                                            child: Text(
                                              AppPermissions.getLabel(p),
                                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF012A58)),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Assigned Districts
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Districts:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: assignedDistricts.isEmpty
                                    ? const Text('None assigned (Unrestricted / All)', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Color(0xFF64748B)))
                                    : Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: assignedDistricts.map((d) {
                                          final dName = d is Map ? (d['name'] ?? 'District').toString() : d.toString();
                                          return Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF012A58).withValues(alpha: 0.08),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: const Color(0xFF012A58).withValues(alpha: 0.2)),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.location_on_rounded, size: 10, color: Color(0xFF012A58)),
                                                const SizedBox(width: 3),
                                                Text(
                                                  dName,
                                                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF012A58)),
                                                ),
                                              ],
                                            ),
                                          );
                                        }).toList(),
                                      ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Assigned Patients Count Badge
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '👥 $assignedPatientsCount Patients Assigned',
                                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Action Buttons: Assign Districts, History, Edit Roles & Delete
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.end,
                            children: [
                              OutlinedButton.icon(
                                icon: const Icon(Icons.share_location_rounded, size: 13),
                                label: const Text('Assign Districts', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF012A58),
                                  side: const BorderSide(color: Color(0xFF012A58)),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () async {
                                  final ok = await GsHealthSubAdminDistrictDialog.show(
                                    context,
                                    subAdmin: sa,
                                    problemService: _problemService,
                                  );
                                  if (ok == true && mounted) {
                                    setState(() {});
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('✓ Districts updated for "$name".'),
                                        backgroundColor: const Color(0xFF012A58),
                                      ),
                                    );
                                  }
                                },
                              ),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.history_rounded, size: 13),
                                label: const Text('History', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFFFE3434),
                                  side: const BorderSide(color: Color(0xFFFE3434)),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () => _showSubAdminAssignmentHistoryModal(context, sa),
                              ),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.edit_rounded, size: 13),
                                label: const Text('Edit Roles', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFFFE3434),
                                  side: const BorderSide(color: Color(0xFFFE3434)),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () => _showEditSubAdminModal(context, sa),
                              ),
                              InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => _confirmRemoveSubAdmin(context, saId, name),
                                child: Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: Color(0xFFFE3434).withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFE3434), size: 16),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubAdminFilterChip(String label, String value) {
    final isSelected = _subAdminStatusFilter == value;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _subAdminStatusFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFE3434) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? const Color(0xFFFE3434) : const Color(0xFFE2E8F0)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }

  void _showSubAdminAssignmentHistoryModal(BuildContext context, Map<String, dynamic> sa) {
    final saId = (sa['id'] ?? '').toString();
    final name = (sa['name'] ?? 'Sub-Admin').toString();

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return FutureBuilder<List<dynamic>>(
          future: ApiService().fetchSubAdminAssignmentHistory(saId),
          builder: (ctx, snapshot) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF012A58).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.history_rounded, color: Color(0xFF012A58), size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Assignments by $name',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Text(
                          'Audit records of patients routed by this Sub-Admin',
                          style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: Container(
                width: double.maxFinite,
                constraints: const BoxConstraints(maxWidth: 480, maxHeight: 360),
                child: snapshot.connectionState == ConnectionState.waiting
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF012A58)))
                    : (snapshot.data == null || snapshot.data!.isEmpty)
                        ? const Center(
                            child: Text(
                              'No patient assignments recorded by this sub-admin yet.',
                              style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                            ),
                          )
                        : ListView.separated(
                            itemCount: snapshot.data!.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (ctx, idx) {
                              final item = snapshot.data![idx];
                              final pName = (item['patient_name'] ?? (item['patient'] is Map ? item['patient']['name'] : '') ?? 'Patient').toString();
                              final dName = (item['dentist_name'] ?? (item['dentist'] is Map ? item['dentist']['name'] : '') ?? 'Doctor').toString();
                              final dClinic = (item['clinic_name'] ?? (item['clinic'] is Map ? item['clinic']['clinic_name'] : '') ?? '').toString();
                              final date = (item['created_at'] ?? '').toString();
                              return ListTile(
                                leading: CircleAvatar(
                                  radius: 16,
                                  backgroundColor: const Color(0xFF012A58).withValues(alpha: 0.08),
                                  child: Text(
                                    pName.isNotEmpty ? pName[0].toUpperCase() : 'P',
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF012A58), fontWeight: FontWeight.bold),
                                  ),
                                ),
                                title: Text(pName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                subtitle: Text(
                                  'Assigned to $dName${dClinic.isNotEmpty ? " • $dClinic" : ""}',
                                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                ),
                                trailing: Text(
                                  date.length >= 10 ? date.substring(0, 10) : '',
                                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                ),
                              );
                            },
                          ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmRemoveSubAdmin(BuildContext context, String subAdminId, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFFE3434), size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Delete $name?', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        content: Text('Are you sure you want to permanently delete $name from Sub-Admins? They will lose all portal access.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton.icon(
            icon: const Icon(Icons.delete_forever_rounded, size: 16),
            label: const Text('Delete Sub-Admin', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(backgroundColor: Color(0xFFFE3434), foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.of(ctx).pop();
              _problemService.removeSubAdminLocally(subAdminId);
              if (mounted) setState(() {});
              await ApiService().deleteSubAdmin(subAdminId);
              await _problemService.syncSubAdminsFromApi();
              if (mounted) setState(() {});
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('🗑️ Sub-Admin "$name" removed successfully.'),
                    backgroundColor: Color(0xFFFE3434),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  void _showRegisterSubAdminModal(BuildContext context) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final cityCtrl = TextEditingController();
    final pincodeCtrl = TextEditingController();
    String selectedSubAdminLanguage = 'English';
    bool isLoading = false;
    String status = 'ACTIVE';

    final Set<String> selectedPerms = Set.from(AppPermissions.defaultPermissions);
    final Set<String> selectedDistrictIds = {};

    const availableLanguages = [
      'English',
      'Hindi',
      'Telugu',
      'Tamil',
      'Kannada',
      'Bengali',
      'Marathi',
      'Gujarati',
      'Malayalam',
      'Punjabi',
    ];

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
                padding: const EdgeInsets.all(22),
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
                            color: const Color(0xFFFE3434).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.shield_outlined, color: Color(0xFFFE3434), size: 22),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Create Sub-Admin Account',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textDark),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Mobile identifier authentication • Assign module permissions',
                                style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
                          onPressed: () => Navigator.of(dialogCtx).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(color: Color(0xFFF1F5F9)),
                    const SizedBox(height: 10),

                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Full Name *
                            TextField(
                              controller: nameCtrl,
                              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                              cursorColor: AppTheme.primaryBlue,
                              decoration: InputDecoration(
                                labelText: 'Full Name *',
                                hintText: 'e.g. Rahul Sharma',
                                prefixIcon: const Icon(Icons.person_outline_rounded, size: 18),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Mobile Phone Number *
                            TextField(
                              controller: phoneCtrl,
                              keyboardType: TextInputType.phone,
                              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                              cursorColor: AppTheme.primaryBlue,
                              decoration: InputDecoration(
                                labelText: 'Mobile Phone Number *',
                                hintText: '+91 98765 43210',
                                prefixIcon: const Icon(Icons.phone_android_rounded, size: 18),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Email (Optional)
                            TextField(
                              controller: emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                              cursorColor: AppTheme.primaryBlue,
                              decoration: InputDecoration(
                                labelText: 'Email Address (Optional)',
                                hintText: 'subadmin@gshealth.com (Optional)',
                                prefixIcon: const Icon(Icons.email_outlined, size: 18),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // City & Pincode
                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: TextField(
                                    controller: cityCtrl,
                                    style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                                    cursorColor: AppTheme.primaryBlue,
                                    decoration: InputDecoration(
                                      labelText: 'City (Optional)',
                                      hintText: 'e.g. Hyderabad',
                                      prefixIcon: const Icon(Icons.location_city_rounded, size: 18),
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
                                    controller: pincodeCtrl,
                                    keyboardType: TextInputType.number,
                                    style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                                    cursorColor: AppTheme.primaryBlue,
                                    decoration: InputDecoration(
                                      labelText: 'Pincode (Optional)',
                                      hintText: '500032',
                                      prefixIcon: const Icon(Icons.pin_drop_outlined, size: 18),
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Language Dropdown (No symbols)
                            DropdownButtonFormField<String>(
                              initialValue: selectedSubAdminLanguage,
                              dropdownColor: Colors.white,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: 'Languages Known',
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              items: availableLanguages.map((l) {
                                return DropdownMenuItem(value: l, child: Text(l, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)));
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setModalState(() => selectedSubAdminLanguage = val);
                                }
                              },
                            ),
                            const SizedBox(height: 16),

                            // District Jurisdiction Selection
                            const Text('Assigned District Jurisdiction', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark)),
                            const SizedBox(height: 4),
                            const Text('Select one or more districts assigned to this Sub-Admin.', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                            const SizedBox(height: 8),
                            _problemService.districts.isEmpty
                                ? const Text('No districts registered yet. Districts can be assigned anytime.', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: AppTheme.textMuted))
                                : Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: _problemService.districts.map((d) {
                                      final dId = (d['id'] ?? '').toString();
                                      final dName = (d['name'] ?? 'District').toString();
                                      final isSelected = selectedDistrictIds.contains(dId);
                                      return FilterChip(
                                        label: Text(dName, style: TextStyle(fontSize: 11.5, color: isSelected ? Colors.white : const Color(0xFF1E293B))),
                                        selected: isSelected,
                                        selectedColor: const Color(0xFF012A58),
                                        checkmarkColor: Colors.white,
                                        backgroundColor: const Color(0xFFF1F5F9),
                                        onSelected: (val) {
                                          setModalState(() {
                                            if (val) {
                                              selectedDistrictIds.add(dId);
                                            } else {
                                              selectedDistrictIds.remove(dId);
                                            }
                                          });
                                        },
                                      );
                                    }).toList(),
                                  ),
                            const SizedBox(height: 16),

                            // Permission Selector Section
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Module Permissions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark)),
                                Row(
                                  children: [
                                    TextButton(
                                      child: const Text('Select All', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                      onPressed: () {
                                        setModalState(() {
                                          for (final g in AppPermissions.groups) {
                                            for (final p in g.permissions) {
                                              selectedPerms.add(p.key);
                                            }
                                          }
                                        });
                                      },
                                    ),
                                    TextButton(
                                      child: const Text('Clear', style: TextStyle(fontSize: 11, color: Color(0xFFFE3434))),
                                      onPressed: () => setModalState(() => selectedPerms.clear()),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // Groups of permissions
                            ...AppPermissions.groups.map((group) {
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
                                    Row(
                                      children: [
                                        Text(group.icon, style: const TextStyle(fontSize: 14)),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            group.title,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    ...group.permissions.map((perm) {
                                      final isChecked = selectedPerms.contains(perm.key);
                                      return CheckboxListTile(
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        title: Text(perm.label, style: const TextStyle(fontSize: 12)),
                                        value: isChecked,
                                        activeColor: const Color(0xFFFE3434),
                                        onChanged: (val) {
                                          setModalState(() {
                                            if (val == true) {
                                              selectedPerms.add(perm.key);
                                            } else {
                                              selectedPerms.remove(perm.key);
                                            }
                                          });
                                        },
                                      );
                                    }),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Submit Button
                    SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        icon: isLoading
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.check_circle_rounded, size: 18),
                        label: Text(isLoading ? 'Creating Sub-Admin...' : 'Create Sub-Admin Account', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFE3434),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: isLoading
                            ? null
                            : () async {
                                final name = nameCtrl.text.trim();
                                final phone = phoneCtrl.text.trim();
                                final email = emailCtrl.text.trim();
                                final city = cityCtrl.text.trim();
                                final pincode = pincodeCtrl.text.trim();

                                if (name.isEmpty || phone.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('⚠️ Please fill in Full Name and Mobile Phone Number.'), backgroundColor: Color(0xFFFE3434)),
                                  );
                                  return;
                                }

                                setModalState(() => isLoading = true);

                                try {
                                  final res = await ApiService().createSubAdmin(
                                    name: name,
                                    phone: phone,
                                    email: email,
                                    city: city,
                                    pincode: pincode,
                                    languages: [selectedSubAdminLanguage],
                                    permissions: selectedPerms.toList(),
                                    districtIds: selectedDistrictIds.isNotEmpty ? selectedDistrictIds.toList() : null,
                                    status: status,
                                  );

                                  await _problemService.syncSubAdminsFromApi();
                                  setModalState(() => isLoading = false);

                                  if (!dialogCtx.mounted) return;
                                  Navigator.of(dialogCtx).pop();

                                  if (res['success'] == true) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('✅ Sub-Admin "$name" created successfully with ${selectedPerms.length} permissions.'),
                                        backgroundColor: const Color(0xFF012A58),
                                      ),
                                    );
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('⚠️ ${res['message'] ?? 'Notice during creation'}'), backgroundColor: const Color(0xFFFE3434)),
                                    );
                                  }
                                } catch (e) {
                                  setModalState(() => isLoading = false);
                                  if (!dialogCtx.mounted) return;
                                  Navigator.of(dialogCtx).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('⚠️ Error creating Sub-Admin: $e'), backgroundColor: const Color(0xFFFE3434)),
                                  );
                                }
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

  void _showEditSubAdminModal(BuildContext context, Map<String, dynamic> sa) {
    final String saId = (sa['id'] ?? '').toString();
    final nameCtrl = TextEditingController(text: (sa['name'] ?? '').toString());
    final phoneCtrl = TextEditingController(text: (sa['phone'] ?? '').toString());
    final passwordCtrl = TextEditingController();
    bool showPassword = false;
    bool isLoading = false;
    String status = (sa['status'] ?? 'ACTIVE').toString().toUpperCase();

    final Set<String> selectedPerms = {};
    if (sa['permissions'] is List) {
      for (final p in sa['permissions']) {
        if (p != null && p.toString().trim().isNotEmpty) {
          selectedPerms.add(p.toString().trim().toUpperCase());
        }
      }
    }

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
                padding: const EdgeInsets.all(22),
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
                            color: const Color(0xFFFE3434).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.edit_rounded, color: Color(0xFFFE3434), size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Edit ${nameCtrl.text.isNotEmpty ? nameCtrl.text : "Sub-Admin"}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textDark),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${sa['email']} • Update details and assigned roles',
                                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
                          onPressed: () => Navigator.of(dialogCtx).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(color: Color(0xFFF1F5F9)),
                    const SizedBox(height: 10),

                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Full Name *
                            TextField(
                              controller: nameCtrl,
                              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                              cursorColor: AppTheme.primaryBlue,
                              decoration: InputDecoration(
                                label: const Text.rich(
                                  TextSpan(
                                    text: 'Full Name',
                                    style: TextStyle(color: Color(0xFF0F172A)),
                                    children: [
                                      TextSpan(text: ' *', style: TextStyle(color: Color(0xFFFE3434), fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                                prefixIcon: const Icon(Icons.person_outline_rounded, size: 18),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Contact Number *
                            TextField(
                              controller: phoneCtrl,
                              keyboardType: TextInputType.phone,
                              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                              cursorColor: AppTheme.primaryBlue,
                              decoration: InputDecoration(
                                label: const Text.rich(
                                  TextSpan(
                                    text: 'Contact Number',
                                    style: TextStyle(color: Color(0xFF0F172A)),
                                    children: [
                                      TextSpan(text: ' *', style: TextStyle(color: Color(0xFFFE3434), fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                                prefixIcon: const Icon(Icons.phone_outlined, size: 18),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // New Password (Optional)
                            TextField(
                              controller: passwordCtrl,
                              obscureText: !showPassword,
                              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                              cursorColor: AppTheme.primaryBlue,
                              decoration: InputDecoration(
                                labelText: 'Reset Password (Leave blank to keep unchanged)',
                                hintText: 'New password',
                                prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
                                suffixIcon: IconButton(
                                  icon: Icon(showPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 18),
                                  onPressed: () => setModalState(() => showPassword = !showPassword),
                                ),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Status Selector
                            Row(
                              children: [
                                const Text('Account Status:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                const SizedBox(width: 12),
                                ChoiceChip(
                                  label: const Text('Active'),
                                  selected: status == 'ACTIVE',
                                  selectedColor: const Color(0x14012A58),
                                  onSelected: (val) => setModalState(() => status = 'ACTIVE'),
                                ),
                                const SizedBox(width: 8),
                                ChoiceChip(
                                  label: const Text('Deactivated'),
                                  selected: status != 'ACTIVE',
                                  selectedColor: const Color(0x14FE3434),
                                  onSelected: (val) => setModalState(() => status = 'INACTIVE'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Permission Selector
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Module Permissions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark)),
                                Row(
                                  children: [
                                    TextButton(
                                      child: const Text('Select All', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                      onPressed: () {
                                        setModalState(() {
                                          for (final g in AppPermissions.groups) {
                                            for (final p in g.permissions) {
                                              selectedPerms.add(p.key);
                                            }
                                          }
                                        });
                                      },
                                    ),
                                    TextButton(
                                      child: const Text('Clear', style: TextStyle(fontSize: 11, color: Color(0xFFFE3434))),
                                      onPressed: () => setModalState(() => selectedPerms.clear()),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            ...AppPermissions.groups.map((group) {
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
                                    Row(
                                      children: [
                                        Text(group.icon, style: const TextStyle(fontSize: 14)),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            group.title,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    ...group.permissions.map((perm) {
                                      final isChecked = selectedPerms.contains(perm.key);
                                      return CheckboxListTile(
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        title: Text(perm.label, style: const TextStyle(fontSize: 12)),
                                        value: isChecked,
                                        activeColor: const Color(0xFFFE3434),
                                        onChanged: (val) {
                                          setModalState(() {
                                            if (val == true) {
                                              selectedPerms.add(perm.key);
                                            } else {
                                              selectedPerms.remove(perm.key);
                                            }
                                          });
                                        },
                                      );
                                    }),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Update Button
                    SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        icon: isLoading
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save_rounded, size: 18),
                        label: Text(isLoading ? 'Saving Changes...' : 'Save Sub-Admin Changes', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFE3434),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: isLoading
                            ? null
                            : () async {
                                final name = nameCtrl.text.trim();
                                final phone = phoneCtrl.text.trim();
                                if (name.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('⚠️ Full Name cannot be empty.')),
                                  );
                                  return;
                                }
                                final cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
                                if (cleanPhone.length < 10) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('⚠️ Enter a valid 10-digit Contact Number.')),
                                  );
                                  return;
                                }
                                setModalState(() => isLoading = true);

                                try {
                                  final res = await ApiService().updateSubAdmin(
                                    id: saId,
                                    name: nameCtrl.text.trim(),
                                    phone: phoneCtrl.text.trim(),
                                    password: passwordCtrl.text.trim().isNotEmpty ? passwordCtrl.text.trim() : null,
                                    status: status,
                                    permissions: selectedPerms.toList(),
                                  );

                                  await _problemService.syncSubAdminsFromApi();
                                  if (mounted) setState(() {});
                                  setModalState(() => isLoading = false);

                                  if (!dialogCtx.mounted) return;
                                  Navigator.of(dialogCtx).pop();

                                  if (res['success'] == true) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('✅ Sub-Admin "${nameCtrl.text.trim()}" updated successfully.'),
                                        backgroundColor: const Color(0xFF012A58),
                                      ),
                                    );
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('⚠️ ${res['message'] ?? 'Notice during update'}'), backgroundColor: const Color(0xFFFE3434)),
                                    );
                                  }
                                } catch (e) {
                                  setModalState(() => isLoading = false);
                                  if (!dialogCtx.mounted) return;
                                  Navigator.of(dialogCtx).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('⚠️ Error updating Sub-Admin: $e'), backgroundColor: const Color(0xFFFE3434)),
                                  );
                                }
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

  // ==========================================
  // PANEL 1 (NAV INDEX 1): CLINICS DIRECTORY
  // ==========================================
  Widget _buildClinicsPanel() {
    return AdminClinicManagementPanel(
      problemService: _problemService,
      onRegisterNewClinic: () => _showRegisterClinicModal(context),
    );
  }

  // ignore: unused_element
  Widget _buildLegacyClinicsPanelUnused() {
    final clinics = _uniqueClinics;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Flexible(
                    child: Text(
                      '🏥 Partner Clinics Directory',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF012A58).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${clinics.length} Active',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF012A58)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              const Text(
                'Manage registered medical practices, addresses & specialists',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.dashboard_customize_rounded, size: 15, color: Color(0xFF012A58)),
                    label: const Text('Open Clinic Dashboard', style: TextStyle(color: Color(0xFF012A58), fontWeight: FontWeight.bold, fontSize: 11.5)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF012A58)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ClinicDashboardScreen(
                            clinicName: clinics.isNotEmpty ? clinics.first.clinicName : null,
                          ),
                        ),
                      );
                    },
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add_location_alt_rounded, size: 15, color: Colors.white),
                    label: const Text('+ Register New Clinic', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF012A58),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _showRegisterClinicModal(context),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (clinics.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.local_hospital_outlined, size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  const Text('No Registered Clinics Found', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  const Text('Tap "+ Register New Clinic" to add your first clinic practice.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Clinic Now'),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF012A58)),
                    onPressed: () => _showRegisterClinicModal(context),
                  )
                ],
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final crossCount = w > 850 ? 2 : 1;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossCount,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    mainAxisExtent: 250,
                  ),
                  itemCount: clinics.length,
                  itemBuilder: (context, idx) {
                    final clinic = clinics[idx];
                    final associatedDoctors = _problemService.getDoctorsForClinic(clinic);

                    return Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        onTap: () => _showClinicDetailsModal(context, clinic),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2)),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF012A58).withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.local_hospital_rounded, color: Color(0xFF012A58), size: 22),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          clinic.clinicName.isNotEmpty ? clinic.clinicName : 'Clinic',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '📍 ${clinic.location.isNotEmpty ? clinic.location : 'Location not specified'}',
                                          style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted, height: 1.25),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (clinic.phone.isNotEmpty || clinic.email.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            [
                                              if (clinic.phone.isNotEmpty) '📞 ${clinic.phone}',
                                              if (clinic.email.isNotEmpty) '✉️ ${clinic.email}',
                                            ].join(' • '),
                                            style: const TextStyle(fontSize: 10.5, color: Color(0xFF475569)),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  if (clinic.verified)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF012A58).withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text('VERIFIED', style: TextStyle(color: Color(0xFF012A58), fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF012A58).withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.medical_services_outlined, size: 12, color: Color(0xFF012A58)),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        associatedDoctors.isEmpty
                                            ? '0 Clinic Doctors'
                                            : '${associatedDoctors.length} Clinic Doctor${associatedDoctors.length == 1 ? '' : 's'}: ${associatedDoctors.map((d) => d.name).take(2).join(', ')}${associatedDoctors.length > 2 ? '...' : ''}',
                                        style: const TextStyle(fontSize: 10.5, color: Color(0xFF012A58), fontWeight: FontWeight.w600),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Divider(height: 1, color: Color(0xFFF1F5F9)),
                              const SizedBox(height: 8),
                              const Text('Services Offered:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 5,
                                runSpacing: 4,
                                children: clinic.services.isEmpty
                                    ? [
                                        const Text(
                                          'General Healthcare Services',
                                          style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
                                        ),
                                      ]
                                    : (clinic.services.take(4).map((serv) {
                                        return Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF1F5F9),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(serv, style: const TextStyle(fontSize: 10, color: AppTheme.textDark, fontWeight: FontWeight.w500)),
                                        );
                                      }).toList()
                                        ..addAll(clinic.services.length > 4
                                            ? [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFE2E8F0),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text('+${clinic.services.length - 4} more', style: const TextStyle(fontSize: 9.5, color: AppTheme.textMuted, fontWeight: FontWeight.bold)),
                                                )
                                              ]
                                            : [])),
                              ),
                              const Spacer(),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        const Icon(Icons.star_rounded, size: 15, color: Color(0xFFFE3434)),
                                        const SizedBox(width: 3),
                                        Text('${clinic.rating}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                        Flexible(
                                          child: Text(
                                            ' (${clinic.reviewsCount})',
                                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      InkWell(
                                        onTap: () => _showAssociateDoctorModal(context, clinic),
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF012A58).withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.person_add_alt_1_rounded, size: 12, color: Color(0xFF012A58)),
                                              SizedBox(width: 3),
                                              Text(
                                                '+ Add',
                                                style: TextStyle(fontSize: 10.5, color: Color(0xFF012A58), fontWeight: FontWeight.bold),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF012A58).withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              'Details',
                                              style: TextStyle(fontSize: 11, color: Color(0xFF012A58), fontWeight: FontWeight.bold),
                                            ),
                                            SizedBox(width: 3),
                                            Icon(Icons.arrow_forward_rounded, size: 12, color: Color(0xFF012A58)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
        ],
      ),
    );
  }

  // ==========================================
  // COMPLETE CLINIC DETAILS MODAL
  // ==========================================
  void _showClinicDetailsModal(BuildContext context, ClinicModel clinic) {
    bool didRequestClinicDocs = false;
    bool isLoadingClinicDocs = true;
    List<DoctorModel> modalDoctors = _problemService.getDoctorsForClinic(clinic);

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            if (!didRequestClinicDocs) {
              didRequestClinicDocs = true;
              _problemService.fetchClinicDoctors(clinic).then((fresh) {
                if (modalContext.mounted) {
                  setModalState(() {
                    modalDoctors = fresh.isNotEmpty ? fresh : _problemService.getDoctorsForClinic(clinic);
                    isLoadingClinicDocs = false;
                  });
                }
              }).catchError((_) {
                if (modalContext.mounted) {
                  setModalState(() => isLoadingClinicDocs = false);
                }
              });
            }

            return Dialog(
              backgroundColor: Colors.white,
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header Banner
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF012A58).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.local_hospital_rounded, color: Color(0xFF012A58), size: 24),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                clinic.clinicName.isNotEmpty ? clinic.clinicName : 'Clinic Details',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                    decoration: BoxDecoration(
                                      color: clinic.verified ? const Color(0xFF012A58).withValues(alpha: 0.12) : const Color(0xFFFE3434).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          clinic.verified ? Icons.verified_rounded : Icons.pending_rounded,
                                          size: 12,
                                          color: clinic.verified ? const Color(0xFF012A58) : const Color(0xFFFE3434),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          clinic.verified ? 'VERIFIED PRACTICE' : 'PENDING VERIFICATION',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: clinic.verified ? const Color(0xFF012A58) : const Color(0xFFFE3434),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.star_rounded, size: 15, color: Color(0xFFFE3434)),
                                      const SizedBox(width: 2),
                                      Text(
                                        '${clinic.rating} (${clinic.reviewsCount} reviews)',
                                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppTheme.textMuted),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          onPressed: () => Navigator.of(dialogCtx).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    const SizedBox(height: 14),

                    // Scrollable Content
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Section 1: Clinic Identity, Contact & Address Card
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
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Expanded(
                                        child: Row(
                                          children: [
                                            Icon(Icons.business_rounded, size: 15, color: Color(0xFF012A58)),
                                            SizedBox(width: 6),
                                            Flexible(
                                              child: Text(
                                                'Clinic Details & Contact Information',
                                                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      InkWell(
                                        onTap: () {
                                          Clipboard.setData(ClipboardData(text: clinic.location.isNotEmpty ? clinic.location : clinic.id));
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('📋 Clinic details copied to clipboard!'),
                                              duration: Duration(seconds: 2),
                                              backgroundColor: Color(0xFF012A58),
                                            ),
                                          );
                                        },
                                        borderRadius: BorderRadius.circular(6),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: const Color(0xFFCBD5E1)),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.copy_rounded, size: 11, color: Color(0xFF012A58)),
                                              SizedBox(width: 3),
                                              Text('Copy', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF012A58))),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 4,
                                    children: [
                                      Text(
                                        'Clinic ID: ${clinic.id.isNotEmpty ? clinic.id : 'N/A'}',
                                        style: const TextStyle(fontSize: 11, color: Color(0xFF475569), fontWeight: FontWeight.w600),
                                      ),
                                      Text(
                                        'Contact: ${clinic.phone.isNotEmpty ? clinic.phone : 'Not provided'}',
                                        style: const TextStyle(fontSize: 11, color: Color(0xFF475569), fontWeight: FontWeight.w600),
                                      ),
                                      Text(
                                        'Email: ${clinic.email.isNotEmpty ? clinic.email : 'Not provided'}',
                                        style: const TextStyle(fontSize: 11, color: Color(0xFF475569), fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  SelectableText(
                                    '📍 ${clinic.location.isNotEmpty ? clinic.location : 'Address not specified'}',
                                    style: const TextStyle(fontSize: 12.5, color: AppTheme.textDark, height: 1.4, fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Section 2: Services & Treatments
                            const Text(
                              '🩺 Clinical Services & Departments Offered',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                            ),
                            const SizedBox(height: 8),
                            if (clinic.services.isEmpty)
                              const Text('No specialized services listed yet.', style: TextStyle(fontSize: 12, color: AppTheme.textMuted))
                            else
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: clinic.services.map((serv) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.check_circle_rounded, size: 13, color: Color(0xFF012A58)),
                                        const SizedBox(width: 5),
                                        Text(serv, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppTheme.textDark)),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            const SizedBox(height: 18),

                            // Section 3: Registered Clinic Doctors
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                  child: Text(
                                    '👨‍⚕️ Registered Doctors (${modalDoctors.length})',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                InkWell(
                                  onTap: () {
                                    _showAssociateDoctorModal(
                                      context,
                                      clinic,
                                      onAssociated: () {
                                        if (modalContext.mounted) {
                                          setModalState(() {
                                            modalDoctors = _problemService.getDoctorsForClinic(clinic);
                                          });
                                        }
                                      },
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF012A58),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.person_add_alt_1_rounded, size: 13, color: Colors.white),
                                        SizedBox(width: 4),
                                        Text(
                                          '+ Add Doctor',
                                          style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (isLoadingClinicDocs && modalDoctors.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 20),
                                child: Center(child: CircularProgressIndicator()),
                              )
                            else if (modalDoctors.isEmpty)
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFE3434).withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0x40FE3434)),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFFFE3434)),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'No doctors are currently registered with this clinic.',
                                        style: TextStyle(fontSize: 12, color: Color(0xFFFE3434), fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: modalDoctors.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                itemBuilder: (context, docIdx) {
                                  final doc = modalDoctors[docIdx];
                                  final isDocAvail = doc.isAvailable;
                                  final cleanDocInitial = doc.name.replaceAll(RegExp(r'^Dr\.?\s*', caseSensitive: false), '').trim();
                                  final docLetter = cleanDocInitial.isNotEmpty ? cleanDocInitial[0].toUpperCase() : 'D';
                                  return Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                    ),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 22,
                                          backgroundColor: const Color(0xFF012A58).withValues(alpha: 0.12),
                                          backgroundImage: doc.photoBytes != null ? MemoryImage(doc.photoBytes!) : null,
                                          child: doc.photoBytes == null
                                              ? Text(
                                                  docLetter,
                                                  style: const TextStyle(color: Color(0xFF012A58), fontWeight: FontWeight.bold, fontSize: 15),
                                                )
                                              : null,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                doc.name,
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: AppTheme.textDark),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              Text(
                                                '${doc.specialty.isNotEmpty ? doc.specialty : 'General Medicine'}${doc.qualification.isNotEmpty ? ' • ${doc.qualification}' : ''}${doc.experienceYears > 0 ? ' • ${doc.experienceYears} yrs exp' : ''}',
                                                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              if (doc.phone.isNotEmpty || doc.email.isNotEmpty)
                                                Text(
                                                  [
                                                    if (doc.phone.isNotEmpty) '📞 ${doc.phone}',
                                                    if (doc.email.isNotEmpty) '✉️ ${doc.email}',
                                                  ].join(' • '),
                                                  style: const TextStyle(fontSize: 10.5, color: Color(0xFF012A58), fontWeight: FontWeight.w500),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: isDocAvail
                                                    ? const Color(0xFF012A58).withValues(alpha: 0.1)
                                                    : const Color(0xFFFE3434).withValues(alpha: 0.1),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                doc.status.isNotEmpty ? doc.status : (isDocAvail ? 'Available' : 'Unavailable'),
                                                style: TextStyle(
                                                  color: isDocAvail ? const Color(0xFF012A58) : const Color(0xFFFE3434),
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            IconButton(
                                              icon: const Icon(Icons.person_remove_outlined, size: 18, color: Color(0xFFFE3434)),
                                              tooltip: 'Remove Doctor from Clinic',
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                              onPressed: () async {
                                                final confirm = await showDialog<bool>(
                                                  context: dialogCtx,
                                                  builder: (c) => AlertDialog(
                                                    title: const Text('Remove Doctor from Clinic?'),
                                                    content: Text('Disassociate ${doc.name} from ${clinic.clinicName}?\n\nThe doctor\'s global account and patient records will be preserved.'),
                                                    actions: [
                                                      TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
                                                      ElevatedButton(
                                                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFE3434), foregroundColor: Colors.white),
                                                        onPressed: () => Navigator.of(c).pop(true),
                                                        child: const Text('Remove'),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                                if (confirm == true) {
                                                  final removed = await _problemService.removeDoctorFromClinicAssociation(
                                                    clinic: clinic,
                                                    doctor: doc,
                                                  );
                                                  if (modalContext.mounted) {
                                                    setModalState(() {
                                                      modalDoctors = _problemService.getDoctorsForClinic(clinic);
                                                    });
                                                  }
                                                  if (context.mounted) {
                                                    setState(() {});
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(
                                                        content: Text(
                                                          removed
                                                              ? '${doc.name} removed from ${clinic.clinicName}. Global doctor account preserved.'
                                                              : 'Failed to update doctor clinic association.',
                                                        ),
                                                        backgroundColor: const Color(0xFF012A58),
                                                      ),
                                                    );
                                                  }
                                                }
                                              },
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    const SizedBox(height: 14),

                    // Modal Footer Actions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(dialogCtx).pop();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ClinicDashboardScreen(
                                  clinicName: clinic.clinicName,
                                  initialTab: 1,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.dashboard_customize_rounded, size: 16, color: Color(0xFF012A58)),
                          label: const Text('Open Clinic Workspace', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF012A58))),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF012A58)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.of(dialogCtx).pop(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF012A58),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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

  void _showAssociateDoctorModal(
    BuildContext context,
    ClinicModel clinic, {
    VoidCallback? onAssociated,
  }) {
    String selectedDocId = '';
    String searchQuery = '';
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final currentAssociated = _problemService.getDoctorsForClinic(clinic).map((d) => d.id).toSet();
            final candidates = _uniqueDoctors.where((d) {
              if (currentAssociated.contains(d.id)) return false;
              if (searchQuery.isEmpty) return true;
              final q = searchQuery.toLowerCase();
              return d.name.toLowerCase().contains(q) ||
                  d.specialty.toLowerCase().contains(q) ||
                  d.phone.toLowerCase().contains(q);
            }).toList();

            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 480, maxHeight: 540),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF012A58)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Add Doctor to ${clinic.clinicName}',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.of(dialogCtx).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      onChanged: (v) => setModalState(() => searchQuery = v),
                      decoration: InputDecoration(
                        hintText: 'Search registered doctors by name, specialty, phone...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: candidates.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text(
                                    'No unassociated doctors match your search.',
                                    style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
                                  ),
                                  const SizedBox(height: 12),
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.add_rounded, size: 16),
                                    label: const Text('Register New Doctor Instead'),
                                    onPressed: () {
                                      Navigator.of(dialogCtx).pop();
                                      _showRegisterDoctorModal(context);
                                    },
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              itemCount: candidates.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (_, idx) {
                                final doc = candidates[idx];
                                final isSelected = selectedDocId == doc.id;
                                return InkWell(
                                  onTap: () => setModalState(() => selectedDocId = doc.id),
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: isSelected ? const Color(0xFF012A58).withValues(alpha: 0.08) : Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isSelected ? const Color(0xFF012A58) : const Color(0xFFE2E8F0),
                                        width: isSelected ? 1.5 : 1.0,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 18,
                                          backgroundColor: const Color(0xFF012A58).withValues(alpha: 0.1),
                                          child: Text(
                                            doc.name.replaceAll(RegExp(r'^Dr\.?\s*', caseSensitive: false), '').characters.firstOrNull?.toUpperCase() ?? 'D',
                                            style: const TextStyle(color: Color(0xFF012A58), fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(doc.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
                                              Text('${doc.specialty}${doc.phone.isNotEmpty ? ' • ${doc.phone}' : ''}', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted), overflow: TextOverflow.ellipsis),
                                            ],
                                          ),
                                        ),
                                        Icon(
                                          isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                          color: isSelected ? const Color(0xFF012A58) : Colors.grey,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: const Text('Cancel')),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF012A58), foregroundColor: Colors.white),
                          onPressed: (selectedDocId.isEmpty || isSaving)
                              ? null
                              : () async {
                                  setModalState(() => isSaving = true);
                                  final doc = candidates.firstWhere((d) => d.id == selectedDocId);
                                  final ok = await _problemService.associateDoctorToClinic(clinic: clinic, doctor: doc);
                                  if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
                                  onAssociated?.call();
                                  if (mounted) setState(() {});
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(ok ? '✅ ${doc.name} associated with ${clinic.clinicName}.' : '❌ Failed to associate doctor.'),
                                        backgroundColor: ok ? const Color(0xFF012A58) : const Color(0xFFFE3434),
                                      ),
                                    );
                                  }
                                },
                          child: isSaving
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Text('Associate Doctor', style: TextStyle(fontWeight: FontWeight.bold)),
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

  void _showRegisterClinicModal(BuildContext context) {
    final nameCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    final servicesCtrl = TextEditingController(text: 'General Medicine, Specialized Consultations, Diagnostics, Preventative Care');
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 480),
                padding: const EdgeInsets.all(22),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF012A58).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.add_location_alt_rounded, color: Color(0xFF012A58)),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Register New Clinic', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark), overflow: TextOverflow.ellipsis),
                                Text('Create new clinical practice profile', style: TextStyle(fontSize: 11, color: AppTheme.textMuted), overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      TextField(
                        controller: nameCtrl,
                        style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                        cursorColor: AppTheme.primaryBlue,
                        decoration: InputDecoration(
                          labelText: 'Clinic Name *',
                          hintText: 'e.g. City Healthcare Center',
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: locationCtrl,
                        maxLines: 2,
                        style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                        cursorColor: AppTheme.primaryBlue,
                        decoration: InputDecoration(
                          labelText: 'Full Address / Location *',
                          hintText: 'e.g. Door No, Street / Area / City / Pincode',
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: servicesCtrl,
                        style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                        cursorColor: AppTheme.primaryBlue,
                        decoration: InputDecoration(
                          labelText: 'Services Offered (Comma separated)',
                          hintText: 'Teeth Cleaning, Root Canal, Orthodontics',
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            icon: isSaving
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.check, size: 16, color: Colors.white),
                            label: Text(isSaving ? 'Registering...' : 'Register Clinic', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF012A58),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: isSaving
                                ? null
                                : () async {
                                    final name = nameCtrl.text.trim();
                                    final loc = locationCtrl.text.trim();
                                    if (name.isEmpty || loc.isEmpty) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('⚠️ Please fill in Clinic Name and Address.')),
                                      );
                                      return;
                                    }
                                    setModalState(() => isSaving = true);
                                    final servList = servicesCtrl.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

                                    final success = await _problemService.registerClinic(
                                      clinicName: name,
                                      location: loc,
                                      services: servList,
                                    );

                                    setModalState(() => isSaving = false);
                                    if (!context.mounted) return;
                                    Navigator.of(dialogContext).pop();

                                    if (success) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('🎉 Clinic "$name" registered successfully!'),
                                          backgroundColor: const Color(0xFF012A58),
                                        ),
                                      );
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('❌ Failed to save clinic profile.'),
                                          backgroundColor: Color(0xFFFE3434),
                                        ),
                                      );
                                    }
                                  },
                          ),
                        ],
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

  void _showNotificationsModal(BuildContext context, String role) {
    _problemService.syncNotificationsFromApi(role: role);

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final notifs = _problemService.getNotificationsForRole(role);
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
                              const Icon(Icons.notifications_active_rounded, color: AppTheme.primaryBlue, size: 22),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Admin System Notifications',
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
                            key: const Key('admin_mark_all_notifications_read'),
                            onPressed: () async {
                              await _problemService.markAllNotificationsRead(role);
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
                          child: Text('No system notifications.', style: TextStyle(color: Colors.grey, fontSize: 12)),
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
                              key: Key('admin_notification_item_${n.id}'),
                              onTap: () async {
                                if (isUnread) {
                                  await _problemService.markNotificationRead(n.id);
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

  void _showRegisterDoctorModal(BuildContext context) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final qualCtrl = TextEditingController();
    final licenseCtrl = TextEditingController();
    final clinicCtrl = TextEditingController();
    final expCtrl = TextEditingController();
    final feeCtrl = TextEditingController();
    final stateCtrl = TextEditingController();
    final cityCtrl = TextEditingController();
    final pincodeCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    String selectedSpecialty = _problemService.activeSpecialtyNames.isNotEmpty
        ? _problemService.activeSpecialtyNames.first
        : 'General Medicine';
    String selectedLanguage = 'English';
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: 520,
                  maxHeight: screenHeight * 0.85,
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
                            color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.person_add_alt_1_rounded, color: AppTheme.primaryBlue, size: 20),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Create New Doctor Account',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Mobile identifier authentication • Ready for OTP Sign-In',
                                style: TextStyle(fontSize: 10, color: AppTheme.textMuted),
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

                    // Scrollable Form Fields Body
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Doctor Name *
                            TextField(
                              controller: nameCtrl,
                              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                              cursorColor: AppTheme.primaryBlue,
                              decoration: InputDecoration(
                                labelText: 'Doctor Full Name *',
                                hintText: 'e.g. Dr. Jane Miller',
                                prefixIcon: const Icon(Icons.person_outline, size: 16),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Mobile Phone Number *
                            TextField(
                              controller: phoneCtrl,
                              keyboardType: TextInputType.phone,
                              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                              cursorColor: AppTheme.primaryBlue,
                              decoration: InputDecoration(
                                labelText: 'Mobile Phone Number *',
                                hintText: 'e.g. +91 98765 43210',
                                prefixIcon: const Icon(Icons.phone_android_rounded, size: 16),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Email Address (Optional)
                            TextField(
                              controller: emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                              cursorColor: AppTheme.primaryBlue,
                              decoration: InputDecoration(
                                labelText: 'Email Address (Optional)',
                                hintText: 'e.g. jane@gshealth.com (Optional)',
                                prefixIcon: const Icon(Icons.email_outlined, size: 16),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Specialization & Qualification
                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: DropdownButtonFormField<String>(
                                    initialValue: selectedSpecialty,
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      labelText: 'Medical Specialty',
                                      prefixIcon: const Icon(Icons.medical_services_outlined, size: 16),
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    items: <String>{
                                      ..._problemService.activeSpecialtyNames,
                                      'General Dentistry',
                                      'Orthodontics',
                                      'Endodontics',
                                      'Periodontics',
                                      'Pediatric Dentistry',
                                      'Oral & Maxillofacial Surgery',
                                      'Cosmetic Dentistry',
                                    }.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis))).toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        setModalState(() {
                                          selectedSpecialty = val;
                                          final currentQual = qualCtrl.text.trim();
                                          if (currentQual.isEmpty || currentQual == 'BDS, MDS' || currentQual == 'MBBS, MD') {
                                            qualCtrl.text = MedicalSpecialtyModel.getDefaultQualificationForSpecialty(val);
                                          }
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
                                      hintText: 'MBBS, MD / BDS',
                                      prefixIcon: const Icon(Icons.school_outlined, size: 16),
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // License Number & Experience
                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: TextField(
                                    controller: licenseCtrl,
                                    style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                                    cursorColor: AppTheme.primaryBlue,
                                    decoration: InputDecoration(
                                      labelText: 'License Number *',
                                      hintText: 'e.g. DEN-88490',
                                      prefixIcon: const Icon(Icons.badge_outlined, size: 16),
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
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
                                    cursorColor: AppTheme.primaryBlue,
                                    decoration: InputDecoration(
                                      labelText: 'Years Exp.',
                                      hintText: '5',
                                      prefixIcon: const Icon(Icons.work_history_outlined, size: 16),
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // State, City & Pincode
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: stateCtrl,
                                    style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                                    cursorColor: AppTheme.primaryBlue,
                                    decoration: InputDecoration(
                                      labelText: 'State',
                                      hintText: 'e.g. Telangana',
                                      prefixIcon: const Icon(Icons.map_outlined, size: 15),
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: TextField(
                                    controller: cityCtrl,
                                    style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                                    cursorColor: AppTheme.primaryBlue,
                                    decoration: InputDecoration(
                                      labelText: 'City (Optional)',
                                      hintText: 'e.g. Hyderabad',
                                      prefixIcon: const Icon(Icons.location_city_outlined, size: 15),
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: TextField(
                                    controller: pincodeCtrl,
                                    keyboardType: TextInputType.number,
                                    style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                                    cursorColor: AppTheme.primaryBlue,
                                    decoration: InputDecoration(
                                      labelText: 'Pincode (Optional)',
                                      hintText: 'e.g. 500032',
                                      prefixIcon: const Icon(Icons.pin_drop_outlined, size: 15),
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // Practice / Clinic Name & Fee
                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: TextField(
                                    controller: clinicCtrl,
                                    style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                                    cursorColor: AppTheme.primaryBlue,
                                    decoration: InputDecoration(
                                      labelText: 'Practice / Clinic Name (Optional)',
                                      hintText: 'e.g. Apex Care Clinic',
                                      prefixIcon: const Icon(Icons.storefront_outlined, size: 16),
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    controller: feeCtrl,
                                    style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                                    cursorColor: AppTheme.primaryBlue,
                                    decoration: InputDecoration(
                                      labelText: 'Fee',
                                      hintText: 'Enter fee',
                                      prefixIcon: const Icon(Icons.payments_outlined, size: 16),
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // Clinic Address
                            TextField(
                              controller: addressCtrl,
                              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                              cursorColor: AppTheme.primaryBlue,
                              decoration: InputDecoration(
                                labelText: 'Clinic Address / Location',
                                hintText: 'Enter clinic address',
                                prefixIcon: const Icon(Icons.place_outlined, size: 16),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Languages Known Selection Dropdown (No symbol)
                            DropdownButtonFormField<String>(
                              initialValue: selectedLanguage,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: 'Languages Known / Spoken',
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              items: const [
                                'English', 'Hindi', 'Telugu', 'Tamil', 'Kannada', 'Malayalam', 'Marathi', 'Bengali', 'Gujarati', 'Punjabi', 'Spanish'
                              ].map((lang) {
                                return DropdownMenuItem(value: lang, child: Text(lang, style: const TextStyle(fontSize: 12)));
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setModalState(() => selectedLanguage = val);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Fixed Submit Button at Bottom
                    ElevatedButton.icon(
                      icon: isSubmitting
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check_circle_rounded, size: 16),
                      label: Text(
                        isSubmitting ? 'Creating Doctor Account...' : 'Create Doctor Account',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: isSubmitting
                          ? null
                          : () async {
                              final name = nameCtrl.text.trim();
                              final phone = phoneCtrl.text.trim();
                              final email = emailCtrl.text.trim();

                              if (name.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter doctor name.')));
                                return;
                              }
                              if (phone.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter mobile phone number.')));
                                return;
                              }

                              setModalState(() => isSubmitting = true);

                              final expYears = int.tryParse(expCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 5;
                              final doctor = _problemService.registerDoctor(
                                name: name,
                                email: email,
                                phone: phone,
                                licenseNumber: licenseCtrl.text.trim(),
                                specialty: selectedSpecialty,
                                qualification: qualCtrl.text.isNotEmpty
                                    ? qualCtrl.text
                                    : MedicalSpecialtyModel.getDefaultQualificationForSpecialty(selectedSpecialty),
                                clinicName: clinicCtrl.text.trim(),
                                experienceYears: expYears,
                                consultationFee: feeCtrl.text.trim(),
                                state: stateCtrl.text.trim(),
                                city: cityCtrl.text.trim(),
                                pincode: pincodeCtrl.text.trim(),
                                clinicAddress: addressCtrl.text.trim(),
                                languages: [selectedLanguage],
                                setAsCurrentDoctor: false,
                              );

                              Navigator.of(dialogContext).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('🎉 Registered ${doctor.name} successfully! Doctor can now sign in using Mobile OTP.'),
                                  backgroundColor: const Color(0xFF012A58),
                                  duration: const Duration(seconds: 4),
                                ),
                              );
                            },
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

  void _showEditDoctorFeeAndSlotsDialog(BuildContext context, DoctorModel doc) {
    final feeCtrl = TextEditingController(text: doc.consultationFee);
    final slotCtrl = TextEditingController(text: doc.nextAvailableSlots.isNotEmpty ? doc.nextAvailableSlots.first : '');
    final qualCtrl = TextEditingController(text: doc.qualification);
    final clinicCtrl = TextEditingController(text: doc.clinicName);
    final specOptions = <String>{
      ..._problemService.activeSpecialtyNames,
      'General Dentistry',
      'Orthodontics',
      'Endodontics',
      'Periodontics',
      doc.specialty,
    }.where((s) => s.isNotEmpty).toList();
    String selectedSpecialty = specOptions.contains(doc.specialty) ? doc.specialty : specOptions.first;
    String selectedVerification = doc.status == 'Suspended' ? 'SUSPENDED' : 'VERIFIED';

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text('Manage Profile, Verification & Slots • ${doc.name}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selectedSpecialty,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Medical Specialty',
                        prefixIcon: const Icon(Icons.medical_services_outlined),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: specOptions
                          .map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setModalState(() => selectedSpecialty = v);
                      },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: qualCtrl,
                      style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                      cursorColor: AppTheme.primaryBlue,
                      decoration: InputDecoration(
                        labelText: 'Qualifications',
                        hintText: 'MBBS, MD / BDS, MDS',
                        prefixIcon: const Icon(Icons.school_outlined),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: clinicCtrl,
                      style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                      cursorColor: AppTheme.primaryBlue,
                      decoration: InputDecoration(
                        labelText: 'Associated Clinic / Hospital',
                        prefixIcon: const Icon(Icons.local_hospital_outlined),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: selectedVerification,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Doctor Verification Status',
                        prefixIcon: const Icon(Icons.verified_user_outlined),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'VERIFIED', child: Text('Verified & Approved', style: TextStyle(fontSize: 12))),
                        DropdownMenuItem(value: 'PENDING_VERIFICATION', child: Text('Pending Verification', style: TextStyle(fontSize: 12))),
                        DropdownMenuItem(value: 'SUSPENDED', child: Text('Suspended', style: TextStyle(fontSize: 12))),
                      ],
                      onChanged: (v) {
                        if (v != null) setModalState(() => selectedVerification = v);
                      },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: feeCtrl,
                      style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                      cursorColor: AppTheme.primaryBlue,
                      decoration: InputDecoration(
                        labelText: 'Standard Consultation Fee',
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
                        hintText: 'e.g. Today, 3:30 PM',
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
                  icon: const Icon(Icons.save_rounded, size: 16),
                  label: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    await _problemService.updateDoctorProfessionalProfile(
                      doctorId: doc.id,
                      specialty: selectedSpecialty,
                      qualification: qualCtrl.text.trim(),
                      clinicName: clinicCtrl.text.trim(),
                      consultationFee: feeCtrl.text.trim(),
                      verificationStatus: selectedVerification,
                    );
                    _problemService.updateDoctorFeeAndSlots(
                      doctorId: doc.id,
                      consultationFee: feeCtrl.text.trim(),
                      availableSlot: slotCtrl.text.trim(),
                    );
                    if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('⚡ Updated ${doc.name} (${selectedSpecialty}) profile, verification & slots!'),
                          backgroundColor: const Color(0xFF012A58),
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

  void _confirmRemoveDoctor(BuildContext context, DoctorModel doc) {
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFFE3434), size: 24),
              const SizedBox(width: 8),
              Text('Remove ${doc.name}?', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: Text('Are you sure you want to remove ${doc.name} (${doc.specialty}) from the platform directory?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: const Text('Cancel')),
            ElevatedButton.icon(
              icon: const Icon(Icons.delete_forever_rounded, size: 16),
              label: const Text('Remove Doctor', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(backgroundColor: Color(0xFFFE3434), foregroundColor: Colors.white),
              onPressed: () {
                _problemService.removeDoctor(doc.id);
                Navigator.of(dialogCtx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('🗑️ ${doc.name} removed from platform directory.'),
                    backgroundColor: Color(0xFFFE3434),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  // ==========================================
  // PANEL 2: MASTER DOCTORS & SPECIALISTS DIRECTORY (ALL SPECIALTIES)
  // ==========================================
  String _adminDoctorSpecialtyFilter = 'All';

  void _openAdminSpecialtyDoctorsPage(
    String specialty,
    PatientConsultationRequest? pendingRequest,
  ) {
    final clean = specialty.trim();
    if (clean.isEmpty || clean.toLowerCase() == 'all' || clean.toLowerCase() == 'all specialties') {
      setState(() => _adminDoctorSpecialtyFilter = 'All');
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FindDoctorsScreen(
          initialSpecialty: clean,
          isSpecialtyPage: true,
          isAdminView: true,
          onAdminCreateDoctor: () => _showRegisterDoctorModal(context),
          onAdminEditDoctor: (ctx, doc) => _showEditDoctorFeeAndSlotsDialog(ctx, doc),
          onAdminDeleteDoctor: (ctx, doc) => _confirmRemoveDoctor(ctx, doc),
          onAdminAssignDoctor: pendingRequest != null
              ? (ctx, doc) => _showAssignDoctorDialog(ctx, pendingRequest, preSelectedDoctor: doc)
              : null,
        ),
      ),
    );
  }

  void _openAdminDoctorProfilePage(
    DoctorModel doc,
    PatientConsultationRequest? pendingRequest,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (routeCtx) => DoctorProfileScreen(
          doctor: doc,
          isAdminView: true,
          onAdminEditDoctor: () {
            final current = _problemService.allDoctors
                    .where((d) => d.id == doc.id)
                    .firstOrNull ??
                doc;
            _showEditDoctorFeeAndSlotsDialog(routeCtx, current);
          },
          onAdminDeleteDoctor: () {
            final current = _problemService.allDoctors
                    .where((d) => d.id == doc.id)
                    .firstOrNull ??
                doc;
            _confirmRemoveDoctor(routeCtx, current);
          },
          onAdminAssignDoctor: pendingRequest != null
              ? () {
                  final current = _problemService.allDoctors
                          .where((d) => d.id == doc.id)
                          .firstOrNull ??
                      doc;
                  _showAssignDoctorDialog(
                    routeCtx,
                    pendingRequest,
                    preSelectedDoctor: current,
                  );
                }
              : null,
        ),
      ),
    );
  }

  Widget _buildDentistsPanel() {
    final allDoctors = _uniqueDoctors;
    final doctors = allDoctors.where((doc) {
      return MedicalSpecialtyModel.matchesSpecialtyFilter(doc.specialty, _adminDoctorSpecialtyFilter);
    }).toList();
    final requests = _problemService.requests;
    final PatientConsultationRequest? pendingRequest =
        requests.where((r) => r.status == 'Pending Admin Review').firstOrNull ?? requests.firstOrNull;
    final activeSpecs = _problemService.activeSpecialties;
    final filterOptions = <String>{
      ...activeSpecs.map((s) => s.name),
    }.toList();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.medical_services_rounded, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '👨‍⚕️ Master Doctors Directory, Verification & Specialist Assignment',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      SizedBox(height: 3),
                      const Text(
                        'All multi-specialty medical specialists registered on GS HEALTH • Tap any doctor to view profile & availability',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Statistics Header
          Row(
            children: [
              _buildMiniStatCard('Total Doctors', '${allDoctors.length}', Icons.badge_rounded, AppTheme.primaryBlue),
              const SizedBox(width: 12),
              _buildMiniStatCard('Available Now', '${allDoctors.where((d) => d.status == 'Available').length}', Icons.check_circle_rounded, const Color(0xFF012A58)),
              const SizedBox(width: 12),
              _buildMiniStatCard('Specialties', '${activeSpecs.length}', Icons.category_rounded, const Color(0xFFFE3434)),
            ],
          ),
          const SizedBox(height: 16),

          // ALL Specialty Dropdown + Quick Specialty Chips Strip
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                PopupMenuButton<String>(
                  key: const Key('admin_all_specialties_dropdown_button'),
                  tooltip: 'Select Medical Specialty',
                  offset: const Offset(0, 44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  color: Colors.white,
                  onSelected: (value) => _openAdminSpecialtyDoctorsPage(value, pendingRequest),
                  itemBuilder: (context) => [
                    PopupMenuItem<String>(
                      value: 'All',
                      child: Row(
                        children: [
                          Icon(
                            _adminDoctorSpecialtyFilter == 'All'
                                ? Icons.check_circle_rounded
                                : Icons.medical_services_outlined,
                            size: 16,
                            color: _adminDoctorSpecialtyFilter == 'All'
                                ? AppTheme.primaryBlue
                                : AppTheme.textMedium,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'All Specialties',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: _adminDoctorSpecialtyFilter == 'All'
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: AppTheme.textDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    ...activeSpecs.map(
                      (spec) => PopupMenuItem<String>(
                        key: Key('admin_specialty_dropdown_item_${spec.name}'),
                        value: spec.name,
                        child: Row(
                          children: [
                            const Icon(
                              Icons.local_hospital_outlined,
                              size: 16,
                              color: AppTheme.primaryBlue,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                spec.name,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: AppTheme.textDark,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 12,
                              color: AppTheme.textMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_rounded, size: 15, color: Colors.white),
                        SizedBox(width: 6),
                        Text(
                          'All',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Colors.white),
                      ],
                    ),
                  ),
                ),
                ...filterOptions.map((spec) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      key: Key('admin_specialty_chip_$spec'),
                      label: Text(
                        spec,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textDark,
                        ),
                      ),
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      onPressed: () => _openAdminSpecialtyDoctorsPage(spec, pendingRequest),
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (_showPendingVerificationOnly) ...[
            Builder(
              builder: (context) {
                final pendingList = _uniqueDoctors.where(isPendingVerificationDoctor).toList();
                return Container(
                  key: const Key('admin_pending_verification_panel'),
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.gsRed.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.gsRed.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.verified_user_outlined, color: AppTheme.gsRed, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Doctors pending verification (${pendingList.length})',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: AppTheme.gsNavy),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          TextButton(
                            onPressed: () => setState(() => _showPendingVerificationOnly = false),
                            child: const Text('Show all', style: TextStyle(color: AppTheme.gsNavy, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                      if (pendingList.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text(
                            'No doctors currently pending verification.',
                            style: TextStyle(fontSize: 12.5, color: AppTheme.textMedium),
                          ),
                        )
                      else
                        ...pendingList.map(
                          (doc) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(doc.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                            subtitle: Text('${doc.specialty} · ${doc.verificationStatus}', style: const TextStyle(fontSize: 11.5)),
                            trailing: TextButton(
                              onPressed: () => _showEditDoctorFeeAndSlotsDialog(context, doc),
                              child: const Text('Verify'),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'All Registered Doctors & Specialists',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                key: const Key('admin_create_doctor_button'),
                icon: const Icon(Icons.person_add_rounded, size: 16),
                label: const Text('+ Create Doctor', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _showRegisterDoctorModal(context),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Compact Single-Line List of Doctors
          if (doctors.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Column(
                children: [
                  Icon(Icons.medical_services_outlined, size: 42, color: AppTheme.textMuted),
                  SizedBox(height: 10),
                  Text('No Doctors Registered Yet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark)),
                  SizedBox(height: 4),
                  Text('Click "+ Create Doctor" above to onboard a doctor into the platform.',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: doctors.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final doc = doctors[index];
                return _buildAdminCompactDoctorRow(doc, pendingRequest);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildAdminCompactDoctorRow(
    DoctorModel doc,
    PatientConsultationRequest? pendingRequest,
  ) {
    final rawInitial = doc.name
        .replaceAll(RegExp(r'^Dr\.?\s*', caseSensitive: false), '')
        .trim();
    final initial = rawInitial.isNotEmpty ? rawInitial[0].toUpperCase() : 'D';
    final displayName = doc.name.trim().toLowerCase().startsWith('dr')
        ? doc.name.trim()
        : 'Dr. ${doc.name.trim()}';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: Key('admin_doctor_card_${doc.id}'),
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openAdminDoctorProfilePage(doc, pendingRequest),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.025),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              GestureDetector(
                key: Key('admin_doctor_image_${doc.id}'),
                onTap: () => _openAdminDoctorProfilePage(doc, pendingRequest),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primaryBlue,
                        AppTheme.primaryBlue.withValues(alpha: 0.78),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: GestureDetector(
                  key: Key('admin_doctor_name_${doc.id}'),
                  onTap: () => _openAdminDoctorProfilePage(doc, pendingRequest),
                  child: Text(
                    displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppTheme.textDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                key: Key('admin_view_profile_button_${doc.id}'),
                tooltip: 'View Doctor Profile',
                onPressed: () => _openAdminDoctorProfilePage(doc, pendingRequest),
                icon: const Icon(
                  Icons.arrow_forward_rounded,
                  size: 20,
                  color: AppTheme.primaryBlue,
                ),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniStatCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 10, color: AppTheme.textMuted), overflow: TextOverflow.ellipsis),
                  Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textDark), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAdminCoordinatorStageDialog(BuildContext ctx, PatientConsultationRequest req) async {
    String selectedStage = PatientProblemService.coordinatorLifecycleStages.first;
    final noteCtrl = TextEditingController();
    await showDialog<void>(
      context: ctx,
      builder: (dCtx) => StatefulBuilder(
        builder: (dCtx, setDialogState) => AlertDialog(
          title: Text('Coordinator Stage • ${req.patientName}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedStage,
                decoration: const InputDecoration(labelText: 'Escalation Status'),
                items: PatientProblemService.coordinatorLifecycleStages
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setDialogState(() => selectedStage = v ?? selectedStage),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Follow-up Note (Optional)',
                  hintText: 'Phone call outcome / specialist matched',
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dCtx).pop(), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final res = await _problemService.updateCoordinatorRequestStatus(
                  requestId: req.id,
                  status: selectedStage,
                  followUpNote: noteCtrl.text.trim(),
                );
                final ok = res['success'] == true;
                if (dCtx.mounted) Navigator.of(dCtx).pop();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(ok ? 'Status updated to $selectedStage' : 'Failed to update status'),
                      backgroundColor: ok ? const Color(0xFF012A58) : const Color(0xFFFE3434),
                    ),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteRequest(BuildContext context, PatientConsultationRequest req) {
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(
            children: [
              Icon(Icons.delete_forever_rounded, color: Color(0xFFFE3434), size: 22),
              SizedBox(width: 8),
              Text('Remove Consultation', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: Text(
            'Are you sure you want to delete the consultation request for "${req.patientName}" (${req.problemCategory})? This action cannot be undone and will permanently remove it from Supabase.',
            style: const TextStyle(fontSize: 13, color: AppTheme.textMedium),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.delete_outline_rounded, size: 16),
              label: const Text('Delete Permanently'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFFFE3434),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.of(dialogCtx).pop();
                await _problemService.deleteProblemRequest(req.id);
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('🗑️ Consultation request for "${req.patientName}" removed successfully.'),
                      backgroundColor: Color(0xFFFE3434),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                  setState(() {});
                }
              },
            ),
          ],
        );
      },
    );
  }

  // ==========================================
  // PANEL 1: ADMIN DASHBOARD (RESPONSIVE & OVERFLOW FREE)
  // ==========================================
  Widget _buildDashboardPanel() {
    final Map<String, PatientConsultationRequest> uniqueMap = {};
    for (final r in _problemService.requests) {
      final pKey = (r.patientId != null && r.patientId!.isNotEmpty && !r.patientId!.startsWith('USR-'))
          ? r.patientId!.trim().toLowerCase()
          : (r.patientName.isNotEmpty && r.patientName.toLowerCase() != 'patient' && r.patientName != 'Patient Consultation' ? r.patientName.trim().toLowerCase() : '');
      final catKey = r.problemCategory.trim().toLowerCase();
      final key = (pKey.isNotEmpty && catKey.isNotEmpty) ? '${pKey}_$catKey' : r.id;

      if (!uniqueMap.containsKey(key)) {
        uniqueMap[key] = r;
      } else {
        final existing = uniqueMap[key]!;
        final hasRealUuid = r.id.isNotEmpty && !r.id.startsWith('PR-') && !r.id.startsWith('REQ-');
        final hasAssignedDoctor = (r.assignedDoctorName != null && r.assignedDoctorName!.isNotEmpty && r.assignedDoctorName != 'null');
        final isConfirmed = (r.status == 'Confirmed' || r.status == 'Accepted' || r.status == 'Doctor Assigned');

        uniqueMap[key] = PatientConsultationRequest(
          id: hasRealUuid ? r.id : existing.id,
          patientId: (r.patientId != null && r.patientId!.isNotEmpty) ? r.patientId : existing.patientId,
          patientName: (r.patientName.isNotEmpty && r.patientName != 'Patient' && r.patientName != 'Patient Consultation') ? r.patientName : existing.patientName,
          patientPhone: r.patientPhone.isNotEmpty ? r.patientPhone : existing.patientPhone,
          problemCategory: r.problemCategory.isNotEmpty ? r.problemCategory : existing.problemCategory,
          problemDescription: (r.problemDescription.isNotEmpty && r.problemDescription != 'Scheduled dental consultation') ? r.problemDescription : existing.problemDescription,
          symptoms: r.symptoms.isNotEmpty ? r.symptoms : existing.symptoms,
          preferredLocation: r.preferredLocation.isNotEmpty ? r.preferredLocation : existing.preferredLocation,
          severity: r.severity.isNotEmpty ? r.severity : existing.severity,
          submittedAt: r.submittedAt,
          status: (isConfirmed || r.status.isNotEmpty) ? r.status : existing.status,
          adminNotes: (r.adminNotes != null && r.adminNotes!.isNotEmpty) ? r.adminNotes : existing.adminNotes,
          assignedDoctorId: (r.assignedDoctorId != null && r.assignedDoctorId!.isNotEmpty) ? r.assignedDoctorId : existing.assignedDoctorId,
          assignedDoctorName: hasAssignedDoctor ? r.assignedDoctorName : existing.assignedDoctorName,
          assignedDoctorSpecialty: (r.assignedDoctorSpecialty != null && r.assignedDoctorSpecialty!.isNotEmpty) ? r.assignedDoctorSpecialty : existing.assignedDoctorSpecialty,
          assignedDoctorClinic: (r.assignedDoctorClinic != null && r.assignedDoctorClinic!.isNotEmpty) ? r.assignedDoctorClinic : existing.assignedDoctorClinic,
          confirmedTimeSlot: (r.confirmedTimeSlot != null && r.confirmedTimeSlot!.isNotEmpty) ? r.confirmedTimeSlot : existing.confirmedTimeSlot,
          city: r.city.isNotEmpty ? r.city : existing.city,
          pincode: r.pincode.isNotEmpty ? r.pincode : existing.pincode,
          state: r.state.isNotEmpty ? r.state : existing.state,
        );
      }
    }
    final requests = uniqueMap.values.toList();
    final pendingCount = requests.where((r) {
      final st = r.status.trim().toLowerCase();
      return st == 'pending admin review' || st == 'submitted' || st == 'admin review';
    }).length;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          // KPI Stat Metrics Grid (Adaptable crossAxisCount & childAspectRatio)
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final crossCount = w > 900 ? 5 : (w > 650 ? 3 : (w > 420 ? 2 : 1));
              final childRatio = w > 900 ? 1.45 : (w > 650 ? 1.5 : (w > 420 ? 1.6 : 2.6));

              return GridView.count(
                crossAxisCount: crossCount,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: childRatio,
                children: [
                  _KpiCard(
                    title: 'Total Patients',
                    value: '${_uniquePatients.length}',
                    growth: 'Central DB Synced',
                    accentColor: AppTheme.primaryBlue,
                    icon: Icons.people_alt_rounded,
                  ),
                  _KpiCard(
                    title: 'Total Doctors',
                    value: '${_uniqueDoctors.length}',
                    growth: 'Verified Doctors',
                    accentColor: const Color(0xFF012A58),
                    icon: Icons.medical_services_rounded,
                  ),
                  _KpiCard(
                    title: 'Total Referrals',
                    value: '${_problemService.adminPatientReferrals.length}',
                    growth: 'Patient-to-Doctor',
                    accentColor: const Color(0xFFFE3434),
                    icon: Icons.share_rounded,
                  ),
                  _KpiCard(
                    title: 'Pending Consultations',
                    value: '$pendingCount',
                    growth: 'Requires Action',
                    accentColor: const Color(0xFFFE3434),
                    icon: Icons.pending_actions_rounded,
                  ),
                  _KpiCard(
                    title: 'Total Sub-Admins',
                    value: '${_uniqueSubAdmins.length}',
                    growth: 'Portal Sub-Admins',
                    accentColor: const Color(0xFFFE3434),
                    icon: Icons.supervisor_account_rounded,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),

          // PATIENT PROBLEM CONSULTATIONS CONTAINER
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '🩺 Patient Problem Consultations',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Review symptoms & assign doctor via WhatsApp',
                            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0x14012A58),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.mark_chat_read_rounded, size: 14, color: Color(0xFFFE3434)),
                          SizedBox(width: 4),
                          Text(
                            'WhatsApp',
                            style: TextStyle(color: Color(0xFFFE3434), fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                if (requests.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.inbox_outlined, size: 36, color: AppTheme.textMuted),
                        SizedBox(height: 8),
                        Text('No patient consultation requests found.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark)),
                        SizedBox(height: 4),
                        const Text('New patient consultation requests raised by patients will appear here for admin review.', style: TextStyle(fontSize: 11, color: AppTheme.textMuted), textAlign: TextAlign.center),
                      ],
                    ),
                  )
                else
                  Column(
                    children: requests.map((req) {
                      final isPending = req.status == 'Pending Admin Review';

                      return LayoutBuilder(
                        builder: (context, cardConstraints) {
                          final displayPatientName = req.patientName.trim().isNotEmpty && req.patientName.trim().toLowerCase() != 'patient'
                              ? req.patientName.trim()
                              : (_problemService.allPatients.any((p) => (req.patientId != null && p.id == req.patientId) || (p.name.isNotEmpty && p.name.toLowerCase() != 'patient'))
                                  ? _problemService.allPatients.firstWhere((p) => (req.patientId != null && p.id == req.patientId) || (p.name.isNotEmpty && p.name.toLowerCase() != 'patient')).name
                                  : 'Patient');
                          final displayPhone = req.patientPhone.isNotEmpty
                              ? req.patientPhone
                              : (_problemService.allPatients.firstWhere((p) => p.id == req.patientId || p.name == req.patientName, orElse: () => PatientProfile()).phone.isNotEmpty
                                  ? _problemService.allPatients.firstWhere((p) => p.id == req.patientId || p.name == req.patientName, orElse: () => PatientProfile()).phone
                                  : '');
                          final displayCity = req.getDisplayCity(_problemService.allPatients);
                          final displayPin = req.getDisplayPincode(_problemService.allPatients);
                          final initialLetter = displayPatientName.isNotEmpty ? displayPatientName[0].toUpperCase() : 'P';
                          final isSevere = req.severity.toLowerCase() == 'severe';
                          final isModerate = req.severity.toLowerCase() == 'moderate';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isPending ? const Color(0x40FE3434) : const Color(0xFFE2E8F0),
                                width: isPending ? 1.4 : 1.0,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
                                ),
                                BoxShadow(
                                  color: isPending
                                      ? const Color(0xFFFE3434).withValues(alpha: 0.06)
                                      : const Color(0xFF012A58).withValues(alpha: 0.05),
                                  blurRadius: 12,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Left Status Accent Bar
                                  Container(
                                    width: 5,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: isPending
                                            ? const [Color(0xFFFE3434), Color(0xFFFE3434)]
                                            : const [Color(0xFF012A58), Color(0xFF012A58)],
                                      ),
                                    ),
                                  ),

                                  // Main Card Content
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // 1. Top Header: Avatar + Patient Name + Badges
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              // Avatar with Status Dot
                                              Stack(
                                                clipBehavior: Clip.none,
                                                children: [
                                                  Container(
                                                    width: 44,
                                                    height: 44,
                                                    decoration: BoxDecoration(
                                                      gradient: LinearGradient(
                                                        begin: Alignment.topLeft,
                                                        end: Alignment.bottomRight,
                                                        colors: isPending
                                                            ? const [Color(0xFFFE3434), Color(0xFFFE3434)]
                                                            : const [Color(0xFFFE3434), Color(0xFF012A58)],
                                                      ),
                                                      borderRadius: BorderRadius.circular(14),
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: (isPending ? const Color(0xFFFE3434) : const Color(0xFFFE3434)).withValues(alpha: 0.25),
                                                          blurRadius: 8,
                                                          offset: const Offset(0, 3),
                                                        ),
                                                      ],
                                                    ),
                                                    child: Center(
                                                      child: Text(
                                                        initialLetter,
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 18,
                                                          fontWeight: FontWeight.w900,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  Positioned(
                                                    right: -2,
                                                    bottom: -2,
                                                    child: Container(
                                                      padding: const EdgeInsets.all(2),
                                                      decoration: const BoxDecoration(
                                                        color: Colors.white,
                                                        shape: BoxShape.circle,
                                                      ),
                                                      child: Icon(
                                                        isPending ? Icons.hourglass_top_rounded : Icons.check_circle_rounded,
                                                        color: isPending ? const Color(0xFFFE3434) : const Color(0xFF012A58),
                                                        size: 13,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(width: 12),

                                              // Name & Contact Column
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      displayPatientName,
                                                      style: const TextStyle(
                                                        fontSize: 15.5,
                                                        fontWeight: FontWeight.w800,
                                                        color: Color(0xFF0F172A),
                                                        letterSpacing: 0.2,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                      maxLines: 1,
                                                    ),
                                                    const SizedBox(height: 3),
                                                    Row(
                                                      children: [
                                                        const Icon(Icons.phone_rounded, size: 11, color: Color(0xFF64748B)),
                                                        const SizedBox(width: 4),
                                                        Flexible(
                                                          child: Text(
                                                            displayPhone.isNotEmpty ? displayPhone : 'Phone not provided',
                                                            style: const TextStyle(
                                                              fontSize: 11.5,
                                                              fontWeight: FontWeight.w600,
                                                              color: Color(0xFF64748B),
                                                            ),
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 8),

                                              // Severity Badge
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                                                decoration: BoxDecoration(
                                                  color: isSevere
                                                      ? const Color(0x14FE3434)
                                                      : (isModerate ? const Color(0x14FE3434) : const Color(0x14FE3434)),
                                                  borderRadius: BorderRadius.circular(10),
                                                  border: Border.all(
                                                    color: isSevere
                                                        ? const Color(0x40FE3434)
                                                        : (isModerate ? const Color(0x40FE3434) : const Color(0x40FE3434)),
                                                    width: 1,
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Container(
                                                      width: 6,
                                                      height: 6,
                                                      decoration: BoxDecoration(
                                                        shape: BoxShape.circle,
                                                        color: isSevere
                                                            ? const Color(0xFFFE3434)
                                                            : (isModerate ? const Color(0xFFFE3434) : const Color(0xFFFE3434)),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 5),
                                                    Text(
                                                      req.severity,
                                                      style: TextStyle(
                                                        fontSize: 10.5,
                                                        fontWeight: FontWeight.w800,
                                                        color: isSevere
                                                            ? const Color(0xFFFE3434)
                                                            : (isModerate ? const Color(0xFFFE3434) : const Color(0xFF012A58)),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),

                                          const SizedBox(height: 12),

                                          // 2. City & Location Tag Bar
                                          if (displayCity.isNotEmpty || displayPin.isNotEmpty) ...[
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF1F5F9),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(Icons.location_on_rounded, size: 12, color: Color(0xFFFE3434)),
                                                  const SizedBox(width: 4),
                                                  Flexible(
                                                    child: Text(
                                                      '${displayCity.isNotEmpty ? displayCity : "Location"}${displayPin.isNotEmpty ? " • PIN: $displayPin" : ""}',
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w700,
                                                        color: Color(0xFF334155),
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                          ],

                                          // 3. Problem Category & Complaint Container
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF8FAFC),
                                              borderRadius: BorderRadius.circular(14),
                                              border: Border.all(color: const Color(0xFFE2E8F0)),
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                // Category Tag
                                                Row(
                                                  children: [
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0x14012A58),
                                                        borderRadius: BorderRadius.circular(6),
                                                        border: Border.all(color: const Color(0x40012A58)),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          const Text('🦷', style: TextStyle(fontSize: 11)),
                                                          const SizedBox(width: 4),
                                                          Flexible(
                                                            child: Text(
                                                              req.problemCategory,
                                                              style: const TextStyle(
                                                                fontSize: 11,
                                                                fontWeight: FontWeight.w800,
                                                                color: Color(0xFF012A58),
                                                              ),
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                if (req.problemDescription.trim().isNotEmpty) ...[
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    req.problemDescription.trim(),
                                                    style: const TextStyle(
                                                      fontSize: 12.5,
                                                      color: Color(0xFF334155),
                                                      height: 1.4,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),

                                          // 4. Assigned Specialist Section (Strictly Real Database Data)
                                          if ((req.assignedDoctorName != null && req.assignedDoctorName!.isNotEmpty) ||
                                              (req.assignedDoctorId != null && req.assignedDoctorId!.isNotEmpty) ||
                                              req.status.toUpperCase().contains('ASSIGNED') ||
                                              req.status == 'Doctor Assigned' ||
                                              req.status == 'Confirmed') ...[
                                            Builder(
                                              builder: (context) {
                                                DoctorModel? assignedDoc;
                                                final docId = req.assignedDoctorId ?? req.preferredDoctorId;
                                                if (docId != null && docId.isNotEmpty) {
                                                  try {
                                                    assignedDoc = _problemService.allDoctors.firstWhere((d) => d.id == docId || d.userId == docId);
                                                  } catch (_) {}
                                                }
                                                if (assignedDoc == null && req.displayDoctorName.isNotEmpty) {
                                                  final dName = req.displayDoctorName.toLowerCase().replaceAll('dr.', '').trim();
                                                  try {
                                                    assignedDoc = _problemService.allDoctors.firstWhere((d) => d.name.toLowerCase().replaceAll('dr.', '').trim().contains(dName) || dName.contains(d.name.toLowerCase().replaceAll('dr.', '').trim()));
                                                  } catch (_) {}
                                                }

                                                final rawDocName = assignedDoc?.name.trim().isNotEmpty == true
                                                    ? assignedDoc!.name.trim()
                                                    : req.displayDoctorName.trim();
                                                final docName = rawDocName.isNotEmpty
                                                    ? (rawDocName.toLowerCase().startsWith('dr.') ? rawDocName : 'Dr. $rawDocName')
                                                    : '';
                                                final docSpecialty = assignedDoc?.specialty.trim().isNotEmpty == true
                                                    ? assignedDoc!.specialty.trim()
                                                    : req.displayDoctorSpecialty.trim();
                                                final docClinic = assignedDoc?.clinicName.trim().isNotEmpty == true
                                                    ? assignedDoc!.clinicName.trim()
                                                    : (req.assignedDoctorClinic?.trim() ?? (req.preferredDoctorClinic?.trim() ?? ''));
                                                final docPhone = assignedDoc?.phone.trim().isNotEmpty == true
                                                    ? assignedDoc!.phone.trim()
                                                    : (req.assignedDoctorPhone?.trim() ?? '');
                                                final docEmail = assignedDoc?.email.trim().isNotEmpty == true
                                                    ? assignedDoc!.email.trim()
                                                    : '';
                                                final docQualification = assignedDoc?.qualification.trim().isNotEmpty == true
                                                    ? assignedDoc!.qualification.trim()
                                                    : '';
                                                final docExperience = (assignedDoc != null && assignedDoc.experienceYears > 0)
                                                    ? '${assignedDoc.experienceYears} Yrs Experience'
                                                    : '';
                                                final docRating = (assignedDoc != null && assignedDoc.rating > 0 && assignedDoc.reviewCount > 0)
                                                    ? '${assignedDoc.rating.toStringAsFixed(1)} ★'
                                                    : '';
                                                final docCity = assignedDoc?.city.trim().isNotEmpty == true ? assignedDoc!.city.trim() : '';
                                                final docPin = assignedDoc?.pincode.trim().isNotEmpty == true ? assignedDoc!.pincode.trim() : '';
                                                final docAddress = assignedDoc?.clinicAddress.trim().isNotEmpty == true
                                                    ? assignedDoc!.clinicAddress.trim()
                                                    : (assignedDoc?.state.trim().isNotEmpty == true ? assignedDoc!.state.trim() : '');
                                                
                                                String docLocation = '';
                                                if (docAddress.isNotEmpty && docCity.isNotEmpty) {
                                                  docLocation = '$docAddress, $docCity${docPin.isNotEmpty ? " • PIN: $docPin" : ""}';
                                                } else if (docCity.isNotEmpty) {
                                                  docLocation = '$docCity${docPin.isNotEmpty ? " • PIN: $docPin" : ""}';
                                                } else if (docAddress.isNotEmpty) {
                                                  docLocation = docAddress;
                                                }

                                                final docFee = (assignedDoc?.consultationFee.trim().isNotEmpty == true &&
                                                        assignedDoc!.consultationFee.trim() != '\$75' &&
                                                        assignedDoc.consultationFee.trim() != '75')
                                                    ? assignedDoc.consultationFee.trim()
                                                    : '';
                                                final docLanguages = (assignedDoc?.languages != null && assignedDoc!.languages.isNotEmpty)
                                                    ? assignedDoc.languages.join(', ')
                                                    : '';
                                                final timeSlot = (req.confirmedTimeSlot != null && req.confirmedTimeSlot!.trim().isNotEmpty)
                                                    ? req.confirmedTimeSlot!.trim()
                                                    : '';

                                                if (docName.isEmpty && docSpecialty.isEmpty) {
                                                  return const SizedBox.shrink();
                                                }

                                                return Container(
                                                  margin: const EdgeInsets.only(top: 10),
                                                  padding: const EdgeInsets.all(14),
                                                  decoration: BoxDecoration(
                                                    gradient: const LinearGradient(
                                                      colors: [Color(0x14012A58), Color(0x14012A58)],
                                                      begin: Alignment.topLeft,
                                                      end: Alignment.bottomRight,
                                                    ),
                                                    borderRadius: BorderRadius.circular(16),
                                                    border: Border.all(color: const Color(0x40012A58), width: 1.2),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: const Color(0xFF012A58).withValues(alpha: 0.08),
                                                        blurRadius: 10,
                                                        offset: const Offset(0, 3),
                                                      ),
                                                    ],
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      // Top Doctor Identity Row
                                                      Row(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Container(
                                                            padding: const EdgeInsets.all(8),
                                                            decoration: BoxDecoration(
                                                              color: const Color(0xFF012A58).withValues(alpha: 0.15),
                                                              shape: BoxShape.circle,
                                                            ),
                                                            child: const Icon(Icons.verified_user_rounded, color: Color(0xFF012A58), size: 20),
                                                          ),
                                                          const SizedBox(width: 10),
                                                          Expanded(
                                                            child: Column(
                                                              crossAxisAlignment: CrossAxisAlignment.start,
                                                              children: [
                                                                Text(
                                                                  docName,
                                                                  style: const TextStyle(
                                                                    fontWeight: FontWeight.w900,
                                                                    fontSize: 15,
                                                                    color: Color(0xFF012A58),
                                                                    letterSpacing: 0.1,
                                                                  ),
                                                                ),
                                                                const SizedBox(height: 4),
                                                                Wrap(
                                                                  spacing: 6,
                                                                  runSpacing: 4,
                                                                  crossAxisAlignment: WrapCrossAlignment.center,
                                                                  children: [
                                                                    Container(
                                                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                                                      decoration: BoxDecoration(
                                                                        color: const Color(0x14012A58),
                                                                        borderRadius: BorderRadius.circular(6),
                                                                        border: Border.all(color: const Color(0x40012A58)),
                                                                      ),
                                                                      child: const Row(
                                                                        mainAxisSize: MainAxisSize.min,
                                                                        children: [
                                                                          Icon(Icons.check_circle, size: 10, color: Color(0xFFFE3434)),
                                                                          SizedBox(width: 3),
                                                                          Text(
                                                                            'Assigned Doctor',
                                                                            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF012A58)),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                    ),
                                                                    if (docSpecialty.isNotEmpty || docQualification.isNotEmpty || docExperience.isNotEmpty)
                                                                      Text(
                                                                        [
                                                                          if (docSpecialty.isNotEmpty) docSpecialty,
                                                                          if (docQualification.isNotEmpty) docQualification,
                                                                          if (docExperience.isNotEmpty) '($docExperience)',
                                                                        ].join(' • '),
                                                                        style: const TextStyle(
                                                                          fontSize: 11.5,
                                                                          fontWeight: FontWeight.w600,
                                                                          color: Color(0xFF012A58),
                                                                        ),
                                                                      ),
                                                                  ],
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ],
                                                      ),

                                                      if (docClinic.isNotEmpty || docLocation.isNotEmpty || docPhone.isNotEmpty || docEmail.isNotEmpty) ...[
                                                        const Padding(
                                                          padding: EdgeInsets.symmetric(vertical: 8),
                                                          child: Divider(color: Color(0x40012A58), height: 1, thickness: 0.8),
                                                        ),
                                                      ],

                                                      // Real Doctor Details Rows (Render ONLY if provided in DB)
                                                      if (docClinic.isNotEmpty) ...[
                                                        Row(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: [
                                                            const Padding(
                                                              padding: EdgeInsets.only(top: 2),
                                                              child: Icon(Icons.local_hospital_rounded, size: 13, color: Color(0xFF012A58)),
                                                            ),
                                                            const SizedBox(width: 6),
                                                            const Text('Clinic: ', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF012A58))),
                                                            Expanded(
                                                              child: Text(
                                                                docClinic,
                                                                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        const SizedBox(height: 4),
                                                      ],

                                                      if (docLocation.isNotEmpty) ...[
                                                        Row(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: [
                                                            const Padding(
                                                              padding: EdgeInsets.only(top: 2),
                                                              child: Icon(Icons.location_on_rounded, size: 13, color: Color(0xFF012A58)),
                                                            ),
                                                            const SizedBox(width: 6),
                                                            const Text('Location: ', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF012A58))),
                                                            Expanded(
                                                              child: Text(
                                                                docLocation,
                                                                style: const TextStyle(fontSize: 11.5, color: Color(0xFF334155)),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        const SizedBox(height: 4),
                                                      ],

                                                      if (docPhone.isNotEmpty) ...[
                                                        Row(
                                                          crossAxisAlignment: CrossAxisAlignment.center,
                                                          children: [
                                                            const Icon(Icons.phone_in_talk_rounded, size: 13, color: Color(0xFF012A58)),
                                                            const SizedBox(width: 6),
                                                            const Text('Contact: ', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF012A58))),
                                                            Expanded(
                                                              child: Text(
                                                                docPhone,
                                                                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFFFE3434)),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        const SizedBox(height: 4),
                                                      ],

                                                      if (docEmail.isNotEmpty) ...[
                                                        Row(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: [
                                                            const Padding(
                                                              padding: EdgeInsets.only(top: 2),
                                                              child: Icon(Icons.email_outlined, size: 13, color: Color(0xFF012A58)),
                                                            ),
                                                            const SizedBox(width: 6),
                                                            const Text('Email: ', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF012A58))),
                                                            Expanded(
                                                              child: Text(
                                                                docEmail,
                                                                style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569)),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ],

                                                      // Real Metadata Chips (Only if present in DB)
                                                      if (docFee.isNotEmpty || docLanguages.isNotEmpty || docRating.isNotEmpty || timeSlot.isNotEmpty) ...[
                                                        const SizedBox(height: 6),
                                                        Wrap(
                                                          spacing: 6,
                                                          runSpacing: 5,
                                                          children: [
                                                            if (docFee.isNotEmpty)
                                                              Container(
                                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                                decoration: BoxDecoration(
                                                                  color: Colors.white,
                                                                  borderRadius: BorderRadius.circular(6),
                                                                  border: Border.all(color: const Color(0x40012A58)),
                                                                ),
                                                                child: Row(
                                                                  mainAxisSize: MainAxisSize.min,
                                                                  children: [
                                                                    const Icon(Icons.payments_outlined, size: 11, color: Color(0xFF012A58)),
                                                                    const SizedBox(width: 4),
                                                                    Text('Fee: $docFee', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF012A58))),
                                                                  ],
                                                                ),
                                                              ),
                                                            if (docLanguages.isNotEmpty)
                                                              Container(
                                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                                decoration: BoxDecoration(
                                                                  color: Colors.white,
                                                                  borderRadius: BorderRadius.circular(6),
                                                                  border: Border.all(color: const Color(0x40012A58)),
                                                                ),
                                                                child: Row(
                                                                  mainAxisSize: MainAxisSize.min,
                                                                  children: [
                                                                    const Icon(Icons.translate_rounded, size: 11, color: Color(0xFF012A58)),
                                                                    const SizedBox(width: 4),
                                                                    Text(docLanguages, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF012A58))),
                                                                  ],
                                                                ),
                                                              ),
                                                            if (docRating.isNotEmpty)
                                                              Container(
                                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                                decoration: BoxDecoration(
                                                                  color: Colors.white,
                                                                  borderRadius: BorderRadius.circular(6),
                                                                  border: Border.all(color: const Color(0x40012A58)),
                                                                ),
                                                                child: Row(
                                                                  mainAxisSize: MainAxisSize.min,
                                                                  children: [
                                                                    const Icon(Icons.star_rounded, size: 12, color: Color(0xFFFE3434)),
                                                                    const SizedBox(width: 3),
                                                                    Text(docRating, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFFFE3434))),
                                                                  ],
                                                                ),
                                                              ),
                                                            if (timeSlot.isNotEmpty)
                                                              Container(
                                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                                decoration: BoxDecoration(
                                                                  color: const Color(0x14012A58),
                                                                  borderRadius: BorderRadius.circular(6),
                                                                  border: Border.all(color: const Color(0x40012A58)),
                                                                ),
                                                                child: Row(
                                                                  mainAxisSize: MainAxisSize.min,
                                                                  children: [
                                                                    const Icon(Icons.schedule_rounded, size: 11, color: Color(0xFF012A58)),
                                                                    const SizedBox(width: 4),
                                                                    Text('Slot: $timeSlot', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF012A58))),
                                                                  ],
                                                                ),
                                                              ),
                                                          ],
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                );
                                              },
                                            ),
                                          ],

                                          const SizedBox(height: 14),

                                          // 5. Action Toolbar Row
                                          Row(
                                            children: [
                                              Expanded(
                                                child: ElevatedButton(
                                                  onPressed: () => _showAssignDoctorDialog(context, req),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: isPending ? const Color(0xFF012A58) : const Color(0xFF012A58),
                                                    foregroundColor: Colors.white,
                                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                                    elevation: 2,
                                                    shadowColor: (isPending ? const Color(0xFF012A58) : const Color(0xFF012A58)).withValues(alpha: 0.35),
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                  ),
                                                  child: Row(
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      Icon(
                                                        isPending ? Icons.person_search_rounded : Icons.mark_chat_read_rounded,
                                                        size: 15,
                                                        color: Colors.white,
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Flexible(
                                                        child: Text(
                                                          isPending ? 'Suggest Doctor & WhatsApp' : 'Resend WhatsApp Link',
                                                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.1),
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              OutlinedButton.icon(
                                                key: Key('admin_coord_status_${req.id}'),
                                                icon: const Icon(Icons.track_changes_rounded, size: 15),
                                                label: const Text('Stage', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                                onPressed: () => _showAdminCoordinatorStageDialog(context, req),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                decoration: BoxDecoration(
                                                  color: const Color(0x14FE3434),
                                                  borderRadius: BorderRadius.circular(12),
                                                  border: Border.all(color: const Color(0x40FE3434)),
                                                ),
                                                child: IconButton(
                                                  tooltip: 'Remove Request',
                                                  icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFE3434), size: 18),
                                                  onPressed: () => _confirmDeleteRequest(context, req),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // DIRECT PATIENT-TO-DOCTOR REFERRALS OVERVIEW CONTAINER
          _buildDashboardReferralsSection(),
          const SizedBox(height: 20),

          // Charts Row
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 750) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: _buildAppointmentOverviewCard()),
                    const SizedBox(width: 14),
                    Expanded(flex: 2, child: _buildAppointmentsByStatusCard()),
                  ],
                );
              }
              return Column(
                children: [
                  _buildAppointmentOverviewCard(),
                  const SizedBox(height: 14),
                  _buildAppointmentsByStatusCard(),
                ],
              );
            },
          ),
        ],
      ),
    ),
    ),
    );
  }

  Widget _buildDashboardReferralsSection() {
    final patientRefs = _problemService.adminPatientReferrals;
    final pendingCount = patientRefs.where((r) => r.status == 'Pending').length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Flexible(
                          child: Text(
                            '🔄 Patient Referrals',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (pendingCount > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0x14FE3434),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0x40FE3434)),
                            ),
                            child: Text(
                              '$pendingCount New',
                              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFFFE3434)),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Patient referrals & specialist consultation tracking',
                      style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _selectedNavIndex = 11),
                icon: const Icon(Icons.open_in_new_rounded, size: 14, color: Color(0xFFFE3434)),
                label: const Text(
                  'Full View',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFFFE3434)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (patientRefs.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Column(
                children: [
                  Icon(Icons.group_add_outlined, size: 36, color: AppTheme.textMuted),
                  SizedBox(height: 8),
                  Text(
                    'No patient referrals recorded yet.',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'When patients refer other patients to specialists, real-time records will appear here.',
                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            Column(
              children: patientRefs.take(5).map((ref) {
                final isAccepted = ref.status == 'Accepted';
                final isRejected = ref.status == 'Rejected';
                final statusColor = isAccepted
                    ? const Color(0xFF012A58)
                    : (isRejected ? const Color(0xFFFE3434) : const Color(0xFFFE3434));
                final statusBg = isAccepted
                    ? const Color(0x14012A58)
                    : (isRejected ? const Color(0x14FE3434) : const Color(0x14FE3434));
                final statusText = isAccepted
                    ? '🟢 Accepted by Doctor'
                    : (isRejected ? '🔴 Declined' : '🟡 Pending Review');

                final dateStr = '${ref.referralDate.day}/${ref.referralDate.month}/${ref.referralDate.year}';
                final patientLoc = [
                  if (ref.referredPatientLocation.isNotEmpty) ref.referredPatientLocation,
                  if (ref.referredPatientCity.isNotEmpty) ref.referredPatientCity,
                  if (ref.referredPatientPincode.isNotEmpty) '(${ref.referredPatientPincode})',
                ].join(', ');

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: ref.status == 'Pending' ? const Color(0x40FE3434) : const Color(0xFFE2E8F0),
                      width: ref.status == 'Pending' ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: Wrap prevents any pixel overflow on small screens
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                            decoration: BoxDecoration(
                              color: statusBg,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              statusText,
                              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: statusColor),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0x14012A58),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.chat_bubble_rounded, size: 10, color: Color(0xFFFE3434)),
                                const SizedBox(width: 3),
                                Text(
                                  ref.whatsappStatus == 'Sent' ? 'WhatsApp Sent' : 'Queued',
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFFE3434)),
                                ),
                              ],
                            ),
                          ),
                          Text(dateStr, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Referring Patient & Referred Patient Cards (RenderFlex Safe with Expanded)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left: Referring Patient
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0x14FE3434),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0x40FE3434)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.person_pin_rounded, size: 13, color: Color(0xFF012A58)),
                                      SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          'Referring Patient',
                                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF012A58)),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    ref.referrerPatientName.isNotEmpty ? ref.referrerPatientName : 'Patient Referrer',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (ref.referrerPatientPhone.isNotEmpty)
                                    Text(
                                      '+91 ${ref.referrerPatientPhone}',
                                      style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),

                          // Right: Referred Patient
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0x14012A58),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0x40012A58)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.person_rounded, size: 13, color: Color(0xFF012A58)),
                                      SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          'Referred Patient',
                                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF012A58)),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    ref.referredPatientName.isNotEmpty ? ref.referredPatientName : 'Referred Patient',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '+91 ${ref.referredPatientMobile}${ref.referredPatientAge.isNotEmpty ? " • ${ref.referredPatientAge} Yrs" : ""}',
                                    style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Location & Consulting Doctor Strip
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (patientLoc.isNotEmpty) ...[
                              Row(
                                children: [
                                  const Icon(Icons.location_on_outlined, size: 12, color: Color(0xFFFE3434)),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      'Patient Address: $patientLoc',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF012A58)),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                            ],
                            Row(
                              children: [
                                const Icon(Icons.medical_services_outlined, size: 12, color: Color(0xFF012A58)),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'Doctor: ${ref.doctorName} • ${ref.requiredSpecialist}${ref.doctorClinicName.isNotEmpty ? " (${ref.doctorClinicName})" : ""}',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Action button
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => _showAdminReferralDetailsModal(context, ref),
                          icon: const Icon(Icons.visibility_rounded, size: 14, color: AppTheme.primaryBlue),
                          label: const Text(
                            'View Referral Details',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
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
    );
  }

  Widget _buildAppointmentOverviewCard() {
    final appointments = deduplicateAdminAppointments(_overviewAppointments);
    final now = DateTime.now();
    const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final buckets = <({String label, int year, int month, int count})>[];
    for (int i = 5; i >= 0; i--) {
      final dt = DateTime(now.year, now.month - i, 1);
      final count = appointments.where((a) {
        final parsed = DateTime.tryParse(a.dateRaw) ?? DateTime.tryParse(a.createdAtRaw);
        if (parsed == null) return false;
        final local = parsed.toLocal();
        return local.year == dt.year && local.month == dt.month;
      }).length;
      buckets.add((label: monthNames[dt.month - 1], year: dt.year, month: dt.month, count: count));
    }
    final maxCount = buckets.fold<int>(0, (m, b) => b.count > m ? b.count : m);

    return Container(
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
              const Flexible(
                child: Text(
                  'Appointment Overview (Last 6 Months)',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${appointments.length} Total',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primaryBlue),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (maxCount == 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 34),
              child: Center(
                child: Text(
                  'No appointments recorded in the last 6 months.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ),
            )
          else
            SizedBox(
              height: 150,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: buckets.asMap().entries.map((entry) {
                  final isCurrent = entry.key == buckets.length - 1;
                  final b = entry.value;
                  final pct = (b.count / maxCount).clamp(0.08, 1.0);
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        '${b.count}',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: isCurrent ? AppTheme.gsRed : AppTheme.gsNavy,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _buildBarColumn(b.label, b.count == 0 ? 0.04 : pct, isCurrent),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAppointmentsByStatusCard() {
    final appointments = deduplicateAdminAppointments(_overviewAppointments);
    final total = appointments.length;
    final completed = appointments.where((a) => a.status.toUpperCase().contains('COMPLET')).length;
    final cancelled = appointments.where((a) {
      final s = a.status.toUpperCase();
      return s.contains('CANCEL') || s.contains('REJECT');
    }).length;
    final scheduled = (total - completed - cancelled).clamp(0, total);

    final completedPct = total > 0 ? completed / total : 0.0;
    final scheduledPct = total > 0 ? scheduled / total : 0.0;
    final cancelledPct = total > 0 ? cancelled / total : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Appointments by Status',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textDark),
          ),
          const SizedBox(height: 16),
          if (total == 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 34),
              child: Center(
                child: Text(
                  'No appointments recorded yet.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ),
            )
          else
            Row(
              children: [
                SizedBox(
                  width: 100,
                  height: 100,
                  child: CustomPaint(
                    painter: _DonutChartPainter(
                      slices: [
                        if (completedPct > 0) _DonutSlice(pct: completedPct, color: const Color(0xFF012A58)),
                        if (scheduledPct > 0) _DonutSlice(pct: scheduledPct, color: const Color(0x80012A58)),
                        if (cancelledPct > 0) _DonutSlice(pct: cancelledPct, color: const Color(0xFFFE3434)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _LegendRow(
                        color: const Color(0xFF012A58),
                        label: 'Completed ($completed)',
                        value: '${(completedPct * 100).round()}%',
                      ),
                      const SizedBox(height: 8),
                      _LegendRow(
                        color: const Color(0x80012A58),
                        label: 'Scheduled ($scheduled)',
                        value: '${(scheduledPct * 100).round()}%',
                      ),
                      const SizedBox(height: 8),
                      _LegendRow(
                        color: const Color(0xFFFE3434),
                        label: 'Cancelled ($cancelled)',
                        value: '${(cancelledPct * 100).round()}%',
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  final List<Map<String, String>> _adminPatientsList = [];

  void _showAddPatientDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final ageCtrl = TextEditingController();
    final cityCtrl = TextEditingController();
    final pincodeCtrl = TextEditingController();
    String selectedPatientLanguage = 'English';

    const availableLanguages = [
      'English', 'Hindi', 'Telugu', 'Tamil', 'Kannada', 'Bengali', 'Marathi', 'Gujarati', 'Malayalam', 'Punjabi'
    ];

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryBlue.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.person_add_rounded, color: AppTheme.primaryBlue, size: 22),
                          ),
                          const SizedBox(width: 10),
                          const Text('Register New Patient', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: AppTheme.textDark)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: nameCtrl,
                        style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                        cursorColor: AppTheme.primaryBlue,
                        decoration: const InputDecoration(labelText: 'Patient Full Name *', prefixIcon: Icon(Icons.person_outline_rounded)),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: phoneCtrl,
                        keyboardType: TextInputType.phone,
                        style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                        cursorColor: AppTheme.primaryBlue,
                        decoration: const InputDecoration(labelText: 'Mobile Phone Number *', prefixIcon: Icon(Icons.phone_android_rounded)),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                        cursorColor: AppTheme.primaryBlue,
                        decoration: const InputDecoration(labelText: 'Email Address (Optional)', prefixIcon: Icon(Icons.email_outlined)),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: cityCtrl,
                              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                              cursorColor: AppTheme.primaryBlue,
                              decoration: const InputDecoration(labelText: 'City', prefixIcon: Icon(Icons.location_city_rounded)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: pincodeCtrl,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                              cursorColor: AppTheme.primaryBlue,
                              decoration: const InputDecoration(labelText: 'Pincode', prefixIcon: Icon(Icons.pin_drop_outlined)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: ageCtrl,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                              cursorColor: AppTheme.primaryBlue,
                              decoration: const InputDecoration(labelText: 'Age', prefixIcon: Icon(Icons.cake_outlined)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: selectedPatientLanguage,
                              isExpanded: true,
                              decoration: const InputDecoration(labelText: 'Language'),
                              items: availableLanguages.map((l) => DropdownMenuItem(value: l, child: Text(l, style: const TextStyle(fontSize: 12)))).toList(),
                              onChanged: (val) {
                                if (val != null) setModalState(() => selectedPatientLanguage = val);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                        label: const Text('Register & Save Patient Profile', style: TextStyle(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          final name = nameCtrl.text.trim();
                          final phone = phoneCtrl.text.trim();
                          final email = emailCtrl.text.trim();
                          final city = cityCtrl.text.trim();
                          final pin = pincodeCtrl.text.trim();

                          if (name.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Full Name cannot be empty.')));
                            return;
                          }
                          final cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
                          if (cleanPhone.length < 10) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Enter a valid 10-digit Contact Number.')));
                            return;
                          }

                          await ApiService().registerUser(
                            name: name,
                            phone: phone,
                            email: email,
                            role: 'Patient',
                            city: city,
                            pincode: pin,
                            languages: [selectedPatientLanguage],
                          );

                          await _problemService.syncPatientsFromApi();

                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                          }
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('🎉 Registered $name successfully!'),
                                backgroundColor: const Color(0xFF012A58),
                              ),
                            );
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

  // ==========================================
  // PANEL: REFERRAL MANAGEMENT & TRACKING
  // ==========================================
  String _referralSearchQuery = '';
  String _adminReferralStatusFilter = 'All';
  bool _isRefreshingReferrals = false;
  bool _hasTriggeredInitialReferralsSync = false;

  Future<void> _refreshAdminReferrals() async {
    setState(() {
      _isRefreshingReferrals = true;
      _hasTriggeredInitialReferralsSync = true;
    });
    await _problemService.syncAdminReferralsFromApi();
    if (mounted) {
      setState(() => _isRefreshingReferrals = false);
    }
  }

  Widget _buildReferralManagementPanel() {
    final allPatientRefs = _problemService.adminPatientReferrals;

    if (allPatientRefs.isEmpty && !_isRefreshingReferrals && !_hasTriggeredInitialReferralsSync) {
      _hasTriggeredInitialReferralsSync = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _problemService.syncAdminReferralsFromApi();
      });
    }

    final filtered = allPatientRefs.where((r) {
      // 1. Status Filter
      if (_adminReferralStatusFilter != 'All' && r.status.toLowerCase() != _adminReferralStatusFilter.toLowerCase()) {
        return false;
      }
      // 2. Search Query
      if (_referralSearchQuery.isEmpty) return true;
      final q = _referralSearchQuery.toLowerCase();
      return r.referrerPatientName.toLowerCase().contains(q) ||
          r.referrerPatientPhone.contains(q) ||
          r.referrerPatientEmail.toLowerCase().contains(q) ||
          r.referredPatientName.toLowerCase().contains(q) ||
          r.referredPatientMobile.contains(q) ||
          r.referredPatientCity.toLowerCase().contains(q) ||
          r.referredPatientPincode.contains(q) ||
          r.referredPatientLocation.toLowerCase().contains(q) ||
          r.doctorName.toLowerCase().contains(q) ||
          r.doctorSpecialty.toLowerCase().contains(q) ||
          r.doctorClinicName.toLowerCase().contains(q) ||
          r.requiredSpecialist.toLowerCase().contains(q) ||
          r.clinicalComplaint.toLowerCase().contains(q) ||
          r.status.toLowerCase().contains(q);
    }).toList();

    final pendingCount = allPatientRefs.where((r) => r.status == 'Pending').length;
    final acceptedCount = allPatientRefs.where((r) => r.status == 'Accepted').length;
    final rejectedCount = allPatientRefs.where((r) => r.status == 'Rejected').length;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header Bar
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFE3434), Color(0xFFFE3434)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFE3434).withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(Icons.group_add_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Referral Management & Tracking',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.textDark),
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Track patient referrals, specialist consultations & doctor assignments',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _isRefreshingReferrals ? null : _refreshAdminReferrals,
                icon: _isRefreshingReferrals
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Refresh Data', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFE3434),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // 2. Growth & Referral KPI Metrics Grid
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final crossCount = w > 900 ? 5 : (w > 560 ? 3 : 2);
              final childRatio = w > 900 ? 1.5 : (w > 560 ? 1.4 : 1.32);

              return GridView.count(
                crossAxisCount: crossCount,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: childRatio,
                children: [
                  _KpiCard(
                    title: 'Total Referrals',
                    value: '${allPatientRefs.length}',
                    growth: 'All Referrals',
                    accentColor: const Color(0xFFFE3434),
                    icon: Icons.share_rounded,
                  ),
                  _KpiCard(
                    title: 'Pending Review',
                    value: '$pendingCount',
                    growth: 'Awaiting Doctor',
                    accentColor: const Color(0xFFFE3434),
                    icon: Icons.hourglass_top_rounded,
                  ),
                  _KpiCard(
                    title: 'Accepted by Doctor',
                    value: '$acceptedCount',
                    growth: 'Confirmed Care',
                    accentColor: const Color(0xFF012A58),
                    icon: Icons.check_circle_rounded,
                  ),
                  _KpiCard(
                    title: 'Referrals Declined',
                    value: '$rejectedCount',
                    growth: 'Unavailable',
                    accentColor: const Color(0xFFFE3434),
                    icon: Icons.cancel_outlined,
                  ),
                  _KpiCard(
                    title: 'WhatsApp Delivered',
                    value: '${allPatientRefs.where((r) => r.whatsappStatus == 'Sent').length}',
                    growth: 'Mobile Alerts',
                    accentColor: const Color(0xFFFE3434),
                    icon: Icons.chat_bubble_rounded,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),

          // 3. Status Filters & Search Bar
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 650;
              final filterRow = SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildReferralFilterChip('All', allPatientRefs.length),
                    const SizedBox(width: 8),
                    _buildReferralFilterChip('Pending', pendingCount),
                    const SizedBox(width: 8),
                    _buildReferralFilterChip('Accepted', acceptedCount),
                    const SizedBox(width: 8),
                    _buildReferralFilterChip('Rejected', rejectedCount),
                  ],
                ),
              );

              final searchField = SizedBox(
                width: isNarrow ? double.infinity : 280,
                child: TextField(
                  onChanged: (val) => setState(() => _referralSearchQuery = val.trim()),
                  style: const TextStyle(fontSize: 12.5, color: Color(0xFF0F172A), fontWeight: FontWeight.w500),
                  cursorColor: AppTheme.primaryBlue,
                  decoration: InputDecoration(
                    hintText: 'Search patient, doctor, location...',
                    hintStyle: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    prefixIcon: const Icon(Icons.search_rounded, size: 16, color: AppTheme.primaryBlue),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                ),
              );

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    filterRow,
                    const SizedBox(height: 10),
                    searchField,
                  ],
                );
              }

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: filterRow),
                  const SizedBox(width: 12),
                  searchField,
                ],
              );
            },
          ),
          const SizedBox(height: 14),

          // 4. Comprehensive Referrals Table
          if (filtered.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(36),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Column(
                children: [
                  Icon(Icons.group_add_outlined, color: AppTheme.textMuted, size: 42),
                  SizedBox(height: 10),
                  Text(
                    'No Matching Referral Records Found',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'When patients refer other patients to doctors, full referral details and status will appear here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                ],
              ),
            )
          else
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                  columns: const [
                    DataColumn(label: Text('Referring Patient', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    DataColumn(label: Text('Referred Patient', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    DataColumn(label: Text('Location & PIN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    DataColumn(label: Text('Consulting Doctor & Clinic', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    DataColumn(label: Text('Specialty & Notes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    DataColumn(label: Text('WhatsApp', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    DataColumn(label: Text('Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                  ],
                  rows: filtered.map((ref) {
                    final isAccepted = ref.status == 'Accepted';
                    final isRejected = ref.status == 'Rejected';

                    final statusColor = isAccepted
                        ? const Color(0xFF012A58)
                        : (isRejected ? const Color(0xFFFE3434) : const Color(0xFFFE3434));
                    final statusBg = isAccepted
                        ? const Color(0x14012A58)
                        : (isRejected ? const Color(0x14FE3434) : const Color(0x14FE3434));
                    final statusText = isAccepted
                        ? '🟢 Accepted'
                        : (isRejected ? '🔴 Declined' : '🟡 Pending');

                    final dateStr = '${ref.referralDate.day}/${ref.referralDate.month}/${ref.referralDate.year}';

                    final patientLoc = [
                      if (ref.referredPatientLocation.isNotEmpty) ref.referredPatientLocation,
                      if (ref.referredPatientCity.isNotEmpty) ref.referredPatientCity,
                      if (ref.referredPatientPincode.isNotEmpty) '(${ref.referredPatientPincode})',
                    ].join(', ');

                    return DataRow(
                      cells: [
                        // 1. Referring Patient
                        DataCell(
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.person_pin_rounded, size: 14, color: Color(0xFFFE3434)),
                                  const SizedBox(width: 4),
                                  Text(
                                    ref.referrerPatientName.isNotEmpty ? ref.referrerPatientName : 'Patient Referrer',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF012A58)),
                                  ),
                                ],
                              ),
                              if (ref.referrerPatientPhone.isNotEmpty)
                                Text(
                                  '+91 ${ref.referrerPatientPhone}',
                                  style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
                                ),
                            ],
                          ),
                        ),

                        // 2. Referred Patient
                        DataCell(
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ref.referredPatientName.isNotEmpty ? ref.referredPatientName : 'Referred Patient',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textDark),
                              ),
                              Text(
                                [
                                  '+91 ${ref.referredPatientMobile}',
                                  if (ref.referredPatientAge.isNotEmpty) '${ref.referredPatientAge} Yrs',
                                  if (ref.referredPatientGender.isNotEmpty) ref.referredPatientGender,
                                ].join(' • '),
                                style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
                              ),
                            ],
                          ),
                        ),

                        // 3. Patient Location & Pincode
                        DataCell(
                          patientLoc.isNotEmpty
                              ? Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0x14012A58),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0x40012A58)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.location_on_outlined, size: 12, color: Color(0xFFFE3434)),
                                      const SizedBox(width: 3),
                                      Text(
                                        patientLoc,
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF012A58)),
                                      ),
                                    ],
                                  ),
                                )
                              : const Text('—', style: TextStyle(color: AppTheme.textMuted)),
                        ),

                        // 4. Consulting Doctor & Clinic
                        DataCell(
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.medical_services_outlined, size: 13, color: Color(0xFF012A58)),
                                  const SizedBox(width: 4),
                                  Text(
                                    ref.doctorName.isNotEmpty ? ref.doctorName : 'Dr. Specialist',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF0F172A)),
                                  ),
                                ],
                              ),
                              Text(
                                ref.doctorClinicName.isNotEmpty ? ref.doctorClinicName : 'Independent Practice',
                                style: const TextStyle(fontSize: 10.5, color: AppTheme.textMedium),
                              ),
                            ],
                          ),
                        ),

                        // 5. Specialty & Notes
                        DataCell(
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0x14FE3434),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  ref.requiredSpecialist,
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFFE3434)),
                                ),
                              ),
                              if (ref.clinicalComplaint.isNotEmpty)
                                SizedBox(
                                  width: 140,
                                  child: Text(
                                    ref.clinicalComplaint,
                                    style: const TextStyle(fontSize: 10, color: AppTheme.textMuted, fontStyle: FontStyle.italic),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                          ),
                        ),

                        // 6. Status
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusBg,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                            ),
                            child: Text(statusText, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5, color: statusColor)),
                          ),
                        ),

                        // 7. WhatsApp Status
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.chat_bubble_outline_rounded, size: 12, color: Color(0xFFFE3434)),
                              const SizedBox(width: 4),
                              Text(
                                ref.whatsappStatus == 'Sent' ? 'Delivered' : 'Queued',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFFE3434)),
                              ),
                            ],
                          ),
                        ),

                        // 8. Date
                        DataCell(Text(dateStr, style: const TextStyle(fontSize: 11.5))),

                        // 9. Actions
                        DataCell(
                          IconButton(
                            icon: const Icon(Icons.visibility_outlined, size: 18, color: AppTheme.primaryBlue),
                            tooltip: 'View Referral Details',
                            onPressed: () => _showAdminReferralDetailsModal(context, ref),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReferralFilterChip(String label, int count) {
    final isSelected = _adminReferralStatusFilter == label;
    return FilterChip(
      label: Text(
        '$label ($count)',
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.white : AppTheme.textDark,
        ),
      ),
      selected: isSelected,
      selectedColor: const Color(0xFFFE3434),
      backgroundColor: Colors.white,
      checkmarkColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? const Color(0xFFFE3434) : const Color(0xFFE2E8F0),
        ),
      ),
      onSelected: (selected) {
        if (selected) {
          setState(() => _adminReferralStatusFilter = label);
        }
      },
    );
  }

  void _showAdminReferralDetailsModal(BuildContext context, PatientReferral ref) {
    final isAccepted = ref.status == 'Accepted';
    final isRejected = ref.status == 'Rejected';
    final statusColor = isAccepted
        ? const Color(0xFF012A58)
        : (isRejected ? const Color(0xFFFE3434) : const Color(0xFFFE3434));
    final statusBg = isAccepted
        ? const Color(0x14012A58)
        : (isRejected ? const Color(0x14FE3434) : const Color(0x14FE3434));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Grab Bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Referral Details',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        ref.status,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Section 1: Referring Patient
                _buildDetailCard(
                  title: '1. REFERRING PATIENT',
                  icon: Icons.person_pin_rounded,
                  color: const Color(0xFFFE3434),
                  items: [
                    {'label': 'Referrer Name', 'value': ref.referrerPatientName},
                    {'label': 'Referrer Mobile', 'value': '+91 ${ref.referrerPatientPhone}'},
                    if (ref.referrerPatientEmail.isNotEmpty)
                      {'label': 'Referrer Email', 'value': ref.referrerPatientEmail},
                  ],
                ),
                const SizedBox(height: 12),

                // Section 2: Referred Patient
                _buildDetailCard(
                  title: '2. REFERRED PATIENT',
                  icon: Icons.person_rounded,
                  color: const Color(0xFFFE3434),
                  items: [
                    {'label': 'Patient Name', 'value': ref.referredPatientName},
                    {'label': 'Mobile Number', 'value': '+91 ${ref.referredPatientMobile}'},
                    {'label': 'Age & Gender', 'value': '${ref.referredPatientAge} Years • ${ref.referredPatientGender}'},
                    {'label': 'Location', 'value': '${ref.referredPatientLocation}, ${ref.referredPatientCity} (${ref.referredPatientPincode})'},
                  ],
                ),
                const SizedBox(height: 12),

                // Section 3: Consulting Doctor & Clinic
                _buildDetailCard(
                  title: '3. CONSULTING DOCTOR & CLINIC',
                  icon: Icons.medical_services_rounded,
                  color: const Color(0xFF012A58),
                  items: [
                    {'label': 'Doctor Name', 'value': ref.doctorName},
                    {'label': 'Specialty', 'value': ref.doctorSpecialty.isNotEmpty ? ref.doctorSpecialty : ref.requiredSpecialist},
                    {'label': 'Clinic Name', 'value': ref.doctorClinicName.isNotEmpty ? ref.doctorClinicName : 'Independent Practice'},
                    if (ref.doctorLocation.isNotEmpty)
                      {'label': 'Clinic Address', 'value': ref.doctorLocation},
                  ],
                ),
                const SizedBox(height: 12),

                // Section 4: Clinical Complaint & Notifications
                _buildDetailCard(
                  title: '4. CLINICAL COMPLAINT & NOTIFICATIONS',
                  icon: Icons.notes_rounded,
                  color: const Color(0xFFFE3434),
                  items: [
                    {'label': 'Specialist Category', 'value': ref.requiredSpecialist},
                    {'label': 'Clinical Complaint', 'value': ref.clinicalComplaint.isNotEmpty ? ref.clinicalComplaint : 'Not specified'},
                    {'label': 'Referral Date', 'value': '${ref.referralDate.day}/${ref.referralDate.month}/${ref.referralDate.year}'},
                    {'label': 'WhatsApp Status', 'value': ref.whatsappStatus == 'Sent' ? 'Delivered (+91 ${ref.referredPatientMobile})' : 'Queued'},
                    if (isRejected && ref.rejectionReason != null)
                      {'label': 'Rejection Reason', 'value': ref.rejectionReason!},
                  ],
                ),
                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Close Details', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailCard({
    required String title,
    required IconData icon,
    required Color color,
    required List<Map<String, String>> items,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: color),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...items.map((it) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 130,
                    child: Text(
                      it['label'] ?? '',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      it['value'] ?? '—',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppTheme.textDark),
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
  // PANEL 2: PATIENTS MANAGEMENT DATA TABLE
  // ==========================================
  Widget _buildPatientsPanel() {
    final List<PatientProfile> allPatientsFromDb = _uniquePatients;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'Patients Directory',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _showAddPatientDialog,
                icon: const Icon(Icons.add, size: 16, color: Colors.white),
                label: const Text('Add Patient', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  elevation: 1,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (allPatientsFromDb.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: const [
                  Icon(Icons.people_outline_rounded, size: 42, color: AppTheme.textMuted),
                  SizedBox(height: 10),
                  Text('No Registered Patients Found', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark)),
                  SizedBox(height: 4),
                  Text('Click "+ Add Patient" above to register a patient directly into the platform.',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                ],
              ),
            )
          else
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  showCheckboxColumn: false,
                  columns: const [
                    DataColumn(label: Text('Name', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Mobile', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('City', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Pincode', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Language', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Email', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                  rows: allPatientsFromDb.map((patient) {
                    final String name = patient.name.trim().isNotEmpty ? patient.name.trim() : (patient.email.isNotEmpty ? patient.email.split('@').first : 'Patient');
                    final String phone = patient.phone.trim().isNotEmpty ? patient.phone.trim() : 'Not provided';
                    final String email = (patient.email.trim().isNotEmpty && patient.email != '--') ? patient.email.trim() : 'Not provided';
                    final String city = (patient.city.trim().isNotEmpty && patient.city != '--') ? patient.city.trim() : 'Not provided';
                    final String pincode = (patient.pincode.trim().isNotEmpty && patient.pincode != '--') ? patient.pincode.trim() : 'Not provided';
                    final String status = patient.id.isNotEmpty ? 'Registered' : 'Pending';
                    final String language = patient.languages.isNotEmpty
                        ? patient.languages.join(', ')
                        : 'English';
                    return _buildPatientDataRow(patient, name, phone, city, pincode, language, email, status, const Color(0x14012A58), const Color(0xFFFE3434));
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _confirmRemovePatient(BuildContext context, String email, String name) {
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFFE3434), size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Remove $name?',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: Text('Are you sure you want to remove patient $name from the directory?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: const Text('Cancel')),
            ElevatedButton.icon(
              icon: const Icon(Icons.delete_forever_rounded, size: 16),
              label: const Text('Remove Patient', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(backgroundColor: Color(0xFFFE3434), foregroundColor: Colors.white),
              onPressed: () {
                setState(() {
                  _adminPatientsList.removeWhere((p) => p['email'] == email || p['name'] == name);
                });
                _problemService.removePatient(email);
                Navigator.of(dialogCtx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('🗑️ Patient $name removed from directory.'),
                    backgroundColor: Color(0xFFFE3434),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  DataRow _buildPatientDataRow(PatientProfile patient, String name, String phone, String city, String pincode, String language, String email, String status, Color bg, Color text) {
    return DataRow(
      onSelectChanged: (_) => _navigateToPatientDetails(patient),
      cells: [
        DataCell(
          InkWell(
            onTap: () => _navigateToPatientDetails(patient),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: AppTheme.softBlueCard,
                    backgroundImage: patient.photoBytes != null ? MemoryImage(patient.photoBytes!) : null,
                    child: patient.photoBytes == null
                        ? Text(
                            name.isNotEmpty ? name[0].toUpperCase() : 'P',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                      color: AppTheme.primaryBlue,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 10, color: AppTheme.primaryBlue),
                ],
              ),
            ),
          ),
        ),
        DataCell(Text(phone, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: const Color(0x14012A58), borderRadius: BorderRadius.circular(6)),
            child: Text(city, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
          ),
        ),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: const Color(0x14FE3434), borderRadius: BorderRadius.circular(6)),
            child: Text(pincode, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFFE3434))),
          ),
        ),
        DataCell(Text(language, style: const TextStyle(fontSize: 12))),
        DataCell(Text(email, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted))),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
            child: Text(status, style: TextStyle(color: text, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
        ),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.visibility_outlined, color: AppTheme.primaryBlue, size: 18),
                tooltip: 'View Patient Details',
                onPressed: () => _navigateToPatientDetails(patient),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFE3434), size: 18),
                tooltip: 'Remove Patient',
                onPressed: () => _confirmRemovePatient(context, email, name),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _navigateToPatientDetails(PatientProfile patient) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PatientDetailsScreen(
          patient: patient,
          onAssignDoctor: _showAssignDoctorDialog,
        ),
      ),
    );
  }

  // ==========================================
  // PANEL 3: SPECIALTY-BASED HEALTHCARE REPORTING
  // ==========================================
  Widget _buildSpecialtyReportingPanel() {
    final specialtyStats = _problemService.getSpecialtyAnalyticsBreakdown();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Specialty-Based Healthcare Analytics',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textDark),
          ),
          const SizedBox(height: 16),
          // Specialty-Based Reporting Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
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
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Specialty-Based Healthcare Reporting',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Real-time breakdown of registered specialists, consultations, and confirmed appointments by medical specialty',
                            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => setState(() => _selectedNavIndex = 12),
                      icon: const Icon(Icons.category_rounded, size: 15, color: AppTheme.primaryBlue),
                      label: const Text('Manage Specialties', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowHeight: 40,
                    dataRowMinHeight: 42,
                    dataRowMaxHeight: 48,
                    columns: const [
                      DataColumn(label: Text('Medical Specialty', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      DataColumn(label: Text('Department', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      DataColumn(label: Text('Total Doctors', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      DataColumn(label: Text('Available', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      DataColumn(label: Text('Consultations', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      DataColumn(label: Text('Confirmed Appts', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    ],
                    rows: specialtyStats.map((row) {
                      final isActive = row['isActive'] == true;
                      return DataRow(
                        cells: [
                          DataCell(Text('${row['name']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textDark))),
                          DataCell(Text('${row['department']}', style: const TextStyle(fontSize: 11.5, color: AppTheme.textMedium))),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isActive ? const Color(0x14012A58) : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isActive ? 'Active' : 'Inactive',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isActive ? const Color(0xFFFE3434) : AppTheme.textMuted,
                                ),
                              ),
                            ),
                          ),
                          DataCell(Text('${row['totalDoctors']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.primaryBlue))),
                          DataCell(Text('${row['verifiedDoctors']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF012A58)))),
                          DataCell(Text('${row['consultations']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                          DataCell(Text('${row['appointments']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFFFE3434)))),
                        ],
                      );
                    }).toList(),
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
  // PANEL 12: MEDICAL SPECIALTIES MANAGEMENT (DYNAMIC ADMIN CONTROL)
  // ==========================================
  Widget _buildMedicalSpecialtiesPanel() {
    final specialties = _problemService.specialties;
    final activeCount = specialties.where((s) => s.isActive).length;
    final breakdown = _problemService.getSpecialtyAnalyticsBreakdown();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Banner
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.category_rounded, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Multi-Specialty Healthcare Configuration',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$activeCount Active of ${specialties.length} Medical Specialties • Add, edit, activate or deactivate specialties dynamically without code changes',
                        style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: () => _showAddOrEditSpecialtyModal(context),
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
                  label: const Text('+ Add Specialty', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          LayoutBuilder(
            builder: (context, constraints) {
              final crossCount = constraints.maxWidth > 850 ? 2 : 1;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: specialties.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossCount,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  mainAxisExtent: 188,
                ),
                itemBuilder: (context, index) {
                  final spec = specialties[index];
                  Map<String, dynamic>? matchedStats;
                  for (final b in breakdown) {
                    if (b['code'] == spec.code || b['name'] == spec.name) {
                      matchedStats = b;
                      break;
                    }
                  }
                  final docCount = matchedStats?['totalDoctors'] ?? 0;

                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: spec.isActive ? AppTheme.primaryBlue.withValues(alpha: 0.25) : const Color(0xFFE2E8F0),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
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
                                color: spec.isActive
                                    ? AppTheme.primaryBlue.withValues(alpha: 0.1)
                                    : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                spec.iconData,
                                color: spec.isActive ? AppTheme.primaryBlue : AppTheme.textMuted,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    spec.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: AppTheme.textDark),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '${spec.department} • Default: ${spec.defaultQualifications}',
                                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Edit Specialty',
                              icon: const Icon(Icons.edit_outlined, size: 18, color: AppTheme.primaryBlue),
                              onPressed: () => _showAddOrEditSpecialtyModal(context, existing: spec),
                            ),
                            Switch.adaptive(
                              value: spec.isActive,
                              activeTrackColor: const Color(0xFF012A58),
                              onChanged: (val) async {
                                await _problemService.toggleMedicalSpecialtyStatus(spec.id, val);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        val
                                            ? '✅ Activated ${spec.name} across GS HEALTH.'
                                            : '⏸️ Deactivated ${spec.name}.',
                                      ),
                                      backgroundColor: val ? const Color(0xFF012A58) : const Color(0xFF64748B),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          spec.description.isNotEmpty
                              ? spec.description
                              : 'Specialized clinical care and consultations for ${spec.name}.',
                          style: const TextStyle(fontSize: 11.5, color: AppTheme.textMedium),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Spacer(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0x14012A58),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$docCount Registered Specialist${docCount == 1 ? "" : "s"}',
                                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                              ),
                            ),
                            Flexible(
                              child: Text(
                                'Consultations: ${spec.consultationTypes.take(2).join(", ")}',
                                style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  void _showAddOrEditSpecialtyModal(BuildContext context, {MedicalSpecialtyModel? existing}) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final deptCtrl = TextEditingController(text: existing?.department ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final qualCtrl = TextEditingController(
      text: existing != null ? existing.defaultQualifications : 'MBBS, MD',
    );
    final consultCtrl = TextEditingController(
      text: existing != null
          ? existing.consultationTypes.join(', ')
          : 'Initial Consultation, Specialist Evaluation, Follow-up Visit',
    );
    bool isActive = existing?.isActive ?? true;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(
                existing == null ? 'Add Medical Specialty' : 'Edit ${existing.name}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Specialty Name *',
                        hintText: 'e.g. Nephrology',
                        prefixIcon: Icon(Icons.medical_services_outlined),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: deptCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Clinical Department',
                        hintText: 'e.g. Renal Sciences',
                        prefixIcon: Icon(Icons.domain_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: descCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        hintText: 'Brief clinical scope of this medical specialty',
                        prefixIcon: Icon(Icons.description_outlined),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: qualCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Default Qualifications (comma-separated)',
                        hintText: 'MBBS, MD, DM',
                        prefixIcon: Icon(Icons.school_outlined),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: consultCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Consultation Types (comma-separated)',
                        hintText: 'Specialist Consultation, Follow-up Visit',
                        prefixIcon: Icon(Icons.assignment_outlined),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Active on Platform', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      subtitle: const Text('Show in Patient Find Doctors & Doctor Registration', style: TextStyle(fontSize: 11)),
                      value: isActive,
                      onChanged: (v) => setModalState(() => isActive = v),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                  label: Text(existing == null ? 'Add Specialty' : 'Save Changes'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    final quals = qualCtrl.text.trim();
                    final consults = consultCtrl.text
                        .split(',')
                        .map((s) => s.trim())
                        .where((s) => s.isNotEmpty)
                        .toList();

                    if (existing == null) {
                      await _problemService.addMedicalSpecialty(
                        name: name,
                        department: deptCtrl.text.trim().isNotEmpty ? deptCtrl.text.trim() : name,
                        description: descCtrl.text.trim(),
                        defaultQualifications: quals.isNotEmpty ? quals : 'MBBS, MD',
                        consultationTypes: consults,
                      );
                    } else {
                      await _problemService.updateMedicalSpecialty(
                        existing.id,
                        name: name,
                        department: deptCtrl.text.trim().isNotEmpty ? deptCtrl.text.trim() : name,
                        description: descCtrl.text.trim(),
                        isActive: isActive,
                        defaultQualifications: quals.isNotEmpty ? quals : existing.defaultQualifications,
                        consultationTypes: consults.isNotEmpty ? consults : existing.consultationTypes,
                      );
                    }
                    if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(existing == null ? '✅ Added $name specialty!' : '✅ Updated $name specialty!'),
                          backgroundColor: const Color(0xFF012A58),
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

  Widget _buildBarColumn(String day, double pct, bool isHighlight) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: 20,
          height: 90 * pct,
          decoration: BoxDecoration(
            color: isHighlight ? AppTheme.primaryBlue : AppTheme.softBlueCard,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          day,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
            color: isHighlight ? AppTheme.primaryBlue : AppTheme.textMuted,
          ),
        ),
      ],
    );
  }
}

// KPI STAT CARD WIDGET (OVERFLOW PROOF WITH FITTED BOX)
class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final String growth;
  final Color accentColor;
  final IconData icon;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.growth,
    required this.accentColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 14, color: accentColor),
              ),
            ],
          ),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textDark),
              ),
            ),
          ),
          Text(
            growth,
            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: accentColor),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}

// LEGEND ROW WIDGET
class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;
  final String value;

  const _LegendRow({required this.color, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textDark, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
        ),
        Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
      ],
    );
  }
}

// Donut Slice & Custom Painter
class _DonutSlice {
  final double pct;
  final Color color;
  const _DonutSlice({required this.pct, required this.color});
}

class _DonutChartPainter extends CustomPainter {
  final List<_DonutSlice> slices;
  const _DonutChartPainter({required this.slices});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    double startAngle = -1.57;

    for (final slice in slices) {
      final sweepAngle = slice.pct * 2 * 3.14159;
      final paint = Paint()
        ..color = slice.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 20;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 10),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
