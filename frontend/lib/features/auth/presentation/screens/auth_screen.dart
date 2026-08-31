import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/denta_guru_logo.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/services/session_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Role enum for authentication
enum UserRole { patient, dentist, admin }

class AuthScreen extends StatefulWidget {
  final String? initialRole; // 'Patient', 'Dentist', 'Admin'
  final int initialTab; // 0 for Sign In, 1 for Register

  const AuthScreen({
    super.key,
    this.initialRole,
    this.initialTab = 0,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late UserRole _selectedRole;

  // Controllers for Sign In
  final _loginFormKey = GlobalKey<FormState>();
  final _loginEmailController = TextEditingController();
  bool _isLoggingIn = false;

  // Controllers for Registration
  final _registerFormKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isRegistering = false;

  // Common & Location Fields
  final _cityController = TextEditingController();
  final _pincodeController = TextEditingController();
  final _locationController = TextEditingController();

  // Role-Specific Fields - Patient
  final _ageController = TextEditingController();
  final _emergencyContactController = TextEditingController();
  final _referralCodeController = TextEditingController();
  String? _selectedGender;
  String? _selectedBloodGroup;

  // Role-Specific Fields - Dentist
  final _licenseNoController = TextEditingController();
  final _clinicNameController = TextEditingController();
  final _experienceController = TextEditingController(text: '5');
  final _clinicAddressController = TextEditingController();
  String? _selectedSpecialty;

  // Languages Selection
  static const List<String> _availableLanguages = [
    'English', 'Hindi', 'Telugu', 'Tamil', 'Kannada', 'Malayalam', 'Marathi', 'Bengali', 'Gujarati', 'Punjabi', 'Spanish'
  ];
  String? _selectedLanguage;

  // Profile Image Picker Bytes
  Uint8List? _pickedImageBytes;
  String? _pickedImageName;

  // OTP Verification States for Registration Flow
  bool _isOtpVerified = false;
  bool _isOtpSent = false;
  bool _isSendingOtp = false;
  bool _isVerifyingOtp = false;
  final _otpController = TextEditingController();
  String? _otpErrorMessage;
  String? _currentExpectedOtp;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: widget.initialTab);
    _tabController.addListener(() {
      // In registration tab, Admin / Sub-Admin are not allowed; automatically switch to Patient
      if (_tabController.index == 1 && _selectedRole == UserRole.admin) {
        _selectedRole = UserRole.patient;
      }
      setState(() {});
    });

    // Auto-populate referral code if opened with ?ref=... parameter
    try {
      final refParam = Uri.base.queryParameters['ref'];
      if (refParam != null && refParam.trim().isNotEmpty) {
        _referralCodeController.text = refParam.trim().toUpperCase();
      }
    } catch (_) {}

    // Initialize selected role from widget param or default to Patient
    final roleStr = (widget.initialRole ?? 'Patient').toLowerCase();
    if (roleStr == 'dentist') {
      _selectedRole = UserRole.dentist;
    } else if (roleStr == 'admin' || roleStr == 'sub-admin' || roleStr == 'subadmin') {
      // Admin/Sub-Admin are only accessible through sign-in portal, not registration
      if (widget.initialTab == 1) {
        _selectedRole = UserRole.patient;
      } else {
        _selectedRole = UserRole.admin;
      }
    } else {
      _selectedRole = UserRole.patient;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginEmailController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _ageController.dispose();
    _emergencyContactController.dispose();
    _referralCodeController.dispose();
    _licenseNoController.dispose();
    _clinicNameController.dispose();
    _experienceController.dispose();
    _clinicAddressController.dispose();
    _pincodeController.dispose();
    _locationController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  String get _roleName {
    switch (_selectedRole) {
      case UserRole.patient:
        return 'Patient';
      case UserRole.dentist:
        return 'Dentist';
      case UserRole.admin:
        return 'Admin';
    }
  }

  Color get _accentColor {
    switch (_selectedRole) {
      case UserRole.patient:
        return AppTheme.primaryBlue; // #0052CC
      case UserRole.dentist:
        return const Color(0xFF0D9488); // Teal
      case UserRole.admin:
        return const Color(0xFF6366F1); // Indigo
    }
  }

  IconData get _roleIcon {
    switch (_selectedRole) {
      case UserRole.patient:
        return Icons.person_rounded;
      case UserRole.dentist:
        return Icons.medical_services_rounded;
      case UserRole.admin:
        return Icons.admin_panel_settings_rounded;
    }
  }

  String get _targetRoute {
    switch (_selectedRole) {
      case UserRole.patient:
        return '/patient';
      case UserRole.dentist:
        return '/dentist';
      case UserRole.admin:
        return '/admin';
    }
  }

  Future<void> _pickGalleryImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 800,
      );
      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _pickedImageBytes = bytes;
          _pickedImageName = image.name;
        });
      }
    } catch (e) {
      debugPrint('Error picking gallery photo: $e');
    }
  }

  Future<void> _handleLogin() async {
    if (!_loginFormKey.currentState!.validate()) return;

    final identifier = _loginEmailController.text.trim();

    setState(() => _isLoggingIn = true);

    try {
      final res = await ApiService().loginUser(
        email: identifier,
        phone: identifier,
        role: _roleName,
      );

      if (!mounted) return;
      setState(() => _isLoggingIn = false);

      if (res['success'] == true) {
        final Map<String, dynamic> responseData = res['data'] is Map<String, dynamic> ? res['data'] : {};
        final Map<String, dynamic> userData = (responseData['user'] is Map<String, dynamic>)
            ? responseData['user']
            : (res['user'] is Map<String, dynamic> ? res['user'] : {});

        final String registeredRole = (userData['role'] ?? _roleName).toString().toLowerCase();

        // ⛔ ENFORCE STRICT PORTAL ROLE MATCHING (Sub-Admin is also valid for Admin portal)
        final bool isSelAdmin = _selectedRole == UserRole.admin;
        final bool isSelDentist = _selectedRole == UserRole.dentist;
        final bool isSelPatient = _selectedRole == UserRole.patient;

        final bool isRegAdmin = registeredRole.contains('admin');
        final bool isRegSubAdmin = registeredRole.contains('sub-admin') || registeredRole.contains('subadmin');
        final bool isRegDentist = registeredRole.contains('dentist') || registeredRole.contains('doctor');
        final bool isRegPatient = registeredRole.contains('patient');

        // Sub-admins should be treated as admin-class for portal routing
        if ((isSelAdmin && !isRegAdmin && !isRegSubAdmin) || (isSelDentist && !isRegDentist) || (isSelPatient && !isRegPatient)) {
          final displayRole = userData['role'] ?? (isRegDentist ? 'Dentist' : (isRegAdmin || isRegSubAdmin ? 'Admin' : 'Patient'));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⛔ Access Denied: This account is registered as a $displayRole. Please switch to the $displayRole tab to sign in.'),
              backgroundColor: const Color(0xFFEF4444),
              duration: const Duration(seconds: 4),
            ),
          );
          return;
        }

        final String? returnedPhoto = userData['profilePhoto'];
        Uint8List? photoBytes;
        if (returnedPhoto != null && returnedPhoto.trim().isNotEmpty) {
          try {
            final base64Str = returnedPhoto.contains(',') ? returnedPhoto.split(',').last : returnedPhoto;
            photoBytes = base64Decode(base64Str.trim());
            debugPrint('✅ Successfully decoded user profile photo (${photoBytes.length} bytes)');
          } catch (e) {
            debugPrint('❌ Error decoding returned user photo: $e');
          }
        }

        final userPhone = (userData['phone'] != null && userData['phone'].toString().isNotEmpty)
            ? userData['phone'].toString()
            : (_phoneController.text.trim().isNotEmpty
                ? _phoneController.text.trim()
                : (!identifier.contains('@') && identifier.isNotEmpty ? identifier : ''));

        final String effectiveToken = (responseData['accessToken'] ?? res['accessToken'] ?? res['token'] ?? 'sb_session_${userData['id'] ?? DateTime.now().millisecondsSinceEpoch}').toString();
        final String effectiveUserId = (userData['id'] ?? Supabase.instance.client.auth.currentUser?.id ?? 'user_${DateTime.now().millisecondsSinceEpoch}').toString();
        final String effectiveEmail = userData['email'] ?? (identifier.contains('@') ? identifier : '');
        final String effectiveName = (userData['name'] != null && userData['name'].toString().trim().isNotEmpty)
            ? userData['name'].toString().trim()
            : (effectiveEmail.contains('@') ? effectiveEmail.split('@').first : identifier);

        AnalyticsService.logLogin(method: 'Direct_Contact_Login', role: _roleName);

        if (registeredRole.contains('dentist') || registeredRole.contains('doctor')) {
          final docName = (userData['name'] != null && userData['name'].toString().trim().isNotEmpty)
              ? userData['name'].toString().trim()
              : (userData['email'] != null ? userData['email'].toString() : identifier);
          final docId = (userData['id'] ?? Supabase.instance.client.auth.currentUser?.id ?? '').toString();
          
          PatientProblemService().registerDoctor(
            id: docId,
            name: docName,
            email: userData['email'] ?? (identifier.contains('@') ? identifier : ''),
            phone: userPhone,
            licenseNumber: 'DEN-LIC-REGISTERED',
            specialty: 'General Dentistry',
            clinicName: userData['clinicName'] ?? '',
            experienceYears: 5,
            photoBytes: photoBytes,
          );
          await SessionService().saveSession(
            token: effectiveToken,
            role: 'Dentist',
            userId: docId,
            email: effectiveEmail,
            phone: userPhone,
            name: docName,
            metadata: {
              ...userData,
              'clinicName': userData['clinicName'] ?? '',
              'specialty': 'General Dentistry',
            },
          );
          await PatientProblemService().syncAllDataFromApi();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🎉 Welcome back, ${userData['name'] ?? 'Doctor'}! Logging into Dentist Workspace...'),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
          context.go('/dentist');
        } else if (registeredRole.contains('admin') || registeredRole.contains('sub-admin') || registeredRole.contains('subadmin') || registeredRole.contains('sub_admin')) {
          final isSubAdmin = registeredRole.contains('sub-admin') || registeredRole.contains('subadmin') || registeredRole.contains('sub_admin') || (userData['email'] != 'anusripvc202@gmail.com' && (userData['role']?.toString().toLowerCase().contains('sub') ?? false));

          if (isSubAdmin) {
            List<String> perms = [];
            if (userData['permissions'] is List) {
              perms = List<String>.from((userData['permissions'] as List).map((e) => e.toString()));
            }
            PatientProblemService().setSubAdminSession(
              id: userData['id']?.toString() ?? '',
              name: userData['name']?.toString() ?? 'Sub-Admin',
              email: userData['email']?.toString() ?? (identifier.contains('@') ? identifier : ''),
              phone: userData['phone']?.toString() ?? userPhone,
              permissions: perms,
              status: userData['status']?.toString() ?? 'ACTIVE',
            );
          } else {
            PatientProblemService().clearSubAdminSession();
          }
          await SessionService().saveSession(
            token: effectiveToken,
            role: isSubAdmin ? 'Sub-Admin' : 'Admin',
            userId: effectiveUserId,
            email: effectiveEmail,
            phone: userPhone,
            name: effectiveName,
            metadata: {
              ...userData,
              'isSubAdmin': isSubAdmin,
            },
          );
          await PatientProblemService().syncAllDataFromApi();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🎉 Welcome back, ${userData['name'] ?? 'Admin'}! Opening Admin Dashboard...'),
              backgroundColor: const Color(0xFF6366F1),
            ),
          );
          context.go('/admin');
        } else {
          // Patient Role
          final prefs = await SharedPreferences.getInstance();
          final userEmailKey = (userData['email'] ?? (identifier.contains('@') ? identifier : '')).toString().trim().toLowerCase();
          final cachedProfileStr = prefs.getString('dentaguru_patient_profile_$userEmailKey') ?? prefs.getString('dentaguru_patient_profile');
          Map<String, dynamic> cachedMap = {};
          if (cachedProfileStr != null && cachedProfileStr.isNotEmpty) {
            try {
              cachedMap = jsonDecode(cachedProfileStr);
            } catch (_) {}
          }

          Map<String, dynamic> dbProfileMeta = {};
          try {
            var q = Supabase.instance.client.from('users').select('device_token, city, pincode, state');
            final uRow = identifier.contains('@') ? await q.ilike('email', identifier).maybeSingle() : await q.eq('phone', identifier).maybeSingle();
            if (uRow != null && uRow['device_token'] != null && uRow['device_token'].toString().startsWith('{')) {
              dbProfileMeta = jsonDecode(uRow['device_token'].toString());
            }
          } catch (_) {}

          final authMeta = Supabase.instance.client.auth.currentUser?.userMetadata ?? {};
          final String loginAge = (userData['age'] ?? dbProfileMeta['age'] ?? cachedMap['age'] ?? authMeta['age'] ?? authMeta['patient_age'] ?? '').toString();
          final String loginGender = (userData['gender'] ?? dbProfileMeta['gender'] ?? cachedMap['gender'] ?? authMeta['gender'] ?? 'Female').toString();
          final String loginBloodGroup = (userData['bloodGroup'] ?? userData['blood_group'] ?? dbProfileMeta['bloodGroup'] ?? cachedMap['bloodGroup'] ?? authMeta['bloodGroup'] ?? 'O Positive (O+)').toString();
          final String loginEmergency = (userData['emergencyContact'] ?? userData['emergency_contact'] ?? dbProfileMeta['emergencyContact'] ?? cachedMap['emergencyContact'] ?? authMeta['emergencyContact'] ?? userPhone).toString();

          PatientProblemService().updatePatientProfile(
            id: userData['id']?.toString() ?? '',
            name: userData['name'] ?? (identifier.contains('@') ? identifier.split('@').first : 'Patient'),
            email: userData['email'] ?? (identifier.contains('@') ? identifier : ''),
            phone: userPhone,
            age: loginAge.isNotEmpty ? loginAge : '',
            gender: loginGender.isNotEmpty ? loginGender : 'Female',
            bloodGroup: loginBloodGroup.isNotEmpty ? loginBloodGroup : 'O Positive (O+)',
            emergencyContact: loginEmergency.isNotEmpty ? loginEmergency : userPhone,
            city: (userData['city'] ?? dbProfileMeta['city'] ?? cachedMap['city'] ?? '').toString(),
            pincode: (userData['pincode'] ?? dbProfileMeta['pincode'] ?? cachedMap['pincode'] ?? '').toString(),
            photoBytes: photoBytes,
          );
          await SessionService().saveSession(
            token: effectiveToken,
            role: 'Patient',
            userId: effectiveUserId,
            email: effectiveEmail,
            phone: userPhone,
            name: effectiveName,
            metadata: {
              ...userData,
              'age': loginAge,
              'gender': loginGender,
              'bloodGroup': loginBloodGroup,
              'emergencyContact': loginEmergency,
              'city': (userData['city'] ?? dbProfileMeta['city'] ?? cachedMap['city'] ?? '').toString(),
              'pincode': (userData['pincode'] ?? dbProfileMeta['pincode'] ?? cachedMap['pincode'] ?? '').toString(),
            },
          );
          await PatientProblemService().syncAllDataFromApi();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🎉 Welcome back, ${userData['name'] ?? 'Patient'}! Logging into Patient Portal...'),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
          context.go('/patient');
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Login Failed: ${res['message'] ?? 'User not registered. Please Register first.'}'),
            backgroundColor: const Color(0xFFEF4444),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('Login Error: $e');
      if (!mounted) return;
      setState(() => _isLoggingIn = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Network error during login: $e'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  void _handleRegister() async {
    if (!_registerFormKey.currentState!.validate()) return;
    setState(() => _isRegistering = true);

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final registeredAge = _ageController.text.trim();

    if (_selectedRole == UserRole.admin && email.isNotEmpty && email.toLowerCase() != 'anusripvc202@gmail.com') {
      setState(() => _isRegistering = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⛔ Access Denied: Only the primary administrator email (anusripvc202@gmail.com) is authorized to register as Admin.'),
          backgroundColor: Color(0xFFEF4444),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    String? photoBase64;
    if (_pickedImageBytes != null) {
      photoBase64 = 'data:image/png;base64,${base64Encode(_pickedImageBytes!)}';
    }

    final location = _selectedRole == UserRole.dentist
        ? _clinicAddressController.text.trim()
        : _locationController.text.trim();
    final city = _cityController.text.trim();
    final pincode = _pincodeController.text.trim();
    final clinicAddress = _clinicAddressController.text.trim();
    final String chosenRole = _selectedRole == UserRole.dentist ? 'Dentist' : 'Patient';

    // Mandatory Field Validations
    if (city.isEmpty) {
      setState(() => _isRegistering = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ City is a mandatory field.'), backgroundColor: Color(0xFFEF4444)),
      );
      return;
    }

    if (pincode.isEmpty || pincode.length != 6) {
      setState(() => _isRegistering = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Please enter a valid 6-digit Pincode.'), backgroundColor: Color(0xFFEF4444)),
      );
      return;
    }

    if (location.isEmpty) {
      setState(() => _isRegistering = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Location / Address is a mandatory field.'), backgroundColor: Color(0xFFEF4444)),
      );
      return;
    }

    // Language selection is mandatory for registration
    if (_selectedLanguage == null || _selectedLanguage!.trim().isEmpty) {
      setState(() => _isRegistering = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Preferred Language selection is mandatory.'), backgroundColor: Color(0xFFEF4444)),
      );
      return;
    }

    final selectedLangs = [_selectedLanguage!];

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
        specialty: _selectedRole == UserRole.dentist ? _selectedSpecialty : null,
        licenseNumber: _selectedRole == UserRole.dentist ? _licenseNoController.text.trim() : null,
        clinicName: _selectedRole == UserRole.dentist ? _clinicNameController.text.trim() : null,
        clinicAddress: _selectedRole == UserRole.dentist ? clinicAddress : null,
        location: location.isNotEmpty ? location : clinicAddress,
        city: city,
        pincode: pincode,
        profilePhoto: photoBase64,
        languages: selectedLangs,
        referralCode: _selectedRole == UserRole.patient && _referralCodeController.text.trim().isNotEmpty
            ? _referralCodeController.text.trim().toUpperCase()
            : null,
      );

      if (!mounted) return;
      setState(() => _isRegistering = false);

      if (res['success'] == true) {
        final Map<String, dynamic> regData = res['data'] is Map<String, dynamic> ? res['data'] : {};
        final Map<String, dynamic> regUser = (regData['user'] is Map<String, dynamic>)
            ? regData['user']
            : (res['user'] is Map<String, dynamic> ? res['user'] : {});

        final String regToken = (regData['accessToken'] ?? res['accessToken'] ?? res['token'] ?? 'sb_session_${regUser['id'] ?? DateTime.now().millisecondsSinceEpoch}').toString();
        final String regUserId = (regUser['id'] ?? Supabase.instance.client.auth.currentUser?.id ?? 'user_${DateTime.now().millisecondsSinceEpoch}').toString();

        if (_selectedRole == UserRole.patient) {
          PatientProblemService().updatePatientProfile(
            id: regUserId,
            name: name,
            email: email,
            phone: phone,
            age: registeredAge.isNotEmpty ? registeredAge : '',
            gender: _selectedGender ?? 'Female',
            bloodGroup: _selectedBloodGroup ?? 'O Positive (O+)',
            emergencyContact: _emergencyContactController.text.trim().isEmpty ? phone : _emergencyContactController.text.trim(),
            address: location,
            city: city,
            pincode: pincode,
            photoBytes: _pickedImageBytes,
          );
          await SessionService().saveSession(
            token: regToken,
            role: 'Patient',
            userId: regUserId,
            email: email,
            phone: phone,
            name: name,
            metadata: {
              'age': registeredAge,
              'gender': _selectedGender ?? 'Female',
              'bloodGroup': _selectedBloodGroup ?? 'O Positive (O+)',
              'emergencyContact': _emergencyContactController.text.trim().isEmpty ? phone : _emergencyContactController.text.trim(),
              'city': city,
              'pincode': pincode,
              'address': location,
            },
          );
        } else {
          final exp = int.tryParse(_experienceController.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 5;
          final docId = (res['user']?['id'] ?? Supabase.instance.client.auth.currentUser?.id ?? '').toString();
          PatientProblemService().registerDoctor(
            id: docId,
            name: name,
            email: email,
            phone: phone,
            licenseNumber: _licenseNoController.text.trim(),
            specialty: _selectedSpecialty ?? 'General Dentistry',
            clinicName: _clinicNameController.text.trim(),
            clinicAddress: clinicAddress.isNotEmpty ? clinicAddress : location,
            city: city,
            pincode: pincode,
            qualification: 'BDS, MDS',
            experienceYears: exp,
            photoBytes: _pickedImageBytes,
            languages: selectedLangs,
          );
          await SessionService().saveSession(
            token: regToken,
            role: 'Dentist',
            userId: docId,
            email: email,
            phone: phone,
            name: name,
            metadata: {
              'licenseNumber': _licenseNoController.text.trim(),
              'specialty': _selectedSpecialty ?? 'General Dentistry',
              'clinicName': _clinicNameController.text.trim(),
              'clinicAddress': clinicAddress.isNotEmpty ? clinicAddress : location,
              'city': city,
              'pincode': pincode,
              'experienceYears': exp,
              'languages': selectedLangs,
            },
          );
        }

        await PatientProblemService().syncAllDataFromApi();
        if (!mounted) return;
        AnalyticsService.logRegistration(method: 'Mobile_OTP', role: chosenRole);

        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 Registered $chosenRole account successfully!'),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 2),
          ),
        );
        context.go(_targetRoute);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ${res['message'] ?? 'Could not register user.'}'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isRegistering = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Registration Error: $e'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  Future<void> _handleSendOtp() async {
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();

    if (phone.isEmpty && email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Please enter your Mobile Number or Email Address to receive OTP.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isSendingOtp = true;
      _otpErrorMessage = null;
      _currentExpectedOtp = null;
    });

    bool sendSuccess = false;
    String successMsg = '';

    // 1. Mobile Phone SMS OTP via Backend SMS Gateway & Supabase
    if (phone.isNotEmpty) {
      final backendRes = await ApiService().requestOtp(phone: phone, email: email);
      sendSuccess = backendRes['success'] == true;
      if (backendRes['otp'] != null) {
        _currentExpectedOtp = backendRes['otp'].toString();
      }

      if (sendSuccess) {
        if (backendRes['simulated'] == true && backendRes['otp'] != null) {
          successMsg = 'OTP sent to mobile $phone (Code: ${backendRes['otp']})';
        } else {
          successMsg = 'OTP sent to mobile number $phone.';
        }
      }
    }

    // 2. Email OTP via Supabase Auth & Supabase Email Service
    if (email.isNotEmpty) {
      final supabaseRes = await SupabaseService().sendEmailOtp(email);
      final emailSent = supabaseRes['success'] == true;
      sendSuccess = sendSuccess || emailSent;
      if (emailSent && successMsg.isEmpty) {
        successMsg = 'OTP sent to your email address.';
      }
    }

    if (!mounted) return;
    setState(() {
      _isSendingOtp = false;
      if (sendSuccess) {
        _isOtpSent = true;
        _otpController.clear();
      }
    });

    if (sendSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMsg.isNotEmpty ? successMsg : 'OTP sent successfully.'),
          backgroundColor: const Color(0xFF10B981),
          duration: const Duration(seconds: 6),
        ),
      );
    } else {
      setState(() {
        _otpErrorMessage = 'Unable to send OTP. Please check your mobile number and try again.';
      });
    }
  }

  Future<void> _handleVerifyOtp() async {
    final code = _otpController.text.trim();
    if (code.isEmpty) {
      setState(() => _otpErrorMessage = 'Please enter the OTP code');
      return;
    }

    setState(() {
      _isVerifyingOtp = true;
      _otpErrorMessage = null;
    });

    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();

    bool verified = false;

    // 1. Direct match with received OTP
    if (_currentExpectedOtp != null && _currentExpectedOtp == code) {
      verified = true;
    }

    // 2. Mobile Phone SMS OTP verification via Backend API & Supabase
    if (!verified && phone.isNotEmpty) {
      final res = await ApiService().verifyOtp(phone: phone, email: email, code: code);
      verified = res['success'] == true;
    }

    // 3. Email OTP verification via Supabase Auth
    if (!verified && email.isNotEmpty) {
      final supabaseVerify = await SupabaseService().verifyEmailOtp(email: email, token: code);
      verified = supabaseVerify['success'] == true;
    }

    if (!mounted) return;
    setState(() => _isVerifyingOtp = false);

    if (verified) {
      AnalyticsService.logOtpVerification(status: 'verified', method: phone.isNotEmpty ? 'SMS_Mobile_OTP' : 'Email_OTP');
      setState(() {
        _isOtpVerified = true;
        _otpErrorMessage = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 OTP verified successfully! You can now complete registration.'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    } else {
      setState(() => _otpErrorMessage = 'Invalid or expired OTP code.');
    }
  }

  Widget _buildOtpVerificationSection() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF86EFAC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.mark_email_read_rounded, color: Color(0xFF16A34A), size: 18),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Security OTP Verification',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF166534)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _isOtpVerified ? const Color(0xFFDCF8C6) : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _isOtpVerified ? 'VERIFIED ✓' : 'STEP 1 OF 2',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: _isOtpVerified ? const Color(0xFF15803D) : const Color(0xFFD97706),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Enter the OTP verification code dispatched to your Mobile Phone SMS or Email Inbox.',
            style: TextStyle(fontSize: 11, color: Color(0xFF166534)),
          ),
          const SizedBox(height: 12),

          if (!_isOtpSent && !_isOtpVerified) ...[
            ElevatedButton.icon(
              icon: _isSendingOtp
                  ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.send_to_mobile_rounded, size: 16),
              label: Text(_isSendingOtp ? 'Sending OTP...' : 'Send OTP to Mobile & Email', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(40),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _isSendingOtp ? null : _handleSendOtp,
            ),
          ] else if (!_isOtpVerified && _isOtpSent) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF86EFAC)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.mark_email_read_rounded, color: Color(0xFF15803D), size: 16),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'OTP verification code has been dispatched to your Mobile SMS / Email Inbox.',
                          style: TextStyle(fontSize: 11, color: Color(0xFF15803D), fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  if (ApiService.lastGeneratedOtp != null) ...[
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () {
                        _otpController.text = ApiService.lastGeneratedOtp ?? '';
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('OTP code filled into input field!'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF16A34A)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.key_rounded, size: 14, color: Color(0xFF16A34A)),
                            const SizedBox(width: 5),
                            const Expanded(
                              child: Text(
                                'Verification Code:',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDCFCE7),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: const Color(0xFF86EFAC)),
                              ),
                              child: Text(
                                ApiService.lastGeneratedOtp ?? '',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2,
                                  color: Color(0xFF15803D),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.touch_app_rounded, size: 12, color: Color(0xFF16A34A)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    maxLength: 8,
                    style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13.5, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: 'Enter OTP code',
                      counterText: '',
                      filled: true,
                      fillColor: Colors.white,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _isVerifyingOtp ? null : _handleVerifyOtp,
                    child: _isVerifyingOtp
                        ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Verify', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ),
              ],
            ),
            if (_otpErrorMessage != null) ...[
              const SizedBox(height: 6),
              Text(_otpErrorMessage!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 11, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 6),
            InkWell(
              onTap: _handleSendOtp,
              child: const Text('Didn\'t receive code? Resend OTP to Mobile & Email', style: TextStyle(fontSize: 10, color: AppTheme.primaryBlue, fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
            ),
          ] else ...[
            const Text(
              'Identity verified via 4-digit Mobile SMS & Email OTP. Click Create Account below to finish.',
              style: TextStyle(fontSize: 11, color: Color(0xFF15803D), fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }

  void _autoFillDemo(UserRole role) {
    setState(() {
      _selectedRole = role;
      if (role == UserRole.admin) {
        _loginEmailController.text = '8977906566';
      } else if (role == UserRole.dentist) {
        _loginEmailController.text = '8977906566';
      } else {
        _loginEmailController.text = '7799332395';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.softBlueBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.05),
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            const DentaGuruLogo(height: 26),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _tabController.index == 1
                    ? '$_roleName Registration'
                    : '$_roleName Portal Authentication',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              elevation: 8,
              shadowColor: Colors.black.withValues(alpha: 0.08),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Prominent Brand Logo Header
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: DentaGuruLogo(height: 44),
                      ),
                    ),

                    // Dynamic Header with Role Icon & Gradient
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [_accentColor.withValues(alpha: 0.15), _accentColor.withValues(alpha: 0.05)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _accentColor.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _accentColor,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: _accentColor.withValues(alpha: 0.35),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Icon(_roleIcon, color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'DentaGuru Platform',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: _accentColor,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _tabController.index == 1
                                      ? 'Create your $_roleName account on DentaGuru'
                                      : 'Select your role to access $_roleName Workspace',
                                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Material 3 Dynamic Role Selector Segmented Bar
                    Text(
                      _tabController.index == 1 ? 'Registering as:' : 'Select User Role:',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textDark),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 44,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          _buildRoleTile(UserRole.patient, 'Patient', Icons.person_outline_rounded),
                          _buildRoleTile(UserRole.dentist, 'Dentist', Icons.medical_services_outlined),
                          if (_tabController.index == 0)
                            _buildRoleTile(UserRole.admin, 'Admin', Icons.admin_panel_settings_outlined),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Tab Bar (Sign In & Register)
                    Container(
                      height: 46,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        indicator: BoxDecoration(
                          color: _accentColor,
                          borderRadius: BorderRadius.circular(11),
                          boxShadow: [
                            BoxShadow(
                              color: _accentColor.withValues(alpha: 0.3),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        labelColor: Colors.white,
                        unselectedLabelColor: AppTheme.textMuted,
                        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        indicatorSize: TabBarIndicatorSize.tab,
                        tabs: const [
                          Tab(text: 'Sign In'),
                          Tab(text: 'Register'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Tab Body
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: _tabController.index == 0
                          ? KeyedSubtree(key: const ValueKey('signin_tab'), child: _buildSignInForm())
                          : KeyedSubtree(key: const ValueKey('register_tab'), child: _buildRegisterForm()),
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

  Widget _buildRoleTile(UserRole role, String label, IconData icon) {
    final bool isSelected = _selectedRole == role;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedRole = role;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            color: isSelected ? _accentColor : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: _accentColor.withValues(alpha: 0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected ? Colors.white : AppTheme.textMuted,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    fontSize: 11.5,
                    color: isSelected ? Colors.white : AppTheme.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================= 1. SIGN IN FORM =================
  Widget _buildSignInForm() {
    return Form(
      key: _loginFormKey,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 6),

            // Demo Auto-fill Banner
            InkWell(
              onTap: () => _autoFillDemo(_selectedRole),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _accentColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _accentColor.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.touch_app_rounded, color: _accentColor, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tap to auto-fill $_roleName demo contact',
                        style: TextStyle(fontSize: 11, color: _accentColor, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Fast Direct Login Flow (Mobile Number OR Email Address - No password/OTP required)
            TextFormField(
              controller: _loginEmailController,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13.5, fontWeight: FontWeight.w500),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Please enter your registered mobile number or email address';
                }
                return null;
              },
              decoration: _buildInputDecoration(
                label: 'Registered Mobile Number or Email *',
                hint: 'e.g. +91 98765 43210 or user@dentaguru.com',
                icon: Icons.phone_android_rounded,
              ),
            ),
            const SizedBox(height: 18),

            // Direct Sign In Button
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _isLoggingIn ? null : _handleLogin,
              child: _isLoggingIn
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Text('Sign In as $_roleName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  // ================= 2. DYNAMIC REGISTER FORM =================
  Widget _buildRegisterForm() {
    return Form(
      key: _registerFormKey,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 4),

            // Profile Picture Picker Box
            GestureDetector(
              onTap: _pickGalleryImage,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: 80,
                decoration: BoxDecoration(
                  color: _pickedImageBytes != null ? _accentColor.withValues(alpha: 0.05) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _pickedImageBytes != null ? _accentColor : const Color(0xFFCBD5E1),
                    width: _pickedImageBytes != null ? 2 : 1.5,
                  ),
                ),
                child: _pickedImageBytes != null
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 26,
                            backgroundImage: MemoryImage(_pickedImageBytes!),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _pickedImageName ?? 'Photo Selected',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textDark),
                              ),
                              Text(
                                'Tap to change photo',
                                style: TextStyle(fontSize: 10, color: _accentColor, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo_outlined, color: _accentColor, size: 22),
                          const SizedBox(height: 4),
                          Text(
                            'Upload Profile Picture (Optional)',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: _accentColor),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 14),

            // Mandatory Primary Identifier: Full Name
            TextFormField(
              controller: _nameController,
              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13.5, fontWeight: FontWeight.w500),
              validator: (val) => (val == null || val.trim().isEmpty) ? 'Please enter full name' : null,
              decoration: _buildInputDecoration(
                label: _selectedRole == UserRole.dentist
                    ? 'Practitioner Full Name & Title'
                    : _selectedRole == UserRole.admin
                        ? 'Administrator Full Name'
                        : 'Patient Full Name',
                hint: _selectedRole == UserRole.dentist ? 'e.g. Dr. Nikhil' : 'e.g. Jane Smith',
                isRequired: true,
                icon: Icons.person_outline_rounded,
              ),
            ),
            const SizedBox(height: 12),

            // Mandatory Primary Identifier: Mobile Phone Number
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13.5, fontWeight: FontWeight.w500),
              validator: (val) {
                if (val == null || val.trim().isEmpty) return 'Mobile phone number is mandatory';
                final clean = val.replaceAll(RegExp(r'[^0-9]'), '');
                if (clean.length < 10) return 'Enter valid 10-digit mobile number';
                return null;
              },
              decoration: _buildInputDecoration(
                label: 'Mobile Phone Number',
                hint: '+91 98765 43210',
                isRequired: true,
                icon: Icons.phone_android_rounded,
              ),
            ),
            const SizedBox(height: 12),

            // Mandatory Primary Identifier: Preferred Language
            DropdownButtonFormField<String>(
              initialValue: _selectedLanguage,
              dropdownColor: Colors.white,
              isExpanded: true,
              validator: (val) => (val == null || val.isEmpty) ? 'Please select a preferred Language' : null,
              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w600),
              decoration: _buildInputDecoration(
                label: 'Select Language',
                hint: 'Select Language',
                isRequired: true,
                icon: Icons.translate_rounded,
              ),
              items: _availableLanguages.map((lang) {
                return DropdownMenuItem(
                  value: lang,
                  child: Text(lang, style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w600)),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _selectedLanguage = val);
                }
              },
            ),
            const SizedBox(height: 12),

            // Optional Field: Email Address
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13.5, fontWeight: FontWeight.w500),
              validator: (val) {
                if (val != null && val.trim().isNotEmpty && !val.contains('@')) {
                  return 'Enter a valid email address';
                }
                return null;
              },
              decoration: _buildInputDecoration(
                label: 'Email Address (Optional)',
                hint: 'user@dentaguru.com (Optional)',
                isRequired: false,
                icon: Icons.email_outlined,
              ),
            ),
            const SizedBox(height: 12),

            // DYNAMIC ROLE-SPECIFIC FIELDS
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _buildRoleSpecificFields(),
            ),

            const SizedBox(height: 12),

            // OTP Verification Box Before Creating Account
            _buildOtpVerificationSection(),

            const SizedBox(height: 16),

            // Register Submit Button (ACTIVE ONLY AFTER OTP VERIFICATION)
            Opacity(
              opacity: _isOtpVerified ? 1.0 : 0.6,
              child: ElevatedButton.icon(
                icon: Icon(
                  _isOtpVerified ? Icons.check_circle_rounded : Icons.lock_rounded,
                  size: 18,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isOtpVerified ? _accentColor : Colors.grey.shade400,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  elevation: _isOtpVerified ? 2 : 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: (_isRegistering || !_isOtpVerified) ? null : _handleRegister,
                label: _isRegistering
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : Text(
                        _isOtpVerified ? 'Create $_roleName Account' : 'Verify Mobile OTP to Complete Registration',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleSpecificFields() {
    switch (_selectedRole) {
      case UserRole.patient:
        return Column(
          key: const ValueKey('patient_fields'),
          children: [
            Row(
              children: [
                Expanded(
                  flex: 4,
                  child: TextFormField(
                    controller: _ageController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13.5, fontWeight: FontWeight.w500),
                    decoration: _buildInputDecoration(
                      label: 'Age',
                      hint: '28',
                      icon: Icons.cake_outlined,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 6,
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedGender,
                    dropdownColor: Colors.white,
                    isExpanded: true,
                    style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w600),
                    decoration: _buildInputDecoration(
                      label: 'Gender',
                      hint: 'Select Gender',
                      icon: Icons.people_outline_rounded,
                    ),
                    items: ['Female', 'Male', 'Other', 'Prefer not to say'].map((g) {
                      return DropdownMenuItem(
                        value: g,
                        child: Text(
                          g,
                          style: const TextStyle(color: Color(0xFF0F172A), fontSize: 12.5, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (val) => setState(() => _selectedGender = val ?? 'Female'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedBloodGroup,
              dropdownColor: Colors.white,
              isExpanded: true,
              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w600),
              decoration: _buildInputDecoration(
                label: 'Blood Group',
                hint: 'Select Blood Group',
                icon: Icons.bloodtype_outlined,
              ),
              items: [
                'O Positive (O+)',
                'A Positive (A+)',
                'B Positive (B+)',
                'AB Positive (AB+)',
                'O Negative (O-)',
                'A Negative (A-)',
                'B Negative (B-)',
                'AB Negative (AB-)',
              ].map((bg) {
                return DropdownMenuItem(
                  value: bg,
                  child: Text(
                    bg,
                    style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: (val) => setState(() => _selectedBloodGroup = val ?? 'O Positive (O+)'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emergencyContactController,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13.5, fontWeight: FontWeight.w500),
              decoration: _buildInputDecoration(
                label: 'Emergency Contact (Optional)',
                hint: '+91 98765 99880',
                icon: Icons.contact_phone_outlined,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _referralCodeController,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(color: Color(0xFF5B21B6), fontSize: 13.5, fontWeight: FontWeight.bold, letterSpacing: 1.2),
              decoration: _buildInputDecoration(
                label: 'Referral Code (Optional)',
                hint: 'e.g. DG-RAH7302',
                icon: Icons.card_giftcard_rounded,
              ),
            ),
            const SizedBox(height: 12),
            // MANDATORY FIELD 1: Location *
            TextFormField(
              controller: _locationController,
              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13.5, fontWeight: FontWeight.w500),
              validator: (val) => (val == null || val.trim().isEmpty) ? 'Please enter Location / Street Address' : null,
              decoration: _buildInputDecoration(
                label: 'Location / Address',
                hint: 'e.g. Door No, Street / Area Name',
                isRequired: true,
                icon: Icons.location_on_outlined,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                // MANDATORY FIELD 2: City *
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _cityController,
                    style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13.5, fontWeight: FontWeight.w500),
                    validator: (val) => (val == null || val.trim().isEmpty) ? 'Please enter City' : null,
                    decoration: _buildInputDecoration(
                      label: 'City',
                      hint: 'e.g. City Name',
                      isRequired: true,
                      icon: Icons.location_city_rounded,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // MANDATORY FIELD 3: Pincode *
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _pincodeController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13.5, fontWeight: FontWeight.w500),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'Enter Pincode';
                      if (val.trim().length != 6) return '6-digit PIN';
                      return null;
                    },
                    decoration: _buildInputDecoration(
                      label: 'Pincode',
                      hint: '6-Digit PIN',
                      isRequired: true,
                      icon: Icons.pin_drop_outlined,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );

      case UserRole.dentist:
        return Column(
          key: const ValueKey('dentist_fields'),
          children: [
            TextFormField(
              controller: _licenseNoController,
              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13.5, fontWeight: FontWeight.w500),
              validator: (val) => (val == null || val.trim().isEmpty) ? 'Enter Dental License Number' : null,
              decoration: _buildInputDecoration(
                label: 'Dental Council License Number',
                hint: 'DEN-LIC-88490',
                isRequired: true,
                icon: Icons.badge_outlined,
              ),
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<String>(
              initialValue: _selectedSpecialty,
              isExpanded: true,
              dropdownColor: Colors.white,
              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w600),
              decoration: _buildInputDecoration(
                label: 'Dental Specialization',
                hint: 'Select Specialty',
                icon: Icons.medical_services_outlined,
              ),
              items: [
                'General Dentistry',
                'Orthodontics',
                'Endodontics',
                'Periodontics',
                'Pediatric Dentistry',
                'Oral & Maxillofacial Surgery',
                'Prosthodontics',
              ].map((sp) {
                return DropdownMenuItem(value: sp, child: Text(sp, style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis));
              }).toList(),
              onChanged: (val) => setState(() => _selectedSpecialty = val ?? 'General Dentistry'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _clinicNameController,
                    style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13.5, fontWeight: FontWeight.w500),
                    validator: (val) => (val == null || val.trim().isEmpty) ? 'Enter clinic name' : null,
                    decoration: _buildInputDecoration(
                      label: 'Primary Clinic Name',
                      hint: 'Metro Dental Care Practice',
                      isRequired: true,
                      icon: Icons.domain_rounded,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _experienceController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13.5, fontWeight: FontWeight.w500),
                    decoration: _buildInputDecoration(
                      label: 'Exp. (Years)',
                      hint: '5',
                      icon: Icons.work_outline_rounded,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // MANDATORY FIELD 1: Location / Clinic Address *
            TextFormField(
              controller: _clinicAddressController,
              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13.5, fontWeight: FontWeight.w500),
              validator: (val) => (val == null || val.trim().isEmpty) ? 'Please enter Location / Clinic Address' : null,
              decoration: _buildInputDecoration(
                label: 'Location / Clinic Address',
                hint: 'e.g. Area / Landmark / Street',
                isRequired: true,
                icon: Icons.location_on_outlined,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                // MANDATORY FIELD 2: City *
                Expanded(
                  child: TextFormField(
                    controller: _cityController,
                    style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13.5, fontWeight: FontWeight.w500),
                    validator: (val) => (val == null || val.trim().isEmpty) ? 'Please enter City' : null,
                    decoration: _buildInputDecoration(
                      label: 'City',
                      hint: 'e.g. City Name',
                      isRequired: true,
                      icon: Icons.location_city_rounded,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // MANDATORY FIELD 3: Pincode *
                Expanded(
                  child: TextFormField(
                    controller: _pincodeController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13.5, fontWeight: FontWeight.w500),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'Enter Pincode';
                      if (val.trim().length != 6) return '6-digit PIN';
                      return null;
                    },
                    decoration: _buildInputDecoration(
                      label: 'Pincode',
                      hint: '6-Digit PIN',
                      isRequired: true,
                      icon: Icons.pin_drop_outlined,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );

      case UserRole.admin:
        return const SizedBox.shrink();
    }
  }

  InputDecoration _buildInputDecoration({
    required String label,
    required String hint,
    bool isRequired = false,
    IconData? icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      label: isRequired
          ? Text.rich(
              TextSpan(
                text: label,
                style: const TextStyle(color: Color(0xFF475569), fontSize: 13),
                children: const [
                  TextSpan(
                    text: ' *',
                    style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
            )
          : Text(label, style: const TextStyle(color: Color(0xFF475569), fontSize: 13)),
      labelStyle: const TextStyle(color: Color(0xFF475569), fontSize: 13),
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
      prefixIcon: icon != null ? Icon(icon, color: _accentColor, size: 18) : null,
      prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
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
        borderSide: BorderSide(color: _accentColor, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
      ),
    );
  }
}
