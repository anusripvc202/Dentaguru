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
import '../../../../core/constants/permissions.dart';
import '../../../../core/models/referral_model.dart';
import 'patient_details_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> with TickerProviderStateMixin {
  int _selectedNavIndex = 0; // 0: Dashboard, 1: Clinics, 2: Dentists, 3: Patients, 4: Appointments, 5: Revenue, 6: Reports, 7: Reviews, 8: Settings, 9: Sub-Admins
  final PatientProblemService _problemService = PatientProblemService();

  Timer? _autoSyncTimer;
  RealtimeChannel? _realtimeChannel;

  // Sub-Admin Management State
  final List<Map<String, String>> _subAdmins = [];

  void _addSubAdmin(Map<String, String> subAdmin) {
    setState(() => _subAdmins.add(subAdmin));
  }

  void _removeSubAdmin(int index) {
    setState(() => _subAdmins.removeAt(index));
  }

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
    _problemService.syncAllDataFromApi();

    // ⏱️ Auto-sync timer: polls every 4s to catch new requests raised on other devices
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) _problemService.syncProblemRequestsFromApi();
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
              final matchesSpecialty = selectedSpecialtyFilter == 'All' ||
                  doc.specialty.toLowerCase().contains(selectedSpecialtyFilter.toLowerCase());
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
                final matchesSpecialty = selectedSpecialtyFilter == 'All' ||
                    doc.specialty.toLowerCase().contains(selectedSpecialtyFilter.toLowerCase());
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
                : '123 Healthcare Blvd, Medical Hub, Suite 400';
            final doctorPhone = selectedDoctor?.phone ?? '+1 202 555 0100';
            final caseFee = selectedDoctor?.getFeeForCategory(req.problemCategory) ?? '\$75';
            final waText = "🏥 *DentaGuru Clinical Recommendation*\n\n"
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
                "Please open your DentaGuru App to confirm your consultation slot.";

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
                                            color: req.severity == 'Severe' ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            'Severity: ${req.severity}',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: req.severity == 'Severe' ? const Color(0xFF991B1B) : const Color(0xFF92400E),
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
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFFFDE68A)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.recommend_rounded, color: Color(0xFFD97706), size: 20),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '⭐ Patient Referral Preference: ${req.preferredDoctorName}',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF92400E)),
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
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFBFDBFE)),
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
                                      color: const Color(0xFFDBEAFE),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text('Priority Ranked', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF1D4ED8))),
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
                                        icon: const Icon(Icons.clear_rounded, size: 18, color: Color(0xFFEF4444)),
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
                                  ...['All', 'Orthodontics', 'Endodontics', 'General', 'Surgery', 'Periodontics'].map((spec) {
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
                                        selectedColor: const Color(0xFF10B981).withValues(alpha: 0.2),
                                        labelStyle: TextStyle(color: isSel ? const Color(0xFF047857) : AppTheme.textDark),
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
                                               color: const Color(0xFFFEF3C7),
                                               borderRadius: BorderRadius.circular(10),
                                               border: Border.all(color: const Color(0xFFFDE68A)),
                                             ),
                                             child: Row(
                                               children: [
                                                 const Icon(Icons.location_off_rounded, color: Color(0xFFD97706), size: 16),
                                                 const SizedBox(width: 8),
                                                 Expanded(
                                                   child: Text(
                                                     'No doctor found directly in "${searchKeyword.isNotEmpty ? searchKeyword : cityFilterController.text.isNotEmpty ? cityFilterController.text : pincodeFilterController.text}". Showing nearest available doctors:',
                                                     style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF92400E)),
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
                                                 badgeBg = const Color(0xFFDCFCE7); // Emerald green for Same Pincode
                                                 badgeFg = const Color(0xFF15803D);
                                               } else if (tier == 2) {
                                                 badgeBg = const Color(0xFFCCFBF1); // Teal for Nearby Pincode
                                                 badgeFg = const Color(0xFF0F766E);
                                               } else if (tier == 3) {
                                                 badgeBg = const Color(0xFFDBEAFE); // Blue for Same City
                                                 badgeFg = const Color(0xFF1E40AF);
                                               } else if (tier == 5) {
                                                 badgeBg = const Color(0xFFE0E7FF); // Indigo for Same State
                                                 badgeFg = const Color(0xFF3730A3);
                                               }

                                               return GestureDetector(
                                                 onTap: () => setModalState(() => selectedDoctor = doc),
                                                 child: Container(
                                                   margin: const EdgeInsets.only(bottom: 8),
                                                   padding: const EdgeInsets.all(10),
                                                   decoration: BoxDecoration(
                                                     color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
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
                                                                      color: doc.status == 'Available' ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                                                                      borderRadius: BorderRadius.circular(6),
                                                                    ),
                                                                    child: Text(
                                                                      doc.status,
                                                                      style: TextStyle(
                                                                        fontSize: 9.5,
                                                                        fontWeight: FontWeight.bold,
                                                                        color: doc.status == 'Available' ? const Color(0xFF15803D) : const Color(0xFFB45309),
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
                                                                        color: const Color(0xFFFEF3C7),
                                                                        borderRadius: BorderRadius.circular(6),
                                                                        border: Border.all(color: const Color(0xFFFDE68A)),
                                                                      ),
                                                                      child: const Text('Matched Specialty', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFFB45309))),
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
                                  color: const Color(0xFFEFF6FF),
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
                                  color: const Color(0xFFDCFCE7).withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: const Color(0xFF86EFAC)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF15803D),
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
                                        style: const TextStyle(fontSize: 11.5, color: Color(0xFF14532D), height: 1.45),
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
                                            backgroundColor: const Color(0xFF10B981),
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
                                                backgroundColor: const Color(0xFF10B981),
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
                                            backgroundColor: const Color(0xFF2563EB),
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
                                                backgroundColor: const Color(0xFF2563EB),
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
                                                backgroundColor: const Color(0xFF10B981),
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
            : (isDone ? const Color(0xFFDCFCE7) : Colors.transparent),
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
                  ? const Color(0xFF10B981)
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
                color: isActive ? AppTheme.primaryBlue : (isDone ? const Color(0xFF15803D) : AppTheme.textMuted),
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
          appBar: isDesktop
              ? null
              : AppBar(
                  backgroundColor: Colors.white,
                  elevation: 1,
                  titleSpacing: 10,
                  title: const FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: DentaGuruLogo(height: 28),
                  ),
                  actions: [
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
                                    'DentaGuru Clinical Admin Portal',
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
                                    final adminNotifs = _problemService.appNotifications
                                        .where((n) => n.recipientRole == 'Admin' || n.recipientId == 'ALL_ADMINS')
                                        .toList();
                                    final unreadCount = adminNotifs.where((n) => !n.isRead).length;

                                    return Stack(
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.notifications_none_rounded, color: AppTheme.textDark, size: 22),
                                          onPressed: () => _showNotificationsModal(context, 'Admin'),
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
                                const SizedBox(width: 8),
                                ScaleTransition(
                                  scale: _pulseScaleAnimation,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFDCFCE7),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text('Admin Mode', style: TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.bold, fontSize: 11)),
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

                    // Mobile Horizontal Navigation Bar Pills (When container is < 950px)
                    if (!isDesktop)
                      Container(
                        height: 48,
                        color: Colors.white,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: Row(
                            children: [
                              _buildMobileNavPill(0, 'Dashboard', Icons.grid_view_rounded),
                              _buildMobileNavPill(
                                11,
                                'Referrals',
                                Icons.group_add_rounded,
                                badgeCount: _problemService.adminPatientReferrals.where((r) => r.status == 'Pending').length,
                              ),
                              _buildMobileNavPill(3, 'Patients', Icons.people_outline_rounded),
                              _buildMobileNavPill(1, 'Clinics', Icons.local_hospital_outlined),
                              _buildMobileNavPill(2, 'Dentists', Icons.medical_services_outlined),
                              _buildMobileNavPill(4, 'Appointments', Icons.calendar_month_outlined),
                              _buildMobileNavPill(10, 'Chats', Icons.forum_outlined),
                              _buildMobileNavPill(5, 'Revenue', Icons.account_balance_wallet_outlined),
                              _buildMobileNavPill(9, 'Sub-Admins', Icons.supervisor_account_outlined),
                            ],
                          ),
                        ),
                      ),

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
                  currentIndex: _getBottomNavIndex(),
                  selectedItemColor: AppTheme.primaryBlue,
                  unselectedItemColor: AppTheme.textMuted,
                  selectedFontSize: 11,
                  unselectedFontSize: 11,
                  onTap: (index) {
                    setState(() {
                      if (index == 0) _selectedNavIndex = 0; // Dashboard
                      if (index == 1) _selectedNavIndex = 3; // Patients
                      if (index == 2) _selectedNavIndex = 5; // Revenue
                    });
                  },
                  items: const [
                    BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'Dashboard'),
                    BottomNavigationBarItem(icon: Icon(Icons.people_alt_rounded), label: 'Patients'),
                    BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet_rounded), label: 'Revenue'),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildMobileNavPill(int index, String label, IconData icon, {int badgeCount = 0}) {
    final isSelected = _selectedNavIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedNavIndex = index),
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
                  color: isSelected ? Colors.white : const Color(0xFFEF4444),
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

  int _getBottomNavIndex() {
    if (_selectedNavIndex == 3) return 1;
    if (_selectedNavIndex == 5) return 2;
    return 0;
  }

  String _getNavTitle() {
    switch (_selectedNavIndex) {
      case 0:
        return 'Dashboard Overview';
      case 1:
        return 'Clinics Directory';
      case 2:
        return 'Dentists & Specialists';
      case 3:
        return 'Patients Directory';
      case 4:
        return 'Appointments Schedule';
      case 5:
        return 'Revenue & Financials';
      case 6:
        return 'Reports & Analytics';
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
                  _buildSubNavItem(1, Icons.domain_rounded, 'Clinics Directory'),
                  _buildSubNavItem(2, Icons.medical_services_rounded, 'Dentists & Specialists'),
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

              // CATEGORY 4: FINANCIALS & ANALYTICS DROPDOWN
              _buildSidebarDropdownCategory(
                categoryTitle: 'Financials & Reports',
                categoryIcon: Icons.account_balance_wallet_rounded,
                initiallyExpanded: false,
                children: [
                  _buildSubNavItem(5, Icons.payments_rounded, 'Revenue & Payments'),
                  _buildSubNavItem(6, Icons.bar_chart_rounded, 'Reports & Analytics'),
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
                  _buildSubNavItem(9, Icons.supervisor_account_rounded, 'Sub-Admins', badgeCount: _subAdmins.length),
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
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          childrenPadding: const EdgeInsets.only(bottom: 6),
          leading: Icon(categoryIcon, size: 18, color: AppTheme.primaryBlue),
          title: Text(
            categoryTitle,
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

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.primaryBlue : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
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
                  color: isSelected ? Colors.white : const Color(0xFFEF4444),
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
        onTap: () {
          setState(() {
            _selectedNavIndex = index;
          });
        },
      ),
    );
  }

  Widget _buildSelectedPanel() {
    switch (_selectedNavIndex) {
      case 0:
        return _buildDashboardPanel();
      case 1:
        return _buildClinicsPanel();
      case 2:
        return _buildDentistsPanel();
      case 3:
        return _buildPatientsPanel();
      case 5:
        return _buildRevenuePanel();
      case 9:
        return _buildSubAdminsPanel();
      case 10:
        return _buildPatientDoctorChatsPanel();
      case 11:
        return _buildReferralManagementPanel();
      default:
        return _buildDashboardPanel();
    }
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
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
                                      color: const Color(0xFF0284C7).withValues(alpha: 0.25),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFF38BDF8), width: 0.8),
                                    ),
                                    child: Text(
                                      'Doctor: $doctorName',
                                      style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFF10B981), width: 0.8),
                                    ),
                                    child: const Text('AUDIT LOGGED', style: TextStyle(color: Color(0xFF10B981), fontSize: 9, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text('Room ID: $roomId • Consulting Doctor: $doctorName', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 20),
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
                                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
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
                        future: ApiService().fetchChatMessages(roomId: roomId),
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
                              final isDoc = senderRoleStr.contains('dentist') || senderRoleStr.contains('doctor') || type == 'doctor';
                              
                              String fromName = sender is Map ? (sender['name'] ?? (isDoc ? doctorName : patientName)) : (isDoc ? doctorName : patientName);
                              if (isDoc && !fromName.toLowerCase().startsWith('dr')) {
                                fromName = 'Dr. $fromName';
                              }
                              final String fromRole = isDoc ? 'Dentist' : 'Patient';
                              final String toName = isDoc ? patientName : doctorName;
                              final String toRole = isDoc ? 'Patient' : 'Dentist';

                              final time = msg['created_at'] != null ? DateTime.tryParse(msg['created_at'].toString()) : null;
                              final timeStr = time != null 
                                  ? '${time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour)}:${time.minute.toString().padLeft(2, '0')} ${time.hour >= 12 ? 'PM' : 'AM'}'
                                  : '';

                              return Align(
                                alignment: isDoc ? Alignment.centerRight : Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
                                  decoration: BoxDecoration(
                                    color: isDoc ? const Color(0xFFE0F2FE) : const Color(0xFFDCFCE7),
                                    borderRadius: BorderRadius.circular(14).copyWith(
                                      topRight: isDoc ? const Radius.circular(2) : const Radius.circular(14),
                                      topLeft: isDoc ? const Radius.circular(14) : const Radius.circular(2),
                                    ),
                                    border: Border.all(
                                      color: isDoc ? const Color(0xFFBAE6FD) : const Color(0xFFBBF7D0),
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
                                            isDoc ? Icons.medical_services_rounded : Icons.person_rounded,
                                            size: 13,
                                            color: isDoc ? const Color(0xFF0284C7) : const Color(0xFF16A34A),
                                          ),
                                          Text(
                                            '$fromName ($fromRole)',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: isDoc ? const Color(0xFF0284C7) : const Color(0xFF16A34A),
                                            ),
                                          ),
                                          const Icon(Icons.arrow_forward_rounded, size: 11, color: Color(0xFF94A3B8)),
                                          Text(
                                            'To: $toName ($toRole)',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: isDoc ? const Color(0xFF0F766E) : const Color(0xFF0369A1),
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
                        final email = log['user_email'] ?? 'admin@dentaguru.com';
                        final ip = log['ip_address'] ?? '127.0.0.1';
                        final time = log['created_at'] != null ? DateTime.tryParse(log['created_at'].toString()) : null;
                        final dateStr = time != null ? '${time.day}/${time.month}/${time.year} ${time.hour}:${time.minute.toString().padLeft(2, '0')}' : '';

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3B82F6).withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.security_rounded, size: 18, color: Color(0xFF3B82F6)),
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
      _fetchAdminConversations();
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
                                backgroundColor: const Color(0xFF3B82F6),
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
                                  backgroundColor: const Color(0xFF3B82F6),
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
                                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF10B981), width: 0.8),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.shield_rounded, color: Color(0xFF10B981), size: 14),
                                  SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      'Sub-Admins Strictly Restricted (403 Forbidden)',
                                      style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold),
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
                decoration: InputDecoration(
                  hintText: 'Search conversations by patient, doctor, or keyword...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
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
                    final doctorName = (conv['doctorName'] ?? 'Attending Dentist').toString();
                    final lastMsg = (conv['lastMessage'] ?? '').toString();
                    final totalMsgs = conv['totalMessages'] ?? 0;
                    final time = conv['lastMessageTime'] != null ? DateTime.tryParse(conv['lastMessageTime'].toString()) : null;
                    final timeStr = time != null ? '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}' : '';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
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
    final rawList = _problemService.subAdmins;
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
                    colors: [Color(0xFF6366F1), Color(0xFF818CF8)],
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
                      decoration: InputDecoration(
                        hintText: 'Search sub-admins by name, email, phone...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
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
                      backgroundColor: const Color(0xFF6366F1),
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
                          color: const Color(0xFF6366F1).withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.supervisor_account_outlined, size: 40, color: Color(0xFF6366F1)),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        rawList.isEmpty ? 'No Sub-Admins Created Yet' : 'No Sub-Admins Match Filter',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Create sub-admins and assign granular permissions for patients, dentists, doctor assignments, appointments, problems, and reports.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: AppTheme.textMuted, height: 1.5),
                      ),
                      if (rawList.isEmpty) ...[
                        const SizedBox(height: 18),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.person_add_rounded, size: 16),
                          label: const Text('Create First Sub-Admin', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
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
                        border: Border.all(color: isActive ? const Color(0xFFE2E8F0) : const Color(0xFFFCA5A5)),
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
                                backgroundColor: isActive ? const Color(0xFF6366F1) : const Color(0xFF94A3B8),
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
                                            color: isActive ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            isActive ? '✓ Active' : '⛔ Deactivated',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: isActive ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
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
                              Switch(
                                value: isActive,
                                activeThumbColor: const Color(0xFF10B981),
                                onChanged: (val) async {
                                  final newStatus = val ? 'ACTIVE' : 'INACTIVE';
                                  _problemService.updateSubAdminStatusLocally(saId, newStatus);
                                  if (mounted) setState(() {});

                                  await ApiService().toggleSubAdminStatus(saId, status: newStatus);
                                  await _problemService.syncSubAdminsFromApi();
                                  if (mounted) setState(() {});

                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(val ? '✓ Sub-Admin "$name" activated.' : '⛔ Sub-Admin "$name" deactivated.'),
                                        backgroundColor: val ? const Color(0xFF10B981) : const Color(0xFFD97706),
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                },
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
                                    ? const Text('None assigned (Restricted)', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Color(0xFFDC2626)))
                                    : Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: permissions.map((p) {
                                          return Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFEEF2FF),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: const Color(0xFFC7D2FE)),
                                            ),
                                            child: Text(
                                              AppPermissions.getLabel(p),
                                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF4338CA)),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Action Buttons: Edit Permissions & Remove
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              OutlinedButton.icon(
                                icon: const Icon(Icons.edit_rounded, size: 14),
                                label: const Text('Edit Details & Roles', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF6366F1),
                                  side: const BorderSide(color: Color(0xFF6366F1)),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () => _showEditSubAdminModal(context, sa),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => _confirmRemoveSubAdmin(context, saId, name),
                                child: Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 16),
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
          color: isSelected ? const Color(0xFF6366F1) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? const Color(0xFF6366F1) : const Color(0xFFE2E8F0)),
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

  void _confirmRemoveSubAdmin(BuildContext context, String subAdminId, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 22),
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
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
                    backgroundColor: Colors.red,
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
                            color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.shield_outlined, color: Color(0xFF6366F1), size: 22),
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
                              decoration: InputDecoration(
                                labelText: 'Email Address (Optional)',
                                hintText: 'subadmin@dentaguru.com (Optional)',
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
                                    decoration: InputDecoration(
                                      labelText: 'City *',
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
                                    decoration: InputDecoration(
                                      labelText: 'Pincode *',
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
                                      child: const Text('Clear', style: TextStyle(fontSize: 11, color: Colors.red)),
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
                                        activeColor: const Color(0xFF6366F1),
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
                          backgroundColor: const Color(0xFF6366F1),
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
                                    const SnackBar(content: Text('⚠️ Please fill in Full Name and Mobile Phone Number.'), backgroundColor: Color(0xFFD97706)),
                                  );
                                  return;
                                }

                                setModalState(() => isLoading = true);

                                try {
                                  final res = await ApiService().createSubAdmin(
                                    name: name,
                                    phone: phone,
                                    email: email,
                                    city: city.isNotEmpty ? city : 'Hyderabad',
                                    pincode: pincode.isNotEmpty ? pincode : '500032',
                                    languages: [selectedSubAdminLanguage],
                                    permissions: selectedPerms.toList(),
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
                                        backgroundColor: const Color(0xFF10B981),
                                      ),
                                    );
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('⚠️ ${res['message'] ?? 'Notice during creation'}'), backgroundColor: const Color(0xFFD97706)),
                                    );
                                  }
                                } catch (e) {
                                  setModalState(() => isLoading = false);
                                  if (!dialogCtx.mounted) return;
                                  Navigator.of(dialogCtx).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('⚠️ Error creating Sub-Admin: $e'), backgroundColor: const Color(0xFFEF4444)),
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
                            color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.edit_rounded, color: Color(0xFF6366F1), size: 22),
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
                            // Full Name
                            TextField(
                              controller: nameCtrl,
                              decoration: InputDecoration(
                                labelText: 'Full Name',
                                prefixIcon: const Icon(Icons.person_outline_rounded, size: 18),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Phone
                            TextField(
                              controller: phoneCtrl,
                              keyboardType: TextInputType.phone,
                              decoration: InputDecoration(
                                labelText: 'Phone Number',
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
                                  selectedColor: const Color(0xFFDCFCE7),
                                  onSelected: (val) => setModalState(() => status = 'ACTIVE'),
                                ),
                                const SizedBox(width: 8),
                                ChoiceChip(
                                  label: const Text('Deactivated'),
                                  selected: status != 'ACTIVE',
                                  selectedColor: const Color(0xFFFEE2E2),
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
                                      child: const Text('Clear', style: TextStyle(fontSize: 11, color: Colors.red)),
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
                                        activeColor: const Color(0xFF6366F1),
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
                          backgroundColor: const Color(0xFF6366F1),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: isLoading
                            ? null
                            : () async {
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
                                        backgroundColor: const Color(0xFF10B981),
                                      ),
                                    );
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('⚠️ ${res['message'] ?? 'Notice during update'}'), backgroundColor: const Color(0xFFD97706)),
                                    );
                                  }
                                } catch (e) {
                                  setModalState(() => isLoading = false);
                                  if (!dialogCtx.mounted) return;
                                  Navigator.of(dialogCtx).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('⚠️ Error updating Sub-Admin: $e'), backgroundColor: const Color(0xFFEF4444)),
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
    final clinics = _problemService.allClinics;

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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🏥 Partner Clinics Directory',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Manage registered dental practices & health hubs',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.add_location_alt_rounded, size: 16, color: Colors.white),
                label: const Text('+ Register New Clinic', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D9488),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => _showRegisterClinicModal(context),
              ),
            ],
          ),
          const SizedBox(height: 20),
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
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D9488)),
                    onPressed: () => _showRegisterClinicModal(context),
                  )
                ],
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final crossCount = w > 750 ? 2 : 1;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossCount,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    mainAxisExtent: 180,
                  ),
                  itemCount: clinics.length,
                  itemBuilder: (context, idx) {
                    final clinic = clinics[idx];
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2)),
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
                                  color: const Color(0xFF0D9488).withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.local_hospital_rounded, color: Color(0xFF0D9488), size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      clinic.clinicName,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      '📍 ${clinic.location}',
                                      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              if (clinic.verified)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text('VERIFIED', style: TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold)),
                                ),
                            ],
                          ),
                          const Divider(height: 20),
                          const Text('Services Offered:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: clinic.services.map((serv) {
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(serv, style: const TextStyle(fontSize: 10, color: AppTheme.textDark, fontWeight: FontWeight.w500)),
                              );
                            }).toList(),
                          ),
                          const Spacer(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.star_rounded, size: 16, color: Color(0xFFF59E0B)),
                                  const SizedBox(width: 4),
                                  Text('${clinic.rating}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                  Text(' (${clinic.reviewsCount} reviews)', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                ],
                              ),
                              const Text('Verified Practice', style: TextStyle(fontSize: 10, color: Color(0xFF0D9488), fontWeight: FontWeight.bold)),
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

  void _showRegisterClinicModal(BuildContext context) {
    final nameCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    final servicesCtrl = TextEditingController(text: 'Teeth Cleaning, Root Canal, Orthodontics, Dental Implants');
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
                              color: const Color(0xFF0D9488).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.add_location_alt_rounded, color: Color(0xFF0D9488)),
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
                        decoration: InputDecoration(
                          labelText: 'Clinic Name *',
                          hintText: 'e.g. City Dental Care Center',
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: locationCtrl,
                        decoration: InputDecoration(
                          labelText: 'Full Address / Location *',
                          hintText: 'e.g. Street / Area / City',
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: servicesCtrl,
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
                              backgroundColor: const Color(0xFF0D9488),
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
                                          backgroundColor: const Color(0xFF10B981),
                                        ),
                                      );
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('❌ Failed to save clinic profile.'),
                                          backgroundColor: Color(0xFFEF4444),
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
    showDialog(
      context: context,
      builder: (dialogCtx) {
        final notifs = _problemService.appNotifications
            .where((n) => n.recipientRole == role || n.recipientId == 'ALL_ADMINS')
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
                              'Admin System Notifications',
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
                      child: Text('No system notifications.', style: TextStyle(color: Colors.grey, fontSize: 12)),
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

  void _showRegisterDoctorModal(BuildContext context) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final qualCtrl = TextEditingController(text: 'BDS, MDS');
    final licenseCtrl = TextEditingController();
    final clinicCtrl = TextEditingController();
    final expCtrl = TextEditingController(text: '5');
    final feeCtrl = TextEditingController(text: '\$75');
    final stateCtrl = TextEditingController();
    final cityCtrl = TextEditingController();
    final pincodeCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    String selectedSpecialty = 'General Dentistry';
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
                                'Create New Dentist Account',
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
                              decoration: InputDecoration(
                                labelText: 'Email Address (Optional)',
                                hintText: 'e.g. jane@dentaguru.com (Optional)',
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
                                    decoration: InputDecoration(
                                      labelText: 'Specialization',
                                      prefixIcon: const Icon(Icons.medical_services_outlined, size: 16),
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    items: [
                                      'General Dentistry',
                                      'Orthodontics',
                                      'Endodontics',
                                      'Periodontics',
                                      'Pediatric Dentistry',
                                      'Oral & Maxillofacial Surgery',
                                      'Cosmetic Dentistry',
                                    ].map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 11)))).toList(),
                                    onChanged: (val) {
                                      if (val != null) setModalState(() => selectedSpecialty = val);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    controller: qualCtrl,
                                    decoration: InputDecoration(
                                      labelText: 'Qualification',
                                      hintText: 'BDS, MDS',
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
                                    decoration: InputDecoration(
                                      labelText: 'City *',
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
                                    decoration: InputDecoration(
                                      labelText: 'Pincode *',
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
                                    decoration: InputDecoration(
                                      labelText: 'Practice / Clinic Name *',
                                      hintText: 'e.g. Apex Care Dental',
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
                                    decoration: InputDecoration(
                                      labelText: 'Fee',
                                      hintText: '\$75',
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
                              decoration: InputDecoration(
                                labelText: 'Clinic Address / Location',
                                hintText: 'e.g. 123 Healthcare Blvd, Suite 400',
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
                        isSubmitting ? 'Creating Dentist Account...' : 'Create Dentist Account',
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
                                licenseNumber: licenseCtrl.text.isNotEmpty ? licenseCtrl.text : 'DEN-LIC-REG',
                                specialty: selectedSpecialty,
                                qualification: qualCtrl.text.isNotEmpty ? qualCtrl.text : 'BDS, MDS',
                                clinicName: clinicCtrl.text.isNotEmpty ? clinicCtrl.text : 'Dental Practice',
                                experienceYears: expYears,
                                consultationFee: feeCtrl.text.isNotEmpty ? feeCtrl.text : '\$75',
                                state: stateCtrl.text,
                                city: cityCtrl.text.isNotEmpty ? cityCtrl.text : 'Hyderabad',
                                pincode: pincodeCtrl.text.isNotEmpty ? pincodeCtrl.text : '500032',
                                clinicAddress: addressCtrl.text,
                                languages: [selectedLanguage],
                              );

                              Navigator.of(dialogContext).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('🎉 Registered ${doctor.name} successfully! Dentist can now sign in using Mobile OTP.'),
                                  backgroundColor: const Color(0xFF10B981),
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
    final slotCtrl = TextEditingController(text: doc.nextAvailableSlots.isNotEmpty ? doc.nextAvailableSlots.first : 'Today, 2:00 PM');

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Edit Fee & Slots • ${doc.name}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: feeCtrl,
                decoration: InputDecoration(
                  labelText: 'Standard Consultation Fee',
                  hintText: 'e.g. \$85',
                  prefixIcon: const Icon(Icons.payments_outlined),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: slotCtrl,
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
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: const Text('Cancel')),
            ElevatedButton.icon(
              icon: const Icon(Icons.save_rounded, size: 16),
              label: const Text('Update Fee & Slot', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                _problemService.updateDoctorFeeAndSlots(
                  doctorId: doc.id,
                  consultationFee: feeCtrl.text.trim(),
                  availableSlot: slotCtrl.text.trim(),
                );
                Navigator.of(dialogCtx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('⚡ Updated ${doc.name}\'s fee to ${feeCtrl.text.trim()} & slot to ${slotCtrl.text.trim()}!'),
                    backgroundColor: const Color(0xFF10B981),
                  ),
                );
              },
            ),
          ],
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
              const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
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
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () {
                _problemService.removeDoctor(doc.id);
                Navigator.of(dialogCtx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('🗑️ ${doc.name} removed from platform directory.'),
                    backgroundColor: Colors.red,
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
  // PANEL 2: MASTER DENTISTS DIRECTORY (ALL DOCTORS)
  // ==========================================
  Widget _buildDentistsPanel() {
    final doctors = _problemService.allDoctors;
    final requests = _problemService.requests;
    final PatientConsultationRequest? pendingRequest = requests.where((r) => r.status == 'Pending Admin Review').firstOrNull ?? requests.firstOrNull;

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
                        '👨‍⚕️ Master Dentists Directory & Specialist Assignment',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'All verified dental specialists registered on DentaGuru • Match patient problems directly',
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
              _buildMiniStatCard('Total Dentists', '${doctors.length}', Icons.badge_rounded, AppTheme.primaryBlue),
              const SizedBox(width: 12),
              _buildMiniStatCard('Available Now', '${doctors.where((d) => d.status == 'Available').length}', Icons.check_circle_rounded, const Color(0xFF10B981)),
              const SizedBox(width: 12),
              _buildMiniStatCard('Avg Rating', '4.85 ⭐', Icons.star_rounded, const Color(0xFFF59E0B)),
            ],
          ),
          const SizedBox(height: 20),

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
                icon: const Icon(Icons.person_add_rounded, size: 16),
                label: const Text('+ Create Dentist', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
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

          // Grid of Doctors
          if (doctors.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.medical_services_outlined, size: 42, color: AppTheme.textMuted),
                  const SizedBox(height: 10),
                  const Text('No Doctors Registered Yet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark)),
                  const SizedBox(height: 4),
                  const Text('Click "+ Register Doctor" above to onboard a dentist into the platform.',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                ],
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final crossCount = constraints.maxWidth > 750 ? 2 : 1;

                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: doctors.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossCount,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    mainAxisExtent: 310,
                  ),
                itemBuilder: (context, index) {
                  final doc = doctors[index];
                  final isAvailable = doc.status == 'Available';

                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
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
                              radius: 22,
                              backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.12),
                              child: Text(
                                doc.name.replaceAll('Dr.', '').trim().split(' ').last[0],
                                style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue, fontSize: 16),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    doc.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    doc.specialty,
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryBlue),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '${doc.qualification} • ${doc.experienceYears} yrs exp',
                                    style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isAvailable ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    doc.status,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: isAvailable ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 18),
                                  tooltip: 'Remove Doctor from Platform',
                                  onPressed: () => _confirmRemoveDoctor(context, doc),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const Divider(height: 14, color: Color(0xFFF1F5F9)),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('🏥 ${doc.clinicName}', style: const TextStyle(fontSize: 11, color: AppTheme.textMedium, fontWeight: FontWeight.w500)),
                            Text('Fee: ${doc.consultationFee}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Lic: ${doc.licenseNumber}',
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF59E0B)),
                            const SizedBox(width: 3),
                            Text('${doc.rating}', style: const TextStyle(fontSize: 11, color: AppTheme.textDark, fontWeight: FontWeight.w600)),
                            const Spacer(),
                            Text('Slots: ${doc.nextAvailableSlots.first}', style: const TextStyle(fontSize: 10, color: Color(0xFF10B981), fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: doc.procedureFees.entries.take(4).map((entry) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryBlue.withValues(alpha: 0.07),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppTheme.primaryBlue.withValues(alpha: 0.2)),
                              ),
                              child: Text(
                                '${entry.key}: ${entry.value}',
                                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text('City: ${doc.city.isNotEmpty ? doc.city : "Not provided"}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text('PIN: ${doc.pincode.isNotEmpty ? doc.pincode : "Not provided"}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFD97706))),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Mobile: ${doc.phone.isNotEmpty ? doc.phone : "Not provided"} • Languages: ${doc.languages.isNotEmpty ? doc.languages.join(", ") : "English"} • Email: ${doc.email.isNotEmpty ? doc.email : "Not provided"}',
                          style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Spacer(),

                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.edit_calendar_rounded, size: 14),
                                label: const Text('Edit Fee & Slot', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  side: const BorderSide(color: AppTheme.primaryBlue, width: 1.2),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: () => _showEditDoctorFeeAndSlotsDialog(context, doc),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 3,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.recommend_rounded, size: 14),
                                label: const Text('Suggest Doctor', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primaryBlue,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: pendingRequest != null
                                    ? () => _showAssignDoctorDialog(context, pendingRequest, preSelectedDoctor: doc)
                                    : null,
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

  void _confirmDeleteRequest(BuildContext context, PatientConsultationRequest req) {
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(
            children: [
              Icon(Icons.delete_forever_rounded, color: Colors.red, size: 22),
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
                backgroundColor: Colors.red,
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
                      backgroundColor: Colors.red.shade700,
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
          preferredLocation: (r.preferredLocation != null && r.preferredLocation!.isNotEmpty) ? r.preferredLocation : existing.preferredLocation,
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
                    value: '${_problemService.allPatients.length}',
                    growth: 'Central DB Synced',
                    accentColor: AppTheme.primaryBlue,
                    icon: Icons.people_alt_rounded,
                  ),
                  _KpiCard(
                    title: 'Total Dentists',
                    value: '${_problemService.allDoctors.length}',
                    growth: 'Verified Dentists',
                    accentColor: const Color(0xFF10B981),
                    icon: Icons.medical_services_rounded,
                  ),
                  _KpiCard(
                    title: 'Total Referrals',
                    value: '${_problemService.adminPatientReferrals.length}',
                    growth: 'Patient-to-Doctor',
                    accentColor: const Color(0xFF8B5CF6),
                    icon: Icons.share_rounded,
                  ),
                  _KpiCard(
                    title: 'Pending Consultations',
                    value: '$pendingCount',
                    growth: 'Requires Action',
                    accentColor: const Color(0xFFD97706),
                    icon: Icons.pending_actions_rounded,
                  ),
                  _KpiCard(
                    title: 'Total Sub-Admins',
                    value: '${_problemService.subAdmins.length}',
                    growth: 'Portal Sub-Admins',
                    accentColor: const Color(0xFF6366F1),
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
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.mark_chat_read_rounded, size: 14, color: Color(0xFF16A34A)),
                          SizedBox(width: 4),
                          Text(
                            'WhatsApp',
                            style: TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.bold, fontSize: 11),
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
                        Text('New dental requests raised by patients will appear here for admin review.', style: TextStyle(fontSize: 11, color: AppTheme.textMuted), textAlign: TextAlign.center),
                      ],
                    ),
                  )
                else
                  Column(
                    children: requests.map((req) {
                      final isPending = req.status == 'Pending Admin Review';

                      return LayoutBuilder(
                        builder: (context, cardConstraints) {
                          final isNarrow = cardConstraints.maxWidth < 520;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isPending ? const Color(0xFFF59E0B) : const Color(0xFFCBD5E1),
                                width: isPending ? 1.5 : 1,
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
                                        color: isPending ? const Color(0xFFFEF3C7) : const Color(0xFFDCFCE7),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        isPending ? Icons.pending_actions_rounded : Icons.check_circle_rounded,
                                        color: isPending ? const Color(0xFFD97706) : const Color(0xFF16A34A),
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            req.patientName.trim().isNotEmpty && req.patientName.trim().toLowerCase() != 'patient'
                                                ? req.patientName
                                                : (_problemService.allPatients.any((p) => (req.patientId != null && p.id == req.patientId) || (p.name.isNotEmpty && p.name.toLowerCase() != 'patient'))
                                                    ? _problemService.allPatients.firstWhere((p) => (req.patientId != null && p.id == req.patientId) || (p.name.isNotEmpty && p.name.toLowerCase() != 'patient')).name
                                                    : 'Patient'),
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            '📞 Phone: ${req.patientPhone.isNotEmpty ? req.patientPhone : (_problemService.allPatients.firstWhere((p) => p.id == req.patientId || p.name == req.patientName, orElse: () => PatientProfile()).phone.isNotEmpty ? _problemService.allPatients.firstWhere((p) => p.id == req.patientId || p.name == req.patientName, orElse: () => PatientProfile()).phone : 'Not Provided')}',
                                            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '📍 City: ${req.getDisplayCity(_problemService.allPatients)}${req.getDisplayPincode(_problemService.allPatients).isNotEmpty ? " • PIN: ${req.getDisplayPincode(_problemService.allPatients)}" : ""}',
                                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: req.severity == 'Severe'
                                            ? const Color(0xFFFEE2E2)
                                            : req.severity == 'Moderate'
                                                ? const Color(0xFFFEF3C7)
                                                : const Color(0xFFDBEAFE),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        req.severity,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: req.severity == 'Severe'
                                              ? const Color(0xFF991B1B)
                                              : req.severity == 'Moderate'
                                                  ? const Color(0xFF92400E)
                                                  : AppTheme.primaryBlue,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),

                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Issue: ${req.problemCategory}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppTheme.primaryBlue),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  req.problemDescription,
                                  style: const TextStyle(fontSize: 12, color: AppTheme.textDark, height: 1.3),
                                ),

                                if (req.assignedDoctorName != null || req.assignedDoctorId != null || req.status.toUpperCase().contains('ASSIGNED') || req.status == 'Doctor Assigned' || req.status == 'Confirmed') ...[
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF0FDF4),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0xFF86EFAC)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.verified_user_rounded, color: Color(0xFF16A34A), size: 16),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Assigned: ${req.displayDoctorName} (${req.displayDoctorSpecialty})',
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF14532D)),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              if (req.confirmedTimeSlot != null && req.confirmedTimeSlot!.isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                Text(
                                                  '⏰ Time Slot: ${req.confirmedTimeSlot}',
                                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppTheme.primaryBlue),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],

                                const SizedBox(height: 12),

                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        icon: const Icon(Icons.mark_chat_read_rounded, size: 16),
                                        label: Text(
                                          isPending ? '🟢 Suggest Doctor & Launch WhatsApp' : '💬 Resend WhatsApp Link',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: isPending ? const Color(0xFF10B981) : AppTheme.primaryBlue,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                          elevation: 1,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                        onPressed: () => _showAssignDoctorDialog(context, req),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      tooltip: 'Remove Request',
                                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                                      onPressed: () => _confirmDeleteRequest(context, req),
                                    ),
                                  ],
                                ),
                              ],
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
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFFDE68A)),
                            ),
                            child: Text(
                              '$pendingCount New',
                              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFFD97706)),
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
                icon: const Icon(Icons.open_in_new_rounded, size: 14, color: Color(0xFF8B5CF6)),
                label: const Text(
                  'Full View',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF8B5CF6)),
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
                    ? const Color(0xFF10B981)
                    : (isRejected ? const Color(0xFFEF4444) : const Color(0xFFF59E0B));
                final statusBg = isAccepted
                    ? const Color(0xFFDCFCE7)
                    : (isRejected ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7));
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
                      color: ref.status == 'Pending' ? const Color(0xFFDDD6FE) : const Color(0xFFE2E8F0),
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
                              color: const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.chat_bubble_rounded, size: 10, color: Color(0xFF16A34A)),
                                const SizedBox(width: 3),
                                Text(
                                  ref.whatsappStatus == 'Sent' ? 'WhatsApp Sent' : 'Queued',
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF16A34A)),
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
                                color: const Color(0xFFEEF2FF),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFC7D2FE)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.person_pin_rounded, size: 13, color: Color(0xFF4338CA)),
                                      SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          'Referring Patient',
                                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF4338CA)),
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
                                color: const Color(0xFFF0FDF4),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFBBF7D0)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.person_rounded, size: 13, color: Color(0xFF15803D)),
                                      SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          'Referred Patient',
                                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
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
                                  const Icon(Icons.location_on_outlined, size: 12, color: Color(0xFF0284C7)),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      'Patient Address: $patientLoc',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF0369A1)),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                            ],
                            Row(
                              children: [
                                const Icon(Icons.medical_services_outlined, size: 12, color: Color(0xFF0D9488)),
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
            'Appointment Overview',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textDark),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 160,
            width: double.infinity,
            child: CustomPaint(
              painter: _AreaCurvePainter(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('Apr', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              Text('May', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              Text('Jun', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              Text('Jul', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              Text('Aug', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              Text('Sep', style: TextStyle(fontSize: 11, color: AppTheme.primaryBlue, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAppointmentsByStatusCard() {
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
          Row(
            children: [
              SizedBox(
                width: 100,
                height: 100,
                child: CustomPaint(
                  painter: _DonutChartPainter(
                    slices: const [
                      _DonutSlice(pct: 0.65, color: Color(0xFF0D9488)),
                      _DonutSlice(pct: 0.25, color: Color(0xFF0052CC)),
                      _DonutSlice(pct: 0.10, color: Color(0xFF60A5FA)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    _LegendRow(color: Color(0xFF0D9488), label: 'Completed', value: '65%'),
                    SizedBox(height: 8),
                    _LegendRow(color: Color(0xFF0052CC), label: 'Scheduled', value: '25%'),
                    SizedBox(height: 8),
                    _LegendRow(color: Color(0xFF60A5FA), label: 'Cancelled', value: '10%'),
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
    final ageCtrl = TextEditingController(text: '28');
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
                        decoration: const InputDecoration(labelText: 'Patient Full Name *', prefixIcon: Icon(Icons.person_outline_rounded)),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Mobile Phone Number *', prefixIcon: Icon(Icons.phone_android_rounded)),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Email Address (Optional)', prefixIcon: Icon(Icons.email_outlined)),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: cityCtrl,
                              decoration: const InputDecoration(labelText: 'City *', prefixIcon: Icon(Icons.location_city_rounded)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: pincodeCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Pincode *', prefixIcon: Icon(Icons.pin_drop_outlined)),
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
                          final name = nameCtrl.text.trim().isEmpty ? 'New Patient' : nameCtrl.text.trim();
                          final phone = phoneCtrl.text.trim();
                          final email = emailCtrl.text.trim();
                          final city = cityCtrl.text.trim().isNotEmpty ? cityCtrl.text.trim() : 'Hyderabad';
                          final pin = pincodeCtrl.text.trim().isNotEmpty ? pincodeCtrl.text.trim() : '500032';

                          if (phone.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter mobile phone number.')));
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
                                backgroundColor: const Color(0xFF10B981),
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

  Future<void> _refreshAdminReferrals() async {
    setState(() => _isRefreshingReferrals = true);
    await _problemService.syncAdminReferralsFromApi();
    if (mounted) {
      setState(() => _isRefreshingReferrals = false);
    }
  }

  Widget _buildReferralManagementPanel() {
    final analytics = _problemService.adminReferralAnalytics;
    final allPatientRefs = _problemService.adminPatientReferrals;

    if (allPatientRefs.isEmpty && !_isRefreshingReferrals) {
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
                    colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.25),
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
                  backgroundColor: const Color(0xFF8B5CF6),
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
                    accentColor: const Color(0xFF8B5CF6),
                    icon: Icons.share_rounded,
                  ),
                  _KpiCard(
                    title: 'Pending Review',
                    value: '$pendingCount',
                    growth: 'Awaiting Doctor',
                    accentColor: const Color(0xFFF59E0B),
                    icon: Icons.hourglass_top_rounded,
                  ),
                  _KpiCard(
                    title: 'Accepted by Doctor',
                    value: '$acceptedCount',
                    growth: 'Confirmed Care',
                    accentColor: const Color(0xFF10B981),
                    icon: Icons.check_circle_rounded,
                  ),
                  _KpiCard(
                    title: 'Referrals Declined',
                    value: '$rejectedCount',
                    growth: 'Unavailable',
                    accentColor: const Color(0xFFEF4444),
                    icon: Icons.cancel_outlined,
                  ),
                  _KpiCard(
                    title: 'WhatsApp Delivered',
                    value: '${allPatientRefs.where((r) => r.whatsappStatus == 'Sent').length}',
                    growth: 'Mobile Alerts',
                    accentColor: const Color(0xFF25D366),
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
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'Search patient, doctor, location...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 16, color: AppTheme.textMuted),
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
                    final isPending = ref.status == 'Pending';
                    final isAccepted = ref.status == 'Accepted';
                    final isRejected = ref.status == 'Rejected';

                    final statusColor = isAccepted
                        ? const Color(0xFF10B981)
                        : (isRejected ? const Color(0xFFEF4444) : const Color(0xFFF59E0B));
                    final statusBg = isAccepted
                        ? const Color(0xFFDCFCE7)
                        : (isRejected ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7));
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
                                  const Icon(Icons.person_pin_rounded, size: 14, color: Color(0xFF6366F1)),
                                  const SizedBox(width: 4),
                                  Text(
                                    ref.referrerPatientName.isNotEmpty ? ref.referrerPatientName : 'Patient Referrer',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF4338CA)),
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
                                    color: const Color(0xFFEFF6FF),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFFBFDBFE)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.location_on_outlined, size: 12, color: Color(0xFF0284C7)),
                                      const SizedBox(width: 3),
                                      Text(
                                        patientLoc,
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF0369A1)),
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
                                  const Icon(Icons.medical_services_outlined, size: 13, color: Color(0xFF0D9488)),
                                  const SizedBox(width: 4),
                                  Text(
                                    ref.doctorName.isNotEmpty ? ref.doctorName : 'Dr. Specialist',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF0F172A)),
                                  ),
                                ],
                              ),
                              Text(
                                ref.doctorClinicName.isNotEmpty ? ref.doctorClinicName : 'DentaGuru Partner Clinic',
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
                                  color: const Color(0xFFF3E8FF),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  ref.requiredSpecialist,
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF7E22CE)),
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
                              const Icon(Icons.chat_bubble_outline_rounded, size: 12, color: Color(0xFF25D366)),
                              const SizedBox(width: 4),
                              Text(
                                ref.whatsappStatus == 'Sent' ? 'Delivered' : 'Queued',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF16A34A)),
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
      selectedColor: const Color(0xFF8B5CF6),
      backgroundColor: Colors.white,
      checkmarkColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? const Color(0xFF8B5CF6) : const Color(0xFFE2E8F0),
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
        ? const Color(0xFF10B981)
        : (isRejected ? const Color(0xFFEF4444) : const Color(0xFFF59E0B));
    final statusBg = isAccepted
        ? const Color(0xFFDCFCE7)
        : (isRejected ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7));

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
                  color: const Color(0xFF6366F1),
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
                  color: const Color(0xFF0284C7),
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
                  color: const Color(0xFF0D9488),
                  items: [
                    {'label': 'Doctor Name', 'value': ref.doctorName},
                    {'label': 'Specialty', 'value': ref.doctorSpecialty.isNotEmpty ? ref.doctorSpecialty : ref.requiredSpecialist},
                    {'label': 'Clinic Name', 'value': ref.doctorClinicName.isNotEmpty ? ref.doctorClinicName : 'DentaGuru Partner Clinic'},
                    if (ref.doctorLocation.isNotEmpty)
                      {'label': 'Clinic Address', 'value': ref.doctorLocation},
                  ],
                ),
                const SizedBox(height: 12),

                // Section 4: Clinical Complaint & Notifications
                _buildDetailCard(
                  title: '4. CLINICAL COMPLAINT & NOTIFICATIONS',
                  icon: Icons.notes_rounded,
                  color: const Color(0xFF8B5CF6),
                  items: [
                    {'label': 'Specialist Category', 'value': ref.requiredSpecialist},
                    {'label': 'Clinical Complaint', 'value': ref.clinicalComplaint.isNotEmpty ? ref.clinicalComplaint : 'General specialized evaluation'},
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
    final List<PatientProfile> allPatientsFromDb = _problemService.allPatients;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Patients Directory',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textDark),
              ),
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
                    const String status = 'Active';
                    final String language = patient.languages.isNotEmpty
                        ? patient.languages.join(', ')
                        : 'English';
                    return _buildPatientDataRow(patient, name, phone, city, pincode, language, email, status, const Color(0xFFDCFCE7), const Color(0xFF16A34A));
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
              const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
              const SizedBox(width: 8),
              Text('Remove $name?', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: Text('Are you sure you want to remove patient $name from the directory?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: const Text('Cancel')),
            ElevatedButton.icon(
              icon: const Icon(Icons.delete_forever_rounded, size: 16),
              label: const Text('Remove Patient', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () {
                setState(() {
                  _adminPatientsList.removeWhere((p) => p['email'] == email || p['name'] == name);
                });
                _problemService.removePatient(email);
                Navigator.of(dialogCtx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('🗑️ Patient $name removed from directory.'),
                    backgroundColor: Colors.red,
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
            decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(6)),
            child: Text(city, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
          ),
        ),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(6)),
            child: Text(pincode, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFD97706))),
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
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 18),
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
  // PANEL 3: REVENUE OVERVIEW & PAYMENTS
  // ==========================================
  Widget _buildRevenuePanel() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Revenue & Financial Analytics',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textDark),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 750) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: _buildMonthRevenueCard()),
                    const SizedBox(width: 14),
                    Expanded(flex: 2, child: _buildRevenueByServiceCard()),
                  ],
                );
              }
              return Column(
                children: [
                  _buildMonthRevenueCard(),
                  const SizedBox(height: 14),
                  _buildRevenueByServiceCard(),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMonthRevenueCard() {
    final requests = _problemService.requests;
    final totalRev = requests.length * 85;

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
          const Text('Total Monthly Revenue', style: TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Row(
            children: [
              Text('\$$totalRev', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
              const SizedBox(width: 10),
              Text(totalRev > 0 ? '+100%' : 'Live Sync', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: totalRev > 0 ? const Color(0xFF10B981) : AppTheme.textMuted)),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildBarColumn('Fri', 0.4, false),
              _buildBarColumn('Sat', 0.55, false),
              _buildBarColumn('Sun', 0.45, false),
              _buildBarColumn('Mon', 0.7, false),
              _buildBarColumn('Tue', 0.95, true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueByServiceCard() {
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
          const Text('Revenue by Service Category', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 100,
                height: 100,
                child: CustomPaint(
                  painter: _DonutChartPainter(
                    slices: const [
                      _DonutSlice(pct: 0.35, color: Color(0xFF0D9488)),
                      _DonutSlice(pct: 0.25, color: Color(0xFF0052CC)),
                      _DonutSlice(pct: 0.20, color: Color(0xFF3B82F6)),
                      _DonutSlice(pct: 0.20, color: Color(0xFF93C5FD)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  children: const [
                    _LegendRow(color: Color(0xFF0D9488), label: 'Cleaning', value: '35%'),
                    SizedBox(height: 8),
                    _LegendRow(color: Color(0xFF0052CC), label: 'Root Canal', value: '25%'),
                    SizedBox(height: 8),
                    _LegendRow(color: Color(0xFF3B82F6), label: 'Implants', value: '20%'),
                    SizedBox(height: 8),
                    _LegendRow(color: Color(0xFF93C5FD), label: 'Others', value: '20%'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
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

// Custom Painter for Smooth Area Curve Chart
class _AreaCurvePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = AppTheme.primaryBlue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          AppTheme.primaryBlue.withValues(alpha: 0.2),
          AppTheme.primaryBlue.withValues(alpha: 0.0),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = Path()
      ..moveTo(0, size.height * 0.7)
      ..cubicTo(size.width * 0.2, size.height * 0.5, size.width * 0.35, size.height * 0.8, size.width * 0.5, size.height * 0.45)
      ..cubicTo(size.width * 0.65, size.height * 0.2, size.width * 0.8, size.height * 0.5, size.width, size.height * 0.15);

    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
