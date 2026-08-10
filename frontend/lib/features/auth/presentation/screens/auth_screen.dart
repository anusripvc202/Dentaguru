import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/denta_guru_logo.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/services/firebase_service.dart';

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
  final _loginPasswordController = TextEditingController();
  bool _showLoginPassword = false;
  bool _isLoggingIn = false;

  // Controllers for Registration
  final _registerFormKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _showRegPassword = false;
  bool _isRegistering = false;

  // Role-Specific Fields - Patient
  final _ageController = TextEditingController();
  final _emergencyContactController = TextEditingController();
  String? _selectedGender;
  String? _selectedBloodGroup;

  // Role-Specific Fields - Dentist
  final _licenseNoController = TextEditingController();
  final _clinicNameController = TextEditingController();
  final _experienceController = TextEditingController(text: '5');
  final _clinicAddressController = TextEditingController();
  String? _selectedSpecialty;
  String? _selectedExistingClinic;

  // Role-Specific Fields - Admin
  final _adminEmployeeIdController = TextEditingController();
  final _adminDeptController = TextEditingController();

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
  String? _receivedOtp;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: widget.initialTab);

    // Initialize selected role from widget param or default to Patient
    final roleStr = (widget.initialRole ?? 'Patient').toLowerCase();
    if (roleStr == 'dentist') {
      _selectedRole = UserRole.dentist;
    } else if (roleStr == 'admin') {
      _selectedRole = UserRole.admin;
    } else {
      _selectedRole = UserRole.patient;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _ageController.dispose();
    _emergencyContactController.dispose();
    _licenseNoController.dispose();
    _clinicNameController.dispose();
    _experienceController.dispose();
    _adminEmployeeIdController.dispose();
    _adminDeptController.dispose();
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

    setState(() => _isLoggingIn = true);
    final email = _loginEmailController.text.trim();
    final password = _loginPasswordController.text.trim();

    try {
      final res = await ApiService().loginUser(
        email: email,
        password: password,
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

        // ⛔ ENFORCE STRICT PORTAL ROLE MATCHING
        final bool isSelAdmin = _selectedRole == UserRole.admin;
        final bool isSelDentist = _selectedRole == UserRole.dentist;
        final bool isSelPatient = _selectedRole == UserRole.patient;

        final bool isRegAdmin = registeredRole.contains('admin');
        final bool isRegDentist = registeredRole.contains('dentist') || registeredRole.contains('doctor');
        final bool isRegPatient = registeredRole.contains('patient');

        if ((isSelAdmin && !isRegAdmin) || (isSelDentist && !isRegDentist) || (isSelPatient && !isRegPatient)) {
          final displayRole = userData['role'] ?? (isRegDentist ? 'Dentist' : (isRegAdmin ? 'Admin' : 'Patient'));
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
                : (!email.contains('@') && email.isNotEmpty ? email : '9063663180'));

        if (registeredRole.contains('dentist') || registeredRole.contains('doctor')) {
          PatientProblemService().registerDoctor(
            name: userData['name'] ?? 'Dr. Dentist',
            email: userData['email'] ?? email,
            phone: userPhone,
            licenseNumber: 'DEN-LIC-REGISTERED',
            specialty: 'General Dentistry',
            clinicName: userData['clinicName'] ?? '',
            experienceYears: 5,
            photoBytes: photoBytes,
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🎉 Welcome back, ${userData['name'] ?? 'Doctor'}! Logging into Dentist Workspace...'),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
          context.go('/dentist');
        } else if (registeredRole.contains('admin')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🎉 Welcome back, ${userData['name'] ?? 'Admin'}! Logging into Admin Dashboard...'),
              backgroundColor: const Color(0xFF6366F1),
            ),
          );
          context.go('/admin');
        } else {
          // Patient Role
          PatientProblemService().updatePatientProfile(
            id: userData['id']?.toString() ?? '',
            name: userData['name'] ?? email.split('@').first,
            email: userData['email'] ?? email,
            phone: userPhone,
            age: '28',
            gender: 'Female',
            bloodGroup: 'O Positive (O+)',
            emergencyContact: userPhone,
            photoBytes: photoBytes,
          );
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
      if (!mounted) return;
      setState(() => _isLoggingIn = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Network error: $e'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  Future<void> _handleRegister() async {
    if (!_registerFormKey.currentState!.validate()) return;

    setState(() => _isRegistering = true);
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text.trim();

    String? photoBase64;
    if (_pickedImageBytes != null) {
      photoBase64 = 'data:image/png;base64,${base64Encode(_pickedImageBytes!)}';
    }

    try {
      final res = await ApiService().registerUser(
        name: name,
        email: email,
        password: password,
        phone: phone,
        role: _roleName,
        specialty: _selectedSpecialty,
        licenseNumber: _licenseNoController.text.trim(),
        clinicName: _clinicNameController.text.trim(),
        clinicAddress: _clinicAddressController.text.trim(),
        profilePhoto: photoBase64,
      );

      if (!mounted) return;
      setState(() => _isRegistering = false);

      if (res['success'] == true) {
        if (_selectedRole == UserRole.patient) {
          PatientProblemService().updatePatientProfile(
            name: name,
            email: email,
            phone: phone,
            age: _ageController.text.trim().isEmpty ? '28' : _ageController.text.trim(),
            gender: _selectedGender ?? 'Female',
            bloodGroup: _selectedBloodGroup ?? 'O Positive (O+)',
            emergencyContact: _emergencyContactController.text.trim().isEmpty ? phone : _emergencyContactController.text.trim(),
            photoBytes: _pickedImageBytes,
          );
        } else if (_selectedRole == UserRole.dentist) {
          final exp = int.tryParse(_experienceController.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 5;
          PatientProblemService().registerDoctor(
            name: name,
            email: email,
            phone: phone,
            licenseNumber: _licenseNoController.text.trim(),
            specialty: _selectedSpecialty ?? 'General Dentistry',
            clinicName: _clinicNameController.text.trim(),
            clinicAddress: _clinicAddressController.text.trim(),
            experienceYears: exp,
            photoBytes: _pickedImageBytes,
          );
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 Registered $_roleName account successfully!'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
        context.go(_targetRoute);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Registration Failed: ${res['message'] ?? 'Could not register user.'}'),
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
          content: Text('⚠️ Please enter your Phone Number or Email Address to receive OTP.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isSendingOtp = true;
      _otpErrorMessage = null;
    });

    // 1. Send 4-digit OTP via Backend API (Nodemailer Email & SMS)
    final res = await ApiService().requestOtp(phone: phone, email: email);

    // 2. Also send SMS OTP via Firebase Phone Auth if phone provided
    if (phone.isNotEmpty) {
      FirebaseService.sendFirebasePhoneOtp(
        phone,
        onCodeSent: (verId) {
          debugPrint('📩 Firebase Phone Auth SMS dispatched to $phone');
        },
        onError: (err) {
          debugPrint('⚠️ Firebase Phone Auth warning: $err');
        },
      );
    }

    if (!mounted) return;
    setState(() {
      _isSendingOtp = false;
      _isOtpSent = true;
      _otpController.clear();
    });

    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('📩 OTP Verification Code sent to ${email.isNotEmpty ? email : phone}. Check your inbox.'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    } else {
      setState(() {
        _otpErrorMessage = res['message'] ?? 'Failed to send OTP code. Check your network connection.';
      });
    }
  }

  Future<void> _handleVerifyOtp() async {
    final code = _otpController.text.trim();
    if (code.isEmpty) {
      setState(() => _otpErrorMessage = 'Please enter OTP code');
      return;
    }

    setState(() {
      _isVerifyingOtp = true;
      _otpErrorMessage = null;
    });

    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();

    // Verify code via Firebase or Backend API
    bool verified = await FirebaseService.verifyFirebaseOtp(code);
    if (!verified) {
      final res = await ApiService().verifyOtp(phone: phone, email: email, code: code);
      verified = res['success'] == true;
    }

    if (!mounted) return;
    setState(() => _isVerifyingOtp = false);

    if (verified) {
      setState(() {
        _isOtpVerified = true;
        _otpErrorMessage = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 OTP Verified successfully! "Create Account" button is now ACTIVE.'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    } else {
      setState(() => _otpErrorMessage = 'Invalid or expired OTP code. Please try again.');
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
              Expanded(
                child: Text(
                  'Security OTP Verification',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF166534)),
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
            'We dispatch a live 4-digit OTP code to both Mobile Phone SMS and Email Inbox for instant authentication.',
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
              child: const Row(
                children: [
                  Icon(Icons.mark_email_read_rounded, color: Color(0xFF15803D), size: 16),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'OTP verification code has been dispatched to your Mobile SMS & Email Inbox.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF15803D), fontWeight: FontWeight.w600),
                    ),
                  ),
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
                    maxLength: 4,
                    decoration: InputDecoration(
                      hintText: '4-digit OTP',
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
              'Identity verified via Mobile SMS & Email OTP. Click Create Account below to finish.',
              style: TextStyle(fontSize: 11, color: Color(0xFF15803D), fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }

  void _showForgotPasswordDialog(BuildContext context) {
    final emailCtrl = TextEditingController(text: _loginEmailController.text.trim());
    final otpCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    bool codeSent = false;
    bool isSubmitting = false;
    String? dialogError;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (stCtx, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Row(
                children: [
                  Icon(Icons.lock_reset_rounded, color: AppTheme.primaryBlue, size: 24),
                  SizedBox(width: 8),
                  Text('Reset Password', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!codeSent) ...[
                    const Text(
                      'Enter your registered email address or phone number to receive a password reset OTP code.',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: emailCtrl,
                      decoration: InputDecoration(
                        labelText: 'Registered Email or Phone',
                        hintText: 'user@dentaguru.com',
                        prefixIcon: const Icon(Icons.email_outlined, color: AppTheme.primaryBlue),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ] else ...[
                    const Text(
                      'Enter the 4-digit OTP code sent to your email/phone and set a new password.',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: otpCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      decoration: InputDecoration(
                        labelText: 'Enter OTP Code',
                        hintText: '1234',
                        counterText: '',
                        prefixIcon: const Icon(Icons.key_rounded, color: Color(0xFF10B981)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: newPassCtrl,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Set New Password',
                        hintText: '••••••••',
                        prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppTheme.primaryBlue),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                  if (dialogError != null) ...[
                    const SizedBox(height: 8),
                    Text(dialogError!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final targetEmail = emailCtrl.text.trim();
                          if (targetEmail.isEmpty) {
                            setModalState(() => dialogError = 'Please enter your email or phone.');
                            return;
                          }

                          if (!codeSent) {
                            setModalState(() {
                              isSubmitting = true;
                              dialogError = null;
                            });
                            await ApiService().forgotPassword(email: targetEmail);
                            setModalState(() {
                              isSubmitting = false;
                              codeSent = true;
                              otpCtrl.clear();
                            });
                          } else {
                            final code = otpCtrl.text.trim();
                            final newPass = newPassCtrl.text.trim();
                            if (code.isEmpty || newPass.isEmpty) {
                              setModalState(() => dialogError = 'Please enter OTP code and set new password.');
                              return;
                            }

                            setModalState(() {
                              isSubmitting = true;
                              dialogError = null;
                            });

                            final res = await ApiService().resetPassword(
                              email: targetEmail,
                              code: code,
                              newPassword: newPass,
                            );

                            setModalState(() => isSubmitting = false);

                            if (res['success'] == true) {
                              _loginEmailController.text = targetEmail;
                              _loginPasswordController.text = newPass;
                              if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(res['message'] ?? '🎉 Password reset successfully!'),
                                    backgroundColor: const Color(0xFF10B981),
                                    duration: const Duration(seconds: 4),
                                  ),
                                );
                              }
                            } else {
                              setModalState(() => dialogError = res['message'] ?? 'Password reset failed.');
                            }
                          }
                        },
                  child: isSubmitting
                      ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(codeSent ? 'Reset & Save Password' : 'Send Reset OTP', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _autoFillDemo(UserRole role) {
    setState(() {
      _selectedRole = role;
      if (role == UserRole.patient) {
        _loginEmailController.text = 'patient@dentaguru.com';
      } else if (role == UserRole.dentist) {
        _loginEmailController.text = 'dr.nikhil@dentaguru.com';
      } else {
        _loginEmailController.text = 'admin@dentaguru.com';
      }
      _loginPasswordController.text = 'Password123!';
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.primaryBlue),
          onPressed: () => context.go('/'),
          tooltip: 'Back to Home Page',
        ),
        title: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              const DentaGuruLogo(height: 26),
              const SizedBox(width: 6),
              Text(
                '$_roleName Portal Authentication',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
              ),
            ],
          ),
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
                                  'Select your role to access $_roleName Workspace',
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
                    const Text(
                      'Select User Role:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textDark),
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
                    SizedBox(
                      height: _selectedRole == UserRole.dentist ? 780 : _selectedRole == UserRole.admin ? 680 : 540,
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildSignInForm(),
                          _buildRegisterForm(),
                        ],
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
                size: 16,
                color: isSelected ? Colors.white : AppTheme.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  fontSize: 12,
                  color: isSelected ? Colors.white : AppTheme.textMuted,
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
                        'Tap to auto-fill $_roleName demo credentials',
                        style: TextStyle(fontSize: 11, color: _accentColor, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Email or Mobile Field
            TextFormField(
              controller: _loginEmailController,
              keyboardType: TextInputType.emailAddress,
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Please enter your registered email or mobile number';
                }
                return null;
              },
              decoration: _buildInputDecoration(
                label: 'Email or Mobile Number',
                hint: 'e.g. user@dentaguru.com',
                icon: Icons.alternate_email_rounded,
              ),
            ),
            const SizedBox(height: 14),

            // Password Field
            TextFormField(
              controller: _loginPasswordController,
              obscureText: !_showLoginPassword,
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Please enter your password';
                }
                if (val.trim().length < 6) {
                  return 'Password must be at least 6 characters';
                }
                return null;
              },
              decoration: _buildInputDecoration(
                label: 'Account Password',
                hint: '••••••••',
                icon: Icons.lock_outline_rounded,
                suffixIcon: IconButton(
                  icon: Icon(
                    _showLoginPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    size: 20,
                    color: AppTheme.textMuted,
                  ),
                  onPressed: () => setState(() => _showLoginPassword = !_showLoginPassword),
                ),
              ),
            ),
            const SizedBox(height: 8),

            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _showForgotPasswordDialog(context),
                child: Text(
                  'Forgot Password?',
                  style: TextStyle(color: _accentColor, fontWeight: FontWeight.w600, fontSize: 12),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Sign In Button
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
                  : Text('Sign In as $_roleName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
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

            // Common Field: Name
            TextFormField(
              controller: _nameController,
              validator: (val) => (val == null || val.trim().isEmpty) ? 'Please enter your full name' : null,
              decoration: _buildInputDecoration(
                label: _selectedRole == UserRole.dentist
                    ? 'Practitioner Full Name & Title'
                    : _selectedRole == UserRole.admin
                        ? 'Administrator Full Name'
                        : 'Patient Full Name',
                hint: _selectedRole == UserRole.dentist ? 'e.g. Dr. Nikhil' : 'e.g. Jane Smith',
                icon: Icons.person_outline_rounded,
              ),
            ),
            const SizedBox(height: 12),

            // Common Field: Email
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              validator: (val) {
                if (val == null || val.trim().isEmpty) return 'Please enter an email address';
                if (!val.contains('@')) return 'Enter a valid email address';
                return null;
              },
              decoration: _buildInputDecoration(
                label: 'Email Address',
                hint: 'user@dentaguru.com',
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

            // Common Field: Password
            TextFormField(
              controller: _passwordController,
              obscureText: !_showRegPassword,
              validator: (val) {
                if (val == null || val.trim().isEmpty) return 'Please set a password';
                if (val.trim().length < 6) return 'Password must be at least 6 characters';
                return null;
              },
              decoration: _buildInputDecoration(
                label: 'Set Account Password',
                hint: '••••••••',
                icon: Icons.lock_outline_rounded,
                suffixIcon: IconButton(
                  icon: Icon(
                    _showRegPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    size: 20,
                    color: AppTheme.textMuted,
                  ),
                  onPressed: () => setState(() => _showRegPassword = !_showRegPassword),
                ),
              ),
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
                        _isOtpVerified ? 'Create $_roleName Account' : 'Complete OTP to Activate Account Creation',
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
                  flex: 3,
                  child: TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    validator: (val) => (val == null || val.trim().isEmpty) ? 'Enter phone' : null,
                    decoration: _buildInputDecoration(
                      label: 'Phone Number',
                      hint: '+1 202 555 0142',
                      icon: Icons.phone_outlined,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _ageController,
                    keyboardType: TextInputType.number,
                    decoration: _buildInputDecoration(
                      label: 'Age',
                      hint: '28',
                      icon: Icons.cake_outlined,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedGender,
              decoration: _buildInputDecoration(
                label: 'Gender',
                hint: 'Select Gender',
                icon: Icons.people_outline_rounded,
              ),
              items: ['Female', 'Male', 'Other', 'Prefer not to say'].map((g) {
                return DropdownMenuItem(value: g, child: Text(g, style: const TextStyle(fontSize: 13)));
              }).toList(),
              onChanged: (val) => setState(() => _selectedGender = val ?? 'Female'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedBloodGroup,
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
                return DropdownMenuItem(value: bg, child: Text(bg, style: const TextStyle(fontSize: 13)));
              }).toList(),
              onChanged: (val) => setState(() => _selectedBloodGroup = val ?? 'O Positive (O+)'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emergencyContactController,
              keyboardType: TextInputType.phone,
              decoration: _buildInputDecoration(
                label: 'Emergency Contact Phone',
                hint: '+1 202 555 9988',
                icon: Icons.contact_phone_outlined,
              ),
            ),
          ],
        );

      case UserRole.dentist:
        return Column(
          key: const ValueKey('dentist_fields'),
          children: [
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              validator: (val) => (val == null || val.trim().isEmpty) ? 'Enter phone number' : null,
              decoration: _buildInputDecoration(
                label: 'Contact Phone Number',
                hint: '+1 202 555 0100',
                icon: Icons.phone_outlined,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _licenseNoController,
              validator: (val) => (val == null || val.trim().isEmpty) ? 'Enter license number' : null,
              decoration: _buildInputDecoration(
                label: 'Dental License Registration No.',
                hint: 'e.g. DEN-LIC-8890',
                icon: Icons.badge_outlined,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedSpecialty,
              isExpanded: true,
              decoration: _buildInputDecoration(
                label: 'Dental Specialization',
                hint: 'Select Specialty',
                icon: Icons.medical_services_outlined,
              ),
              items: [
                'Orthodontics',
                'Endodontics',
                'Periodontics',
                'Pediatric Dentistry',
                'Oral & Maxillofacial Surgery',
                'General Dentistry',
                'Prosthodontics',
              ].map((sp) {
                return DropdownMenuItem(value: sp, child: Text(sp, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis));
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
                    validator: (val) => (val == null || val.trim().isEmpty) ? 'Enter clinic name' : null,
                    decoration: _buildInputDecoration(
                      label: 'Clinic Name *',
                      hint: 'e.g. Bright Smile Dental Practice',
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
            TextFormField(
              controller: _clinicAddressController,
              validator: (val) => (val == null || val.trim().isEmpty) ? 'Enter clinic location / address' : null,
              decoration: _buildInputDecoration(
                label: 'Clinic Location / Address *',
                hint: 'e.g. 100 Feet Rd, Indiranagar, Bengaluru',
                icon: Icons.location_on_outlined,
              ),
            ),
          ],
        );

      case UserRole.admin:
        return Column(
          key: const ValueKey('admin_fields'),
          children: [
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    validator: (val) => (val == null || val.trim().isEmpty) ? 'Enter phone' : null,
                    decoration: _buildInputDecoration(
                      label: 'Contact Phone',
                      hint: '+1 202 555 0199',
                      icon: Icons.phone_outlined,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _adminEmployeeIdController,
                    decoration: _buildInputDecoration(
                      label: 'Admin ID',
                      hint: 'ADM-901',
                      icon: Icons.badge_outlined,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _adminDeptController,
              decoration: _buildInputDecoration(
                label: 'Department / Key Code',
                hint: 'Clinical Operations',
                icon: Icons.admin_panel_settings_outlined,
              ),
            ),
          ],
        );
    }
  }

  InputDecoration _buildInputDecoration({
    required String label,
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
      prefixIcon: Icon(icon, color: _accentColor, size: 20),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
