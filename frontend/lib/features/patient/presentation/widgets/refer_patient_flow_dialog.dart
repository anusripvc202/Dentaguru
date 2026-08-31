import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/models/referral_model.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/services/api_service.dart';

class ReferPatientFlowDialog extends StatefulWidget {
  final VoidCallback? onViewMyReferrals;

  const ReferPatientFlowDialog({super.key, this.onViewMyReferrals});

  static Future<void> show(BuildContext context, {VoidCallback? onViewMyReferrals}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ReferPatientFlowDialog(onViewMyReferrals: onViewMyReferrals),
    );
  }

  @override
  State<ReferPatientFlowDialog> createState() => _ReferPatientFlowDialogState();
}

class _ReferPatientFlowDialogState extends State<ReferPatientFlowDialog> {
  final PatientProblemService _patientService = PatientProblemService();
  int _currentStep = 1; // 1: Select Doctor, 2: Patient Details, 3: Confirm, 4: Success

  // Step 1: Doctor Selection State
  DoctorModel? _selectedDoctor;
  String _doctorSearchQuery = '';
  String _selectedSpecialtyFilter = 'All';
  String _selectedCityFilter = 'All';
  String _selectedLanguageFilter = 'All';

  // Step 2: Referred Patient Details (Starts Clean & Empty!)
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _ageController = TextEditingController();
  final _cityController = TextEditingController();
  final _pincodeController = TextEditingController();
  final _locationController = TextEditingController();
  final _complaintController = TextEditingController();

  String _gender = 'Female';
  String _requiredSpecialist = 'Orthodontics';
  bool _isCheckingMobile = false;
  bool _isMobileRegistered = false;
  String? _matchedPatientName;

  // Step 3 & 4: Submission State
  bool _isSubmitting = false;
  String? _submissionErrorMessage;
  PatientReferral? _createdReferral;

  final List<String> _specialtyOptions = const [
    'General Dentistry',
    'Orthodontics',
    'Endodontics',
    'Periodontics',
    'Prosthodontics',
    'Oral & Maxillofacial Surgery',
    'Pediatric Dentistry',
    'Cosmetic Dentistry',
    'Dental Implants',
    'Oral Medicine & Radiology',
  ];

  final List<String> _genderOptions = const ['Female', 'Male', 'Other'];

  @override
  void initState() {
    super.initState();
    _patientService.syncAllDataFromApi();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    _ageController.dispose();
    _cityController.dispose();
    _pincodeController.dispose();
    _locationController.dispose();
    _complaintController.dispose();
    super.dispose();
  }

