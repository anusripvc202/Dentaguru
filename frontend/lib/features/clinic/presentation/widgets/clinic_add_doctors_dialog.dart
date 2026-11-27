import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/models/medical_specialty_model.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/clinic_directions_helper.dart';
import '../../../auth/presentation/widgets/gs_health_registration_view.dart';

/// Unified Clinic Dashboard → Add Doctors modal with two clear options:
/// - **Option 1: Add Existing Doctor** — Search existing registered doctors by Name,
///   Mobile Number, Doctor ID, or Specialization, select one or multiple, and attach
///   them to the clinic without duplicates.
/// - **Option 2: Register New Doctor** — Complete GS Health Doctor Registration Form
///   that creates a new `DOCTOR` account, automatically associates them with the current
///   clinic (`clinicId`), and prevents duplicate accounts by offering a 1-click
///   "Attach Existing Doctor Account" option if the mobile number is already registered.
class ClinicAddDoctorsDialog extends StatefulWidget {
  final String clinicId;
  final String clinicName;
  final ClinicModel? clinic;
  final List<DoctorModel> allRegisteredDoctors;
  final Set<String> alreadyAssociatedDoctorIds;
  final VoidCallback? onDoctorsAssociated;
  final bool initialRegisterNew;

  const ClinicAddDoctorsDialog({
    super.key,
    required this.clinicId,
    required this.clinicName,
    this.clinic,
    required this.allRegisteredDoctors,
    required this.alreadyAssociatedDoctorIds,
    this.onDoctorsAssociated,
    this.initialRegisterNew = false,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String clinicId,
    required String clinicName,
    ClinicModel? clinic,
    required List<DoctorModel> allRegisteredDoctors,
    required Set<String> alreadyAssociatedDoctorIds,
    VoidCallback? onDoctorsAssociated,
    bool initialRegisterNew = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => ClinicAddDoctorsDialog(
        clinicId: clinicId,
        clinicName: clinicName,
        clinic: clinic,
        allRegisteredDoctors: allRegisteredDoctors,
        alreadyAssociatedDoctorIds: alreadyAssociatedDoctorIds,
        onDoctorsAssociated: onDoctorsAssociated,
        initialRegisterNew: initialRegisterNew,
      ),
    );
  }

  @override
  State<ClinicAddDoctorsDialog> createState() => _ClinicAddDoctorsDialogState();
}

class _ClinicAddDoctorsDialogState extends State<ClinicAddDoctorsDialog> {
  // Mode: false = Option 1 (Add Existing Doctor), true = Option 2 (Register New Doctor)
  late bool _isRegisterNewMode;

  // Option 1 state
  final TextEditingController _searchController = TextEditingController();
  String _selectedSpecialtyFilter = 'All';
  final Set<String> _selectedDoctorIds = <String>{};
  bool _isSubmitting = false;
  String? _errorMessage;

  // Option 2 (Register New Doctor) form state
  final GlobalKey<FormState> _registerFormKey = GlobalKey<FormState>();
  final TextEditingController _docNameController = TextEditingController();
  final TextEditingController _docPhoneController = TextEditingController();
  final TextEditingController _docEmailController = TextEditingController();
  final TextEditingController _docQualificationController = TextEditingController();
  final TextEditingController _docExperienceController = TextEditingController(text: '5');
  final TextEditingController _docLicenseController = TextEditingController();
  final TextEditingController _docCityController = TextEditingController();
  final TextEditingController _docStateController = TextEditingController();
  final TextEditingController _docPincodeController = TextEditingController();
  final TextEditingController _docOtpController = TextEditingController();

  late String _newDocSpecialty;
  final Set<String> _newDocLanguages = <String>{'English'};
  Uint8List? _pickedPhotoBytes;
  String? _pickedPhotoName;
  String? _photoErrorText;

  // Optional inline OTP verification state for Option 2
  bool _isSendingOtp = false;
  bool _isVerifyingOtp = false;
  bool _isOtpSent = false;
  bool _isOtpVerified = false;
  String? _verifiedPhone10;
  String? _onScreenTestOtp;
  String? _otpStatusMessage;

  // Duplicate mobile detection state for Option 2
  Map<String, dynamic>? _backendDuplicateDoctor;
  bool _backendDuplicateAlreadyInClinic = false;

  static const List<String> _kDoctorSpecialties = <String>[
    'General Dentistry',
    'Orthodontics',
    'Endodontics',
    'Periodontics',
    'Prosthodontics',
    'Oral & Maxillofacial Surgery',
    'Pediatric Dentistry',
    'General Medicine',
    'Cardiology',
    'Dermatology',
    'Neurology',
    'Orthopedics',
    'Pediatrics',
    'Gynecology',
    'ENT',
    'Ophthalmology',
  ];

