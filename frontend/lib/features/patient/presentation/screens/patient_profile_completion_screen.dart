import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/denta_guru_logo.dart';

/// Deferred Patient Profile Completion screen.
/// Shown when a Patient clicks any service or service-related action while
/// one or more mandatory fields (Profile image, Pincode, Age, Gender) are missing.
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
  late final TextEditingController _pincodeController;
  late final TextEditingController _ageController;

  Uint8List? _photoBytes;
  String? _profileImageUrl;
  String? _selectedGender;

  bool _isSubmitting = false;
  String? _photoError;
  String? _genderError;
  String? _submitError;

  static const List<String> _genderOptions = ['Female', 'Male', 'Other'];

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
    _pincodeController = TextEditingController(text: patient.pincode.trim());
    _ageController = TextEditingController(text: patient.age.trim());
    _photoBytes = patient.photoBytes;
    _profileImageUrl = patient.profileImageUrl;
    _selectedGender = patient.hasValidGender ? patient.gender.trim() : null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pincodeController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  bool get _hasSelectedImage =>
      (_photoBytes != null && _photoBytes!.isNotEmpty) ||
      (_profileImageUrl != null && _profileImageUrl!.trim().isNotEmpty);

  Future<void> _pickImage(ImageSource source) async {
    try {
      if (PatientProfileCompletionScreen.debugPickImageOverride != null) {
        final bytes = await PatientProfileCompletionScreen.debugPickImageOverride!();
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

  Future<void> _handleSaveAndContinue() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final bool formValid = _formKey.currentState?.validate() ?? false;
    final bool hasImage = _hasSelectedImage;
    final bool hasGender = _selectedGender != null && _selectedGender!.trim().isNotEmpty;

    setState(() {
      _photoError = hasImage ? null : 'Profile image is required.';
      _genderError = hasGender ? null : 'Please select your gender.';
      _submitError = null;
    });

    if (!formValid || !hasImage || !hasGender) {
      return;
    }

    setState(() => _isSubmitting = true);

    final res = await _patientService.completePatientProfile(
      photoBytes: _photoBytes,
      profileImageUrl: _profileImageUrl,
      pincode: _pincodeController.text.trim(),
      age: _ageController.text.trim(),
      gender: _selectedGender!,
      name: _nameController.text.trim().isNotEmpty
          ? _nameController.text.trim()
          : null,
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

  @override
  Widget build(BuildContext context) {
    final targetLabel = (widget.serviceTitle ?? '').trim().isNotEmpty
        ? widget.serviceTitle!.trim()
        : 'GS HEALTH services';

    return Scaffold(
      key: const Key('patient_profile_completion_screen'),
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          key: const Key('profile_completion_back_button'),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textDark, size: 20),
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

                    // 1. Profile Image (Required)
                    _buildSectionLabel('PROFILE IMAGE *'),
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
                              child: (_photoBytes != null && _photoBytes!.isNotEmpty)
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
                                          errorBuilder: (_, __, ___) => const Icon(
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
                                      key: const Key('profile_completion_upload_photo_button'),
                                      onPressed: _isSubmitting
                                          ? null
                                          : () => _pickImage(ImageSource.gallery),
                                      icon: const Icon(Icons.photo_library_outlined, size: 16),
                                      label: Text(
                                        _hasSelectedImage ? 'Change Photo' : 'Gallery',
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
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                      ),
                                    ),
                                    if (!kIsWeb)
                                      OutlinedButton.icon(
                                        key: const Key('profile_completion_camera_photo_button'),
                                        onPressed: _isSubmitting
                                            ? null
                                            : () => _pickImage(ImageSource.camera),
                                        icon: const Icon(Icons.camera_alt_outlined, size: 16),
                                        label: const Text(
                                          'Camera',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: AppTheme.gsNavy,
                                          side: const BorderSide(color: AppTheme.gsNavy),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(10),
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

                    // Optional Name field so mobile OTP patients can add/keep their name smoothly
                    _buildSectionLabel('FULL NAME (OPTIONAL)'),
                    const SizedBox(height: 8),
                    TextFormField(
                      key: const Key('profile_completion_name_field'),
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: _inputDecoration('e.g. Riya Sharma'),
                    ),
                    const SizedBox(height: 18),

                    // 2. Pincode (Required)
                    _buildSectionLabel('PINCODE *'),
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
                        if (v.isEmpty) return 'Pincode is required';
                        if (!RegExp(r'^\d{6}$').hasMatch(v)) {
                          return 'Please enter a valid 6-digit pincode';
                        }
                        return null;
                      },
                      decoration: _inputDecoration('e.g. 500081'),
                    ),
                    const SizedBox(height: 18),

                    // 3. Age (Required)
                    _buildSectionLabel('AGE *'),
                    const SizedBox(height: 8),
                    TextFormField(
                      key: const Key('profile_completion_age_field'),
                      controller: _ageController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                      validator: (val) {
                        final v = (val ?? '').trim();
                        if (v.isEmpty) return 'Age is required';
                        final parsed = int.tryParse(v);
                        if (parsed == null || parsed < 1 || parsed > 120) {
                          return 'Please enter a valid age (1-120)';
                        }
                        return null;
                      },
                      decoration: _inputDecoration('e.g. 28'),
                    ),
                    const SizedBox(height: 18),

                    // 4. Gender (Required)
                    _buildSectionLabel('GENDER *'),
                    const SizedBox(height: 10),
                    Wrap(
                      key: const Key('profile_completion_gender_section'),
                      spacing: 10,
                      runSpacing: 10,
                      children: _genderOptions.map((g) {
                        final selected = _selectedGender?.toLowerCase() == g.toLowerCase();
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
                                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                                color: selected ? Colors.white : AppTheme.textDark,
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
                    const SizedBox(height: 28),

                    SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        key: const Key('profile_completion_submit_button'),
                        onPressed: _isSubmitting ? null : _handleSaveAndContinue,
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
