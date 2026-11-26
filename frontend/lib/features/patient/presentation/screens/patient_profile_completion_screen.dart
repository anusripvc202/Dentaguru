import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/constants/patient_profile_requirements.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/services/session_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/denta_guru_logo.dart';

/// Deferred Patient Profile Completion screen.
///
/// Renders all 9 client-specified patient profile fields:
/// 1. Profile Image (upload & preview)
/// 2. Full Name
/// 3. Mobile Number (verified & read-only)
/// 4. Address
/// 5. Pincode (6-digit Indian PIN validation)
/// 6. Preferred Language (multi-language selection)
/// 7. Age (valid range 1-120)
/// 8. Gender
/// 9. Blood Group
///
/// Mandatory vs. optional enforcement is controlled flexibly via
/// [PatientProfileRequirementsConfig]. After completion, automatically
/// continues the patient to the service they originally selected.
class PatientProfileCompletionScreen extends StatefulWidget {
  final String? serviceTitle;
  final VoidCallback? onCompleted;

  const PatientProfileCompletionScreen({
    super.key,
    this.serviceTitle,
    this.onCompleted,
  });

  /// Test hook for deterministically picking a profile image in widget tests.
  @visibleForTesting
  static Future<Uint8List?> Function()? debugPickImageOverride;

  @override
  State<PatientProfileCompletionScreen> createState() =>
      _PatientProfileCompletionScreenState();
}