  Future<void> _checkMobileNumber(String value) async {
    final clean = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.length == 10) {
      setState(() => _isCheckingMobile = true);
      try {
        final res = await ApiService().checkPatientExistsByMobile(clean);
        if (mounted) {
          setState(() {
            _isCheckingMobile = false;
            _isMobileRegistered = res['exists'] == true;
            if (_isMobileRegistered && res['patient'] != null) {
              _matchedPatientName = res['patient']['name']?.toString();
            } else {
              _matchedPatientName = null;
            }
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isCheckingMobile = false);
      }
    } else {
      if (_isMobileRegistered || _matchedPatientName != null) {
        setState(() {
          _isMobileRegistered = false;
          _matchedPatientName = null;
        });
      }
    }
  }

  Future<void> _submitReferral() async {
    if (_selectedDoctor == null) return;
    setState(() {
      _isSubmitting = true;
      _submissionErrorMessage = null;
    });

    final res = await _patientService.submitPatientReferral(
      referredPatientName: _nameController.text.trim(),
      referredPatientMobile: _mobileController.text.trim(),
      referredPatientAge: _ageController.text.trim(),
      referredPatientGender: _gender,
      referredPatientCity: _cityController.text.trim(),
      referredPatientPincode: _pincodeController.text.trim(),
      referredPatientLocation: _locationController.text.trim(),
      requiredSpecialist: _requiredSpecialist,
      clinicalComplaint: _complaintController.text.trim(),
      doctorId: _selectedDoctor!.id,
    );

    if (!mounted) return;

    if (res['success'] == true) {
      final refJson = res['referral'];
      PatientReferral? ref;
      if (refJson != null) {
        try {
          ref = PatientReferral.fromJson(Map<String, dynamic>.from(refJson));
        } catch (_) {}
      }
      setState(() {
        _isSubmitting = false;
        _createdReferral = ref ?? _patientService.myCreatedPatientReferrals.firstOrNull;
        _currentStep = 4;
      });
    } else {
      setState(() {
        _isSubmitting = false;
        _submissionErrorMessage = res['message'] ?? 'Failed to submit referral. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const primaryColor = Color(0xFF0284C7);

    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header Handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 48,
            height: 5,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(10),
            ),
          ),

          // Header Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.person_add_alt_1_rounded, color: primaryColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Refer a Patient',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Connect a patient with a specialized doctor',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  color: isDark ? Colors.white70 : Colors.black54,
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Stepper Progress Indicator
          _buildStepProgressIndicator(isDark, primaryColor),

          const Divider(height: 1, thickness: 1),

          // Main Step Body
          Expanded(
            child: _buildCurrentStepContent(isDark, primaryColor),
          ),
        ],
      ),
    );
  }

  Widget _buildStepProgressIndicator(bool isDark, Color primaryColor) {
    final steps = ['Select Doctor', 'Patient Info', 'Confirm', 'Submitted'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: List.generate(steps.length, (index) {
          final stepNum = index + 1;
          final isCompleted = _currentStep > stepNum;
          final isCurrent = _currentStep == stepNum;

          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isCompleted
                              ? const Color(0xFF10B981)
                              : (isCurrent ? primaryColor : (isDark ? Colors.white12 : Colors.black12)),
                        ),
                        child: Center(
                          child: isCompleted
                              ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                              : Text(
                                  '$stepNum',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: (isCompleted || isCurrent) ? Colors.white : (isDark ? Colors.white54 : Colors.black54),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          steps[index],
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                            color: isCurrent
                                ? (isDark ? Colors.white : const Color(0xFF0F172A))
                                : (isDark ? Colors.white38 : Colors.black45),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                if (index < steps.length - 1)
                  Container(
                    width: 16,
                    height: 2,
                    color: isCompleted ? const Color(0xFF10B981) : (isDark ? Colors.white12 : Colors.black12),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCurrentStepContent(bool isDark, Color primaryColor) {
    switch (_currentStep) {
      case 1:
        return _buildStep1SelectDoctor(isDark, primaryColor);
      case 2:
        return _buildStep2PatientDetails(isDark, primaryColor);
      case 3:
        return _buildStep3ConfirmReferral(isDark, primaryColor);
      case 4:
        return _buildStep4Success(isDark, primaryColor);
      default:
        return const SizedBox.shrink();
    }
  }

  // ─────────────────────────────────────────────
  // STEP 1: SELECT DOCTOR
  // ─────────────────────────────────────────────
  Widget _buildStep1SelectDoctor(bool isDark, Color primaryColor) {
    return AnimatedBuilder(
      animation: _patientService,
      builder: (context, _) {
        final allDoctors = _patientService.allDoctors;

        // Extract available filter values
        final specialties = <String>[
          'All',
          ...allDoctors.map((d) => d.specialty).where((s) => s.isNotEmpty).toSet()
        ];
        final cities = <String>[
          'All',
          ...allDoctors.map((d) => d.city).where((c) => c.isNotEmpty).toSet()
        ];
        const languages = <String>['All', 'English', 'Hindi', 'Telugu', 'Tamil', 'Kannada'];

        // Apply filters
        final filteredDoctors = allDoctors.where((doc) {
          if (_selectedSpecialtyFilter != 'All' &&
              !doc.specialty.toLowerCase().contains(_selectedSpecialtyFilter.toLowerCase())) {
            return false;
          }
          if (_selectedCityFilter != 'All' &&
              !doc.city.toLowerCase().contains(_selectedCityFilter.toLowerCase())) {
            return false;
          }
          if (_selectedLanguageFilter != 'All' &&
              !doc.languages.any((l) => l.toLowerCase() == _selectedLanguageFilter.toLowerCase())) {
            return false;
          }
          if (_doctorSearchQuery.isNotEmpty) {
            final q = _doctorSearchQuery.toLowerCase().trim();
            final cleanDigitsQ = q.replaceAll(RegExp(r'\D'), '');
            final cleanDocPhone = doc.phone.replaceAll(RegExp(r'\D'), '');
            final matchName = doc.name.toLowerCase().contains(q);
            final matchSpec = doc.specialty.toLowerCase().contains(q);
            final matchClinic = doc.clinicName.toLowerCase().contains(q) || doc.clinicAddress.toLowerCase().contains(q);
            final matchCity = doc.city.toLowerCase().contains(q);
            final matchPincode = doc.pincode.contains(q);
            final matchPhone = (cleanDigitsQ.isNotEmpty && cleanDocPhone.contains(cleanDigitsQ)) || doc.phone.toLowerCase().contains(q);
            if (!matchName && !matchSpec && !matchClinic && !matchCity && !matchPincode && !matchPhone) return false;
          }
          return true;
        }).toList();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Select Doctor',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Select the doctor you want to refer the patient to.',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                onChanged: (val) => setState(() => _doctorSearchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Search doctor, contact number, specialty, clinic, city or pincode...',
                  hintStyle: TextStyle(fontSize: 13, color: isDark ? Colors.white38 : Colors.black38),
                  prefixIcon: Icon(Icons.search_rounded, size: 20, color: primaryColor),
                  suffixIcon: _doctorSearchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () => setState(() => _doctorSearchQuery = ''),
                        )
                      : null,
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),

            // Filter Chips Bar
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  _buildFilterDropdown(
                    label: 'Specialty',
                    currentValue: _selectedSpecialtyFilter,
                    options: specialties,
                    onChanged: (v) => setState(() => _selectedSpecialtyFilter = v ?? 'All'),
                    isDark: isDark,
                    primaryColor: primaryColor,
                  ),
                  const SizedBox(width: 8),
                  _buildFilterDropdown(
                    label: 'City',
                    currentValue: _selectedCityFilter,
                    options: cities,
                    onChanged: (v) => setState(() => _selectedCityFilter = v ?? 'All'),
                    isDark: isDark,
                    primaryColor: primaryColor,
                  ),
                  const SizedBox(width: 8),
                  _buildFilterDropdown(
                    label: 'Language',
                    currentValue: _selectedLanguageFilter,
                    options: languages,
                    onChanged: (v) => setState(() => _selectedLanguageFilter = v ?? 'All'),
                    isDark: isDark,
                    primaryColor: primaryColor,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 6),

            // Doctors List View
            Expanded(
              child: filteredDoctors.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.person_search_rounded, size: 48, color: isDark ? Colors.white24 : Colors.black26),
                          const SizedBox(height: 12),
                          Text(
                            'No matching doctors found',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Try adjusting your search or filters.',
                            style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.black38),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      itemCount: filteredDoctors.length,
                      itemBuilder: (ctx, idx) {
                        final doc = filteredDoctors[idx];
                        final isSelected = _selectedDoctor?.id == doc.id;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: isDark
                                ? (isSelected ? const Color(0xFF1E293B) : const Color(0xFF131E31))
                                : (isSelected ? const Color(0xFFF0F9FF) : Colors.white),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? primaryColor
                                  : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                              width: isSelected ? 2 : 1,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: primaryColor.withValues(alpha: 0.12),
                                      blurRadius: 10,
                                      offset: const Offset(0, 3),
                                    )
                                  ]
                                : null,
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              setState(() {
                                _selectedDoctor = doc;
                                if (_specialtyOptions.contains(doc.specialty)) {
                                  _requiredSpecialist = doc.specialty;
                                }
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Doctor Avatar
                                  Stack(
                                    children: [
                                      CircleAvatar(
                                        radius: 26,
                                        backgroundColor: primaryColor.withValues(alpha: 0.15),
                                        backgroundImage: doc.photoBytes != null ? MemoryImage(doc.photoBytes!) : null,
                                        child: doc.photoBytes == null
                                            ? Text(
                                                doc.name.isNotEmpty ? doc.name.replaceAll('Dr. ', '').substring(0, 1).toUpperCase() : 'D',
                                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryColor),
                                              )
                                            : null,
                                      ),
                                      if (isSelected)
                                        Positioned(
                                          right: 0,
                                          bottom: 0,
                                          child: Container(
                                            padding: const EdgeInsets.all(2),
                                            decoration: const BoxDecoration(
                                              color: Color(0xFF10B981),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(Icons.check, size: 12, color: Colors.white),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(width: 14),

                                  // Doctor Details
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                doc.name.startsWith('Dr.') ? doc.name : 'Dr. ${doc.name}',
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.bold,
                                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: primaryColor.withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                doc.specialty.isNotEmpty ? doc.specialty : 'Dentist',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: primaryColor,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),

                                        Row(
                                          children: [
                                            Icon(Icons.local_hospital_outlined, size: 13, color: isDark ? Colors.white60 : Colors.black54),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                doc.clinicName.isNotEmpty ? doc.clinicName : 'DentaGuru Partner Clinic',
                                                style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),

                                        if (doc.phone.isNotEmpty) ...[
                                          Row(
                                            children: [
                                              Icon(Icons.phone_outlined, size: 13, color: isDark ? Colors.white54 : Colors.black45),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: Text(
                                                  doc.phone.startsWith('+91') ? doc.phone : '+91 ${doc.phone}',
                                                  style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                        ],

                                        Row(
                                          children: [
                                            Icon(Icons.location_on_outlined, size: 13, color: isDark ? Colors.white54 : Colors.black45),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                '${doc.city.isNotEmpty ? doc.city : "City"}${doc.pincode.isNotEmpty ? " • ${doc.pincode}" : ""}',
                                                style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),

                                        if (doc.languages.isNotEmpty)
                                          Wrap(
                                            spacing: 4,
                                            children: doc.languages.take(3).map((l) => Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                l,
                                                style: TextStyle(fontSize: 10, color: isDark ? Colors.white70 : Colors.black87),
                                              ),
                                            )).toList(),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // Bottom Action Bar
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : Colors.white,
                border: Border(top: BorderSide(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0))),
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _selectedDoctor == null
                        ? null
                        : () {
                            setState(() => _currentStep = 2);
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      disabledBackgroundColor: primaryColor.withValues(alpha: 0.4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Text('Continue to Patient Details', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward_rounded, size: 18, color: Colors.white),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilterDropdown({
    required String label,
    required String currentValue,
    required List<String> options,
    required ValueChanged<String?> onChanged,
    required bool isDark,
    required Color primaryColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: currentValue != 'All'
            ? primaryColor.withValues(alpha: 0.12)
            : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: currentValue != 'All' ? primaryColor : Colors.transparent,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: options.contains(currentValue) ? currentValue : 'All',
          isDense: true,
          icon: Icon(Icons.arrow_drop_down_rounded, size: 18, color: currentValue != 'All' ? primaryColor : (isDark ? Colors.white60 : Colors.black54)),
          dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          style: TextStyle(
            fontSize: 12,
            fontWeight: currentValue != 'All' ? FontWeight.bold : FontWeight.normal,
            color: currentValue != 'All' ? primaryColor : (isDark ? Colors.white70 : Colors.black87),
          ),
          items: options.map((opt) => DropdownMenuItem(value: opt, child: Text(opt == 'All' ? '$label: All' : opt))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // STEP 2: REFERRED PATIENT DETAILS
  // ─────────────────────────────────────────────
  Widget _buildStep2PatientDetails(bool isDark, Color primaryColor) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Referred Patient Details',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Enter the details of the patient you want to refer.',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFieldLabel('Patient Name', isDark, isRequired: true),
                  TextFormField(
                    controller: _nameController,
                    decoration: _inputDecoration('Enter full name of the patient', isDark),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'Patient Name is required';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),

                  _buildFieldLabel('Mobile Number', isDark, isRequired: true),
                  TextFormField(
                    controller: _mobileController,
                    keyboardType: TextInputType.phone,
                    maxLength: 10,
                    onChanged: _checkMobileNumber,
                    decoration: _inputDecoration('10-digit mobile number', isDark).copyWith(
                      counterText: '',
                      prefixText: '+91 ',
                      prefixStyle: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.black87),
                      suffixIcon: _isCheckingMobile
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          : (_isMobileRegistered
                              ? const Padding(
                                  padding: EdgeInsets.only(right: 12),
                                  child: Icon(Icons.verified_rounded, color: Color(0xFF10B981), size: 20),
                                )
                              : null),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'Mobile number is required';
                      final clean = val.replaceAll(RegExp(r'[^0-9]'), '');
                      if (clean.length != 10) return 'Please enter a valid 10-digit mobile number';
                      return null;
                    },
                  ),
                  if (_isMobileRegistered)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF10B981), size: 14),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              _matchedPatientName != null
                                  ? 'Registered patient: $_matchedPatientName (Will link directly)'
                                  : 'Existing DentaGuru patient (Will link directly)',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF10B981), fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 14),

                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildFieldLabel('Age', isDark, isRequired: true),
                            TextFormField(
                              controller: _ageController,
                              keyboardType: TextInputType.number,
                              maxLength: 3,
                              decoration: _inputDecoration('e.g. 28', isDark).copyWith(counterText: ''),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) return 'Required';
                                final n = int.tryParse(val.trim());
                                if (n == null || n <= 0 || n > 120) return 'Invalid age';
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildFieldLabel('Gender', isDark, isRequired: true),
                            DropdownButtonFormField<String>(
                              initialValue: _gender,
                              dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                              decoration: _inputDecoration('Select', isDark),
                              items: _genderOptions
                                  .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                                  .toList(),
                              onChanged: (val) => setState(() => _gender = val ?? 'Female'),
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
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildFieldLabel('City', isDark, isRequired: true),
                            TextFormField(
                              controller: _cityController,
                              decoration: _inputDecoration('e.g. Hyderabad', isDark),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) return 'City is required';
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildFieldLabel('Pincode', isDark, isRequired: true),
                            TextFormField(
                              controller: _pincodeController,
                              keyboardType: TextInputType.number,
                              maxLength: 6,
                              decoration: _inputDecoration('6-digit', isDark).copyWith(counterText: ''),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) return 'Required';
                                if (val.trim().length != 6) return '6 digits';
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  _buildFieldLabel('Location / Landmark', isDark, isRequired: true),
                  TextFormField(
                    controller: _locationController,
                    decoration: _inputDecoration('e.g. Madhapur, near Metro Station', isDark),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'Location is required';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),

                  _buildFieldLabel('Required Specialist / Category', isDark, isRequired: true),
                  DropdownButtonFormField<String>(
                    initialValue: _specialtyOptions.contains(_requiredSpecialist) ? _requiredSpecialist : _specialtyOptions.first,
                    dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                    decoration: _inputDecoration('Select category', isDark),
                    items: _specialtyOptions
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (val) => setState(() => _requiredSpecialist = val ?? 'General Dentistry'),
                  ),
                  const SizedBox(height: 14),

                  _buildFieldLabel('Problem / Clinical Complaint', isDark, isRequired: true),
                  TextFormField(
                    controller: _complaintController,
                    maxLines: 3,
                    decoration: _inputDecoration('Describe the dental problem, pain, symptoms or reason for referral...', isDark),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'Please describe the problem or clinical complaint';
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),

        // Bottom Action Bar
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            border: Border(top: BorderSide(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0))),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                OutlinedButton(
                  onPressed: () => setState(() => _currentStep = 1),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  child: const Text('Back'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () {
                        if (_formKey.currentState?.validate() == true) {
                          setState(() => _currentStep = 3);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Text('Review & Confirm', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward_rounded, size: 18, color: Colors.white),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFieldLabel(String label, bool isDark, {bool isRequired = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white70 : const Color(0xFF334155),
          ),
          children: isRequired
              ? const [
                  TextSpan(
                    text: ' *',
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  )
                ]
              : null,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, bool isDark) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: 13, color: isDark ? Colors.white30 : Colors.black38),
      filled: true,
      fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF0284C7), width: 1.5),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // STEP 3: CONFIRM REFERRAL
  // ─────────────────────────────────────────────
  Widget _buildStep3ConfirmReferral(bool isDark, Color primaryColor) {
    final referrerPatient = _patientService.currentPatient;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Confirm Referral',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Please verify the details before submitting the referral.',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        if (_submissionErrorMessage != null)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _submissionErrorMessage!,
                    style: const TextStyle(fontSize: 13, color: Colors.red, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),

        // Summary Cards
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Column(
              children: [
                // Section 1: Referrer
                _buildSummaryCard(
                  title: '1. REFERRER (You)',
                  icon: Icons.person_pin_rounded,
                  color: const Color(0xFF6366F1),
                  isDark: isDark,
                  items: [
                    {'label': 'Name', 'value': referrerPatient.name.isNotEmpty ? referrerPatient.name : 'Logged-in Patient'},
                    {'label': 'Phone', 'value': referrerPatient.phone.isNotEmpty ? referrerPatient.phone : 'Verified Mobile'},
                    if (referrerPatient.email.isNotEmpty)
                      {'label': 'Email', 'value': referrerPatient.email},
                  ],
                ),
                const SizedBox(height: 12),

                // Section 2: Referred Patient
                _buildSummaryCard(
                  title: '2. REFERRED PATIENT',
                  icon: Icons.person_add_rounded,
                  color: const Color(0xFF0284C7),
                  isDark: isDark,
                  items: [
                    {'label': 'Patient Name', 'value': _nameController.text.trim()},
                    {'label': 'Mobile Number', 'value': '+91 ${_mobileController.text.trim()}'},
                    {'label': 'Age & Gender', 'value': '${_ageController.text.trim()} Years • $_gender'},
                    {'label': 'Location', 'value': '${_locationController.text.trim()}, ${_cityController.text.trim()} (${_pincodeController.text.trim()})'},
                    {'label': 'Specialist Category', 'value': _requiredSpecialist},
                    {'label': 'Clinical Problem', 'value': _complaintController.text.trim()},
                  ],
                ),
                const SizedBox(height: 12),

                // Section 3: Selected Doctor
                if (_selectedDoctor != null)
                  _buildSummaryCard(
                    title: '3. RECEIVING DOCTOR',
                    icon: Icons.medical_services_rounded,
                    color: const Color(0xFF10B981),
                    isDark: isDark,
                    items: [
                      {'label': 'Doctor Name', 'value': _selectedDoctor!.name.startsWith('Dr.') ? _selectedDoctor!.name : 'Dr. ${_selectedDoctor!.name}'},
                      {'label': 'Specialty', 'value': _selectedDoctor!.specialty},
                      if (_selectedDoctor!.phone.isNotEmpty)
                        {'label': 'Contact Number', 'value': _selectedDoctor!.phone.startsWith('+91') ? _selectedDoctor!.phone : '+91 ${_selectedDoctor!.phone}'},
                      {'label': 'Clinic', 'value': _selectedDoctor!.clinicName.isNotEmpty ? _selectedDoctor!.clinicName : 'DentaGuru Partner Clinic'},
                      {'label': 'City & Pincode', 'value': '${_selectedDoctor!.city.isNotEmpty ? _selectedDoctor!.city : "City"} • ${_selectedDoctor!.pincode}'},
                    ],
                  ),
              ],
            ),
          ),
        ),

        // Bottom Action Bar
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            border: Border(top: BorderSide(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0))),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                OutlinedButton(
                  onPressed: _isSubmitting ? null : () => setState(() => _currentStep = 2),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  child: const Text('Back'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submitReferral,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(Icons.check_circle_outline_rounded, size: 18, color: Colors.white),
                                SizedBox(width: 8),
                                Text('Submit Referral', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required IconData icon,
    required Color color,
    required bool isDark,
    required List<Map<String, String>> items,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, thickness: 1),
          const SizedBox(height: 10),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(
                        item['label'] ?? '',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        item['value'] ?? '',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // ─────────────────────────────────────────────
  // STEP 4: REFERRAL SUBMITTED (SUCCESS SCREEN)
  // ─────────────────────────────────────────────
  Widget _buildStep4Success(bool isDark, Color primaryColor) {
    final doctorName = _createdReferral?.doctorName ?? (_selectedDoctor != null ? (_selectedDoctor!.name.startsWith('Dr.') ? _selectedDoctor!.name : 'Dr. ${_selectedDoctor!.name}') : 'Doctor');
    final patientName = _createdReferral?.referredPatientName ?? _nameController.text.trim();
    final patientMobile = _createdReferral?.referredPatientMobile ?? _mobileController.text.trim();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        children: [
          const SizedBox(height: 8),

          // Success Circle Icon
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Icon(Icons.check_circle_rounded, size: 48, color: Color(0xFF10B981)),
            ),
          ),
          const SizedBox(height: 14),

          Text(
            'Referral Submitted Successfully!',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),

          Text(
            '$patientName has been referred to $doctorName.',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // Referral Details Summary Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
            ),
            child: Column(
              children: [
                _buildSuccessRow('Referred Patient', patientName, isDark),
                if (_locationController.text.trim().isNotEmpty || _cityController.text.trim().isNotEmpty || _pincodeController.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildSuccessRow(
                    'Location & Pincode',
                    [
                      if (_locationController.text.trim().isNotEmpty) _locationController.text.trim(),
                      if (_cityController.text.trim().isNotEmpty) _cityController.text.trim(),
                      if (_pincodeController.text.trim().isNotEmpty) '(${_pincodeController.text.trim()})',
                    ].join(', '),
                    isDark,
                  ),
                ],
                const SizedBox(height: 8),
                _buildSuccessRow('Receiving Doctor', doctorName, isDark),
                const SizedBox(height: 8),
                _buildSuccessRow('Specialty', _requiredSpecialist, isDark),
                const SizedBox(height: 8),
                _buildSuccessRow('Status', 'Pending Review', isDark, isBadge: true, badgeColor: const Color(0xFFF59E0B)),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // WhatsApp Notification Status Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF25D366).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF25D366).withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF25D366), size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'WhatsApp notification sent to the referred patient (+91 $patientMobile).',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF25D366),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Open WhatsApp Button with Detailed Doctor Information
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.chat_rounded, size: 18, color: Colors.white),
              label: Text(
                'Open WhatsApp with $patientName',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final ref = _createdReferral;
                final doc = _selectedDoctor;
                final docName = ref?.doctorName.isNotEmpty == true
                    ? ref!.doctorName
                    : (doc != null ? (doc.name.startsWith('Dr.') ? doc.name : 'Dr. ${doc.name}') : 'Doctor');
                final specialty = ref?.requiredSpecialist.isNotEmpty == true ? ref!.requiredSpecialist : (doc?.specialty ?? _requiredSpecialist);
                final qual = (doc?.qualification.isNotEmpty == true && doc!.qualification != 'BDS, MDS') ? ' (${doc.qualification})' : '';
                final clinic = ref?.doctorClinicName.isNotEmpty == true ? ref!.doctorClinicName : (doc?.clinicName ?? '');
                final locationParts = [
                  if (ref?.doctorLocation.isNotEmpty == true) ref!.doctorLocation else if (doc?.clinicAddress.isNotEmpty == true) doc!.clinicAddress,
                  if (ref?.doctorCity.isNotEmpty == true) ref!.doctorCity else if (doc?.city.isNotEmpty == true) doc!.city,
                  if (ref?.doctorPincode.isNotEmpty == true) 'PIN: ${ref!.doctorPincode}' else if (doc?.pincode.isNotEmpty == true) 'PIN: ${doc!.pincode}',
                ].where((s) => s.trim().isNotEmpty).toList();

                final docPhone = (doc?.phone.isNotEmpty == true) ? doc!.phone : '';

                final buffer = StringBuffer();
                buffer.writeln('Hi $patientName,');
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
                if (_complaintController.text.trim().isNotEmpty) {
                  buffer.writeln();
                  buffer.writeln('📋 *Clinical Reason:* ${_complaintController.text.trim()}');
                }
                buffer.writeln();
                buffer.writeln('You can reach out directly to the clinic or doctor to schedule your appointment. Wishing you the best dental care!');

                String rawPhone = patientMobile.replaceAll(RegExp(r'[^0-9]'), '');
                if (rawPhone.startsWith('0') && rawPhone.length == 11) {
                  rawPhone = '91${rawPhone.substring(1)}';
                } else if (rawPhone.length == 10) {
                  rawPhone = '91$rawPhone';
                }

                final waUrl = Uri.parse(rawPhone.isNotEmpty
                    ? 'https://wa.me/$rawPhone?text=${Uri.encodeComponent(buffer.toString())}'
                    : 'https://wa.me/?text=${Uri.encodeComponent(buffer.toString())}');
                try {
                  await launchUrl(waUrl, mode: LaunchMode.externalApplication);
                } catch (_) {}
              },
            ),
          ),
          const SizedBox(height: 10),

          // Buttons
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                if (widget.onViewMyReferrals != null) {
                  widget.onViewMyReferrals!();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('View My Referrals', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Back to Dashboard',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.black54),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildSuccessRow(String label, String value, bool isDark, {bool isBadge = false, Color badgeColor = Colors.blue}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black54),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        if (isBadge)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              value,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: badgeColor),
            ),
          )
        else
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF0F172A)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }
}
