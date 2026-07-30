import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../widgets/denta_guru_logo.dart';
import '../theme/app_theme.dart';
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
    // Form Controllers
    final loginEmailController = TextEditingController(text: defaultEmail);
    final loginPasswordController = TextEditingController(text: 'password123');
    bool showLoginPassword = false;

    // Common Registration Fields
    final nameController = TextEditingController(
      text: portalRole == 'Dentist'
          ? 'Dr. Sarah Jenkins'
          : portalRole == 'Admin'
              ? 'Robert Vance'
              : 'Sarah Jenkins',
    );
    final emailController = TextEditingController(text: defaultEmail);
    final phoneController = TextEditingController(text: '+1 202 555 0142');
    final passwordController = TextEditingController(text: 'Password@123');
    bool showRegPassword = false;
    bool agreeTerms = true;

    // Patient Specific
    final ageController = TextEditingController(text: '28');
    final emergencyContactController = TextEditingController(text: '+1 202 555 9988');
    String selectedGender = 'Female';
    String selectedBloodGroup = 'O+';

    // Dentist Specific
    final licenseNoController = TextEditingController(text: 'DEN-884920-US');
    final clinicNameController = TextEditingController(text: 'Apex Dental Care & Implant Center');
    final experienceController = TextEditingController(text: '8 Years');
    String selectedSpecialty = 'Orthodontics';

    // Admin Specific
    final adminTitleController = TextEditingController(text: 'Chief Medical Administrator');
    final facilityIdController = TextEditingController(text: 'FAC-FL-90210');
    final adminSecurityKeyController = TextEditingController(text: 'ADM-SEC-9901');

    final galleryAvatars = [
      'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=150',
      'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150',
      'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=150',
      'https://images.unsplash.com/photo-1622253692010-333f2da6031d?w=150',
    ];
    int selectedAvatarIndex = portalRole == 'Dentist' ? 3 : 0;

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
                elevation: 12,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 460, maxHeight: 690),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Dialog Header
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(portalIcon, color: accentColor, size: 24),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$portalRole Access Portal',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                      color: AppTheme.textDark,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'DentaGuru Digital Network • $portalRole Module',
                                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
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
                        const SizedBox(height: 16),

                        // Side by Side Tab Bar (Sign In & Register)
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
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                                      decoration: InputDecoration(
                                        labelText: '$portalRole Email / ID',
                                        prefixIcon: const Icon(Icons.email_outlined, size: 20),
                                        filled: true,
                                        fillColor: const Color(0xFFF8FAFC),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(14),
                                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                        ),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                      ),
                                    ),
                                    const SizedBox(height: 14),

                                    TextField(
                                      controller: loginPasswordController,
                                      obscureText: !showLoginPassword,
                                      decoration: InputDecoration(
                                        labelText: 'Password',
                                        prefixIcon: const Icon(Icons.lock_outline, size: 20),
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
                                        filled: true,
                                        fillColor: const Color(0xFFF8FAFC),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(14),
                                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                        ),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                                        Navigator.of(dialogContext).pop();
                                        context.go(targetRoute);
                                      },
                                      child: Text('Sign In as $portalRole', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                    ),
                                  ],
                                ),
                              ),

                              // ================= 2. REGISTER FORM =================
                              SingleChildScrollView(
                                physics: const BouncingScrollPhysics(),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    const SizedBox(height: 6),
                                    // Avatar Selection Header
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 26,
                                          backgroundColor: accentColor.withValues(alpha: 0.15),
                                          backgroundImage: NetworkImage(galleryAvatars[selectedAvatarIndex]),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '$portalRole Profile Photo',
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textDark),
                                              ),
                                              const SizedBox(height: 4),
                                              SingleChildScrollView(
                                                scrollDirection: Axis.horizontal,
                                                child: Row(
                                                  children: List.generate(galleryAvatars.length, (idx) {
                                                    final isSelected = selectedAvatarIndex == idx;
                                                    return GestureDetector(
                                                      onTap: () => setModalState(() => selectedAvatarIndex = idx),
                                                      child: Container(
                                                        margin: const EdgeInsets.only(right: 6),
                                                        padding: const EdgeInsets.all(2),
                                                        decoration: BoxDecoration(
                                                          shape: BoxShape.circle,
                                                          border: Border.all(
                                                            color: isSelected ? accentColor : Colors.transparent,
                                                            width: 2,
                                                          ),
                                                        ),
                                                        child: CircleAvatar(
                                                          radius: 12,
                                                          backgroundImage: NetworkImage(galleryAvatars[idx]),
                                                        ),
                                                      ),
                                                    );
                                                  }),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),

                                    // Field 1: Name / Title
                                    TextField(
                                      controller: nameController,
                                      decoration: InputDecoration(
                                        labelText: portalRole == 'Dentist'
                                            ? 'Full Name & Title (e.g. Dr. John Doe, DDS)'
                                            : portalRole == 'Admin'
                                                ? 'Administrator Full Name'
                                                : 'Patient Full Name',
                                        prefixIcon: const Icon(Icons.person_outline_rounded, size: 18),
                                        filled: true,
                                        fillColor: const Color(0xFFF8FAFC),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                        ),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      ),
                                    ),
                                    const SizedBox(height: 10),

                                    // Field 2: Email
                                    TextField(
                                      controller: emailController,
                                      decoration: InputDecoration(
                                        labelText: '$portalRole Email Address',
                                        prefixIcon: const Icon(Icons.email_outlined, size: 18),
                                        filled: true,
                                        fillColor: const Color(0xFFF8FAFC),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                        ),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      ),
                                    ),
                                    const SizedBox(height: 10),

                                    // ============ ROLE-SPECIFIC FIELDS ============
                                    if (portalRole == 'Patient') ...[
                                      // Patient Specific: Phone & Age Row
                                      Row(
                                        children: [
                                          Expanded(
                                            flex: 3,
                                            child: TextField(
                                              controller: phoneController,
                                              decoration: InputDecoration(
                                                labelText: 'Phone Number',
                                                prefixIcon: const Icon(Icons.phone_outlined, size: 18),
                                                filled: true,
                                                fillColor: const Color(0xFFF8FAFC),
                                                border: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(12),
                                                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                                ),
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            flex: 2,
                                            child: TextField(
                                              controller: ageController,
                                              decoration: InputDecoration(
                                                labelText: 'Age',
                                                prefixIcon: const Icon(Icons.cake_outlined, size: 18),
                                                filled: true,
                                                fillColor: const Color(0xFFF8FAFC),
                                                border: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(12),
                                                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                                ),
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),

                                      // Gender Chips
                                      Row(
                                        children: [
                                          const Text('Gender: ', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppTheme.textMuted)),
                                          const SizedBox(width: 8),
                                          Wrap(
                                            spacing: 6,
                                            children: ['Female', 'Male', 'Other'].map((g) {
                                              final isSelected = selectedGender == g;
                                              return ChoiceChip(
                                                label: Text(g, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                                                selected: isSelected,
                                                selectedColor: accentColor.withValues(alpha: 0.15),
                                                labelStyle: TextStyle(color: isSelected ? accentColor : AppTheme.textDark),
                                                onSelected: (val) {
                                                  if (val) setModalState(() => selectedGender = g);
                                                },
                                              );
                                            }).toList(),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),

                                      // Blood Group Chips
                                      const Text('Blood Group', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppTheme.textMuted)),
                                      const SizedBox(height: 6),
                                      SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: Row(
                                          children: ['O+', 'A+', 'B+', 'AB+', 'O-', 'A-'].map((bg) {
                                            final isSelected = selectedBloodGroup == bg;
                                            return Padding(
                                              padding: const EdgeInsets.only(right: 6),
                                              child: ChoiceChip(
                                                label: Text(bg, style: const TextStyle(fontSize: 11)),
                                                selected: isSelected,
                                                selectedColor: accentColor,
                                                labelStyle: TextStyle(color: isSelected ? Colors.white : AppTheme.textDark, fontWeight: FontWeight.bold),
                                                onSelected: (val) {
                                                  if (val) setModalState(() => selectedBloodGroup = bg);
                                                },
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                      const SizedBox(height: 10),

                                      // Emergency Contact
                                      TextField(
                                        controller: emergencyContactController,
                                        decoration: InputDecoration(
                                          labelText: 'Emergency Contact Phone',
                                          prefixIcon: const Icon(Icons.contact_phone_outlined, size: 18),
                                          filled: true,
                                          fillColor: const Color(0xFFF8FAFC),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                          ),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                        ),
                                      ),
                                    ] else if (portalRole == 'Dentist') ...[
                                      // Dentist Specific: License No. & Specialty
                                      TextField(
                                        controller: licenseNoController,
                                        decoration: InputDecoration(
                                          labelText: 'Dental License Registration No.',
                                          prefixIcon: const Icon(Icons.badge_outlined, size: 18),
                                          filled: true,
                                          fillColor: const Color(0xFFF8FAFC),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                          ),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                        ),
                                      ),
                                      const SizedBox(height: 10),

                                      // Specialty Dropdown
                                      DropdownButtonFormField<String>(
                                        value: selectedSpecialty,
                                        decoration: InputDecoration(
                                          labelText: 'Dental Specialization',
                                          prefixIcon: const Icon(Icons.medical_services_outlined, size: 18),
                                          filled: true,
                                          fillColor: const Color(0xFFF8FAFC),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                          ),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                        ),
                                        items: [
                                          'Orthodontics',
                                          'Endodontics',
                                          'Periodontics',
                                          'Pediatric Dentistry',
                                          'Oral & Maxillofacial Surgery',
                                          'General Dentistry',
                                        ].map((sp) {
                                          return DropdownMenuItem(
                                            value: sp,
                                            child: Text(sp, style: const TextStyle(fontSize: 12)),
                                          );
                                        }).toList(),
                                        onChanged: (val) {
                                          if (val != null) {
                                            setModalState(() => selectedSpecialty = val);
                                          }
                                        },
                                      ),
                                      const SizedBox(height: 10),

                                      // Clinic Name & Experience
                                      Row(
                                        children: [
                                          Expanded(
                                            flex: 3,
                                            child: TextField(
                                              controller: clinicNameController,
                                              decoration: InputDecoration(
                                                labelText: 'Clinic / Practice Name',
                                                prefixIcon: const Icon(Icons.location_city_outlined, size: 18),
                                                filled: true,
                                                fillColor: const Color(0xFFF8FAFC),
                                                border: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(12),
                                                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                                ),
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            flex: 2,
                                            child: TextField(
                                              controller: experienceController,
                                              decoration: InputDecoration(
                                                labelText: 'Experience',
                                                prefixIcon: const Icon(Icons.work_history_outlined, size: 18),
                                                filled: true,
                                                fillColor: const Color(0xFFF8FAFC),
                                                border: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(12),
                                                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                                ),
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ] else if (portalRole == 'Admin') ...[
                                      // Admin Specific: Admin Title & Facility ID
                                      TextField(
                                        controller: adminTitleController,
                                        decoration: InputDecoration(
                                          labelText: 'Administrative Designation Title',
                                          prefixIcon: const Icon(Icons.admin_panel_settings_outlined, size: 18),
                                          filled: true,
                                          fillColor: const Color(0xFFF8FAFC),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                          ),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                        ),
                                      ),
                                      const SizedBox(height: 10),

                                      TextField(
                                        controller: facilityIdController,
                                        decoration: InputDecoration(
                                          labelText: 'Healthcare Facility Tax / License ID',
                                          prefixIcon: const Icon(Icons.verified_outlined, size: 18),
                                          filled: true,
                                          fillColor: const Color(0xFFF8FAFC),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                          ),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                        ),
                                      ),
                                      const SizedBox(height: 10),

                                      TextField(
                                        controller: adminSecurityKeyController,
                                        obscureText: true,
                                        decoration: InputDecoration(
                                          labelText: 'System Security Passcode',
                                          prefixIcon: const Icon(Icons.key_outlined, size: 18),
                                          filled: true,
                                          fillColor: const Color(0xFFF8FAFC),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                          ),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 10),

                                    // Password Field with Toggle
                                    TextField(
                                      controller: passwordController,
                                      obscureText: !showRegPassword,
                                      decoration: InputDecoration(
                                        labelText: 'Set Account Password',
                                        prefixIcon: const Icon(Icons.lock_outline, size: 18),
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
                                        filled: true,
                                        fillColor: const Color(0xFFF8FAFC),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                        ),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                                        elevation: 2,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      onPressed: agreeTerms
                                          ? () {
                                              Navigator.of(dialogContext).pop();
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text('🎉 Registered ${nameController.text} as $portalRole!'),
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
      body: Container(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(
                  child: DentaGuruLogo(height: 68),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Multi-Vendor Dental Healthcare Ecosystem',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 32),

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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _showAuthDialog(
            context,
            portalRole: portalRole,
            defaultEmail: defaultEmail,
            targetRoute: targetRoute,
            accentColor: accentColor,
            portalIcon: icon,
            initialTab: 0,
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: accentColor, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(fontSize: 12, color: AppTheme.textMuted, height: 1.3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.arrow_forward_rounded, color: accentColor, size: 20),
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
