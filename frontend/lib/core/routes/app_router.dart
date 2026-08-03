import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../widgets/denta_guru_logo.dart';
import '../theme/app_theme.dart';
import '../services/patient_problem_service.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/patient/presentation/screens/patient_dashboard.dart';
import '../../features/dentist/presentation/screens/dentist_timeline.dart';
import '../../features/clinic/presentation/screens/clinic_dashboard.dart';
import '../../features/admin/presentation/screens/admin_dashboard.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  void _showAuthDialog(
    BuildContext context, {
    required String portalRole, // 'Patient', 'Dentist', or 'Admin'
    required String defaultEmail,
    required String targetRoute,
    required Color accentColor,
    required IconData portalIcon,
    int initialTab = 0,
  }) {
    // Form Controllers - Empty defaults for ALL fields (Login & Register)
    final loginEmailController = TextEditingController();
    final loginPasswordController = TextEditingController();
    bool showLoginPassword = false;

    // Registration Fields (EMPTY by default)
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    final passwordController = TextEditingController();
    bool showRegPassword = false;
    bool agreeTerms = true;

    // Picked Image Bytes from Device Gallery
    Uint8List? pickedImageBytes;
    String? pickedImageName;

    Future<void> pickGalleryImage(StateSetter setModalState) async {
      try {
        final ImagePicker picker = ImagePicker();
        final XFile? image = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 800,
          maxHeight: 800,
          imageQuality: 85,
        );
        if (image != null) {
          final bytes = await image.readAsBytes();
          setModalState(() {
            pickedImageBytes = bytes;
            pickedImageName = image.name;
          });
        }
      } catch (e) {
        debugPrint('Gallery picker info: $e');
      }
    }

    // Dropdown Values (null by default)
    String? selectedGender;
    String? selectedBloodGroup;

    // Patient Specific
    final ageController = TextEditingController();
    final emergencyContactController = TextEditingController();

    // Dentist Specific
    final licenseNoController = TextEditingController();
    final clinicNameController = TextEditingController();
    final experienceController = TextEditingController();
    String? selectedSpecialty;

    // Admin Specific
    final adminTitleController = TextEditingController();
    final facilityIdController = TextEditingController();
    final adminSecurityKeyController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return DefaultTabController(
          length: 2,
          initialIndex: initialTab,
          child: StatefulBuilder(
            builder: (context, setModalState) {
              return Dialog(
                backgroundColor: Colors.white,
                elevation: 16,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 460, maxHeight: 700),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Professional Dialog Header with DentaGuru Logo
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const DentaGuruLogo(height: 36),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted, size: 22),
                              onPressed: () => Navigator.of(dialogContext).pop(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(portalIcon, color: accentColor, size: 18),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$portalRole Access Portal',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 17,
                                      color: AppTheme.textDark,
                                    ),
                                  ),
                                  Text(
                                    'DentaGuru Healthcare Network • $portalRole Module',
                                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Side by Side Animated Tab Bar (Sign In & Register)
                        Container(
                          height: 48,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: TabBar(
                            indicator: BoxDecoration(
                              color: accentColor,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: accentColor.withValues(alpha: 0.3),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            labelColor: Colors.white,
                            unselectedLabelColor: AppTheme.textMuted,
                            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            indicatorSize: TabBarIndicatorSize.tab,
                            tabs: const [
                              Tab(text: 'Sign In'),
                              Tab(text: 'Register'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Tab Body View
                        Expanded(
                          child: TabBarView(
                            children: [
                              // ================= 1. SIGN IN FORM =================
                              SingleChildScrollView(
                                physics: const BouncingScrollPhysics(),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    const SizedBox(height: 8),
                                    // Quick Demo Fill Banner
                                    InkWell(
                                      onTap: () {
                                        setModalState(() {
                                          loginEmailController.text = defaultEmail;
                                          loginPasswordController.text = 'password123';
                                        });
                                      },
                                      borderRadius: BorderRadius.circular(10),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: accentColor.withValues(alpha: 0.08),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: accentColor.withValues(alpha: 0.2)),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(Icons.touch_app_rounded, color: accentColor, size: 16),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Tap to auto-fill $portalRole demo credentials',
                                              style: TextStyle(fontSize: 11, color: accentColor, fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),

                                    TextField(
                                      controller: loginEmailController,
                                      decoration: _buildCleanFieldDecoration(
                                        label: '$portalRole Email / User ID',
                                        icon: Icons.email_outlined,
                                        accentColor: accentColor,
                                      ),
                                    ),
                                    const SizedBox(height: 14),

                                    TextField(
                                      controller: loginPasswordController,
                                      obscureText: !showLoginPassword,
                                      decoration: _buildCleanFieldDecoration(
                                        label: 'Password',
                                        icon: Icons.lock_outline,
                                        accentColor: accentColor,
                                        suffixIcon: IconButton(
                                          icon: Icon(
                                            showLoginPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                            size: 20,
                                          ),
                                          onPressed: () {
                                            setModalState(() {
                                              showLoginPassword = !showLoginPassword;
                                            });
                                          },
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton(
                                        onPressed: () {},
                                        child: Text(
                                          'Forgot Password?',
                                          style: TextStyle(color: accentColor, fontWeight: FontWeight.w600, fontSize: 12),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: accentColor,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        elevation: 2,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                      ),
                                      onPressed: () {
                                        if (portalRole == 'Patient') {
                                          final enteredEmail = loginEmailController.text.trim();
                                          final extractedName = enteredEmail.isNotEmpty ? enteredEmail.split('@').first : 'Sarah Jenkins';
                                          PatientProblemService().updatePatientProfile(
                                            name: extractedName,
                                            email: enteredEmail.isNotEmpty ? enteredEmail : defaultEmail,
                                            phone: '+1 202 555 0142',
                                            age: '28',
                                            gender: 'Female',
                                            bloodGroup: 'O Positive (O+)',
                                            emergencyContact: '+1 202 555 9988',
                                          );
                                        }
                                        Navigator.of(dialogContext).pop();
                                        context.go(targetRoute);
                                      },
                                      child: Text('Sign In as $portalRole', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                    ),
                                  ],
                                ),
                              ),

                              // ================= 2. REDESIGNED REGISTER FORM =================
                              SingleChildScrollView(
                                physics: const BouncingScrollPhysics(),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    const SizedBox(height: 6),

                                    // Real Device Gallery Image Picker Box
                                    GestureDetector(
                                      onTap: () => pickGalleryImage(setModalState),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 250),
                                        curve: Curves.easeInOut,
                                        height: 94,
                                        decoration: BoxDecoration(
                                          color: pickedImageBytes != null
                                              ? accentColor.withValues(alpha: 0.05)
                                              : const Color(0xFFF8FAFC),
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(
                                            color: pickedImageBytes != null ? accentColor : const Color(0xFFCBD5E1),
                                            width: pickedImageBytes != null ? 2 : 1.5,
                                          ),
                                        ),
                                        child: pickedImageBytes != null
                                            ? Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Container(
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      border: Border.all(color: accentColor, width: 2),
                                                    ),
                                                    child: CircleAvatar(
                                                      radius: 30,
                                                      backgroundImage: MemoryImage(pickedImageBytes!),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 14),
                                                  Column(
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        pickedImageName ?? 'Gallery Photo Selected',
                                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textDark),
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Row(
                                                        children: [
                                                          Icon(Icons.photo_library_rounded, size: 14, color: accentColor),
                                                          const SizedBox(width: 4),
                                                          Text(
                                                            'Tap to change photo from Gallery',
                                                            style: TextStyle(fontSize: 11, color: accentColor, fontWeight: FontWeight.w600),
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              )
                                            : Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.all(8),
                                                    decoration: BoxDecoration(
                                                      color: accentColor.withValues(alpha: 0.1),
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: Icon(Icons.add_a_photo_rounded, color: accentColor, size: 20),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  const Text(
                                                    'Upload Profile Picture from Device Gallery',
                                                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppTheme.textDark),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  const Text(
                                                    'Tap to open device photo gallery',
                                                    style: TextStyle(fontSize: 10, color: AppTheme.textMuted),
                                                  ),
                                                ],
                                              ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),

                                    // Field 1: Name
                                    TextField(
                                      controller: nameController,
                                      decoration: _buildCleanFieldDecoration(
                                        label: portalRole == 'Dentist'
                                            ? 'Full Name & Practitioner Title'
                                            : portalRole == 'Admin'
                                                ? 'Administrator Full Name'
                                                : 'Patient Full Name',
                                        icon: Icons.person_outline_rounded,
                                        accentColor: accentColor,
                                      ),
                                    ),
                                    const SizedBox(height: 12),

                                    // Field 2: Email
                                    TextField(
                                      controller: emailController,
                                      decoration: _buildCleanFieldDecoration(
                                        label: 'Email Address',
                                        icon: Icons.email_outlined,
                                        accentColor: accentColor,
                                      ),
                                    ),
                                    const SizedBox(height: 12),

                                    // ============ ROLE-SPECIFIC FIELDS ============
                                    if (portalRole == 'Patient') ...[
                                      // Phone & Age Row
                                      Row(
                                        children: [
                                          Expanded(
                                            flex: 3,
                                            child: TextField(
                                              controller: phoneController,
                                              decoration: _buildCleanFieldDecoration(
                                                label: 'Phone Number',
                                                icon: Icons.phone_outlined,
                                                accentColor: accentColor,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            flex: 2,
                                            child: TextField(
                                              controller: ageController,
                                              decoration: _buildCleanFieldDecoration(
                                                label: 'Age',
                                                icon: Icons.cake_outlined,
                                                accentColor: accentColor,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),

                                      // Gender Dropdown
                                      DropdownButtonFormField<String>(
                                        initialValue: selectedGender,
                                        decoration: _buildCleanFieldDecoration(
                                          label: 'Gender',
                                          icon: Icons.people_outline_rounded,
                                          accentColor: accentColor,
                                        ),
                                        items: ['Female', 'Male', 'Other', 'Prefer not to say'].map((g) {
                                          return DropdownMenuItem(
                                            value: g,
                                            child: Text(g, style: const TextStyle(fontSize: 13)),
                                          );
                                        }).toList(),
                                        onChanged: (val) => setModalState(() => selectedGender = val),
                                      ),
                                      const SizedBox(height: 12),

                                      // Blood Group Dropdown
                                      DropdownButtonFormField<String>(
                                        initialValue: selectedBloodGroup,
                                        decoration: _buildCleanFieldDecoration(
                                          label: 'Blood Group',
                                          icon: Icons.bloodtype_outlined,
                                          accentColor: accentColor,
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
                                            child: Text(bg, style: const TextStyle(fontSize: 13)),
                                          );
                                        }).toList(),
                                        onChanged: (val) => setModalState(() => selectedBloodGroup = val),
                                      ),
                                      const SizedBox(height: 12),

                                      // Emergency Contact Phone
                                      TextField(
                                        controller: emergencyContactController,
                                        decoration: _buildCleanFieldDecoration(
                                          label: 'Emergency Contact Phone',
                                          icon: Icons.contact_phone_outlined,
                                          accentColor: accentColor,
                                        ),
                                      ),
                                    ] else if (portalRole == 'Dentist') ...[
                                      // Contact Phone Number
                                      TextField(
                                        controller: phoneController,
                                        decoration: _buildCleanFieldDecoration(
                                          label: 'Contact Phone Number',
                                          icon: Icons.phone_outlined,
                                          accentColor: accentColor,
                                        ),
                                      ),
                                      const SizedBox(height: 12),

                                      // License No.
                                      TextField(
                                        controller: licenseNoController,
                                        decoration: _buildCleanFieldDecoration(
                                          label: 'Dental License Registration No.',
                                          icon: Icons.badge_outlined,
                                          accentColor: accentColor,
                                        ),
                                      ),
                                      const SizedBox(height: 12),

                                      // Specialty Dropdown
                                      DropdownButtonFormField<String>(
                                        initialValue: selectedSpecialty,
                                        decoration: _buildCleanFieldDecoration(
                                          label: 'Dental Specialization',
                                          icon: Icons.medical_services_outlined,
                                          accentColor: accentColor,
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
                                          return DropdownMenuItem(
                                            value: sp,
                                            child: Text(sp, style: const TextStyle(fontSize: 13)),
                                          );
                                        }).toList(),
                                        onChanged: (val) => setModalState(() => selectedSpecialty = val),
                                      ),
                                      const SizedBox(height: 12),

                                      // Clinic Name & Experience
                                      Row(
                                        children: [
                                          Expanded(
                                            flex: 3,
                                            child: TextField(
                                              controller: clinicNameController,
                                              decoration: _buildCleanFieldDecoration(
                                                label: 'Practice Name',
                                                icon: Icons.location_city_outlined,
                                                accentColor: accentColor,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            flex: 2,
                                            child: TextField(
                                              controller: experienceController,
                                              decoration: _buildCleanFieldDecoration(
                                                label: 'Years Exp.',
                                                icon: Icons.work_history_outlined,
                                                accentColor: accentColor,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ] else if (portalRole == 'Admin') ...[
                                      // Admin Designation Title
                                      TextField(
                                        controller: adminTitleController,
                                        decoration: _buildCleanFieldDecoration(
                                          label: 'Designation Title',
                                          icon: Icons.admin_panel_settings_outlined,
                                          accentColor: accentColor,
                                        ),
                                      ),
                                      const SizedBox(height: 12),

                                      TextField(
                                        controller: facilityIdController,
                                        decoration: _buildCleanFieldDecoration(
                                          label: 'Facility Tax / License ID',
                                          icon: Icons.verified_outlined,
                                          accentColor: accentColor,
                                        ),
                                      ),
                                      const SizedBox(height: 12),

                                      TextField(
                                        controller: adminSecurityKeyController,
                                        obscureText: true,
                                        decoration: _buildCleanFieldDecoration(
                                          label: 'System Security Passcode',
                                          icon: Icons.key_outlined,
                                          accentColor: accentColor,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 12),

                                    // Password Field with Toggle
                                    TextField(
                                      controller: passwordController,
                                      obscureText: !showRegPassword,
                                      decoration: _buildCleanFieldDecoration(
                                        label: 'Set Account Password',
                                        icon: Icons.lock_outline,
                                        accentColor: accentColor,
                                        suffixIcon: IconButton(
                                          icon: Icon(
                                            showRegPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                            size: 18,
                                          ),
                                          onPressed: () {
                                            setModalState(() {
                                              showRegPassword = !showRegPassword;
                                            });
                                          },
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),

                                    // Terms Checkbox
                                    Row(
                                      children: [
                                        SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: Checkbox(
                                            value: agreeTerms,
                                            activeColor: accentColor,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                            onChanged: (val) => setModalState(() => agreeTerms = val ?? true),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'I agree to DentaGuru $portalRole Terms & Privacy Policy',
                                            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),

                                    // Create Account CTA Button
                                    ElevatedButton.icon(
                                      icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                                      label: Text('Create $portalRole Account', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: agreeTerms ? accentColor : Colors.grey,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                      ),
                                      onPressed: agreeTerms
                                          ? () {
                                              final displayName = nameController.text.trim().isEmpty ? '$portalRole User' : nameController.text.trim();
                                              if (portalRole == 'Patient') {
                                                PatientProblemService().updatePatientProfile(
                                                  name: displayName,
                                                  email: emailController.text,
                                                  phone: phoneController.text,
                                                  age: ageController.text,
                                                  gender: selectedGender ?? 'Female',
                                                  bloodGroup: selectedBloodGroup ?? 'O Positive (O+)',
                                                  emergencyContact: emergencyContactController.text,
                                                  photoBytes: pickedImageBytes,
                                                );
                                              } else if (portalRole == 'Dentist') {
                                                final expNum = int.tryParse(experienceController.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 5;
                                                PatientProblemService().registerDoctor(
                                                  name: displayName,
                                                  email: emailController.text,
                                                  phone: phoneController.text,
                                                  licenseNumber: licenseNoController.text,
                                                  specialty: selectedSpecialty ?? 'General Dentistry',
                                                  clinicName: clinicNameController.text,
                                                  experienceYears: expNum,
                                                );
                                              }
                                              Navigator.of(dialogContext).pop();
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text('🎉 Registered $displayName as $portalRole!'),
                                                  backgroundColor: const Color(0xFF10B981),
                                                  duration: const Duration(seconds: 3),
                                                ),
                                              );
                                              context.go(targetRoute);
                                            }
                                          : null,
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                ),
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
        );
      },
    );
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
        title: const Row(
          children: [
            DentaGuruLogo(height: 34),
            SizedBox(width: 10),
            Text(
              'Portal Selection',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textDark),
            ),
          ],
        ),
      ),
      body: Container(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Professional Card Box with Real Transparent Logo
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                    border: Border.all(color: const Color(0xFFEEF2F6)),
                  ),
                  child: Column(
                    children: [
                      const DentaGuruLogo(height: 60),
                      const SizedBox(height: 10),
                      const Text(
                        'Multi-Vendor Dental Healthcare Ecosystem',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.textDark, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.shield_outlined, size: 12, color: Color(0xFF10B981)),
                            SizedBox(width: 4),
                            Text(
                              'Encrypted Access • HIPAA Compliant',
                              style: TextStyle(fontSize: 10, color: Color(0xFF10B981), fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 1. Patient Portal Card
                _buildPortalLandingCard(
                  context,
                  title: 'Patient Portal',
                  subtitle: 'Book appointments, view treatment plans & digital prescriptions',
                  icon: Icons.person_rounded,
                  accentColor: AppTheme.primaryBlue,
                  defaultEmail: 'sarah.jenkins@dentaguru.com',
                  targetRoute: '/patient',
                  portalRole: 'Patient',
                ),
                const SizedBox(height: 16),

                // 2. Dentist Portal Card
                _buildPortalLandingCard(
                  context,
                  title: 'Dentist Portal',
                  subtitle: 'Practitioner workspace, treatment timelines & patient logs',
                  icon: Icons.medical_services_rounded,
                  accentColor: const Color(0xFF0284C7),
                  defaultEmail: 'dr.rodriguez@dentaguru.com',
                  targetRoute: '/dentist',
                  portalRole: 'Dentist',
                ),
                const SizedBox(height: 16),

                // 3. Admin Dashboard Card
                _buildPortalLandingCard(
                  context,
                  title: 'Admin Dashboard',
                  subtitle: 'Clinic management, staff roles, billing & system configuration',
                  icon: Icons.admin_panel_settings_rounded,
                  accentColor: AppTheme.brandOrange,
                  defaultEmail: 'admin@dentaguru.com',
                  targetRoute: '/admin',
                  portalRole: 'Admin',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _buildCleanFieldDecoration({
    required String label,
    required IconData icon,
    required Color accentColor,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: null, // Zero pre-filled text sitting inside the input!
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      floatingLabelStyle: TextStyle(
        color: accentColor,
        fontWeight: FontWeight.bold,
        fontSize: 13,
      ),
      labelStyle: const TextStyle(
        color: AppTheme.textMuted,
        fontSize: 13,
      ),
      prefixIcon: Icon(icon, size: 18, color: AppTheme.textMuted),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: accentColor, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Widget _buildPortalLandingCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required String defaultEmail,
    required String targetRoute,
    required String portalRole,
  }) {
    return _AnimatedPortalCard(
      title: title,
      subtitle: subtitle,
      icon: icon,
      accentColor: accentColor,
      onTap: () => _showAuthDialog(
        context,
        portalRole: portalRole,
        defaultEmail: defaultEmail,
        targetRoute: targetRoute,
        accentColor: accentColor,
        portalIcon: icon,
        initialTab: 0,
      ),
    );
  }
}

// Custom Animated Portal Card with Hover & Scale Transitions
class _AnimatedPortalCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onTap;

  const _AnimatedPortalCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.onTap,
  });

  @override
  State<_AnimatedPortalCard> createState() => _AnimatedPortalCardState();
}

class _AnimatedPortalCardState extends State<_AnimatedPortalCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isHovered = true),
        onTapUp: (_) {
          setState(() => _isHovered = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          transform: Matrix4.diagonal3Values(_isHovered ? 1.02 : 1.0, _isHovered ? 1.02 : 1.0, 1.0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _isHovered ? widget.accentColor : const Color(0xFFE2E8F0),
              width: _isHovered ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: _isHovered ? widget.accentColor.withValues(alpha: 0.18) : Colors.black.withValues(alpha: 0.04),
                blurRadius: _isHovered ? 18 : 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: widget.accentColor.withValues(alpha: _isHovered ? 0.2 : 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(widget.icon, color: widget.accentColor, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.subtitle,
                        style: const TextStyle(fontSize: 12, color: AppTheme.textMuted, height: 1.3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: widget.accentColor.withValues(alpha: _isHovered ? 0.2 : 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    color: widget.accentColor,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Router Configurations
final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/patient',
      builder: (context, state) => const PatientDashboardScreen(),
    ),
    GoRoute(
      path: '/dentist',
      builder: (context, state) => const DentistTimelineScreen(),
    ),
    GoRoute(
      path: '/clinic',
      builder: (context, state) => const ClinicDashboardScreen(),
    ),
    GoRoute(
      path: '/admin',
      builder: (context, state) => const AdminDashboardScreen(),
    ),
  ],
);