class _PatientProfileCompletionScreenState
    extends State<PatientProfileCompletionScreen> {
  final PatientProblemService _patientService = PatientProblemService();
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late final TextEditingController _pincodeController;
  late final TextEditingController _ageController;

  Uint8List? _photoBytes;
  String? _profileImageUrl;
  String? _selectedGender;
  String? _selectedBloodGroup;
  late List<String> _selectedLanguages;

  bool _isSubmitting = false;
  String? _photoError;
  String? _genderError;
  String? _languageError;
  String? _bloodGroupError;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    final patient = _patientService.currentPatient;
    final cleanName = patient.name.trim();
    _nameController = TextEditingController(
      text: (cleanName.isNotEmpty && cleanName.toLowerCase() != 'patient')
          ? cleanName
          : '',
    );
    _addressController = TextEditingController(text: patient.address.trim());
    _pincodeController = TextEditingController(text: patient.pincode.trim());
    _ageController = TextEditingController(text: patient.age.trim());
    _photoBytes = patient.photoBytes;
    _profileImageUrl = patient.profileImageUrl;
    _selectedGender = patient.hasValidGender ? patient.gender.trim() : null;
    final cleanBg = patient.bloodGroup.trim();
    _selectedBloodGroup = cleanBg.isNotEmpty ? cleanBg : null;
    final initLangs = patient.languages
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    _selectedLanguages = initLangs.isNotEmpty ? initLangs : <String>['English'];
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _pincodeController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  String _resolveVerifiedMobile() {
    String raw = _patientService.currentPatient.phone.trim();
    if (raw.isEmpty) {
      raw = SessionService().currentSession?.phone?.trim() ?? '';
    }
    if (raw.isEmpty) return 'Verified mobile account';
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10) return '+91 $digits';
    if (digits.length == 12 && digits.startsWith('91')) {
      return '+91 ${digits.substring(2)}';
    }
    return raw.startsWith('+') ? raw : '+$raw';
  }

  bool get _hasSelectedImage =>
      (_photoBytes != null && _photoBytes!.isNotEmpty) ||
      (_profileImageUrl != null && _profileImageUrl!.trim().isNotEmpty);

  Future<void> _pickImage(ImageSource source) async {
    try {
      if (PatientProfileCompletionScreen.debugPickImageOverride != null) {
        final bytes =
            await PatientProfileCompletionScreen.debugPickImageOverride!();
        if (bytes != null && bytes.isNotEmpty && mounted) {
          setState(() {
            _photoBytes = bytes;
            _profileImageUrl = null;
            _photoError = null;
            _submitError = null;
          });
        }
        return;
      }

      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 512,
        imageQuality: 75,
      );
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        if (bytes.isNotEmpty && mounted) {
          setState(() {
            _photoBytes = bytes;
            _profileImageUrl = null;
            _photoError = null;
            _submitError = null;
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to select photo: $e'),
          backgroundColor: AppTheme.gsRed,
        ),
      );
    }
  }

  void _toggleLanguage(String lang) {
    if (_isSubmitting) return;
    setState(() {
      final idx = _selectedLanguages.indexWhere(
        (l) => l.toLowerCase() == lang.toLowerCase(),
      );
      if (idx != -1) {
        if (_selectedLanguages.length > 1 ||
            !PatientProfileRequirementsConfig.requirePreferredLanguage) {
          _selectedLanguages.removeAt(idx);
        }
      } else {
        _selectedLanguages.add(lang);
      }
      _languageError = null;
      _submitError = null;
    });
  }

  Future<void> _handleSaveAndContinue() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final bool formValid = _formKey.currentState?.validate() ?? false;
    final bool hasImage = _hasSelectedImage;
    final bool hasGender =
        _selectedGender != null && _selectedGender!.trim().isNotEmpty;
    final bool hasLangs = _selectedLanguages.isNotEmpty;
    final bool hasBlood =
        _selectedBloodGroup != null && _selectedBloodGroup!.trim().isNotEmpty;

    final String? photoErr =
        (PatientProfileRequirementsConfig.requireProfileImage && !hasImage)
            ? 'Profile image is required.'
            : null;
    final String? genderErr =
        (PatientProfileRequirementsConfig.requireGender && !hasGender)
            ? 'Please select your gender.'
            : null;
    final String? langErr =
        (PatientProfileRequirementsConfig.requirePreferredLanguage && !hasLangs)
            ? 'Please select at least one preferred language.'
            : null;
    final String? bloodErr =
        (PatientProfileRequirementsConfig.requireBloodGroup && !hasBlood)
            ? 'Please select your blood group.'
            : null;

    setState(() {
      _photoError = photoErr;
      _genderError = genderErr;
      _languageError = langErr;
      _bloodGroupError = bloodErr;
      _submitError = null;
    });

    if (!formValid ||
        photoErr != null ||
        genderErr != null ||
        langErr != null ||
        bloodErr != null) {
      return;
    }

    setState(() => _isSubmitting = true);

    final effectiveLangs = _selectedLanguages.isNotEmpty
        ? List<String>.from(_selectedLanguages)
        : <String>['English'];

    final res = await _patientService.completePatientProfile(
      photoBytes: _photoBytes,
      profileImageUrl: _profileImageUrl,
      pincode: _pincodeController.text.trim(),
      age: _ageController.text.trim(),
      gender: _selectedGender ?? '',
      name: _nameController.text.trim().isNotEmpty
          ? _nameController.text.trim()
          : null,
      address: _addressController.text.trim(),
      bloodGroup: _selectedBloodGroup ?? '',
      languages: effectiveLangs,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile completed! Opening your service...'),
          backgroundColor: AppTheme.gsNavy,
          duration: Duration(seconds: 2),
        ),
      );
      if (widget.onCompleted != null) {
        widget.onCompleted!();
      } else if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      }
    } else {
      final msg = res['message']?.toString() ?? 'Could not save your profile.';
      setState(() => _submitError = msg);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppTheme.gsRed,
        ),
      );
    }
  }

  String _labelWithRequirement(String title, bool required) =>
      required ? '$title *' : '$title (OPTIONAL)';

  @override
  Widget build(BuildContext context) {
    final targetLabel = (widget.serviceTitle ?? '').trim().isNotEmpty
        ? widget.serviceTitle!.trim()
        : 'GS HEALTH services';
    final verifiedMobile = _resolveVerifiedMobile();

    return Scaffold(
      key: const Key('patient_profile_completion_screen'),
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          key: const Key('profile_completion_back_button'),
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppTheme.textDark,
            size: 20,
          ),
          onPressed: _isSubmitting
              ? null
              : () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop(false);
                  }
                },
        ),
        title: const GsHealthLogo(
          height: 26,
          alignment: Alignment.centerLeft,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE2E8F0)),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          key: const Key('profile_completion_scroll_view'),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Complete your profile',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.gsNavy,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Add these required details to continue to $targetLabel.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        color: const Color(0xFF475569),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 18),

                    if (_submitError != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: const Color(0x14FE3434),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0x40FE3434)),
                        ),
                        child: Text(
                          _submitError!,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.gsRed,
                          ),
                        ),
                      ),
                    ],

                    // 1. Profile Image
                    _buildSectionLabel(
                      _labelWithRequirement(
                        'PROFILE IMAGE',
                        PatientProfileRequirementsConfig.requireProfileImage,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      key: const Key('profile_completion_image_section'),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _photoError != null
                              ? AppTheme.gsRed
                              : const Color(0xFFE2E8F0),
                          width: _photoError != null ? 1.5 : 1.0,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.gsNavy.withValues(alpha: 0.08),
                              border: Border.all(
                                color: AppTheme.gsNavy.withValues(alpha: 0.25),
                                width: 1.5,
                              ),
                            ),
                            child: ClipOval(
                              child: (_photoBytes != null &&
                                      _photoBytes!.isNotEmpty)
                                  ? Image.memory(
                                      _photoBytes!,
                                      width: 72,
                                      height: 72,
                                      fit: BoxFit.cover,
                                    )
                                  : (_profileImageUrl != null &&
                                          _profileImageUrl!.trim().isNotEmpty)
                                      ? Image.network(
                                          _profileImageUrl!,
                                          width: 72,
                                          height: 72,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              const Icon(
                                            Icons.person_outline_rounded,
                                            size: 32,
                                            color: AppTheme.gsNavy,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.add_a_photo_outlined,
                                          size: 28,
                                          color: AppTheme.gsNavy,
                                        ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _hasSelectedImage
                                      ? 'Profile photo selected'
                                      : 'Upload your profile photo',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textDark,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Helps doctors identify you during consultations.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    ElevatedButton.icon(
                                      key: const Key(
                                        'profile_completion_upload_photo_button',
                                      ),
                                      onPressed: _isSubmitting
                                          ? null
                                          : () =>
                                              _pickImage(ImageSource.gallery),
                                      icon: const Icon(
                                        Icons.photo_library_outlined,
                                        size: 16,
                                      ),
                                      label: Text(
                                        _hasSelectedImage
                                            ? 'Change Photo'
                                            : 'Gallery',
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppTheme.gsNavy,
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                      ),
                                    ),
                                    if (!kIsWeb)
                                      OutlinedButton.icon(
                                        key: const Key(
                                          'profile_completion_camera_photo_button',
                                        ),
                                        onPressed: _isSubmitting
                                            ? null
                                            : () =>
                                                _pickImage(ImageSource.camera),
                                        icon: const Icon(
                                          Icons.camera_alt_outlined,
                                          size: 16,
                                        ),
                                        label: const Text(
                                          'Camera',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: AppTheme.gsNavy,
                                          side: const BorderSide(
                                            color: AppTheme.gsNavy,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_photoError != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _photoError!,
                        key: const Key('profile_completion_photo_error'),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.gsRed,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),

                    // 2. Full Name
                    _buildSectionLabel(
                      _labelWithRequirement(
                        'FULL NAME',
                        PatientProfileRequirementsConfig.requireFullName,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      key: const Key('profile_completion_name_field'),
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      validator: (val) {
                        final v = (val ?? '').trim();
                        if (PatientProfileRequirementsConfig.requireFullName &&
                            v.isEmpty) {
                          return 'Full name is required';
                        }
                        return null;
                      },
                      decoration: _inputDecoration('Enter your full name'),
                    ),
                    const SizedBox(height: 18),

                    // 3. Verified Mobile Number (Read-only)
                    _buildSectionLabel('MOBILE NUMBER (VERIFIED)'),
                    const SizedBox(height: 8),
                    Container(
                      key: const Key('profile_completion_mobile_readonly'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.phone_android_rounded,
                            size: 18,
                            color: Color(0xFF475569),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              verifiedMobile,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF334155),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.gsNavy.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.verified_rounded,
                                  size: 13,
                                  color: AppTheme.gsNavy,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Verified',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.gsNavy,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // 4. Pincode (Required by default)
                    _buildSectionLabel(
                      _labelWithRequirement(
                        'PINCODE',
                        PatientProfileRequirementsConfig.requirePincode,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      key: const Key('profile_completion_pincode_field'),
                      controller: _pincodeController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      validator: (val) {
                        final v = (val ?? '').trim();
                        if (v.isEmpty) {
                          return PatientProfileRequirementsConfig.requirePincode
                              ? 'Pincode is required'
                              : null;
                        }
                        if (!PatientProfileRequirementsConfig.isValidPincode(
                          v,
                        )) {
                          return 'Please enter a valid 6-digit pincode';
                        }
                        return null;
                      },
                      decoration: _inputDecoration('6-digit Indian PIN code'),
                    ),
                    const SizedBox(height: 18),

                    // 5. Age (Required by default)
                    _buildSectionLabel(
                      _labelWithRequirement(
                        'AGE',
                        PatientProfileRequirementsConfig.requireAge,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      key: const Key('profile_completion_age_field'),
                      controller: _ageController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                      validator: (val) {
                        final v = (val ?? '').trim();
                        if (v.isEmpty) {
                          return PatientProfileRequirementsConfig.requireAge
                              ? 'Age is required'
                              : null;
                        }
                        if (!PatientProfileRequirementsConfig.isValidAge(v)) {
                          return 'Please enter a valid age (1-120)';
                        }
                        return null;
                      },
                      decoration: _inputDecoration('Age in years (1-120)'),
                    ),
                    const SizedBox(height: 18),

                    // 6. Gender (Required by default)
                    _buildSectionLabel(
                      _labelWithRequirement(
                        'GENDER',
                        PatientProfileRequirementsConfig.requireGender,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      key: const Key('profile_completion_gender_section'),
                      spacing: 10,
                      runSpacing: 10,
                      children: PatientProfileRequirementsConfig.genderOptions
                          .map((g) {
                        final selected =
                            _selectedGender?.toLowerCase() == g.toLowerCase();
                        return InkWell(
                          key: Key('profile_completion_gender_$g'),
                          onTap: _isSubmitting
                              ? null
                              : () {
                                  setState(() {
                                    _selectedGender = g;
                                    _genderError = null;
                                    _submitError = null;
                                  });
                                },
                          borderRadius: BorderRadius.circular(24),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              color: selected ? AppTheme.gsNavy : Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: selected
                                    ? AppTheme.gsNavy
                                    : (_genderError != null
                                        ? AppTheme.gsRed
                                        : const Color(0xFFCBD5E1)),
                                width: 1.4,
                              ),
                            ),
                            child: Text(
                              g,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                color:
                                    selected ? Colors.white : AppTheme.textDark,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    if (_genderError != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _genderError!,
                        key: const Key('profile_completion_gender_error'),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.gsRed,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),

                    // 7. Address
                    _buildSectionLabel(
                      _labelWithRequirement(
                        'ADDRESS',
                        PatientProfileRequirementsConfig.requireAddress,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      key: const Key('profile_completion_address_field'),
                      controller: _addressController,
                      textCapitalization: TextCapitalization.sentences,
                      maxLines: 2,
                      minLines: 1,
                      textInputAction: TextInputAction.done,
                      validator: (val) {
                        final v = (val ?? '').trim();
                        if (PatientProfileRequirementsConfig.requireAddress &&
                            v.isEmpty) {
                          return 'Address is required';
                        }
                        return null;
                      },
                      decoration: _inputDecoration(
                        'House / street / locality',
                      ),
                    ),
                    const SizedBox(height: 18),

                    // 8. Preferred Languages (Multi-select)
                    _buildSectionLabel(
                      _labelWithRequirement(
                        'PREFERRED LANGUAGES',
                        PatientProfileRequirementsConfig
                            .requirePreferredLanguage,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      key: const Key('profile_completion_languages_section'),
                      spacing: 8,
                      runSpacing: 8,
                      children: PatientProfileRequirementsConfig
                          .supportedLanguages
                          .map((lang) {
                        final selected = _selectedLanguages.any(
                          (l) => l.toLowerCase() == lang.toLowerCase(),
                        );
                        return InkWell(
                          key: Key('profile_completion_lang_$lang'),
                          onTap: () => _toggleLanguage(lang),
                          borderRadius: BorderRadius.circular(20),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: selected ? AppTheme.gsNavy : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: selected
                                    ? AppTheme.gsNavy
                                    : const Color(0xFFCBD5E1),
                                width: 1.2,
                              ),
                            ),
                            child: Text(
                              lang,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                color:
                                    selected ? Colors.white : AppTheme.textDark,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    if (_languageError != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _languageError!,
                        key: const Key('profile_completion_language_error'),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.gsRed,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),

                    // 9. Blood Group
                    _buildSectionLabel(
                      _labelWithRequirement(
                        'BLOOD GROUP',
                        PatientProfileRequirementsConfig.requireBloodGroup,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      key: const Key('profile_completion_blood_group_section'),
                      spacing: 8,
                      runSpacing: 8,
                      children: PatientProfileRequirementsConfig
                          .bloodGroupOptions
                          .map((bg) {
                        final selected =
                            _selectedBloodGroup?.toUpperCase() ==
                                bg.toUpperCase();
                        return InkWell(
                          key: Key('profile_completion_blood_$bg'),
                          onTap: _isSubmitting
                              ? null
                              : () {
                                  setState(() {
                                    _selectedBloodGroup = selected ? null : bg;
                                    _bloodGroupError = null;
                                    _submitError = null;
                                  });
                                },
                          borderRadius: BorderRadius.circular(20),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 15,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: selected ? AppTheme.gsNavy : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: selected
                                    ? AppTheme.gsNavy
                                    : (_bloodGroupError != null
                                        ? AppTheme.gsRed
                                        : const Color(0xFFCBD5E1)),
                                width: 1.3,
                              ),
                            ),
                            child: Text(
                              bg,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                color:
                                    selected ? Colors.white : AppTheme.textDark,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    if (_bloodGroupError != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _bloodGroupError!,
                        key: const Key('profile_completion_blood_error'),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.gsRed,
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),

                    SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        key: const Key('profile_completion_submit_button'),
                        onPressed:
                            _isSubmitting ? null : _handleSaveAndContinue,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.gsNavy,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.2,
                                ),
                              )
                            : const Text(
                                'Save & Continue',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.7,
        color: const Color(0xFF475569),
      ),
    );
  }

  InputDecoration _inputDecoration(String hintText) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(fontSize: 15, color: Color(0xFF94A3B8)),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppTheme.gsNavy, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppTheme.gsRed, width: 1.3),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppTheme.gsRed, width: 1.8),
      ),
    );
  }
}
