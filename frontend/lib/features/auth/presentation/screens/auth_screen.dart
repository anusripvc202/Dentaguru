import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/models/medical_specialty_model.dart';
import '../../../../core/widgets/denta_guru_logo.dart';
import '../../../../core/widgets/gs_health_hero_banner.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/services/session_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/utils/clinic_directions_helper.dart';
import '../../../../core/widgets/map_location_picker_dialog.dart';
import '../widgets/gs_health_registration_view.dart';
export '../widgets/gs_health_registration_view.dart' show UserRole;

class _IndianMobileInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    String normalized = digits;
    if (digits.length == 14 && digits.startsWith('0091')) {
      normalized = digits.substring(4);
    } else if (digits.length == 13 && digits.startsWith('910')) {
      normalized = digits.substring(3);
    } else if (digits.length == 12 && digits.startsWith('91')) {
      normalized = digits.substring(2);
    } else if (digits.length == 11 && digits.startsWith('0')) {
      normalized = digits.substring(1);
    } else if (digits.length > 10) {
      normalized = digits.substring(0, 10);
    }
    return TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
    );
  }
}

class AuthScreen extends StatefulWidget {
  final String? initialRole; // 'Patient', 'Dentist', 'Clinic', 'Admin'
  final int initialTab; // 0 for Register, 1 for Sign In
  final bool? allowAdminRole;
  final String? initialVerifiedPhone;

  const AuthScreen({
    super.key,
    this.initialRole,
    this.initialTab = 1,
    this.allowAdminRole,
    this.initialVerifiedPhone,
  });

  /// Deterministic image picker hook for widget/integration tests.
  @visibleForTesting
  static Future<({Uint8List bytes, String name})?> Function(ImageSource source)?
      debugPickRegistrationImageOverride;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late UserRole _selectedRole;
  late bool _isAdminMode;

  // Controllers for Sign In
  final _loginFormKey = GlobalKey<FormState>();
  final _loginEmailController = TextEditingController();
  bool _isLoggingIn = false;

  // Login OTP & Stage Controller
  bool _isLoginOtpSent = false;
  bool _isSendingLoginCode = false;
  bool _isVerifyingLoginCode = false;
  String? _loginOtpErrorMessage;
  String? _currentLoginOtp;
  late final List<TextEditingController> _otpDigitControllers;
  late final List<FocusNode> _otpDigitFocusNodes;
  Timer? _resendTimer;
  int _resendCountdown = 30;
  bool _canResendOtp = false;
  final _registerFormKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isRegistering = false;

  // Common & Location Fields
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _pincodeController = TextEditingController();
  final _locationController = TextEditingController();
  double? _selectedLatitude;
  double? _selectedLongitude;
  String? _selectedMapLocationName;
  String? _mapLocationError;
  String? _selectedClinicId;

  // Role-Specific Fields - Patient
  final _ageController = TextEditingController();
  final _emergencyContactController = TextEditingController();
  final _referralCodeController = TextEditingController();
  String? _selectedGender;
  String? _selectedBloodGroup;

  // Role-Specific Fields - Dentist / Doctor
  final _licenseNoController = TextEditingController();
  final _clinicNameController = TextEditingController();
  final _experienceController = TextEditingController();
  final _qualificationController = TextEditingController();
  final _clinicAddressController = TextEditingController();
  String? _selectedSpecialty = 'General Medicine';

  // Role-Specific Fields - Sub-Admin / Admin
  final _adminEmployeeIdController = TextEditingController();
  final _adminDeptController = TextEditingController();
  String _selectedAdminRoleType = 'Admin';

  // Preferred Languages multi-select state (defaults to ['English'])
  final Set<String> _selectedLanguages = <String>{'English'};

  void _toggleLanguage(String language) {
    setState(() {
      if (_selectedLanguages.contains(language)) {
        if (_selectedLanguages.length > 1) {
          _selectedLanguages.remove(language);
        }
      } else {
        _selectedLanguages.add(language);
      }
    });
  }

  // Profile Image Picker Bytes
  Uint8List? _pickedImageBytes;
  String? _pickedImageName;
  String? _registrationImageError;

  // OTP Verification States for Registration Flow
  bool _isOtpVerified = false;
  bool _isOtpSent = false;
  bool _isSendingOtp = false;
  bool _isVerifyingOtp = false;
  final _otpController = TextEditingController();
  String? _otpErrorMessage;
  String? _currentRegistrationOtp;
  String? _verifiedPhone;
  String? _verifiedEmail;

