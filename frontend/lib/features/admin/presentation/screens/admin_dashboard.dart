import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/denta_guru_logo.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/services/api_service.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> with TickerProviderStateMixin {
  int _selectedNavIndex = 0; // 0: Dashboard, 1: Clinics, 2: Dentists, 3: Patients, 4: Appointments, 5: Revenue, 6: Reports, 7: Reviews, 8: Settings, 9: Sub-Admins
  final PatientProblemService _problemService = PatientProblemService();

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
    _problemService.syncAllDataFromApi();

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
    _problemService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  void _showAssignDoctorDialog(BuildContext context, PatientConsultationRequest req, {DoctorModel? preSelectedDoctor}) {
    int currentStep = 1; // 1: Patient Problem, 2: Select Doctor, 3: Review & Send
    DoctorModel? selectedDoctor = preSelectedDoctor ?? (_problemService.allDoctors.isNotEmpty ? _problemService.allDoctors.first : null);
    String searchKeyword = '';
    String selectedSpecialtyFilter = 'All';
    String selectedAvailabilityFilter = 'All';
    final stateFilterController = TextEditingController();
    final cityFilterController = TextEditingController();
    final pincodeFilterController = TextEditingController();
    List<DoctorModel>? remoteFilteredDoctors;
    bool isFilteringApi = false;
    final adminNotesController = TextEditingController(
      text: 'Recommended for specialized clinical evaluation and care.',
    );

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final sourceDoctors = remoteFilteredDoctors ?? _problemService.allDoctors;
            // Filter doctors based on search, specialty, availability, state, city and pincode
            final filteredDoctors = sourceDoctors.where((doc) {
              final matchesSearch = doc.name.toLowerCase().contains(searchKeyword.toLowerCase()) ||
                  doc.specialty.toLowerCase().contains(searchKeyword.toLowerCase()) ||
                  doc.clinicName.toLowerCase().contains(searchKeyword.toLowerCase());
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

            // Priority Location Sorting: Same Pincode (Tier 1) -> Nearby Pincode (Tier 2) -> Same City (Tier 3) -> Same State (Tier 5) -> Rating
            filteredDoctors.sort((a, b) {
              final tierA = a.getLocationMatchTier(req.state, req.city, req.pincode);
              final tierB = b.getLocationMatchTier(req.state, req.city, req.pincode);
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
                constraints: const BoxConstraints(maxWidth: 580, maxHeight: 680),
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
                                        Text('📌 Category: ${req.problemCategory}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryBlue)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
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
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFBFDBFE)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.my_location_rounded, size: 16, color: AppTheme.primaryBlue),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Patient Location: ${req.pincode.isNotEmpty ? 'Pin: ${req.pincode}' : ''}${req.city.isNotEmpty ? ' • ${req.city}' : ''}${req.state.isNotEmpty ? ' • ${req.state}' : ''}${req.preferredLocation.isNotEmpty ? ' (${req.preferredLocation})' : ''}',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFDBEAFE),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text('Priority Ranked', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF1D4ED8))),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Search & Location Filter Bar
                            Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    onChanged: (val) => setModalState(() => searchKeyword = val),
                                    decoration: InputDecoration(
                                      hintText: 'Search doctor / clinic...',
                                      prefixIcon: const Icon(Icons.search_rounded, size: 16, color: AppTheme.textMuted),
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  flex: 1,
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
                                  flex: 1,
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
                                  flex: 1,
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
                                  : ListView.builder(
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
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          Expanded(
                                                            child: Text(
                                                              doc.name,
                                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                                                              overflow: TextOverflow.ellipsis,
                                                              maxLines: 1,
                                                            ),
                                                          ),
                                                          const SizedBox(width: 4),
                                                          // Recommendation Badge
                                                          Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                            decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(6)),
                                                            child: Text(badgeLabel, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: badgeFg)),
                                                          ),
                                                          if (isSpecialtyMatch) ...[
                                                            const SizedBox(width: 4),
                                                            Container(
                                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                              decoration: BoxDecoration(
                                                                color: const Color(0xFFFEF3C7),
                                                                borderRadius: BorderRadius.circular(6),
                                                              ),
                                                              child: const Text('Matched Specialty', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFFB45309))),
                                                            ),
                                                          ],
                                                        ],
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        '${doc.specialty} • ${doc.qualification} (${doc.status})',
                                                        style: const TextStyle(fontSize: 11, color: AppTheme.primaryBlue),
                                                        overflow: TextOverflow.ellipsis,
                                                        maxLines: 1,
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        '🏥 ${doc.clinicName}${doc.city.isNotEmpty ? ' (${doc.city}' : ''}${doc.state.isNotEmpty ? ', ${doc.state})' : (doc.city.isNotEmpty ? ')' : '')} • 📍 Pin: ${doc.pincode} • 💰 ${doc.getFeeForCategory(req.problemCategory)} • ⭐ ${doc.rating}',
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
                                        );
                                      },
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

                              Row(
                                children: [
                                  OutlinedButton(
                                    onPressed: () => setModalState(() => currentStep = 2),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    child: const Text('Back'),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      icon: const Icon(Icons.send_rounded, size: 16),
                                      label: const Text(
                                        'Send Doctor Recommendation',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF10B981),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 13),
                                        elevation: 2,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      onPressed: () async {
                                        if (selectedDoctor == null) return;
                                        _problemService.assignDoctorToRequest(
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
                                            content: Text('📱 Doctor recommendation sent to ${req.patientName} & ${selectedDoctor?.name}!'),
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
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Logged out successfully.')),
                        );
                        context.go('/');
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
                                  onPressed: () => context.go('/'),
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
                              _buildMobileNavPill(3, 'Patients', Icons.people_outline_rounded),
                              _buildMobileNavPill(1, 'Clinics', Icons.local_hospital_outlined),
                              _buildMobileNavPill(2, 'Dentists', Icons.medical_services_outlined),
                              _buildMobileNavPill(5, 'Revenue', Icons.account_balance_wallet_outlined),
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

  Widget _buildMobileNavPill(int index, String label, IconData icon) {
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
      default:
        return _buildDashboardPanel();
    }
  }

  // ==========================================
  // PANEL: SUB-ADMIN MANAGEMENT
  // ==========================================
  Widget _buildSubAdminsPanel() {
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
              // Header
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
                      color: const Color(0xFF6366F1).withValues(alpha: 0.25),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.supervisor_account_rounded, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '🛡️ Sub-Admin Management',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${_subAdmins.length} Sub-Admin${_subAdmins.length == 1 ? '' : 's'} registered • Manage portal access roles',
                            style: const TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Top Action Bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Registered Sub-Admins',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Sub-Admins can log in to the Admin Portal with limited access',
                          style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.person_add_rounded, size: 16),
                    label: const Text('+ Add Sub-Admin', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _showRegisterSubAdminModal(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Info Banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F0FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.25)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFF6366F1)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Sub-Admins can log into the Admin Portal using the "Admin" tab with their registered email and password.',
                        style: TextStyle(fontSize: 11, color: Color(0xFF4338CA), fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Sub-Admin List or Empty State
              if (_subAdmins.isEmpty)
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
                      const Text(
                        'No Sub-Admins Created Yet',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Click "+ Add Sub-Admin" above to create a sub-admin account.\nSub-admins can log into the Admin Portal to help manage the platform.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: AppTheme.textMuted, height: 1.5),
                      ),
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
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _subAdmins.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final sa = _subAdmins[index];
                    final initials = (sa['name'] ?? 'SA')
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
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          // Avatar
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF6366F1), Color(0xFF818CF8)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                initials,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          // Info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  sa['name'] ?? 'Sub-Admin',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  sa['email'] ?? '',
                                  style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEDE9FE),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        sa['department'] ?? 'General',
                                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF6D28D9)),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if ((sa['phone'] ?? '').isNotEmpty)
                                      Text(
                                        '📞 ${sa['phone']}',
                                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Badge + Delete
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDCFCE7),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text(
                                  '✓ Active',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF16A34A)),
                                ),
                              ),
                              const SizedBox(height: 8),
                              InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => _confirmRemoveSubAdmin(context, index, sa['name'] ?? 'Sub-Admin'),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
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

  void _confirmRemoveSubAdmin(BuildContext context, int index, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Remove $name?', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        content: Text('Are you sure you want to remove $name from the sub-admin list? They will lose admin portal access.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton.icon(
            icon: const Icon(Icons.delete_forever_rounded, size: 16),
            label: const Text('Remove', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              _removeSubAdmin(index);
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('🗑️ $name removed from sub-admins.'),
                  backgroundColor: Colors.red,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showRegisterSubAdminModal(BuildContext context) {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final deptCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    bool showPassword = false;
    bool isLoading = false;

    const departments = [
      'General Administration',
      'Patient Support',
      'Clinical Operations',
      'Billing & Finance',
      'IT & Technical',
      'Marketing & Outreach',
    ];
    String selectedDept = departments.first;

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
                constraints: const BoxConstraints(maxWidth: 500, maxHeight: 660),
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
                          child: const Icon(Icons.supervisor_account_rounded, color: Color(0xFF6366F1), size: 22),
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
                                'Sub-admin can log in via Admin Portal tab',
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
                    const SizedBox(height: 16),
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
                                labelText: 'Full Name *',
                                hintText: 'e.g. Priya Sharma',
                                prefixIcon: const Icon(Icons.person_outline_rounded, size: 18),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Email
                            TextField(
                              controller: emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              decoration: InputDecoration(
                                labelText: 'Email Address *',
                                hintText: 'subadmin@dentaguru.com',
                                prefixIcon: const Icon(Icons.email_outlined, size: 18),
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
                                hintText: '+91 99999 00000',
                                prefixIcon: const Icon(Icons.phone_outlined, size: 18),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Department Dropdown
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFCBD5E1)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.business_center_outlined, size: 18, color: AppTheme.textMuted),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        value: selectedDept,
                                        isExpanded: true,
                                        hint: const Text('Select Department', style: TextStyle(fontSize: 13)),
                                        items: departments
                                            .map((d) => DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(fontSize: 13))))
                                            .toList(),
                                        onChanged: (val) {
                                          if (val != null) {
                                            setModalState(() => selectedDept = val);
                                            deptCtrl.text = val;
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Password
                            TextField(
                              controller: passwordCtrl,
                              obscureText: !showPassword,
                              decoration: InputDecoration(
                                labelText: 'Password *',
                                hintText: 'Min. 6 characters',
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
                            const SizedBox(height: 18),

                            // Register Button
                            SizedBox(
                              height: 48,
                              child: ElevatedButton.icon(
                                icon: isLoading
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.check_circle_rounded, size: 18),
                                label: Text(
                                  isLoading ? 'Creating Account...' : 'Create Sub-Admin Account',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF6366F1),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: isLoading
                                    ? null
                                    : () async {
                                        final name = nameCtrl.text.trim();
                                        final email = emailCtrl.text.trim();
                                        final password = passwordCtrl.text.trim();
                                        final phone = phoneCtrl.text.trim();

                                        if (name.isEmpty || email.isEmpty || password.isEmpty) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('⚠️ Please fill in Full Name, Email, and Password.'),
                                              backgroundColor: Color(0xFFD97706),
                                            ),
                                          );
                                          return;
                                        }

                                        if (password.length < 6) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('⚠️ Password must be at least 6 characters.'),
                                              backgroundColor: Color(0xFFD97706),
                                            ),
                                          );
                                          return;
                                        }

                                        setModalState(() => isLoading = true);

                                        try {
                                          final res = await ApiService().registerUser(
                                            name: name,
                                            email: email,
                                            password: password,
                                            phone: phone.isEmpty ? '0000000000' : phone,
                                            role: 'Sub-Admin',
                                          );

                                          setModalState(() => isLoading = false);

                                          if (!dialogCtx.mounted) return;
                                          Navigator.of(dialogCtx).pop();

                                          if (res['success'] == true) {
                                            _addSubAdmin({
                                              'name': name,
                                              'email': email,
                                              'phone': phone,
                                              'department': selectedDept,
                                            });
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text('✅ Sub-Admin "$name" created successfully! They can now log in via the Admin tab.'),
                                                backgroundColor: const Color(0xFF10B981),
                                                duration: const Duration(seconds: 4),
                                              ),
                                            );
                                          } else {
                                            _addSubAdmin({
                                              'name': name,
                                              'email': email,
                                              'phone': phone,
                                              'department': selectedDept,
                                            });
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text('⚠️ Backend notice: ${res['message'] ?? 'Account saved locally. Sync when online.'}'),
                                                backgroundColor: const Color(0xFFD97706),
                                                duration: const Duration(seconds: 4),
                                              ),
                                            );
                                          }
                                        } catch (e) {
                                          setModalState(() => isLoading = false);
                                          _addSubAdmin({
                                            'name': name,
                                            'email': email,
                                            'phone': phone,
                                            'department': selectedDept,
                                          });
                                          if (!dialogCtx.mounted) return;
                                          Navigator.of(dialogCtx).pop();
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('⚠️ Network error. Sub-Admin "$name" saved locally.'),
                                              backgroundColor: const Color(0xFFD97706),
                                            ),
                                          );
                                        }
                                      },
                              ),
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
                          hintText: 'e.g. 100 Feet Rd, Indiranagar, Bengaluru',
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
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final passwordCtrl = TextEditingController(text: 'Password123!');
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
    bool obscurePassword = true;
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
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
                              color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.person_add_alt_1_rounded, color: AppTheme.primaryBlue, size: 22),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Create New Dentist Account', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textDark)),
                                Text('Admin Direct Doctor Registration • Ready for Dentist App Login', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
                            onPressed: () => Navigator.of(dialogContext).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Doctor Name
                      TextField(
                        controller: nameCtrl,
                        decoration: InputDecoration(
                          labelText: 'Doctor Full Name *',
                          hintText: 'e.g. Dr. Jane Miller',
                          prefixIcon: const Icon(Icons.person_outline, size: 18),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Email & Phone
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              decoration: InputDecoration(
                                labelText: 'Email Address *',
                                hintText: 'e.g. jane@dentaguru.com',
                                prefixIcon: const Icon(Icons.email_outlined, size: 18),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: phoneCtrl,
                              keyboardType: TextInputType.phone,
                              decoration: InputDecoration(
                                labelText: 'Phone Number *',
                                hintText: 'e.g. +91 98765 43210',
                                prefixIcon: const Icon(Icons.phone_outlined, size: 18),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Password
                      TextField(
                        controller: passwordCtrl,
                        obscureText: obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'Account Password *',
                          hintText: 'Used for Dentist Portal sign-in',
                          prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
                          suffixIcon: IconButton(
                            icon: Icon(obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                            onPressed: () => setModalState(() => obscurePassword = !obscurePassword),
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Specialization & Qualification
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: DropdownButtonFormField<String>(
                              initialValue: selectedSpecialty,
                              decoration: InputDecoration(
                                labelText: 'Specialization',
                                prefixIcon: const Icon(Icons.medical_services_outlined, size: 18),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              items: [
                                'General Dentistry',
                                'Orthodontics',
                                'Endodontics',
                                'Periodontics',
                                'Pediatric Dentistry',
                                'Oral & Maxillofacial Surgery',
                                'Cosmetic Dentistry',
                              ].map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 12)))).toList(),
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
                                prefixIcon: const Icon(Icons.school_outlined, size: 18),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // License Number & Experience
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: licenseCtrl,
                              decoration: InputDecoration(
                                labelText: 'License Number',
                                hintText: 'e.g. DEN-88490',
                                prefixIcon: const Icon(Icons.badge_outlined, size: 18),
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
                              decoration: InputDecoration(
                                labelText: 'Years Exp.',
                                hintText: '5',
                                prefixIcon: const Icon(Icons.work_history_outlined, size: 18),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // State, City & Pincode
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: stateCtrl,
                              decoration: InputDecoration(
                                labelText: 'State',
                                hintText: 'e.g. Telangana',
                                prefixIcon: const Icon(Icons.map_outlined, size: 18),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: cityCtrl,
                              decoration: InputDecoration(
                                labelText: 'City',
                                hintText: 'e.g. Hyderabad',
                                prefixIcon: const Icon(Icons.location_city_outlined, size: 18),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: pincodeCtrl,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Pincode',
                                hintText: 'e.g. 500032',
                                prefixIcon: const Icon(Icons.pin_drop_outlined, size: 18),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Practice / Clinic Name & Fee
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: clinicCtrl,
                              decoration: InputDecoration(
                                labelText: 'Practice / Clinic Name',
                                hintText: 'e.g. Apex Care Dental',
                                prefixIcon: const Icon(Icons.storefront_outlined, size: 18),
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
                              controller: feeCtrl,
                              decoration: InputDecoration(
                                labelText: 'Fee',
                                hintText: '\$75',
                                prefixIcon: const Icon(Icons.payments_outlined, size: 18),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Clinic Address
                      TextField(
                        controller: addressCtrl,
                        decoration: InputDecoration(
                          labelText: 'Clinic Address / Location',
                          hintText: 'e.g. 123 Healthcare Blvd, Suite 400',
                          prefixIcon: const Icon(Icons.place_outlined, size: 18),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Submit Button
                      ElevatedButton.icon(
                        icon: isSubmitting
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.check_circle_rounded, size: 18),
                        label: Text(
                          isSubmitting ? 'Creating Dentist Account...' : 'Create Dentist Account',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
                                final name = nameCtrl.text.trim();
                                final email = emailCtrl.text.trim();
                                final phone = phoneCtrl.text.trim();
                                final password = passwordCtrl.text.trim();

                                if (name.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter doctor name.')));
                                  return;
                                }
                                if (email.isEmpty || !email.contains('@')) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid email address.')));
                                  return;
                                }
                                if (phone.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid phone number.')));
                                  return;
                                }
                                if (password.length < 6) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password must be at least 6 characters.')));
                                  return;
                                }

                                setModalState(() => isSubmitting = true);

                                final expYears = int.tryParse(expCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 5;
                                final doctor = _problemService.registerDoctor(
                                  name: name,
                                  email: email,
                                  phone: phone,
                                  password: password,
                                  licenseNumber: licenseCtrl.text,
                                  specialty: selectedSpecialty,
                                  qualification: qualCtrl.text,
                                  clinicName: clinicCtrl.text,
                                  experienceYears: expYears,
                                  consultationFee: feeCtrl.text,
                                  state: stateCtrl.text,
                                  city: cityCtrl.text,
                                  pincode: pincodeCtrl.text,
                                  clinicAddress: addressCtrl.text,
                                );

                                Navigator.of(dialogContext).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('🎉 Registered ${doctor.name} successfully! Dentist can now sign in using $email.'),
                                    backgroundColor: const Color(0xFF10B981),
                                    duration: const Duration(seconds: 4),
                                  ),
                                );
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
                        Text(
                          '📞 ${doc.phone} • ✉️ ${doc.email}',
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

  // ==========================================
  // PANEL 1: ADMIN DASHBOARD (RESPONSIVE & OVERFLOW FREE)
  // ==========================================
  Widget _buildDashboardPanel() {
    final requests = _problemService.requests;

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
              final crossCount = w > 750 ? 4 : (w > 420 ? 2 : 1);
              final childRatio = w > 750 ? 1.5 : (w > 420 ? 1.6 : 2.6);

              return GridView.count(
                crossAxisCount: crossCount,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: childRatio,
                children: [
                  _KpiCard(
                    title: 'Total Active Patients',
                    value: '${requests.map((r) => r.patientName).toSet().length}',
                    growth: requests.isNotEmpty ? '+100% active' : 'Live Sync',
                    accentColor: AppTheme.primaryBlue,
                    icon: Icons.people_alt_rounded,
                  ),
                  _KpiCard(
                    title: 'Pending Consultations',
                    value: '${requests.where((r) => r.status == "Pending Admin Review").length}',
                    growth: 'Requires Action',
                    accentColor: const Color(0xFFD97706),
                    icon: Icons.pending_actions_rounded,
                  ),
                  _KpiCard(
                    title: 'Assigned Specialists',
                    value: '${_problemService.allDoctors.length}',
                    growth: 'Verified Doctors',
                    accentColor: const Color(0xFF10B981),
                    icon: Icons.account_balance_wallet_rounded,
                  ),
                  _KpiCard(
                    title: 'Partner Clinics',
                    value: '${_problemService.allDoctors.map((d) => d.clinicName).toSet().length}',
                    growth: 'Network Clinics',
                    accentColor: const Color(0xFF8B5CF6),
                    icon: Icons.local_hospital_rounded,
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
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('No patient consultation requests submitted.', style: TextStyle(color: AppTheme.textMuted)),
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
                                            req.patientName,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            '📞 Phone: ${req.patientPhone.isNotEmpty ? req.patientPhone : (_problemService.currentPatient.phone.isNotEmpty ? _problemService.currentPatient.phone : 'Not Provided')}',
                                            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
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

                                if (req.assignedDoctorName != null) ...[
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
                                                'Assigned: ${req.assignedDoctorName} (${req.assignedDoctorSpecialty})',
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

                                SizedBox(
                                  width: isNarrow ? double.infinity : null,
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.mark_chat_read_rounded, size: 16),
                                    label: Text(
                                      isPending ? '🟢 Suggest Doctor & Launch WhatsApp' : '💬 Resend WhatsApp Link',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
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
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final ageCtrl = TextEditingController(text: '28');
    final locationCtrl = TextEditingController();
    final pincodeCtrl = TextEditingController();
    final passwordCtrl = TextEditingController(text: 'Password123!');

    showDialog(
      context: context,
      builder: (dialogContext) {
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
                    decoration: const InputDecoration(labelText: 'Patient Full Name', prefixIcon: Icon(Icons.person_outline_rounded)),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: emailCtrl,
                    decoration: const InputDecoration(labelText: 'Email Address', prefixIcon: Icon(Icons.email_outlined)),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: phoneCtrl,
                          decoration: const InputDecoration(labelText: 'Phone Number', prefixIcon: Icon(Icons.phone_outlined)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: ageCtrl,
                          decoration: const InputDecoration(labelText: 'Age', prefixIcon: Icon(Icons.cake_outlined)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: locationCtrl,
                          decoration: const InputDecoration(labelText: 'Location / Address', prefixIcon: Icon(Icons.location_on_outlined)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: pincodeCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Pincode', prefixIcon: Icon(Icons.pin_drop_outlined)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: passwordCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Set Account Password', prefixIcon: Icon(Icons.lock_outline)),
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
                      final email = emailCtrl.text.trim().isEmpty ? 'patient_${DateTime.now().millisecondsSinceEpoch}@dentaguru.com' : emailCtrl.text.trim();
                      final phone = phoneCtrl.text.trim().isEmpty ? '+12025550000' : phoneCtrl.text.trim();
                      final pass = passwordCtrl.text.trim().isEmpty ? 'Password123!' : passwordCtrl.text.trim();
                      final loc = locationCtrl.text.trim();
                      final pin = pincodeCtrl.text.trim();

                      await ApiService().registerUser(
                        name: name,
                        email: email,
                        password: pass,
                        phone: phone,
                        role: 'Patient',
                        location: loc,
                        pincode: pin,
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
}

  // ==========================================
  // PANEL 2: PATIENTS MANAGEMENT DATA TABLE
  // ==========================================
  Widget _buildPatientsPanel() {
    final List<PatientProfile> allPatientsFromDb = _problemService.allPatients;
    final List<Map<String, String>> patientEntries = [];

    for (final p in allPatientsFromDb) {
      final displayName = p.name.isNotEmpty
          ? p.name
          : (p.email.isNotEmpty ? p.email.split('@').first : 'Patient');

      patientEntries.add({
        'name': displayName,
        'age': p.age.isNotEmpty ? p.age : '28',
        'phone': p.phone.isNotEmpty ? p.phone : '--',
        'email': p.email,
        'lastVisit': 'Active',
        'status': 'Active',
      });
    }

    // Check logged in current patient if not present
    if (_problemService.currentPatient.name.isNotEmpty &&
        !patientEntries.any((p) => p['email'] == _problemService.currentPatient.email)) {
      patientEntries.add({
        'name': _problemService.currentPatient.name,
        'age': _problemService.currentPatient.age.isNotEmpty ? _problemService.currentPatient.age : '28',
        'phone': _problemService.currentPatient.phone,
        'email': _problemService.currentPatient.email,
        'lastVisit': 'Active',
        'status': 'Active',
      });
    }

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

          if (patientEntries.isEmpty)
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
                  const Icon(Icons.people_outline_rounded, size: 42, color: AppTheme.textMuted),
                  const SizedBox(height: 10),
                  const Text('No Registered Patients Found', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark)),
                  const SizedBox(height: 4),
                  const Text('Click "+ Add Patient" above to register a patient directly into the platform.',
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
                  columns: const [
                    DataColumn(label: Text('Name', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Age', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Phone', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Last Visit', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                  rows: patientEntries.map((patient) {
                    final String name = patient['name'] ?? 'Patient';
                    final String age = patient['age'] ?? '28';
                    final String phone = patient['phone'] ?? '--';
                    final String email = patient['email'] ?? '';
                    final String lastVisit = patient['lastVisit'] ?? 'Today';
                    final String status = patient['status'] ?? 'Active';
                    return _buildDataRow(name, age, phone, email, lastVisit, status, const Color(0xFFDCFCE7), const Color(0xFF16A34A));
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

  DataRow _buildDataRow(String name, String age, String phone, String email, String lastVisit, String status, Color bg, Color text) {
    return DataRow(
      cells: [
        DataCell(
          Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: AppTheme.softBlueCard,
                child: Text(name[0], style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
              ),
              const SizedBox(width: 8),
              Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
        ),
        DataCell(Text(age, style: const TextStyle(fontSize: 12))),
        DataCell(Text(phone, style: const TextStyle(fontSize: 12))),
        DataCell(Text(lastVisit, style: const TextStyle(fontSize: 12))),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
            child: Text(status, style: TextStyle(color: text, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
        ),
        DataCell(
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 18),
            tooltip: 'Remove Patient',
            onPressed: () => _confirmRemovePatient(context, email, name),
          ),
        ),
      ],
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: accentColor),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textDark),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            growth,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: accentColor),
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