  @override
  void initState() {
    super.initState();
    _isRegisterNewMode = widget.initialRegisterNew;
    _newDocSpecialty = _kDoctorSpecialties.first;
    _docQualificationController.text =
        MedicalSpecialtyModel.getDefaultQualificationForSpecialty(_newDocSpecialty);
    _docCityController.text = (widget.clinic?.city ?? '').trim();
    _docStateController.text = (widget.clinic?.state ?? '').trim();
    _docPincodeController.text = (widget.clinic?.pincode ?? '').trim();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _docNameController.dispose();
    _docPhoneController.dispose();
    _docEmailController.dispose();
    _docQualificationController.dispose();
    _docExperienceController.dispose();
    _docLicenseController.dispose();
    _docCityController.dispose();
    _docStateController.dispose();
    _docPincodeController.dispose();
    _docOtpController.dispose();
    super.dispose();
  }

  String _normalizePhone10(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 12 && digits.startsWith('91')) return digits.substring(2);
    if (digits.length == 11 && digits.startsWith('0')) return digits.substring(1);
    if (digits.length > 10) return digits.substring(digits.length - 10);
    return digits;
  }

  DoctorModel? _findLocalExistingDoctorByPhone(String rawPhone) {
    final clean10 = _normalizePhone10(rawPhone);
    if (clean10.length != 10) return null;
    for (final doc in widget.allRegisteredDoctors) {
      final doc10 = _normalizePhone10(doc.phone);
      if (doc10 == clean10) return doc;
    }
    return null;
  }

  List<String> get _availableSpecialties {
    final set = <String>{'All'};
    for (final d in widget.allRegisteredDoctors) {
      final sp = d.specialty.trim();
      if (sp.isNotEmpty) set.add(sp);
    }
    return set.toList();
  }

  bool _isAlreadyAssociated(DoctorModel d) {
    return widget.alreadyAssociatedDoctorIds.contains(d.id.trim()) ||
        (d.userId.trim().isNotEmpty &&
            widget.alreadyAssociatedDoctorIds.contains(d.userId.trim())) ||
        (widget.clinicId.trim().isNotEmpty && d.clinicId.trim() == widget.clinicId.trim());
  }

  List<DoctorModel> get _filteredDoctors {
    final kw = _searchController.text.trim().toLowerCase();
    final kwDigits = kw.replaceAll(RegExp(r'\D'), '');
    return widget.allRegisteredDoctors.where((d) {
      if (_selectedSpecialtyFilter != 'All' &&
          d.specialty.trim().toLowerCase() != _selectedSpecialtyFilter.toLowerCase()) {
        return false;
      }
      if (kw.isEmpty) return true;
      final nameMatch = d.name.toLowerCase().contains(kw);
      final idMatch = d.id.toLowerCase().contains(kw) || d.userId.toLowerCase().contains(kw);
      final phoneMatch = d.phone.toLowerCase().contains(kw) ||
          (kwDigits.length >= 3 && d.phone.replaceAll(RegExp(r'\D'), '').contains(kwDigits));
      final specMatch = d.specialty.toLowerCase().contains(kw);
      return nameMatch || idMatch || phoneMatch || specMatch;
    }).toList();
  }

  Future<void> _submitAssociation({List<String>? explicitDoctorIds}) async {
    final idsToAssociate = explicitDoctorIds ?? _selectedDoctorIds.toList();
    if (idsToAssociate.isEmpty || _isSubmitting) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final res = await ApiService().associateDoctorsToClinic(
      clinicId: widget.clinicId,
      doctorIds: idsToAssociate,
      clinicName: widget.clinicName,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (res['success'] == true) {
      for (final docId in idsToAssociate) {
        PatientProblemService().assignDoctorToClinic(
          doctorId: docId,
          clinicId: widget.clinicId,
          clinicName: widget.clinicName,
        );
      }
      widget.onDoctorsAssociated?.call();
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (res['message'] ?? '${idsToAssociate.length} doctor(s) added to ${widget.clinicName}.')
                .toString(),
          ),
          backgroundColor: AppTheme.gsNavy,
        ),
      );
    } else {
      setState(() {
        _errorMessage = (res['message'] ?? 'Unable to associate selected doctors.').toString();
      });
    }
  }

  Future<void> _pickDoctorPhoto() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      if (bytes.length > 5 * 1024 * 1024) {
        setState(() {
          _photoErrorText = 'Profile photo exceeds 5 MB limit. Please select a smaller image.';
        });
        return;
      }
      setState(() {
        _pickedPhotoBytes = bytes;
        _pickedPhotoName = picked.name;
        _photoErrorText = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _photoErrorText = 'Unable to pick image: $e';
      });
    }
  }

  Future<void> _handleSendDoctorOtp() async {
    final clean10 = _normalizePhone10(_docPhoneController.text);
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(clean10)) {
      setState(() {
        _errorMessage = 'Please enter a valid 10-digit Indian mobile number before requesting OTP.';
      });
      return;
    }

    final localDup = _findLocalExistingDoctorByPhone(clean10);
    if (localDup != null) {
      setState(() {
        _errorMessage =
            'Mobile number $clean10 already belongs to ${localDup.name}. Use "Attach Existing Doctor Account" below.';
      });
      return;
    }

    setState(() {
      _isSendingOtp = true;
      _errorMessage = null;
      _otpStatusMessage = null;
    });

    final res = await ApiService().requestOtp(
      phone: clean10,
      email: _docEmailController.text.trim(),
    );

    if (!mounted) return;
    setState(() {
      _isSendingOtp = false;
      if (res['success'] == true) {
        _isOtpSent = true;
        _isOtpVerified = false;
        _onScreenTestOtp = res['otp']?.toString();
        _otpStatusMessage = (res['message'] ?? 'OTP sent to +91 $clean10').toString();
      } else {
        _errorMessage = (res['message'] ?? 'Failed to send OTP.').toString();
      }
    });
  }

  Future<void> _handleVerifyDoctorOtp() async {
    final clean10 = _normalizePhone10(_docPhoneController.text);
    final code = _docOtpController.text.trim();
    if (code.length != 6) {
      setState(() {
        _errorMessage = 'Please enter the 6-digit verification code.';
      });
      return;
    }

    setState(() {
      _isVerifyingOtp = true;
      _errorMessage = null;
    });

    final res = await ApiService().verifyOtp(
      phone: clean10,
      email: _docEmailController.text.trim(),
      code: code,
      role: 'Dentist',
    );

    if (!mounted) return;
    setState(() {
      _isVerifyingOtp = false;
      if (res['success'] == true) {
        _isOtpVerified = true;
        _verifiedPhone10 = clean10;
        _otpStatusMessage = 'Mobile number +91 $clean10 verified.';
      } else {
        _errorMessage = (res['message'] ?? 'Invalid OTP code.').toString();
      }
    });
  }

  Future<void> _submitNewDoctorRegistration() async {
    if (_isSubmitting) return;
    setState(() {
      _errorMessage = null;
      _backendDuplicateDoctor = null;
    });

    final isValid = _registerFormKey.currentState?.validate() ?? false;
    if (!isValid) return;

    final clean10 = _normalizePhone10(_docPhoneController.text);
    final localDup = _findLocalExistingDoctorByPhone(clean10);
    if (localDup != null) {
      final alreadyInThis = _isAlreadyAssociated(localDup);
      setState(() {
        _backendDuplicateDoctor = {
          'id': localDup.id,
          'userId': localDup.userId,
          'name': localDup.name,
          'phone': localDup.phone,
          'specialty': localDup.specialty,
          'qualification': localDup.qualification,
          'clinicId': localDup.clinicId,
        };
        _backendDuplicateAlreadyInClinic = alreadyInThis;
        _errorMessage = alreadyInThis
            ? '${localDup.name} ($clean10) is already associated with ${widget.clinicName}.'
            : 'Mobile number $clean10 already belongs to registered doctor ${localDup.name}. Attach the existing account below instead of creating a duplicate.';
      });
      return;
    }

    setState(() => _isSubmitting = true);

    String? photoDataUri;
    if (_pickedPhotoBytes != null && _pickedPhotoBytes!.isNotEmpty) {
      final lower = (_pickedPhotoName ?? '').toLowerCase();
      final mime = lower.endsWith('.png')
          ? 'image/png'
          : (lower.endsWith('.webp') ? 'image/webp' : 'image/jpeg');
      photoDataUri = 'data:$mime;base64,${base64Encode(_pickedPhotoBytes!)}';
    }

    final docName = _docNameController.text.trim();
    final docEmail = _docEmailController.text.trim();
    final docQual = _docQualificationController.text.trim().isNotEmpty
        ? _docQualificationController.text.trim()
        : MedicalSpecialtyModel.getDefaultQualificationForSpecialty(_newDocSpecialty);
    final docExp = int.tryParse(_docExperienceController.text.trim()) ?? 5;
    final docLicense = _docLicenseController.text.trim();
    final docCity = _docCityController.text.trim().isNotEmpty
        ? _docCityController.text.trim()
        : (widget.clinic?.city ?? '').trim();
    final docState = _docStateController.text.trim().isNotEmpty
        ? _docStateController.text.trim()
        : (widget.clinic?.state ?? '').trim();
    final docPincode = _docPincodeController.text.trim().isNotEmpty
        ? _docPincodeController.text.trim()
        : (widget.clinic?.pincode ?? '').trim();
    final docAddress = (widget.clinic?.displayAddress ?? '').trim();

    final res = await ApiService().registerNewDoctorForClinic(
      clinicId: widget.clinicId,
      clinicName: widget.clinicName,
      name: docName,
      phone: clean10,
      email: docEmail.isNotEmpty ? docEmail : null,
      specialty: _newDocSpecialty,
      qualification: docQual,
      experienceYears: docExp,
      licenseNumber: docLicense,
      city: docCity,
      state: docState,
      pincode: docPincode,
      clinicAddress: docAddress,
      latitude: widget.clinic?.latitude,
      longitude: widget.clinic?.longitude,
      languages: _newDocLanguages.isNotEmpty ? _newDocLanguages.toList() : const ['English'],
      profilePhoto: photoDataUri,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (res['success'] == true) {
      final docMap = res['doctor'] is Map
          ? Map<String, dynamic>.from(res['doctor'] as Map)
          : <String, dynamic>{};
      final newDocId = (docMap['id'] ?? 'doc_${DateTime.now().millisecondsSinceEpoch}').toString();
      final newUserId = (docMap['userId'] ?? docMap['user_id'] ?? newDocId).toString();
      final resolvedDocName = DoctorModel.resolveFullName(
        docMap,
        fallback: docName,
      );
      final displayDocName = resolvedDocName.isNotEmpty
          ? resolvedDocName
          : DoctorModel.formatDoctorDisplayName(docName);

      PatientProblemService().registerDoctor(
        id: newDocId,
        userId: newUserId,
        name: displayDocName,
        email: docEmail,
        phone: clean10,
        specialty: _newDocSpecialty,
        qualification: docQual,
        experienceYears: docExp,
        licenseNumber: docLicense,
        clinicId: widget.clinicId,
        clinicName: widget.clinicName,
        clinicAddress: docAddress,
        city: docCity,
        state: docState,
        pincode: docPincode,
        latitude: widget.clinic?.latitude,
        longitude: widget.clinic?.longitude,
        languages: _newDocLanguages.toList(),
        photoBytes: _pickedPhotoBytes,
        profileImageUrl: docMap['profilePhoto']?.toString(),
        skipApiRegister: true,
      );

      widget.onDoctorsAssociated?.call();
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (res['message'] ?? '$displayDocName registered and associated with ${widget.clinicName}.')
                .toString(),
          ),
          backgroundColor: AppTheme.gsNavy,
        ),
      );
      return;
    }

    if (res['code'] == 'MOBILE_ALREADY_REGISTERED' || res['statusCode'] == 409) {
      final existingDocMap = res['existingDoctor'] is Map
          ? Map<String, dynamic>.from(res['existingDoctor'] as Map)
          : null;
      setState(() {
        _backendDuplicateDoctor = existingDocMap;
        _backendDuplicateAlreadyInClinic = res['alreadyInThisClinic'] == true;
        _errorMessage = (res['message'] ??
                'A doctor with this mobile number is already registered. Attach the existing account below.')
            .toString();
      });
      return;
    }

    setState(() {
      _errorMessage = (res['message'] ?? 'Unable to register doctor.').toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 740),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.gsNavy.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _isRegisterNewMode ? Icons.person_add_rounded : Icons.person_add_alt_1_rounded,
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
                        _isRegisterNewMode ? 'Register New Doctor' : 'Add Doctors to Clinic',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textDark,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _isRegisterNewMode
                            ? 'Create a new GS Health doctor account linked to ${widget.clinicName}'
                            : 'Attach existing doctors or register a new doctor for ${widget.clinicName}',
                        style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Two Clear Options Bar: Option 1 (Add Existing Doctor) | Option 2 (Register New Doctor)
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
                      key: const Key('clinic_add_doctors_tab_existing'),
                      borderRadius: BorderRadius.circular(10),
                      onTap: _isSubmitting
                          ? null
                          : () {
                              setState(() {
                                _isRegisterNewMode = false;
                                _errorMessage = null;
                              });
                            },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                        decoration: BoxDecoration(
                          color: !_isRegisterNewMode ? AppTheme.gsNavy : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.person_search_rounded,
                              size: 16,
                              color: !_isRegisterNewMode ? Colors.white : AppTheme.textDark,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Add Existing Doctor',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: !_isRegisterNewMode ? Colors.white : AppTheme.textDark,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: InkWell(
                      key: const Key('clinic_add_doctors_tab_register_new'),
                      borderRadius: BorderRadius.circular(10),
                      onTap: _isSubmitting
                          ? null
                          : () {
                              setState(() {
                                _isRegisterNewMode = true;
                                _errorMessage = null;
                              });
                            },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                        decoration: BoxDecoration(
                          color: _isRegisterNewMode ? AppTheme.gsNavy : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.person_add_alt_rounded,
                              size: 16,
                              color: _isRegisterNewMode ? Colors.white : AppTheme.textDark,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Register New Doctor',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: _isRegisterNewMode ? Colors.white : AppTheme.textDark,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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

            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.gsRed.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.gsRed.withValues(alpha: 0.3)),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.gsRed),
                ),
              ),
              const SizedBox(height: 10),
            ],

            Expanded(
              child: _isRegisterNewMode ? _buildRegisterNewDoctorView() : _buildExistingDoctorsView(),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // OPTION 1: ADD EXISTING REGISTERED DOCTOR
  // ===========================================================================
  Widget _buildExistingDoctorsView() {
    final filtered = _filteredDoctors;
    final specialties = _availableSpecialties;
    final effectiveSpecialty =
        specialties.contains(_selectedSpecialtyFilter) ? _selectedSpecialtyFilter : 'All';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 310,
              child: TextField(
                key: const Key('clinic_add_doctors_search_field'),
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search by Name, Mobile, ID, or Specialty...',
                  hintStyle: const TextStyle(fontSize: 12.5),
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            SizedBox(
              width: 190,
              child: DropdownButtonFormField<String>(
                key: const Key('clinic_add_doctors_specialty_filter'),
                initialValue: effectiveSpecialty,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Specialization',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: specialties
                    .map((sp) => DropdownMenuItem(
                          value: sp,
                          child: Text(sp, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedSpecialtyFilter = v);
                },
              ),
            ),
            OutlinedButton.icon(
              key: const Key('clinic_register_new_doctor_btn'),
              onPressed: () {
                setState(() {
                  _isRegisterNewMode = true;
                  _errorMessage = null;
                });
              },
              icon: const Icon(Icons.person_add_alt_rounded, size: 16),
              label: const Text(
                'Register New Doctor',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.gsNavy,
                side: const BorderSide(color: AppTheme.gsNavy),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        Row(
          children: [
            Flexible(
              child: Text(
                '${filtered.length} registered doctor(s) found',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textMuted,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Spacer(),
            if (_selectedDoctorIds.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.gsNavy.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_selectedDoctorIds.length} selected',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.gsNavy,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),

        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.person_search_outlined,
                          size: 40,
                          color: AppTheme.textMuted.withValues(alpha: 0.6),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'No matching registered doctors found',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Doctor not registered yet? Register a new doctor account directly under this clinic.',
                          style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              _isRegisterNewMode = true;
                              _errorMessage = null;
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.gsNavy,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.person_add_alt_rounded, size: 16),
                          label: const Text('Register New Doctor'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, idx) {
                    final doc = filtered[idx];
                    final alreadyAssoc = _isAlreadyAssociated(doc);
                    final isSelected = _selectedDoctorIds.contains(doc.id);
                    final hasBytes = doc.photoBytes != null && doc.photoBytes!.isNotEmpty;
                    final hasUrl = (doc.profileImageUrl ?? '').trim().isNotEmpty;

                    return InkWell(
                      key: Key('clinic_add_doctor_item_${doc.id}'),
                      onTap: alreadyAssoc
                          ? null
                          : () {
                              setState(() {
                                if (isSelected) {
                                  _selectedDoctorIds.remove(doc.id);
                                } else {
                                  _selectedDoctorIds.add(doc.id);
                                }
                              });
                            },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: alreadyAssoc
                              ? const Color(0xFFF8FAFC)
                              : (isSelected ? AppTheme.gsNavy.withValues(alpha: 0.06) : Colors.white),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? AppTheme.gsNavy : const Color(0xFFE2E8F0),
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Checkbox(
                              value: alreadyAssoc ? true : isSelected,
                              onChanged: alreadyAssoc
                                  ? null
                                  : (val) {
                                      setState(() {
                                        if (val == true) {
                                          _selectedDoctorIds.add(doc.id);
                                        } else {
                                          _selectedDoctorIds.remove(doc.id);
                                        }
                                      });
                                    },
                            ),
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: AppTheme.gsNavy.withValues(alpha: 0.1),
                              backgroundImage: hasBytes
                                  ? MemoryImage(doc.photoBytes!)
                                  : (hasUrl ? NetworkImage(doc.profileImageUrl!) as ImageProvider : null),
                              child: (!hasBytes && !hasUrl)
                                  ? const Icon(Icons.person_rounded, color: AppTheme.gsNavy, size: 20)
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    doc.displayFullName,
                                    key: Key('clinic_add_doctor_name_${doc.id}'),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      height: 1.25,
                                    ),
                                    softWrap: true,
                                  ),
                                  const SizedBox(height: 3),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                                        decoration: BoxDecoration(
                                          color: alreadyAssoc
                                              ? const Color(0xFF059669).withValues(alpha: 0.12)
                                              : const Color(0xFF64748B).withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          alreadyAssoc ? 'Associated' : 'Available',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w700,
                                            color: alreadyAssoc ? const Color(0xFF059669) : const Color(0xFF475569),
                                          ),
                                        ),
                                      ),
                                      Text(
                                        doc.specialty,
                                        style: const TextStyle(fontSize: 11.5, color: AppTheme.textMedium),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'ID: ${doc.id}${doc.phone.trim().isNotEmpty ? ' • Mobile: ${doc.phone}' : ''}',
                                    style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                                    softWrap: true,
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
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              key: const Key('clinic_add_doctors_confirm_btn'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.gsNavy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: (_selectedDoctorIds.isEmpty || _isSubmitting) ? null : _submitAssociation,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_rounded, size: 18),
              label: Text(
                _selectedDoctorIds.isEmpty
                    ? 'Add Selected Doctors'
                    : 'Add ${_selectedDoctorIds.length} Doctor${_selectedDoctorIds.length > 1 ? 's' : ''}',
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ===========================================================================
  // OPTION 2: REGISTER NEW DOCTOR DIRECTLY UNDER THIS CLINIC
  // ===========================================================================
  Widget _buildRegisterNewDoctorView() {
    final localDup = _findLocalExistingDoctorByPhone(_docPhoneController.text);
    final Map<String, dynamic>? duplicateInfo = _backendDuplicateDoctor ??
        (localDup != null
            ? {
                'id': localDup.id,
                'userId': localDup.userId,
                'name': localDup.name,
                'phone': localDup.phone,
                'specialty': localDup.specialty,
                'qualification': localDup.qualification,
                'clinicId': localDup.clinicId,
              }
            : null);
    final bool dupAlreadyInThisClinic = localDup != null
        ? _isAlreadyAssociated(localDup)
        : _backendDuplicateAlreadyInClinic;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Form(
            key: _registerFormKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(right: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Automatic Clinic Association Read-Only Banner
                  Container(
                    key: const Key('clinic_reg_doc_auto_clinic_banner'),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.gsNavy.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.gsNavy.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.verified_rounded, color: AppTheme.gsNavy, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Automatic Clinic Association: ${widget.clinicName}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.gsNavy,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Clinic ID: ${widget.clinicId} • Doctor will be linked automatically upon registration',
                                style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 2. Profile Photo (Optional)
                  Container(
                    key: const Key('clinic_reg_doc_photo_section'),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: AppTheme.gsNavy.withValues(alpha: 0.1),
                          backgroundImage: _pickedPhotoBytes != null ? MemoryImage(_pickedPhotoBytes!) : null,
                          child: _pickedPhotoBytes == null
                              ? const Icon(Icons.add_a_photo_outlined, color: AppTheme.gsNavy, size: 22)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _pickedPhotoBytes != null
                                    ? (_pickedPhotoName ?? 'Profile photo selected')
                                    : 'Doctor Profile Photo (Optional)',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const Text(
                                'JPG, PNG or WEBP up to 5 MB',
                                style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                              ),
                              if (_photoErrorText != null)
                                Text(
                                  _photoErrorText!,
                                  style: const TextStyle(fontSize: 11.5, color: AppTheme.gsRed),
                                ),
                            ],
                          ),
                        ),
                        OutlinedButton.icon(
                          key: const Key('clinic_reg_doc_pick_photo_btn'),
                          onPressed: _isSubmitting ? null : _pickDoctorPhoto,
                          icon: const Icon(Icons.photo_library_outlined, size: 15),
                          label: Text(_pickedPhotoBytes != null ? 'Change' : 'Upload'),
                        ),
                        if (_pickedPhotoBytes != null) ...[
                          const SizedBox(width: 6),
                          IconButton(
                            key: const Key('clinic_reg_doc_remove_photo_btn'),
                            tooltip: 'Remove Photo',
                            onPressed: _isSubmitting
                                ? null
                                : () => setState(() {
                                      _pickedPhotoBytes = null;
                                      _pickedPhotoName = null;
                                    }),
                            icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.gsRed, size: 18),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 3. Doctor Name & Mobile Number
                  LayoutBuilder(
                    builder: (context, box) {
                      final nameField = TextFormField(
                        key: const Key('clinic_reg_doc_name_field'),
                        controller: _docNameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: 'Doctor Full Name *',
                          hintText: 'e.g. Dr. Riya Kumar Sharma',
                          prefixIcon: const Icon(Icons.person_outline_rounded, size: 18),
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (val) =>
                            (val == null || val.trim().isEmpty) ? 'Please enter doctor full name' : null,
                      );

                      final phoneField = TextFormField(
                        key: const Key('clinic_reg_doc_phone_field'),
                        controller: _docPhoneController,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        onChanged: (_) {
                          setState(() {
                            _backendDuplicateDoctor = null;
                            if (_verifiedPhone10 != _normalizePhone10(_docPhoneController.text)) {
                              _isOtpVerified = false;
                            }
                          });
                        },
                        decoration: InputDecoration(
                          labelText: 'Mobile Number (+91) *',
                          hintText: '10-digit mobile number',
                          prefixIcon: const Icon(Icons.phone_android_rounded, size: 18),
                          suffixIcon: TextButton(
                            key: const Key('clinic_reg_doc_send_otp_btn'),
                            onPressed: (_isSendingOtp || _isSubmitting) ? null : _handleSendDoctorOtp,
                            child: Text(
                              _isOtpVerified
                                  ? 'Verified ✓'
                                  : (_isSendingOtp ? 'Sending...' : (_isOtpSent ? 'Resend OTP' : 'Send OTP')),
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: _isOtpVerified ? const Color(0xFF059669) : AppTheme.gsNavy,
                              ),
                            ),
                          ),
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (val) {
                          final clean = _normalizePhone10(val ?? '');
                          if (clean.isEmpty) return 'Please enter mobile number';
                          if (!RegExp(r'^[6-9]\d{9}$').hasMatch(clean)) {
                            return 'Enter valid 10-digit Indian mobile number';
                          }
                          return null;
                        },
                      );

                      if (box.maxWidth < 500) {
                        return Column(
                          children: [
                            nameField,
                            const SizedBox(height: 12),
                            phoneField,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: nameField),
                          const SizedBox(width: 12),
                          Expanded(child: phoneField),
                        ],
                      );
                    },
                  ),

                  // Inline OTP Verification Bar (when Send OTP was tapped)
                  if (_isOtpSent && !_isOtpVerified) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_onScreenTestOtp != null && _onScreenTestOtp!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  const Icon(Icons.pin_outlined, size: 16, color: AppTheme.gsNavy),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Verification code: $_onScreenTestOtp',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.gsNavy,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      _docOtpController.text = _onScreenTestOtp!;
                                      _handleVerifyDoctorOtp();
                                    },
                                    child: const Text('Fill & Verify'),
                                  ),
                                ],
                              ),
                            ),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  key: const Key('clinic_reg_doc_otp_field'),
                                  controller: _docOtpController,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(6),
                                  ],
                                  decoration: InputDecoration(
                                    hintText: 'Enter 6-digit OTP',
                                    isDense: true,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                key: const Key('clinic_reg_doc_verify_otp_btn'),
                                onPressed: _isVerifyingOtp ? null : _handleVerifyDoctorOtp,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.gsNavy,
                                  foregroundColor: Colors.white,
                                ),
                                child: Text(_isVerifyingOtp ? 'Verifying...' : 'Verify OTP'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_otpStatusMessage != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _otpStatusMessage!,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF059669),
                      ),
                    ),
                  ],

                  // Duplicate Mobile Number Detection Card ("Attach Existing Doctor Account Instead")
                  if (duplicateInfo != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      key: const Key('clinic_reg_doc_duplicate_mobile_card'),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFF59E0B)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  dupAlreadyInThisClinic
                                      ? 'Doctor Already Associated With ${widget.clinicName}'
                                      : 'Doctor Already Registered in GS Health',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    color: Color(0xFF92400E),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${duplicateInfo['name']} (${duplicateInfo['specialty'] ?? 'Specialist'}) • ID: ${duplicateInfo['id']} • Mobile: ${duplicateInfo['phone']}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF78350F)),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            dupAlreadyInThisClinic
                                ? 'This doctor account is already linked to ${widget.clinicName}. Duplicate accounts are prevented.'
                                : 'To prevent duplicate doctor accounts, attach this existing doctor directly to ${widget.clinicName} instead of creating a new account.',
                            style: const TextStyle(fontSize: 11.5, color: Color(0xFF92400E)),
                          ),
                          if (!dupAlreadyInThisClinic) ...[
                            const SizedBox(height: 10),
                            ElevatedButton.icon(
                              key: const Key('clinic_reg_doc_attach_existing_btn'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.gsNavy,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: _isSubmitting
                                  ? null
                                  : () => _submitAssociation(
                                        explicitDoctorIds: [(duplicateInfo['id'] ?? '').toString()],
                                      ),
                              icon: const Icon(Icons.link_rounded, size: 16),
                              label: Text('Attach ${duplicateInfo['name']} to ${widget.clinicName}'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),

                  // 4. Email & Medical Registration / License Number
                  LayoutBuilder(
                    builder: (context, box) {
                      final emailField = TextFormField(
                        key: const Key('clinic_reg_doc_email_field'),
                        controller: _docEmailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: 'Email Address (Optional)',
                          hintText: 'doctor@gshealth.in',
                          prefixIcon: const Icon(Icons.email_outlined, size: 18),
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (val) {
                          final v = (val ?? '').trim();
                          if (v.isEmpty) return null;
                          if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) {
                            return 'Enter a valid email address';
                          }
                          return null;
                        },
                      );

                      final licenseField = TextFormField(
                        key: const Key('clinic_reg_doc_license_field'),
                        controller: _docLicenseController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          labelText: 'Medical Registration Number *',
                          hintText: 'e.g. MCI-2026-1045 / DCI-8821',
                          prefixIcon: const Icon(Icons.badge_outlined, size: 18),
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (val) => (val == null || val.trim().isEmpty)
                            ? 'Please enter medical registration number'
                            : null,
                      );

                      if (box.maxWidth < 500) {
                        return Column(
                          children: [
                            emailField,
                            const SizedBox(height: 12),
                            licenseField,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: emailField),
                          const SizedBox(width: 12),
                          Expanded(child: licenseField),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),

                  // 5. Specialization, Qualification & Experience (Years)
                  DropdownButtonFormField<String>(
                    key: const Key('clinic_reg_doc_specialty_field'),
                    initialValue: _kDoctorSpecialties.contains(_newDocSpecialty)
                        ? _newDocSpecialty
                        : _kDoctorSpecialties.first,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Specialization *',
                      prefixIcon: const Icon(Icons.medical_services_outlined, size: 18),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: _kDoctorSpecialties
                        .map((sp) => DropdownMenuItem(
                              value: sp,
                              child: Text(sp, overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _newDocSpecialty = val;
                          if (_docQualificationController.text.trim().isEmpty) {
                            _docQualificationController.text =
                                MedicalSpecialtyModel.getDefaultQualificationForSpecialty(val);
                          }
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),

                  LayoutBuilder(
                    builder: (context, box) {
                      final qualField = TextFormField(
                        key: const Key('clinic_reg_doc_qualification_field'),
                        controller: _docQualificationController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          labelText: 'Qualification *',
                          hintText: 'e.g. BDS, MDS / MBBS, MD',
                          prefixIcon: const Icon(Icons.school_outlined, size: 18),
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (val) =>
                            (val == null || val.trim().isEmpty) ? 'Please enter qualification' : null,
                      );

                      final expField = TextFormField(
                        key: const Key('clinic_reg_doc_experience_field'),
                        controller: _docExperienceController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(2),
                        ],
                        decoration: InputDecoration(
                          labelText: 'Experience (Years) *',
                          hintText: 'e.g. 6',
                          prefixIcon: const Icon(Icons.work_history_outlined, size: 18),
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (val) {
                          final v = (val ?? '').trim();
                          if (v.isEmpty) return 'Enter experience years';
                          final yrs = int.tryParse(v);
                          if (yrs == null || yrs < 0 || yrs > 70) {
                            return 'Enter valid years (0-70)';
                          }
                          return null;
                        },
                      );

                      if (box.maxWidth < 500) {
                        return Column(
                          children: [
                            qualField,
                            const SizedBox(height: 12),
                            expField,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3, child: qualField),
                          const SizedBox(width: 12),
                          Expanded(flex: 2, child: expField),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),

                  // 6. City, State & Pincode (pre-filled from clinic, editable)
                  LayoutBuilder(
                    builder: (context, box) {
                      final cityField = TextFormField(
                        key: const Key('clinic_reg_doc_city_field'),
                        controller: _docCityController,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: 'City *',
                          hintText: 'e.g. Mumbai',
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (val) =>
                            (val == null || val.trim().isEmpty) ? 'Please enter city' : null,
                      );

                      final stateField = TextFormField(
                        key: const Key('clinic_reg_doc_state_field'),
                        controller: _docStateController,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: 'State',
                          hintText: 'e.g. Maharashtra',
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      );

                      final pincodeField = TextFormField(
                        key: const Key('clinic_reg_doc_pincode_field'),
                        controller: _docPincodeController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        decoration: InputDecoration(
                          labelText: 'Pincode',
                          hintText: '6-digit pincode',
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (val) {
                          final v = (val ?? '').trim();
                          if (v.isEmpty) return null;
                          if (!ClinicDirectionsHelper.isValidPincode(v)) {
                            return 'Enter 6-digit pincode';
                          }
                          return null;
                        },
                      );

                      if (box.maxWidth < 500) {
                        return Column(
                          children: [
                            cityField,
                            const SizedBox(height: 12),
                            stateField,
                            const SizedBox(height: 12),
                            pincodeField,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: cityField),
                          const SizedBox(width: 10),
                          Expanded(child: stateField),
                          const SizedBox(width: 10),
                          Expanded(child: pincodeField),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 14),

                  // 7. Consultation Languages Known
                  const Text(
                    'Consultation Languages Known',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.textDark),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    key: const Key('clinic_reg_doc_languages_wrap'),
                    spacing: 6,
                    runSpacing: 6,
                    children: kGsHealthLanguages.map((lang) {
                      final selected = _newDocLanguages.contains(lang);
                      return FilterChip(
                        label: Text(lang, style: const TextStyle(fontSize: 11.5)),
                        selected: selected,
                        selectedColor: AppTheme.gsNavy.withValues(alpha: 0.14),
                        checkmarkColor: AppTheme.gsNavy,
                        onSelected: (val) {
                          setState(() {
                            if (val) {
                              _newDocLanguages.add(lang);
                            } else if (_newDocLanguages.length > 1) {
                              _newDocLanguages.remove(lang);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              key: const Key('clinic_reg_doc_cancel_btn'),
              onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              key: const Key('clinic_reg_doc_submit_btn'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.gsNavy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _isSubmitting ? null : _submitNewDoctorRegistration,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: const Text('Register & Associate Doctor'),
            ),
          ],
        ),
      ],
    );
  }
}