  String _normalizePhone(String raw) {
    final digits = raw.trim().replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 14 && digits.startsWith('0091')) {
      return digits.substring(4);
    }
    if (digits.length == 13 && digits.startsWith('910')) {
      return digits.substring(3);
    }
    if (digits.length == 12 && digits.startsWith('91')) {
      return digits.substring(2);
    }
    if (digits.length == 11 && digits.startsWith('0')) {
      return digits.substring(1);
    }
    return digits;
  }

  bool _isValidMobilePhone(String raw) {
    final normalized = _normalizePhone(raw);
    return normalized.length == 10 && RegExp(r'^\d{10}$').hasMatch(normalized);
  }

  void _onContactDetailsChanged() {
    final currentPhone = _normalizePhone(_phoneController.text);
    final currentEmail = _emailController.text.trim().toLowerCase();
    final phoneChanged = _verifiedPhone != null && currentPhone != _verifiedPhone;
    final emailChanged = _verifiedEmail != null && currentEmail != _verifiedEmail;

    if ((_isOtpVerified || _isOtpSent) && (phoneChanged || emailChanged)) {
      setState(() {
        _isOtpVerified = false;
        _isOtpSent = false;
        _otpErrorMessage = null;
        _verifiedPhone = null;
        _verifiedEmail = null;
        _otpController.clear();
      });
    }
  }

  @override
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: widget.initialTab);
    _tabController.addListener(() {
      setState(() {});
    });
    _otpDigitControllers = List.generate(6, (_) => TextEditingController());
    _otpDigitFocusNodes = List.generate(6, (_) => FocusNode());

    final rawInitialVerified = widget.initialVerifiedPhone;
    if (rawInitialVerified != null && rawInitialVerified.trim().isNotEmpty) {
      final normalizedVerified = _normalizePhone(rawInitialVerified);
      if (normalizedVerified.length == 10) {
        _phoneController.text = normalizedVerified;
        _verifiedPhone = normalizedVerified;
        _isOtpVerified = true;
        _isOtpSent = true;
      }
    }

    _phoneController.addListener(_onContactDetailsChanged);
    _emailController.addListener(_onContactDetailsChanged);

    // Auto-populate referral code if opened with ?ref=... parameter
    try {
      final refParam = Uri.base.queryParameters['ref'];
      if (refParam != null && refParam.trim().isNotEmpty) {
        _referralCodeController.text = refParam.trim().toUpperCase();
      }
    } catch (_) {}

    // Initialize selected role from widget param or default to Patient
    final roleStr = (widget.initialRole ?? '').toLowerCase();
    _isAdminMode = widget.allowAdminRole == true || roleStr == 'admin' || roleStr == 'sub-admin' || roleStr == 'subadmin';

    if (_isAdminMode) {
      _selectedRole = UserRole.admin;
      _selectedAdminRoleType = (roleStr == 'sub-admin' || roleStr == 'subadmin') ? 'Sub-Admin' : 'Admin';
    } else if (roleStr == 'dentist' || roleStr == 'doctor') {
      _selectedRole = UserRole.dentist;
    } else if (roleStr == 'clinic') {
      _selectedRole = UserRole.clinic;
    } else {
      _selectedRole = UserRole.patient;
    }
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _phoneController.removeListener(_onContactDetailsChanged);
    _emailController.removeListener(_onContactDetailsChanged);
    _tabController.dispose();
    _loginEmailController.dispose();
    for (final c in _otpDigitControllers) {
      c.dispose();
    }
    for (final n in _otpDigitFocusNodes) {
      n.dispose();
    }
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _ageController.dispose();
    _emergencyContactController.dispose();
    _referralCodeController.dispose();
    _licenseNoController.dispose();
    _clinicNameController.dispose();
    _experienceController.dispose();
    _qualificationController.dispose();
    _clinicAddressController.dispose();
    _adminEmployeeIdController.dispose();
    _adminDeptController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _pincodeController.dispose();
    _locationController.dispose();
    _otpController.dispose();
    super.dispose();
  }
  String get _targetRoute {
    switch (_selectedRole) {
      case UserRole.patient:
        return '/patient';
      case UserRole.dentist:
        return '/dentist';
      case UserRole.clinic:
        return '/clinic';
      case UserRole.admin:
        return _selectedAdminRoleType == 'Sub-Admin' ? '/sub-admin' : '/admin';
    }
  }

  static const int _maxProfileImageBytes = 5 * 1024 * 1024; // 5 MB

  String _resolveImageMimeType(String? fileName) {
    final lower = (fileName ?? '').trim().toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/png';
  }

  Future<void> _pickRegistrationImage(ImageSource source) async {
    try {
      Uint8List? bytes;
      String? fileName;

      if (AuthScreen.debugPickRegistrationImageOverride != null) {
        final picked = await AuthScreen.debugPickRegistrationImageOverride!(source);
        if (picked == null) return;
        bytes = picked.bytes;
        fileName = picked.name;
      } else {
        final ImagePicker picker = ImagePicker();
        final XFile? image = await picker.pickImage(
          source: source,
          imageQuality: 85,
          maxWidth: 800,
        );
        if (image == null) return;
        bytes = await image.readAsBytes();
        fileName = image.name;
      }

      if (!mounted) return;
      if (bytes.isEmpty) {
        setState(() {
          _registrationImageError = 'Selected image is empty. Please choose another photo.';
        });
        return;
      }
      if (bytes.length > _maxProfileImageBytes) {
        setState(() {
          _registrationImageError = 'Image exceeds the 5 MB size limit. Please select a smaller photo.';
        });
        return;
      }

      setState(() {
        _pickedImageBytes = bytes;
        _pickedImageName = fileName;
        _registrationImageError = null;
      });
    } catch (e) {
      debugPrint('Error picking registration photo: $e');
      if (!mounted) return;
      final msg = 'Unable to select profile image. Please try again.';
      setState(() => _registrationImageError = msg);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppTheme.gsRed),
      );
    }
  }

  void _removeRegistrationImage() {
    setState(() {
      _pickedImageBytes = null;
      _pickedImageName = null;
      _registrationImageError = null;
    });
  }

  String _maskPhone(String raw) {
    final d = _normalizePhone(raw);
    if (d.length == 10) {
      return '${d.substring(0, 5)} *****';
    }
    return d;
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() {
      _resendCountdown = 30;
      _canResendOtp = false;
    });
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCountdown > 1) {
        setState(() {
          _resendCountdown--;
        });
      } else {
        timer.cancel();
        setState(() {
          _resendCountdown = 0;
          _canResendOtp = true;
        });
      }
    });
  }

  String _getEnteredOtp() {
    return _otpDigitControllers.map((c) => c.text.trim()).join();
  }

  void _handleOtpDigitChange(String val, int index) {
    if (val.length > 1) {
      final digits = val.replaceAll(RegExp(r'[^0-9]'), '');
      for (int i = 0; i < 6; i++) {
        if (i < digits.length) {
          _otpDigitControllers[i].text = digits[i];
        }
      }
      final nextIdx = digits.length >= 6 ? 5 : digits.length;
      _otpDigitFocusNodes[nextIdx].requestFocus();
      if (digits.length >= 6) {
        _handleVerifyLoginCode();
      }
      return;
    }

    if (val.isNotEmpty && index < 5) {
      _otpDigitFocusNodes[index + 1].requestFocus();
    }
    if (_getEnteredOtp().length == 6) {
      _handleVerifyLoginCode();
    }
  }

  void _fillLoginOtp(String? otp) {
    if (otp == null || otp.isEmpty) return;
    final digits = otp.replaceAll(RegExp(r'[^0-9]'), '');
    for (int i = 0; i < _otpDigitControllers.length; i++) {
      if (i < digits.length) {
        _otpDigitControllers[i].text = digits[i];
      } else {
        _otpDigitControllers[i].clear();
      }
    }
    if (digits.length >= 6) {
      _handleVerifyLoginCode();
    }
  }

  void _showTermsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Terms of Use', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const SingleChildScrollView(
          child: Text(
            'GS HEALTH Terms of Use:\n\n'
            '1. Acceptance: By accessing GS HEALTH, you agree to comply with all applicable medical records standards.\n'
            '2. Triage & Consultations: Information provided is intended for triage, specialist matching, and care management.\n'
            '3. Security: All health and consultation data is protected with 256-bit encryption.',
            style: TextStyle(fontSize: 13.5, height: 1.45),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: Color(0xFF012A58), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showPrivacyDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Privacy Policy', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const SingleChildScrollView(
          child: Text(
            'GS HEALTH Privacy Policy:\n\n'
            '1. We respect and protect your personal and healthcare information.\n'
            '2. We never sell patient data to third parties.\n'
            '3. Medical records are shared only with authorized clinical practitioners involved in your care.',
            style: TextStyle(fontSize: 13.5, height: 1.45),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: Color(0xFF012A58), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildSixDigitOtpInput() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final spacing = (totalWidth < 360) ? 5.0 : 8.0;
        final boxWidth = ((totalWidth - (spacing * 5)) / 6).clamp(36.0, 56.0);
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (index) {
            return SizedBox(
              width: boxWidth,
              height: 54,
              child: Focus(
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.backspace) {
                    if (_otpDigitControllers[index].text.isEmpty && index > 0) {
                      _otpDigitFocusNodes[index - 1].requestFocus();
                      _otpDigitControllers[index - 1].clear();
                      return KeyEventResult.handled;
                    }
                  }
                  return KeyEventResult.ignored;
                },
                child: TextFormField(
                  key: Key('login_otp_box_$index'),
                  controller: _otpDigitControllers[index],
                  focusNode: _otpDigitFocusNodes[index],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  style: TextStyle(
                    fontSize: (totalWidth < 360) ? 18 : 22,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1E293B),
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    contentPadding: EdgeInsets.zero,
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.gsNavy, width: 2),
                    ),
                  ),
                  onChanged: (val) => _handleOtpDigitChange(val, index),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  Future<void> _handleSendLoginCode() async {
    final rawInput = _loginEmailController.text.trim();
    if (rawInput.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Please enter your 10-digit mobile number.'),
          backgroundColor: Color(0xFFFE3434),
        ),
      );
      return;
    }

    final normalized = _normalizePhone(rawInput);
    if (normalized.length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Please enter a valid 10-digit mobile number.'),
          backgroundColor: Color(0xFFFE3434),
        ),
      );
      return;
    }

    setState(() {
      _isSendingLoginCode = true;
      _loginOtpErrorMessage = null;
    });

    try {
      final res = await ApiService().requestOtp(
        phone: normalized,
        email: rawInput.contains('@') ? rawInput : '',
      );

      if (!mounted) return;
      setState(() {
        _isSendingLoginCode = false;
      });

      if (res['success'] == true) {
        final bool isAuthorizedAdminMatch = res['isAdmin'] == true;
        final bool canShowOnScreenOtp = ApiConstants.allowOnScreenOtpDisplay &&
            res['deliveryMode'] == 'on_screen';
        final String? returnedOtp = canShowOnScreenOtp ? res['otp']?.toString().trim() : null;
        setState(() {
          _isLoginOtpSent = true;
          _currentLoginOtp = (returnedOtp != null && RegExp(r'^\d{6}$').hasMatch(returnedOtp))
              ? returnedOtp
              : null;
          if (isAuthorizedAdminMatch) {
            _isAdminMode = true;
            _selectedRole = UserRole.admin;
          } else {
            _isAdminMode = false;
          }
          for (final c in _otpDigitControllers) {
            c.clear();
          }
        });
        _startResendTimer();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_otpDigitFocusNodes.isNotEmpty && mounted) {
            _otpDigitFocusNodes[0].requestFocus();
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _currentLoginOtp != null
                  ? 'Test verification code: $_currentLoginOtp'
                  : (res['message']?.toString() ?? 'OTP sent successfully to your mobile number.'),
            ),
            backgroundColor: AppTheme.gsNavy,
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'Failed to send OTP SMS. Please check your mobile number.'),
            backgroundColor: const Color(0xFFFE3434),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSendingLoginCode = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error dispatching OTP: $e'),
          backgroundColor: const Color(0xFFFE3434),
        ),
      );
    }
  }

  Future<void> _handleVerifyLoginCode() async {
    final code = _getEnteredOtp();
    if (code.length < 6) {
      setState(() {
        _loginOtpErrorMessage = 'Please enter all 6 digits of the verification code.';
      });
      return;
    }

    setState(() {
      _isVerifyingLoginCode = true;
      _loginOtpErrorMessage = null;
    });

    final rawInput = _loginEmailController.text.trim();
    final normalized = _normalizePhone(rawInput);

    try {
      final bool isPatientSignIn = !_isAdminMode && _selectedRole == UserRole.patient;
      final res = await ApiService().verifyOtp(
        phone: normalized,
        email: rawInput.contains('@') ? rawInput : '',
        code: code,
        role: _isAdminMode ? _selectedAdminRoleType : (isPatientSignIn ? 'Patient' : null),
        autoCreatePatient: isPatientSignIn,
      );
      final bool verified = res['success'] == true;

      if (!mounted) return;
      setState(() => _isVerifyingLoginCode = false);

      if (verified) {
        await _handleLogin(
          verifiedOtpCode: code,
          otpAlreadyVerified: true,
          verifiedOtpResponse: res,
        );
      } else {
        setState(() {
          _loginOtpErrorMessage = res['message']?.toString() ?? 'Invalid or expired OTP code.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isVerifyingLoginCode = false;
        _loginOtpErrorMessage = 'Verification error: $e';
      });
    }
  }

  Future<void> _handleLogin({
    String? verifiedOtpCode,
    bool otpAlreadyVerified = false,
    Map<String, dynamic>? verifiedOtpResponse,
  }) async {
    if (_isLoggingIn) return;

    final String otpToUse = (verifiedOtpCode ?? _getEnteredOtp()).trim();

    FocusManager.instance.primaryFocus?.unfocus();

    final rawIdentifier = _loginEmailController.text.trim();
    final identifier = (!rawIdentifier.contains('@') && RegExp(r'^[+\d\s\-()]+$').hasMatch(rawIdentifier))
        ? _normalizePhone(rawIdentifier)
        : rawIdentifier;

    setState(() {
      _isLoggingIn = true;
      _loginOtpErrorMessage = null;
    });
    ScaffoldMessenger.of(context).clearSnackBars();

    try {
      late final Map<String, dynamic> res;
      if (otpAlreadyVerified &&
          verifiedOtpResponse != null &&
          verifiedOtpResponse['success'] == true &&
          verifiedOtpResponse['user'] is Map) {
        final vUser = Map<String, dynamic>.from(verifiedOtpResponse['user'] as Map);
        final vRoleLower = (vUser['role'] ?? 'patient').toString().trim().toLowerCase();
        final bool vIsAdminOrSubAdmin = vRoleLower.contains('admin');
        if (_isAdminMode && !vIsAdminOrSubAdmin) {
          res = {
            'success': false,
            'message': 'Role Mismatch: Your account is registered as \'${vUser['role'] ?? 'Patient'}\'. Cannot log into Admin Portal.',
          };
        } else {
          res = {
            'success': true,
            'data': verifiedOtpResponse,
          };
        }
      } else {
        res = await ApiService().loginUser(
          email: identifier,
          phone: identifier,
          otp: otpToUse.isNotEmpty ? otpToUse : null,
          role: _isAdminMode
              ? 'Admin'
              : (_selectedRole == UserRole.clinic ? 'Clinic' : null),
        );
      }

      if (!mounted) return;

      if (res['success'] == true) {
        final Map<String, dynamic> responseData = res['data'] is Map<String, dynamic> ? res['data'] : {};
        final Map<String, dynamic> userData = (responseData['user'] is Map<String, dynamic>)
            ? responseData['user']
            : (res['user'] is Map<String, dynamic> ? res['user'] : {});

        // Authoritative role directly from database
        final String registeredRole = (userData['role'] ?? 'patient').toString().toLowerCase();

        final String? returnedPhoto = userData['profilePhoto']?.toString();
        final parsedPhoto = PatientProfile.parseProfilePhoto(returnedPhoto);
        final Uint8List? photoBytes = parsedPhoto.bytes;
        final String? profileImageUrl = parsedPhoto.url;

        final userPhone = (userData['phone'] != null && userData['phone'].toString().isNotEmpty)
            ? userData['phone'].toString()
            : (!identifier.contains('@') && identifier.isNotEmpty ? identifier : '');

        final String effectiveToken = (responseData['accessToken'] ?? res['accessToken'] ?? res['token'] ?? 'sb_session_${userData['id'] ?? DateTime.now().millisecondsSinceEpoch}').toString();
        final String? effectiveRealtimeToken = (responseData['realtimeToken'] ?? res['realtimeToken'])?.toString();
        final DateTime? effectiveRealtimeExpiresAt = DateTime.tryParse(
          (responseData['realtimeTokenExpiresAt'] ?? res['realtimeTokenExpiresAt'] ?? '').toString(),
        );
        final String effectiveUserId = (userData['id'] ?? SupabaseService.safeCurrentUser?.id ?? 'user_${DateTime.now().millisecondsSinceEpoch}').toString();
        final String effectiveEmail = userData['email'] ?? (identifier.contains('@') ? identifier : '');
        final String effectiveName = (userData['name'] != null && userData['name'].toString().trim().isNotEmpty)
            ? userData['name'].toString().trim()
            : (effectiveEmail.contains('@') ? effectiveEmail.split('@').first : identifier);

        AnalyticsService.logLogin(method: 'OTP_Mobile_Login', role: registeredRole);

        final prevUserId = SessionService().currentSession?.userId.trim();
        if (prevUserId != null && prevUserId.isNotEmpty && prevUserId != effectiveUserId) {
          await PatientProblemService().clearAllDataAndStorage();
        }
        if (effectiveToken.isNotEmpty) {
          ApiService().setAuthToken(effectiveToken);
        }

        // Direct Authoritative Role Routing
        if (registeredRole.contains('clinic') ||
            (_selectedRole == UserRole.clinic && !registeredRole.contains('admin'))) {
          final String clinicName = (userData['clinicName'] ??
                  userData['clinic_name'] ??
                  effectiveName)
              .toString()
              .trim();
          final String canonicalClinicId = (userData['clinicId'] ?? userData['clinic_id'] ?? '').toString().trim();
          final String effectiveClinicSessionId = canonicalClinicId.isNotEmpty ? canonicalClinicId : effectiveUserId;
          final String clinicAddress = (userData['clinicLocation'] ??
                  userData['clinicAddress'] ??
                  userData['location'] ??
                  userData['city'] ??
                  '')
              .toString()
              .trim();
          PatientProblemService().setAuthenticatedClinicSession(
            id: effectiveClinicSessionId,
            clinicName: clinicName.isNotEmpty ? clinicName : effectiveName,
            location: clinicAddress,
            phone: userPhone,
            email: effectiveEmail,
          );
          await SessionService().saveSession(
            token: effectiveToken,
            role: 'Clinic',
            userId: effectiveUserId,
            email: effectiveEmail,
            phone: userPhone,
            name: effectiveName,
            realtimeToken: effectiveRealtimeToken,
            realtimeTokenExpiresAt: effectiveRealtimeExpiresAt,
            metadata: {
              ...userData,
              'accountUserId': effectiveUserId,
              'clinicId': effectiveClinicSessionId,
              'clinicName': clinicName.isNotEmpty ? clinicName : effectiveName,
              if (clinicAddress.isNotEmpty) 'location': clinicAddress,
            },
          );
          if (!mounted) return;
          setState(() => _isLoggingIn = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🎉 Welcome back, ${userData['name'] ?? clinicName}! Opening Clinic Dashboard...'),
              backgroundColor: AppTheme.gsNavy,
            ),
          );
          context.go('/clinic');
        } else if (registeredRole.contains('dentist') || registeredRole.contains('doctor')) {
          final docName = (userData['name'] != null && userData['name'].toString().trim().isNotEmpty)
              ? userData['name'].toString().trim()
              : (userData['email'] != null ? userData['email'].toString() : identifier);
          final docUserId = (userData['userId'] ?? userData['id'] ?? SupabaseService.safeCurrentUser?.id ?? '').toString();
          final docDentistId = (userData['dentistId'] ?? userData['id'] ?? docUserId).toString();
          final returnedSpec = (userData['specialty'] ?? userData['speciality'] ?? '').toString().trim();
          final effectiveSpec = returnedSpec.isNotEmpty ? returnedSpec : 'General Medicine';
          final returnedQual = (userData['qualification'] ?? userData['qualifications'] ?? '').toString().trim();
          final effectiveQual = returnedQual.isNotEmpty
              ? returnedQual
              : MedicalSpecialtyModel.getDefaultQualificationForSpecialty(effectiveSpec);
          final returnedExp = int.tryParse((userData['experienceYears'] ?? userData['experience_years'] ?? '').toString()) ?? 5;
          final returnedStatus = (userData['availability_status'] ?? userData['status'] ?? 'Available').toString();
          final returnedClinicName = (userData['clinicName'] ?? userData['clinic_name'] ?? '').toString().trim();
          final returnedClinicAddress =
              (userData['clinicAddress'] ?? userData['clinic_address'] ?? userData['location'] ?? '').toString().trim();
          final returnedCity = (userData['city'] ?? '').toString().trim();
          final returnedState = (userData['state'] ?? '').toString().trim();
          final returnedPincode = (userData['pincode'] ?? '').toString().trim();
          final double? returnedLat = userData['latitude'] != null
              ? double.tryParse(userData['latitude'].toString())
              : null;
          final double? returnedLng = userData['longitude'] != null
              ? double.tryParse(userData['longitude'].toString())
              : null;
          final List<String>? returnedLangs = userData['languages'] is List
              ? (userData['languages'] as List).map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList()
              : null;

          PatientProblemService().registerDoctor(
            id: docDentistId,
            userId: docUserId,
            name: docName,
            email: userData['email'] ?? (identifier.contains('@') ? identifier : ''),
            phone: userPhone,
            licenseNumber: (userData['licenseNumber'] ?? userData['license_number'] ?? '').toString(),
            specialty: effectiveSpec,
            qualification: effectiveQual,
            clinicId: (userData['clinicId'] ?? userData['clinic_id'] ?? '').toString(),
            clinicName: returnedClinicName,
            clinicAddress: returnedClinicAddress,
            city: returnedCity,
            state: returnedState,
            pincode: returnedPincode,
            latitude: returnedLat,
            longitude: returnedLng,
            languages: returnedLangs,
            experienceYears: returnedExp,
            status: returnedStatus,
            photoBytes: photoBytes,
            profileImageUrl: profileImageUrl,
            skipApiRegister: true,
          );
          await SessionService().saveSession(
            token: effectiveToken,
            role: 'Dentist',
            userId: docDentistId,
            email: effectiveEmail,
            phone: userPhone,
            name: docName,
            realtimeToken: effectiveRealtimeToken,
            realtimeTokenExpiresAt: effectiveRealtimeExpiresAt,
            metadata: {
              ...userData,
              'accountUserId': docUserId,
              'dentistId': docDentistId,
              'userId': docUserId,
              'clinicName': returnedClinicName,
              'clinicAddress': returnedClinicAddress,
              'city': returnedCity,
              'state': returnedState,
              'pincode': returnedPincode,
              if (returnedLat != null) 'latitude': returnedLat,
              if (returnedLng != null) 'longitude': returnedLng,
              'specialty': effectiveSpec,
              'qualification': effectiveQual,
            },
          );
          if (!mounted) return;
          setState(() => _isLoggingIn = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🎉 Welcome back, Dr. $docName! Opening Doctor Workspace...'),
              backgroundColor: AppTheme.gsNavy,
            ),
          );
          context.go('/dentist');
        } else if (registeredRole.contains('admin') || registeredRole.contains('sub-admin') || registeredRole.contains('subadmin') || registeredRole.contains('sub_admin')) {
          final isSubAdmin = registeredRole.contains('sub-admin') || registeredRole.contains('subadmin') || registeredRole.contains('sub_admin');

          if (isSubAdmin) {
            List<String> perms = [];
            if (userData['permissions'] is List) {
              perms = List<String>.from((userData['permissions'] as List).map((e) => e.toString()));
            }
            final List<dynamic>? subAdminDistricts = userData['assignedDistricts'] is List
                ? List<dynamic>.from(userData['assignedDistricts'] as List)
                : (userData['districts'] is List ? List<dynamic>.from(userData['districts'] as List) : null);
            PatientProblemService().setSubAdminSession(
              id: userData['id']?.toString() ?? '',
              name: userData['name']?.toString() ?? 'Sub-Admin',
              email: userData['email']?.toString() ?? (identifier.contains('@') ? identifier : ''),
              phone: userData['phone']?.toString() ?? userPhone,
              permissions: perms,
              assignedDistricts: subAdminDistricts,
              status: userData['status']?.toString() ?? 'ACTIVE',
            );
          } else {
            PatientProblemService().clearSubAdminSession();
            PatientProblemService().setAdminMode(true);
          }

          await SessionService().saveSession(
            token: effectiveToken,
            role: isSubAdmin ? 'Sub-Admin' : 'ADMIN',
            userId: effectiveUserId,
            email: effectiveEmail,
            phone: userPhone,
            name: effectiveName,
            realtimeToken: effectiveRealtimeToken,
            realtimeTokenExpiresAt: effectiveRealtimeExpiresAt,
            metadata: {
              ...userData,
              'accountUserId': effectiveUserId,
              'isSubAdmin': isSubAdmin,
            },
          );
          if (!mounted) return;
          setState(() => _isLoggingIn = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🎉 Welcome back, ${userData['name'] ?? (isSubAdmin ? 'Sub-Admin' : 'Admin')}! Opening ${isSubAdmin ? 'Sub-Admin Workspace' : 'Admin Dashboard'}...'),
              backgroundColor: const Color(0xFF012A58),
            ),
          );
          final router = GoRouter.maybeOf(context);
          if (router != null) {
            router.go(isSubAdmin ? '/sub-admin' : '/admin');
          }
        } else {
          // Patient Role (defer profile completion until service access)
          final existingCurId = PatientProblemService().currentPatient.id.trim();
          if (existingCurId.isNotEmpty && existingCurId != effectiveUserId) {
            await PatientProblemService().clearPatientSessionCache();
          }

          final prefs = await SharedPreferences.getInstance();
          final scopedProfileStr = prefs.getString('dentaguru_patient_profile_$effectiveUserId');
          Map<String, dynamic> cachedMap = {};
          if (scopedProfileStr != null && scopedProfileStr.isNotEmpty) {
            try {
              final decoded = jsonDecode(scopedProfileStr);
              if (decoded is Map<String, dynamic> && decoded['id']?.toString() == effectiveUserId) {
                cachedMap = decoded;
              }
            } catch (_) {}
          }

          Map<String, dynamic> dbProfileMeta = {};
          if (userData['device_token'] != null && userData['device_token'].toString().startsWith('{')) {
            try {
              dbProfileMeta = jsonDecode(userData['device_token'].toString());
            } catch (_) {}
          }

          String cleanVal(dynamic v) => PatientProfile.cleanString(v);

          final currentSbUser = SupabaseService.safeCurrentUser;
          final bool authUserMatches = currentSbUser != null &&
              ((effectiveUserId.isNotEmpty && currentSbUser.id.trim() == effectiveUserId) ||
                  (effectiveEmail.isNotEmpty &&
                      (currentSbUser.email ?? '').trim().toLowerCase() == effectiveEmail.trim().toLowerCase()));
          final authMeta = authUserMatches ? (currentSbUser.userMetadata ?? {}) : const <String, dynamic>{};
          final String loginAge = cleanVal(userData['age'] ?? dbProfileMeta['age'] ?? cachedMap['age'] ?? authMeta['age'] ?? authMeta['patient_age']);
          final String loginGender = cleanVal(userData['gender'] ?? dbProfileMeta['gender'] ?? cachedMap['gender'] ?? authMeta['gender']);
          final String loginPincode = cleanVal(userData['pincode'] ?? dbProfileMeta['pincode'] ?? cachedMap['pincode'] ?? authMeta['pincode']);
          final String loginCity = cleanVal(userData['city'] ?? dbProfileMeta['city'] ?? cachedMap['city'] ?? authMeta['city']);
          final String loginBloodGroup = cleanVal(userData['bloodGroup'] ?? userData['blood_group'] ?? dbProfileMeta['bloodGroup'] ?? cachedMap['bloodGroup'] ?? authMeta['bloodGroup']);
          final String loginEmergency = cleanVal(userData['emergencyContact'] ?? userData['emergency_contact'] ?? dbProfileMeta['emergencyContact'] ?? cachedMap['emergencyContact'] ?? authMeta['emergencyContact'] ?? userPhone);
          final dynamic rawLoginLangs = userData['languages'] ?? dbProfileMeta['languages'] ?? cachedMap['languages'] ?? authMeta['languages'];
          final List<String> loginLanguages = (rawLoginLangs is List && rawLoginLangs.isNotEmpty)
              ? rawLoginLangs.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList()
              : <String>['English'];

          final Uint8List? effectivePhotoBytes = photoBytes ?? PatientProfile.parseProfilePhoto(cachedMap['photoBase64']).bytes;
          final String? effectiveImageUrl = profileImageUrl ?? (cleanVal(cachedMap['profileImageUrl']).isNotEmpty ? cleanVal(cachedMap['profileImageUrl']) : null);

          PatientProblemService().updatePatientProfile(
            id: effectiveUserId,
            name: (userData['name'] != null && cleanVal(userData['name']).isNotEmpty)
                ? cleanVal(userData['name'])
                : (identifier.contains('@') ? identifier.split('@').first : 'Patient'),
            email: cleanVal(userData['email']).isNotEmpty
                ? cleanVal(userData['email'])
                : (identifier.contains('@') ? identifier : ''),
            phone: userPhone,
            age: loginAge,
            gender: loginGender,
            bloodGroup: loginBloodGroup.isNotEmpty ? loginBloodGroup : 'O Positive (O+)',
            emergencyContact: loginEmergency.isNotEmpty ? loginEmergency : userPhone,
            city: loginCity,
            pincode: loginPincode,
            languages: loginLanguages,
            photoBytes: effectivePhotoBytes,
            profileImageUrl: effectiveImageUrl,
            preserveExistingPhoto: false,
            syncRemote: false,
          );
          await SessionService().saveSession(
            token: effectiveToken,
            role: 'Patient',
            userId: effectiveUserId,
            email: effectiveEmail,
            phone: userPhone,
            name: effectiveName,
            realtimeToken: effectiveRealtimeToken,
            realtimeTokenExpiresAt: effectiveRealtimeExpiresAt,
            metadata: {
              ...userData,
              'accountUserId': effectiveUserId,
              'age': loginAge,
              'gender': loginGender,
              'pincode': loginPincode,
              'city': loginCity,
              'bloodGroup': loginBloodGroup.isNotEmpty ? loginBloodGroup : 'O Positive (O+)',
              'emergencyContact': loginEmergency.isNotEmpty ? loginEmergency : userPhone,
              'languages': loginLanguages,
              if (returnedPhoto != null && cleanVal(returnedPhoto).isNotEmpty) 'profilePhoto': returnedPhoto,
            },
          );
          PatientProblemService().syncAllDataFromApi();
          if (!mounted) return;
          setState(() => _isLoggingIn = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🎉 Welcome${cleanVal(userData['name']).isNotEmpty && cleanVal(userData['name']).toLowerCase() != 'patient' ? ' back, ${userData['name']}' : ' to GS HEALTH'}!'),
              backgroundColor: AppTheme.gsNavy,
            ),
          );
          final router = GoRouter.maybeOf(context);
          if (router != null) {
            router.go('/patient');
          }
        }
      } else {
        final String errMsg = (res['message'] ?? 'Failed to authenticate user.').toString();
        final String lowerErr = errMsg.toLowerCase();
        final bool isNonPatientRole = _isAdminMode ||
            _selectedRole == UserRole.dentist ||
            _selectedRole == UserRole.clinic;
        final bool isUnregisteredMobile = verifiedOtpCode != null &&
            verifiedOtpCode.trim().isNotEmpty &&
            !identifier.contains('@') &&
            _isValidMobilePhone(identifier) &&
            isNonPatientRole &&
            (lowerErr.contains('not registered') ||
                lowerErr.contains('not found') ||
                lowerErr.contains('no account') ||
                lowerErr.contains('does not exist'));

        if (isUnregisteredMobile) {
          final String normalizedPhone = _normalizePhone(identifier);
          setState(() {
            _isLoggingIn = false;
            _loginOtpErrorMessage = null;
            _isLoginOtpSent = false;
            _verifiedPhone = normalizedPhone;
            _isOtpVerified = true;
            _isOtpSent = true;
            _phoneController.text = normalizedPhone;
            if (widget.allowAdminRole != true && _selectedRole == UserRole.admin) {
              _selectedRole = UserRole.patient;
              _isAdminMode = false;
            }
            _tabController.index = 0;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Mobile +91$normalizedPhone verified! Complete your GS HEALTH profile.'),
              backgroundColor: AppTheme.gsNavy,
            ),
          );
          return;
        }

        setState(() {
          _isLoggingIn = false;
          _loginOtpErrorMessage = errMsg;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoggingIn = false;
        _loginOtpErrorMessage = 'Sign in error: $e';
      });
    }
  }
  void _handleRegister() async {
    if (_isRegistering) return;

    // Security Guard: Never allow Admin/Sub-Admin registration outside the authorized Admin portal.
    if (_selectedRole == UserRole.admin && widget.allowAdminRole != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Admin accounts require authorized Admin Console provisioning or portal access.'),
          backgroundColor: AppTheme.gsRed,
        ),
      );
      return;
    }

    final bool isFormValid = _registerFormKey.currentState!.validate();
    final bool isDentistMissingMap = _selectedRole == UserRole.dentist &&
        !ClinicDirectionsHelper.hasValidCoordinates(_selectedLatitude, _selectedLongitude);
    if (isDentistMissingMap) {
      setState(() {
        _mapLocationError = 'Please select your clinic location on the map.';
      });
    } else if (_mapLocationError != null) {
      setState(() => _mapLocationError = null);
    }
    if (!isFormValid || isDentistMissingMap) {
      if (isDentistMissingMap) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Please select your clinic location on the map before continuing.'),
            backgroundColor: AppTheme.gsRed,
          ),
        );
      }
      return;
    }

    final name = _selectedRole == UserRole.clinic
        ? (_clinicNameController.text.trim().isNotEmpty
            ? _clinicNameController.text.trim()
            : _nameController.text.trim())
        : _nameController.text.trim();
    final email = _emailController.text.trim();
    final rawPhone = _phoneController.text.trim();
    final phone = _normalizePhone(rawPhone);
    final registeredAge = _ageController.text.trim();

    if (rawPhone.isEmpty || !_isValidMobilePhone(rawPhone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Please enter a valid 10-digit Mobile Phone Number and verify OTP below.'),
          backgroundColor: AppTheme.gsRed,
        ),
      );
      return;
    }

    if (!_isOtpVerified || _verifiedPhone == null || _verifiedPhone != phone) {
      setState(() {
        _isOtpVerified = false;
        _isOtpSent = false;
        _verifiedPhone = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Mobile number changed or not verified. Please verify OTP for the current number.'),
          backgroundColor: AppTheme.gsRed,
        ),
      );
      return;
    }

    String? photoBase64;
    if (_pickedImageBytes != null && _pickedImageBytes!.isNotEmpty) {
      final mime = _resolveImageMimeType(_pickedImageName);
      photoBase64 = 'data:$mime;base64,${base64Encode(_pickedImageBytes!)}';
    }

    final clinicAddress = _clinicAddressController.text.trim();
    final stateValue = _stateController.text.trim();
    final location = (_selectedRole == UserRole.dentist || _selectedRole == UserRole.clinic)
        ? clinicAddress
        : _locationController.text.trim();
    final city = _cityController.text.trim();
    final pincode = _pincodeController.text.trim();
    final String chosenRole = _selectedRole == UserRole.dentist
        ? 'Dentist'
        : (_selectedRole == UserRole.clinic
            ? 'Clinic'
            : (_selectedRole == UserRole.admin ? _selectedAdminRoleType : 'Patient'));

    // Mandatory Field Validations
    if (city.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ City is a mandatory field.'), backgroundColor: AppTheme.gsRed),
      );
      return;
    }

    if (pincode.isNotEmpty && !ClinicDirectionsHelper.isValidPincode(pincode)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Please enter a valid 6-digit Pincode.'), backgroundColor: AppTheme.gsRed),
      );
      return;
    }

    if (_selectedRole == UserRole.dentist || _selectedRole == UserRole.clinic) {
      if (_clinicNameController.text.trim().isEmpty ||
          clinicAddress.isEmpty ||
          stateValue.isEmpty ||
          !ClinicDirectionsHelper.isValidPincode(pincode)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Please complete Clinic Name, Address, City, State, and 6-digit Pincode.'),
            backgroundColor: AppTheme.gsRed,
          ),
        );
        return;
      }
      if (!ClinicDirectionsHelper.hasValidCoordinates(_selectedLatitude, _selectedLongitude)) {
        setState(() {
          _mapLocationError = 'Please select your clinic location on the map.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Please select your clinic location on the map.'),
            backgroundColor: AppTheme.gsRed,
          ),
        );
        return;
      }
    }

    setState(() => _isRegistering = true);

    final List<String> selectedLangs = <String>[
      ...kGsHealthLanguages.where(_selectedLanguages.contains),
      ..._selectedLanguages.where((l) => l.trim().isNotEmpty && !kGsHealthLanguages.contains(l)),
    ];
    if (selectedLangs.isEmpty) {
      selectedLangs.add('English');
    }

    final bool isFacilityRole = _selectedRole == UserRole.dentist || _selectedRole == UserRole.clinic;
    final String? submittedClinicName = isFacilityRole
        ? (_clinicNameController.text.trim().isNotEmpty
            ? _clinicNameController.text.trim()
            : (_selectedRole == UserRole.clinic ? name : null))
        : null;
    final String? submittedClinicAddress = isFacilityRole && clinicAddress.isNotEmpty
        ? clinicAddress
        : (_selectedRole == UserRole.clinic && location.isNotEmpty ? location : null);
    final double? submittedLatitude =
        _selectedRole == UserRole.patient ? null : _selectedLatitude;
    final double? submittedLongitude =
        _selectedRole == UserRole.patient ? null : _selectedLongitude;

    try {
      final res = await ApiService().registerUser(
        name: name,
        email: email,
        phone: phone,
        role: chosenRole,
        age: registeredAge,
        gender: _selectedGender,
        bloodGroup: _selectedBloodGroup,
        emergencyContact: _emergencyContactController.text.trim(),
        specialty: _selectedRole == UserRole.dentist ? (_selectedSpecialty ?? 'General Medicine') : null,
        qualification: _selectedRole == UserRole.dentist
            ? (_qualificationController.text.trim().isNotEmpty
                ? _qualificationController.text.trim()
                : MedicalSpecialtyModel.getDefaultQualificationForSpecialty(_selectedSpecialty ?? 'General Medicine'))
            : null,
        experienceYears: _selectedRole == UserRole.dentist
            ? (int.tryParse(_experienceController.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 5)
            : null,
        licenseNumber: _selectedRole == UserRole.dentist ? _licenseNoController.text.trim() : null,
        clinicId: _selectedRole == UserRole.dentist ? _selectedClinicId : null,
        clinicName: submittedClinicName,
        clinicAddress: submittedClinicAddress,
        location: location.isNotEmpty ? location : (clinicAddress.isNotEmpty ? clinicAddress : null),
        state: stateValue.isNotEmpty ? stateValue : null,
        city: city,
        pincode: pincode,
        latitude: submittedLatitude,
        longitude: submittedLongitude,
        profilePhoto: photoBase64,
        languages: selectedLangs,
        referralCode: _selectedRole == UserRole.patient && _referralCodeController.text.trim().isNotEmpty
            ? _referralCodeController.text.trim().toUpperCase()
            : null,
      );

      if (!mounted) return;

      if (res['success'] == true) {
        final Map<String, dynamic> regData = res['data'] is Map<String, dynamic> ? res['data'] : {};
        final Map<String, dynamic> regUser = (regData['user'] is Map<String, dynamic>)
            ? regData['user']
            : (res['user'] is Map<String, dynamic> ? res['user'] : {});

        final String regToken = (regData['accessToken'] ?? res['accessToken'] ?? res['token'] ?? '').toString().trim();
        final String? regRealtimeToken = (regData['realtimeToken'] ?? res['realtimeToken'])?.toString();
        final DateTime? regRealtimeExpiresAt = DateTime.tryParse(
          (regData['realtimeTokenExpiresAt'] ?? res['realtimeTokenExpiresAt'] ?? '').toString(),
        );
        if (regToken.isEmpty) {
          setState(() => _isRegistering = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Registration Error: Server did not issue a valid session token.'),
              backgroundColor: Color(0xFFFE3434),
            ),
          );
          return;
        }
        final String regUserId = (regUser['id'] ?? SupabaseService.safeCurrentUser?.id ?? 'user_${DateTime.now().millisecondsSinceEpoch}').toString();

        if (_selectedRole == UserRole.patient) {
          PatientProblemService().updatePatientProfile(
            id: regUserId,
            name: name,
            email: email,
            phone: phone,
            age: registeredAge,
            gender: _selectedGender ?? '',
            bloodGroup: _selectedBloodGroup ?? '',
            emergencyContact: _emergencyContactController.text.trim().isEmpty ? phone : _emergencyContactController.text.trim(),
            address: location,
            city: city,
            pincode: pincode,
            languages: selectedLangs,
            photoBytes: _pickedImageBytes,
            preserveExistingPhoto: false,
            syncRemote: false,
          );
          await SessionService().saveSession(
            token: regToken,
            role: 'Patient',
            userId: regUserId,
            email: email,
            phone: phone,
            name: name,
            realtimeToken: regRealtimeToken,
            realtimeTokenExpiresAt: regRealtimeExpiresAt,
            metadata: {
              'accountUserId': regUserId,
              'age': registeredAge,
              'gender': _selectedGender ?? '',
              'bloodGroup': _selectedBloodGroup ?? '',
              'emergencyContact': _emergencyContactController.text.trim().isEmpty ? phone : _emergencyContactController.text.trim(),
              'city': city,
              'pincode': pincode,
              'address': location,
              'languages': selectedLangs,
              if (_selectedLatitude != null) 'latitude': _selectedLatitude,
              if (_selectedLongitude != null) 'longitude': _selectedLongitude,
            },
          );
        } else if (_selectedRole == UserRole.dentist) {
          // Wipe any cached visits/requests/patients from prior sessions before onboarding new doctor
          await PatientProblemService().clearAllDataAndStorage();
          final exp = int.tryParse(_experienceController.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 5;
          final effectiveSpec = _selectedSpecialty ?? 'General Medicine';
          final effectiveQual = _qualificationController.text.trim().isNotEmpty
              ? _qualificationController.text.trim()
              : MedicalSpecialtyModel.getDefaultQualificationForSpecialty(effectiveSpec);
          final docUserId = (regUser['userId'] ?? regUser['id'] ?? res['user']?['id'] ?? SupabaseService.safeCurrentUser?.id ?? regUserId).toString();
          final docDentistId = (regUser['dentistId'] ?? res['user']?['dentistId'] ?? docUserId).toString();
          final uploadedPhotoRaw = (regUser['profilePhoto'] ?? res['user']?['profilePhoto'] ?? '').toString().trim();
          final String? uploadedPhotoUrl = (uploadedPhotoRaw.startsWith('http://') || uploadedPhotoRaw.startsWith('https://'))
              ? uploadedPhotoRaw
              : null;
          PatientProblemService().registerDoctor(
            id: docDentistId,
            userId: docUserId,
            clinicId: (regUser['clinicId'] ?? regUser['clinic_id'] ?? _selectedClinicId ?? '').toString(),
            name: name,
            email: email,
            phone: phone,
            licenseNumber: _licenseNoController.text.trim(),
            specialty: effectiveSpec,
            clinicName: (regUser['clinicName'] ?? _clinicNameController.text).toString().trim(),
            clinicAddress: clinicAddress.isNotEmpty ? clinicAddress : location,
            state: stateValue,
            city: city,
            pincode: pincode,
            latitude: submittedLatitude,
            longitude: submittedLongitude,
            qualification: effectiveQual,
            experienceYears: exp,
            photoBytes: _pickedImageBytes,
            profileImageUrl: uploadedPhotoUrl,
            languages: selectedLangs,
            skipApiRegister: true,
          );
          await SessionService().saveSession(
            token: regToken,
            role: 'Dentist',
            userId: docDentistId,
            email: email,
            phone: phone,
            name: name,
            realtimeToken: regRealtimeToken,
            realtimeTokenExpiresAt: regRealtimeExpiresAt,
            metadata: {
              'accountUserId': docUserId,
              'dentistId': docDentistId,
              'userId': docUserId,
              'licenseNumber': _licenseNoController.text.trim(),
              'specialty': effectiveSpec,
              'qualification': effectiveQual,
              'clinicName': _clinicNameController.text.trim(),
              'clinicAddress': clinicAddress.isNotEmpty ? clinicAddress : location,
              'state': stateValue,
              'city': city,
              'pincode': pincode,
              if (submittedLatitude != null) 'latitude': submittedLatitude,
              if (submittedLongitude != null) 'longitude': submittedLongitude,
              'experienceYears': exp,
              'languages': selectedLangs,
            },
          );
        } else if (_selectedRole == UserRole.clinic) {
          final resolvedClinicId = (regUser['clinicId'] ?? regUser['clinic_id'] ?? regUserId).toString().trim();
          final resolvedClinicName = (regUser['clinicName'] ??
                  (_clinicNameController.text.trim().isNotEmpty
                      ? _clinicNameController.text.trim()
                      : name))
              .toString()
              .trim();
          final resolvedClinicAddr = clinicAddress.isNotEmpty ? clinicAddress : location;
          PatientProblemService().setAuthenticatedClinicSession(
            id: resolvedClinicId,
            clinicName: resolvedClinicName,
            location: resolvedClinicAddr.isNotEmpty ? resolvedClinicAddr : city,
            phone: phone,
            email: email,
          );
          await PatientProblemService().registerClinic(
            clinicName: resolvedClinicName,
            location: resolvedClinicAddr.isNotEmpty ? resolvedClinicAddr : city,
          );
          await PatientProblemService().syncClinicsFromApi();
          await SessionService().saveSession(
            token: regToken,
            role: 'Clinic',
            userId: regUserId,
            email: email,
            phone: phone,
            name: resolvedClinicName,
            realtimeToken: regRealtimeToken,
            realtimeTokenExpiresAt: regRealtimeExpiresAt,
            metadata: {
              'accountUserId': regUserId,
              'clinicId': resolvedClinicId,
              'clinicName': resolvedClinicName,
              'clinicAddress': resolvedClinicAddr,
              'location': resolvedClinicAddr.isNotEmpty ? resolvedClinicAddr : city,
              'city': city,
              'state': stateValue,
              'pincode': pincode,
              if (submittedLatitude != null) 'latitude': submittedLatitude,
              if (submittedLongitude != null) 'longitude': submittedLongitude,
            },
          );
        } else {
          final isSubAdmin = _selectedAdminRoleType == 'Sub-Admin' ||
              regUser['role']?.toString().toLowerCase().contains('sub') == true;

          if (isSubAdmin) {
            PatientProblemService().setSubAdminSession(
              id: regUserId,
              name: name,
              email: email,
              phone: phone,
              permissions: const [
                'ALL',
                'MANAGE_PATIENTS',
                'MANAGE_REQUESTS',
                'VIEW_DENTISTS',
                'MANAGE_CLINICS',
                'MANAGE_REFERRALS',
                'VIEW_RECORDS',
                'APPOINTMENTS'
              ],
              status: 'ACTIVE',
            );
          } else {
            PatientProblemService().clearSubAdminSession();
          }

          await SessionService().saveSession(
            token: regToken,
            role: isSubAdmin ? 'Sub-Admin' : 'Admin',
            userId: regUserId,
            email: email,
            phone: phone,
            name: name,
            realtimeToken: regRealtimeToken,
            realtimeTokenExpiresAt: regRealtimeExpiresAt,
            metadata: {
              'accountUserId': regUserId,
              'city': city,
              'pincode': pincode,
              'isSubAdmin': isSubAdmin,
              'department': _adminDeptController.text.trim(),
              'employeeId': _adminEmployeeIdController.text.trim(),
            },
          );
        }

        // Trigger background data sync without blocking UI navigation
        PatientProblemService().syncAllDataFromApi();
        if (!mounted) return;
        setState(() => _isRegistering = false);
        AnalyticsService.logRegistration(method: 'Mobile_OTP', role: chosenRole);

        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 Registered $chosenRole account successfully!'),
            backgroundColor: AppTheme.gsNavy,
            duration: const Duration(seconds: 2),
          ),
        );
        context.go(SessionService().currentSession?.targetRoute ?? _targetRoute);
      } else {
        final String errCode = (res['code'] ?? '').toString().toUpperCase();
        final String errMsg = (res['message'] ?? 'Could not register user.').toString();
        setState(() {
          _isRegistering = false;
          if (errCode.contains('PROFILE_IMAGE') || errMsg.toLowerCase().contains('profile image')) {
            _registrationImageError = errMsg;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ $errMsg'),
            backgroundColor: const Color(0xFFFE3434),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isRegistering = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Registration Error: $e'),
          backgroundColor: const Color(0xFFFE3434),
        ),
      );
    }
  }

  Future<void> _handleSendOtp() async {
    final rawPhone = _phoneController.text.trim();
    final phone = _normalizePhone(rawPhone);
    final email = _emailController.text.trim();

    if (rawPhone.isEmpty || !_isValidMobilePhone(rawPhone)) {
      setState(() {
        _otpErrorMessage = 'Please enter a valid 10-digit mobile phone number.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Please enter a valid 10-digit Mobile Phone Number to receive OTP.'),
          backgroundColor: Color(0xFFFE3434),
        ),
      );
      return;
    }

    setState(() {
      _isSendingOtp = true;
      _isOtpVerified = false;
      _otpErrorMessage = null;
      _verifiedPhone = phone;
      _verifiedEmail = email.toLowerCase();
    });

    bool sendSuccess = false;
    String successMsg = '';
    String? receivedOtp;

    // 1. Mobile Phone SMS OTP via Backend SMS Gateway & Supabase (or testing-only on-screen mode)
    if (phone.isNotEmpty) {
      final backendRes = await ApiService().requestOtp(phone: phone, email: email);
      sendSuccess = backendRes['success'] == true;

      if (sendSuccess) {
        final bool canShowOnScreenOtp = ApiConstants.allowOnScreenOtpDisplay &&
            backendRes['deliveryMode'] == 'on_screen';
        final rawCode = canShowOnScreenOtp ? backendRes['otp']?.toString().trim() : null;
        if (rawCode != null && RegExp(r'^\d{6}$').hasMatch(rawCode)) {
          receivedOtp = rawCode;
        }
        successMsg = receivedOtp != null
            ? 'Test verification code: $receivedOtp'
            : (backendRes['message']?.toString() ?? 'OTP sent successfully to your mobile number.');
      } else {
        _otpErrorMessage = backendRes['message']?.toString() ?? 'Failed to send OTP SMS. Please check your mobile number.';
      }
    }

    // 2. Email OTP via Supabase Auth & Supabase Email Service
    if (email.isNotEmpty) {
      if (sendSuccess) {
        SupabaseService().sendEmailOtp(email);
      } else {
        final supabaseRes = await SupabaseService().sendEmailOtp(email);
        final emailSent = supabaseRes['success'] == true;
        sendSuccess = sendSuccess || emailSent;
        if (emailSent && successMsg.isEmpty) {
          successMsg = 'OTP sent to your email address.';
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _isSendingOtp = false;
      if (sendSuccess) {
        _isOtpSent = true;
        _currentRegistrationOtp = receivedOtp;
        _otpController.clear();
      }
    });

    if (sendSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMsg.isNotEmpty ? successMsg : 'OTP sent successfully.'),
          backgroundColor: AppTheme.gsNavy,
          duration: const Duration(seconds: 6),
        ),
      );
    } else {
      setState(() {
        _otpErrorMessage ??= 'Unable to send OTP. Please check your mobile number and try again.';
      });
    }
  }

  Future<void> _handleVerifyOtp() async {
    final code = _otpController.text.trim();
    if (code.length != 6) {
      setState(() => _otpErrorMessage = 'Please enter the 6-digit OTP code.');
      return;
    }

    final rawPhone = _phoneController.text.trim();
    final phone = _normalizePhone(rawPhone);
    final email = _emailController.text.trim();

    if (rawPhone.isEmpty || !_isValidMobilePhone(rawPhone)) {
      setState(() {
        _isOtpVerified = false;
        _isOtpSent = false;
        _otpErrorMessage = 'Please enter a valid 10-digit mobile number.';
      });
      return;
    }

    if (_verifiedPhone != null && _verifiedPhone != phone) {
      setState(() {
        _isOtpVerified = false;
        _isOtpSent = false;
        _otpErrorMessage = 'Mobile number changed. Please send a new OTP.';
      });
      return;
    }

    setState(() {
      _isVerifyingOtp = true;
      _otpErrorMessage = null;
    });

    bool verified = false;
    String? errorReason;
    Map<String, dynamic>? verifiedResponse;

    // 1. Mobile Phone SMS OTP verification via Backend API
    if (phone.isNotEmpty) {
      final res = await ApiService().verifyOtp(phone: phone, email: email, code: code);
      verified = res['success'] == true;
      if (verified) {
        verifiedResponse = res;
      } else {
        errorReason = res['message']?.toString();
      }
    }

    // 2. Email OTP verification via Supabase Auth
    if (!verified && email.isNotEmpty) {
      final supabaseVerify = await SupabaseService().verifyEmailOtp(email: email, token: code);
      verified = supabaseVerify['success'] == true;
      if (!verified && errorReason == null) {
        errorReason = supabaseVerify['message']?.toString();
      }
    }

    if (!mounted) return;
    setState(() => _isVerifyingOtp = false);

    if (verified) {
      AnalyticsService.logOtpVerification(status: 'verified', method: phone.isNotEmpty ? 'SMS_Mobile_OTP' : 'Email_OTP');
      if (verifiedResponse != null &&
          verifiedResponse['user'] is Map &&
          (verifiedResponse['accessToken']?.toString().trim().isNotEmpty ?? false)) {
        _loginEmailController.text = phone;
        await _handleLogin(
          verifiedOtpCode: code,
          otpAlreadyVerified: true,
          verifiedOtpResponse: verifiedResponse,
        );
        return;
      }
      setState(() {
        _isOtpVerified = true;
        _verifiedPhone = phone;
        _verifiedEmail = email.toLowerCase();
        _otpErrorMessage = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 OTP verified successfully! You can now complete registration.'),
          backgroundColor: AppTheme.gsNavy,
        ),
      );
    } else {
      setState(() => _otpErrorMessage = errorReason ?? 'Invalid or expired OTP code.');
    }
  }

  Widget _buildOtpVerificationSection() {
    return Container(
      key: const Key('reg_mobile_otp_card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isOtpVerified
              ? AppTheme.gsNavy.withValues(alpha: 0.3)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.phone_android_rounded, color: AppTheme.gsRed, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'MOBILE NUMBER & OTP VERIFICATION',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 0.6,
                    color: AppTheme.gsNavy,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _isOtpVerified ? const Color(0x14012A58) : const Color(0x14FE3434),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: (_isOtpVerified ? AppTheme.gsNavy : AppTheme.gsRed).withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  _isOtpVerified ? 'VERIFIED' : 'REQUIRED',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: _isOtpVerified ? AppTheme.gsNavy : AppTheme.gsRed,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('reg_phone_field'),
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            scrollPadding: const EdgeInsets.only(bottom: 120),
            style: const TextStyle(color: Color(0xFF0F172A), fontSize: 14, fontWeight: FontWeight.w600),
            validator: (val) {
              if (val == null || val.trim().isEmpty) return 'Mobile phone number is mandatory';
              if (!_isValidMobilePhone(val)) return 'Enter valid 10-digit mobile number';
              return null;
            },
            decoration: InputDecoration(
              hintText: '+91 98765 43210',
              hintStyle: const TextStyle(fontSize: 14, color: Color(0xFF94A3B8)),
              prefixIcon: const Icon(Icons.call_outlined, color: AppTheme.gsNavy, size: 18),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.gsNavy, width: 1.6),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (!_isOtpSent && !_isOtpVerified) ...[
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                key: const Key('reg_send_otp_button'),
                icon: _isSendingOtp
                    ? const SizedBox(
                        height: 14,
                        width: 14,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.send_to_mobile_rounded, size: 16),
                label: Text(
                  _isSendingOtp ? 'Sending OTP...' : 'Send verification code',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.gsNavy,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _isSendingOtp ? null : _handleSendOtp,
              ),
            ),
            if (_otpErrorMessage != null) ...[
              const SizedBox(height: 6),
              Text(
                _otpErrorMessage!,
                style: const TextStyle(color: AppTheme.gsRed, fontSize: 11.5, fontWeight: FontWeight.w600),
              ),
            ],
          ] else if (!_isOtpVerified && _isOtpSent) ...[
            if (ApiConstants.allowOnScreenOtpDisplay &&
                _currentRegistrationOtp != null &&
                _currentRegistrationOtp!.isNotEmpty) ...[
              Container(
                key: const Key('reg_onscreen_otp_banner'),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0x14012A58),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.pin_outlined, size: 18, color: Color(0xFF012A58)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your verification code: $_currentRegistrationOtp',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF012A58),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      key: const Key('reg_otp_fill_button'),
                      onTap: () {
                        setState(() {
                          _otpController.text = _currentRegistrationOtp!;
                        });
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppTheme.gsNavy,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Fill',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    key: const Key('reg_otp_code_field'),
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    scrollPadding: const EdgeInsets.only(bottom: 120),
                    style: const TextStyle(color: Color(0xFF0F172A), fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 3),
                    decoration: InputDecoration(
                      hintText: '6-digit OTP code',
                      hintStyle: const TextStyle(letterSpacing: 0, fontSize: 13, color: AppTheme.textMuted),
                      counterText: '',
                      filled: true,
                      fillColor: Colors.white,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppTheme.gsNavy, width: 1.5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton(
                      key: const Key('reg_verify_otp_button'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.gsNavy,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _isVerifyingOtp ? null : _handleVerifyOtp,
                      child: _isVerifyingOtp
                          ? const SizedBox(
                              height: 14,
                              width: 14,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('Verify', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                ),
              ],
            ),
            if (_otpErrorMessage != null) ...[
              const SizedBox(height: 6),
              Text(
                _otpErrorMessage!,
                style: const TextStyle(color: AppTheme.gsRed, fontSize: 11.5, fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 6),
            InkWell(
              onTap: _handleSendOtp,
              child: const Text(
                'Resend verification code',
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppTheme.gsNavy,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ] else ...[
            const Text(
              'Mobile verified. Tap Continue below to finish creating your account.',
              style: TextStyle(fontSize: 12, color: AppTheme.gsNavy, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_tabController.index == 0) {
      return _buildRegistrationScaffold(context);
    }
    return _buildHeroSignInScaffold(context);
  }

  // ================= HERO LAUNCH / SIGN IN VIEW (Based on Reference UI) =================
  Widget _buildHeroSignInScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 900) {
            return _buildDesktopHeroSignIn(context, constraints);
          }
          return _buildMobileHeroSignIn(context, constraints);
        },
      ),
    );
  }

  Widget _buildMobileHeroSignIn(BuildContext context, BoxConstraints constraints) {
    final screenHeight = constraints.maxHeight;
    final heroHeight = (screenHeight * 0.44).clamp(280.0, 400.0);

    return SafeArea(
      top: false,
      bottom: true,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. HERO SECTION WITH IMAGE & OVERLAY
            Stack(
              children: [
                SizedBox(
                  height: heroHeight,
                  width: double.infinity,
                  child: const GsHealthHeroBanner(fit: BoxFit.cover),
                ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.15),
                          Colors.black.withValues(alpha: 0.85),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 40,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Calm, expert medical care.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'AI triage, verified doctors across all specialties, and your records, all in one place.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w400,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // 2. OVERLAPPING WHITE LOGIN CARD
            Transform.translate(
              offset: const Offset(0, -22),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 18,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
                child: _buildLoginCardContent(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopHeroSignIn(BuildContext context, BoxConstraints constraints) {
    return Row(
      children: [
        // Left Hero Column (54% width)
        Expanded(
          flex: 12,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const GsHealthHeroBanner(fit: BoxFit.cover),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.30),
                      Colors.black.withValues(alpha: 0.85),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 48,
                right: 48,
                bottom: 64,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Comprehensive, expert medical care.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 38,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'AI triage, verified doctors across all specialties, and your records, all in one place.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      children: [
                        _buildFeaturePill('Verified Doctors', Icons.verified_user_rounded),
                        _buildFeaturePill('All Medical Specialties', Icons.medical_services_rounded),
                        _buildFeaturePill('Health Records & AI', Icons.health_and_safety_rounded),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Right Sign In Card Column (46% width)
        Expanded(
          flex: 10,
          child: Container(
            color: Colors.white,
            alignment: Alignment.center,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: _buildLoginCardContent(context),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFeaturePill(String title, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginCardContent(BuildContext context) {
    return Form(
      key: _loginFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Centered Official GS HEALTH Logo
          const Center(
            child: GsHealthLogo(
              height: 42,
              alignment: Alignment.center,
            ),
          ),
          const SizedBox(height: 20),

          // Heading & Subtitle
          Text(
            _isLoginOtpSent ? 'Enter your code' : 'Sign in with mobile',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1E293B),
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _isLoginOtpSent
                ? 'Sent to +91 ${_maskPhone(_loginEmailController.text)}'
                : "We'll text you a one-time code.",
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 16),

          if (!_isLoginOtpSent) ...[
            _buildSignInRoleSelector(),
            const SizedBox(height: 16),
          ],

          // Stage 1: Mobile Number Input
          if (!_isLoginOtpSent) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Country Code Selector
                Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    '+91',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Mobile Number Field
                Expanded(
                  child: TextFormField(
                    controller: _loginEmailController,
                    enabled: !_isLoggingIn && !_isSendingLoginCode,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      _IndianMobileInputFormatter(),
                    ],
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _handleSendLoginCode(),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E293B),
                      letterSpacing: 0.5,
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Please enter mobile number';
                      }
                      if (_normalizePhone(val).length != 10) {
                        return 'Please enter 10 digits';
                      }
                      return null;
                    },
                    decoration: InputDecoration(
                      hintText: '98765 43210',
                      hintStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF94A3B8),
                        letterSpacing: 0.5,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.gsNavy, width: 2),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Primary "Send code" Button
            SizedBox(
              height: 52,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_isLoggingIn || _isSendingLoginCode) ? null : _handleSendLoginCode,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.gsNavy,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: (_isSendingLoginCode || _isLoggingIn)
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Send code',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ] else ...[
            // Stage 2: OTP Verification Field
            if (_loginOtpErrorMessage != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0x14FE3434),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0x40FE3434)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Color(0xFFFE3434), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _loginOtpErrorMessage!,
                        style: const TextStyle(fontSize: 12.5, color: Color(0xFFFE3434), fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            _buildSixDigitOtpInput(),

            if (ApiConstants.allowOnScreenOtpDisplay &&
                _currentLoginOtp != null &&
                _currentLoginOtp!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                key: const Key('login_onscreen_otp_banner'),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: const Color(0x14012A58),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.pin_outlined, size: 20, color: Color(0xFF012A58)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Your verification code: $_currentLoginOtp',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF012A58),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      key: const Key('login_otp_fill_button'),
                      onTap: () => _fillLoginOtp(_currentLoginOtp),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.gsNavy,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Fill',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: TextButton(
                    onPressed: () {
                      setState(() {
                        _isLoginOtpSent = false;
                        _loginOtpErrorMessage = null;
                        _currentLoginOtp = null;
                        for (final c in _otpDigitControllers) {
                          c.clear();
                        }
                      });
                    },
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(50, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      '← Edit mobile number',
                      style: TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (!_canResendOtp)
                  Flexible(
                    child: Text(
                      'Resend code in ${_resendCountdown}s',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  Flexible(
                    child: TextButton(
                      onPressed: _isSendingLoginCode ? null : _handleSendLoginCode,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(50, 30),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Resend code',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF012A58)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // Verify & continue Button
            SizedBox(
              height: 52,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_isVerifyingLoginCode || _isLoggingIn) ? null : _handleVerifyLoginCode,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.gsNavy,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: (_isVerifyingLoginCode || _isLoggingIn)
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2),
                      )
                    : const Text(
                        'Verify & continue',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Registration and Switch Link
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  "Don't have an account?",
                  style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _tabController.index = 0;
                    });
                  },
                  child: const Text(
                    'Register here',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF012A58),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Terms of Use and Privacy Policy Footer
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'By continuing you agree to our ',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF94A3B8),
                  ),
                ),
                GestureDetector(
                  onTap: () => _showTermsDialog(context),
                  child: const Text(
                    'Terms of Use',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF012A58),
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                const Text(
                  ' and ',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF94A3B8),
                  ),
                ),
                GestureDetector(
                  onTap: () => _showPrivacyDialog(context),
                  child: const Text(
                    'Privacy Policy',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF012A58),
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildRegistrationScaffold(BuildContext context) {
    final service = PatientProblemService();
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) => _buildRegistrationView(service),
    );
  }

  List<GsRegistrationClinicOption> _registeredClinicOptions(PatientProblemService service) {
    final seen = <String>{};
    final options = <GsRegistrationClinicOption>[];
    for (final c in service.allClinics) {
      final name = c.clinicName.trim();
      final status = c.verificationStatus.trim().toUpperCase();
      if (name.isEmpty || status == 'REJECTED' || status == 'SUSPENDED') continue;
      if (!seen.add(name.toLowerCase())) continue;
      options.add(GsRegistrationClinicOption(id: c.id, name: name, location: c.location.trim()));
    }
    return options;
  }

  Widget _buildRegistrationView(PatientProblemService service) {
    // Dental specialties first (matches reference chip order), followed by every
    // other active specialty already supported by the platform.
    final specialtyOptions = <String>{
      'General Dentistry',
      'Orthodontics',
      'Endodontics',
      'Periodontics',
      'Pediatric Dentistry',
      'Oral & Maxillofacial Surgery',
      'Prosthodontics',
      ...service.activeSpecialtyNames,
    }.toList();

    return GsHealthRegistrationView(
      formKey: _registerFormKey,
      selectedRole: _selectedRole,
      isAuthorizedAdminPortal: widget.allowAdminRole == true,
      isOtpVerified: _isOtpVerified,
      verifiedPhone: _verifiedPhone,
      isRegistering: _isRegistering,
      nameController: _nameController,
      cityController: _cityController,
      stateController: _stateController,
      pincodeController: _pincodeController,
      emailController: _emailController,
      phoneController: _phoneController,
      locationController: _locationController,
      licenseNoController: _licenseNoController,
      qualificationController: _qualificationController,
      clinicNameController: _clinicNameController,
      clinicAddressController: _clinicAddressController,
      experienceController: _experienceController,
      adminEmployeeIdController: _adminEmployeeIdController,
      adminDeptController: _adminDeptController,
      selectedAdminRoleType: _selectedAdminRoleType,
      selectedSpecialty: _selectedSpecialty,
      specialtyOptions: specialtyOptions,
      selectedLanguages: _selectedLanguages,
      selectedLatitude: _selectedLatitude,
      selectedLongitude: _selectedLongitude,
      selectedMapLocationName: _selectedMapLocationName,
      mapLocationErrorText: _mapLocationError,
      onClearMapLocation: () {
        setState(() {
          _selectedLatitude = null;
          _selectedLongitude = null;
          _selectedMapLocationName = null;
        });
      },
      pickedImageBytes: _pickedImageBytes,
      pickedImageName: _pickedImageName,
      mobileOtpSectionBuilder: _buildOtpVerificationSection,
      onRoleSelected: (role) {
        setState(() {
          _selectedRole = role;
          _isAdminMode = widget.allowAdminRole == true && role == UserRole.admin;
        });
        if (role == UserRole.dentist && service.allClinics.isEmpty) {
          // Refresh registered clinics so the dentist can associate with one.
          service.syncClinicsFromApi();
        }
      },
      onLanguageToggled: _toggleLanguage,
      onAdminRoleTypeChanged: (type) {
        setState(() => _selectedAdminRoleType = type);
      },
      onSpecialtyChanged: (specialty) {
        setState(() {
          final previousDefault = MedicalSpecialtyModel.getDefaultQualificationForSpecialty(
            _selectedSpecialty ?? 'General Medicine',
          );
          final currentQual = _qualificationController.text.trim();
          _selectedSpecialty = specialty;
          // Suggest the specialty's typical qualification without overwriting
          // anything the dentist has typed themselves.
          if (currentQual.isEmpty || currentQual == previousDefault) {
            _qualificationController.text =
                MedicalSpecialtyModel.getDefaultQualificationForSpecialty(specialty);
          }
        });
      },
      clinicOptions: _registeredClinicOptions(service),
      onClinicSelected: (clinic) {
        setState(() {
          if (clinic == null) {
            _selectedClinicId = null;
            _clinicNameController.clear();
            _clinicAddressController.clear();
          } else {
            _selectedClinicId = clinic.id.isNotEmpty ? clinic.id : null;
            _clinicNameController.text = clinic.name;
            _clinicAddressController.text = clinic.location;
          }
        });
      },
      onPickImage: () => _pickRegistrationImage(ImageSource.gallery),
      onPickCameraImage: () => _pickRegistrationImage(ImageSource.camera),
      onRemoveImage: _removeRegistrationImage,
      imageErrorText: _registrationImageError,
      onOpenMapPicker: _openMapLocationPicker,
      onContinuePressed: _handleRegister,
      onUseAnotherNumber: () {
        setState(() {
          _isOtpVerified = false;
          _isOtpSent = false;
          _verifiedPhone = null;
          _verifiedEmail = null;
          _currentRegistrationOtp = null;
          _otpErrorMessage = null;
          _otpController.clear();
          _phoneController.clear();
          _loginEmailController.clear();
          _isLoginOtpSent = false;
          _loginOtpErrorMessage = null;
          _currentLoginOtp = null;
          for (final c in _otpDigitControllers) {
            c.clear();
          }
          _tabController.index = 1;
        });
      },
      onOpenAdminSignIn: () {
        setState(() {
          _selectedRole = UserRole.admin;
          _isAdminMode = true;
          _isLoginOtpSent = false;
          _loginOtpErrorMessage = null;
          _tabController.index = 1;
        });
      },
    );
  }

  Widget _buildSignInRoleSelector() {
    return Container(
      key: const Key('signin_role_selector'),
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          _buildLoginRoleOption(
            UserRole.patient,
            'Patient',
            Icons.person_rounded,
            AppTheme.gsNavy,
          ),
          const SizedBox(width: 5),
          _buildLoginRoleOption(
            UserRole.dentist,
            'Doctor',
            Icons.medical_services_rounded,
            AppTheme.gsNavy,
          ),
          const SizedBox(width: 5),
          _buildLoginRoleOption(
            UserRole.clinic,
            'Clinic',
            Icons.add_box_rounded,
            AppTheme.gsRed,
          ),
        ],
      ),
    );
  }

  Widget _buildLoginRoleOption(
    UserRole role,
    String label,
    IconData icon,
    Color roleAccent,
  ) {
    final bool isSelected = _selectedRole == role;
    return Expanded(
      child: GestureDetector(
        key: Key('signin_role_${role.name}'),
        onTap: () {
          setState(() {
            _selectedRole = role;
            _isAdminMode = false;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            border: isSelected
                ? Border.all(color: const Color(0xFFCBD5E1), width: 1.0)
                : Border.all(color: Colors.transparent),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : const [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(4.5),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFF1F5F9)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(
                  icon,
                  size: 15,
                  color: isSelected ? const Color(0xFF012A58) : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF475569),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openMapLocationPicker() {
    final bool useClinicController =
        _selectedRole == UserRole.dentist || _selectedRole == UserRole.clinic;
    MapLocationPickerDialog.show(
      context: context,
      initialAddress: useClinicController
          ? _clinicAddressController.text
          : _locationController.text,
      initialCity: _cityController.text,
      initialState: _stateController.text,
      initialPincode: _pincodeController.text,
      initialLat: _selectedLatitude,
      initialLng: _selectedLongitude,
      isDentist: useClinicController,
      onSelectionConfirmed: (result) {
        setState(() {
          if (result.address.isNotEmpty) {
            if (useClinicController) {
              _clinicAddressController.text = result.address;
            } else {
              _locationController.text = result.address;
            }
          }
          if (result.city.isNotEmpty) _cityController.text = result.city;
          if (result.state.isNotEmpty) _stateController.text = result.state;
          if (result.pincode.isNotEmpty) _pincodeController.text = result.pincode;
          _selectedLatitude = result.latitude;
          _selectedLongitude = result.longitude;
          _selectedMapLocationName = result.locationName;
          _mapLocationError = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '📍 Clinic map location pinned (${result.latitude.toStringAsFixed(4)}, ${result.longitude.toStringAsFixed(4)})',
            ),
            backgroundColor: AppTheme.gsNavy,
            duration: const Duration(seconds: 2),
          ),
        );
      },
    );
  }
}