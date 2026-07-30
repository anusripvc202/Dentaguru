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
    required String portalTitle,
    required String defaultEmail,
    required String targetRoute,
    required Color accentColor,
    required IconData portalIcon,
    int initialTab = 0,
  }) {
    final loginEmailController = TextEditingController(text: defaultEmail);
    final loginPasswordController = TextEditingController(text: 'password123');
    bool showLoginPassword = false;

    final regNameController = TextEditingController(text: 'Sarah Jenkins');
    final regEmailController = TextEditingController(text: 'sarah.jenkins@dentaguru.com');
    final regPhoneController = TextEditingController(text: '+1 202 555 0142');
    final regAgeController = TextEditingController(text: '28');
    final regPasswordController = TextEditingController(text: 'Password@123');
    bool showRegPassword = false;
    bool agreeTerms = true;

    String selectedRole = portalTitle.contains('Dentist')
        ? 'Dentist'
        : portalTitle.contains('Admin')
            ? 'Admin'
            : 'Patient';
    String selectedGender = 'Female';
    String selectedBloodGroup = 'O+';

    final galleryAvatars = [
      'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=150',
      'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150',
      'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=150',
      'https://images.unsplash.com/photo-1622253692010-333f2da6031d?w=150',
    ];
    int selectedAvatarIndex = 0;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return DefaultTabController(
          length: 2,
          initialIndex: initialTab,
          child: StatefulBuilder(
            builder: (context, setModalState) {
              final activeAccent = selectedRole == 'Dentist'
                  ? const Color(0xFF0284C7)
                  : selectedRole == 'Admin'
                      ? AppTheme.brandOrange
                      : AppTheme.primaryBlue;

              return Dialog(
                backgroundColor: Colors.white,
                elevation: 12,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 450, maxHeight: 680),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header info
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: activeAccent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(portalIcon, color: activeAccent, size: 24),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$selectedRole Account Portal',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                      color: AppTheme.textDark,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'DentaGuru Digital Healthcare Network',
                                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
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

                        // Side by Side Tab Switcher (Sign In & Register)
                        Container(
                          height: 48,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: TabBar(
                            indicator: BoxDecoration(
                              color: activeAccent,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: activeAccent.withValues(alpha: 0.3),
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

                        // Tab Content Body
                        Expanded(
                          child: TabBarView(
                            children: [
                              // ================= TAB 1: SIGN IN =================
                              SingleChildScrollView(
                                physics: const BouncingScrollPhysics(),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    const SizedBox(height: 12),
                                    TextField(
                                      controller: loginEmailController,
                                      decoration: InputDecoration(
                                        labelText: 'Email Address',
                                        hintText: 'user@dentaguru.com',
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
                                          style: TextStyle(color: activeAccent, fontWeight: FontWeight.w600, fontSize: 12),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: activeAccent,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                      ),
                                      onPressed: () {
                                        Navigator.of(dialogContext).pop();
                                        context.go(targetRoute);
                                      },
                                      child: const Text('Sign In to Account', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                    ),
                                  ],
                                ),
                              ),

                              // ================= TAB 2: REDESIGNED REGISTER =================
                              SingleChildScrollView(
                                physics: const BouncingScrollPhysics(),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    // 1. Account Role Selector Chips
                                    const Text(
                                      'Select Account Type',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textMuted),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        _buildRoleChip(
                                          title: 'Patient',
                                          icon: Icons.person_rounded,
                                          isSelected: selectedRole == 'Patient',
                                          activeColor: AppTheme.primaryBlue,
                                          onTap: () => setModalState(() => selectedRole = 'Patient'),
                                        ),
                                        const SizedBox(width: 8),
                                        _buildRoleChip(
                                          title: 'Dentist',
                                          icon: Icons.medical_services_rounded,
                                          isSelected: selectedRole == 'Dentist',
                                          activeColor: const Color(0xFF0284C7),
                                          onTap: () => setModalState(() => selectedRole = 'Dentist'),
                                        ),
                                        const SizedBox(width: 8),
                                        _buildRoleChip(
                                          title: 'Clinic',
                                          icon: Icons.local_hospital_rounded,
                                          isSelected: selectedRole == 'Admin',
                                          activeColor: AppTheme.brandOrange,
                                          onTap: () => setModalState(() => selectedRole = 'Admin'),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),

                                    // 2. Avatar Selection Row
                                    Row(
                                      children: [
                                        // Selected avatar display
                                        Stack(
                                          children: [
                                            CircleAvatar(
                                              radius: 28,
                                              backgroundColor: activeAccent.withValues(alpha: 0.15),
                                              backgroundImage: NetworkImage(galleryAvatars[selectedAvatarIndex]),
                                            ),
                                            Positioned(
                                              right: 0,
                                              bottom: 0,
                                              child: Container(
                                                padding: const EdgeInsets.all(4),
                                                decoration: BoxDecoration(
                                                  color: activeAccent,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(color: Colors.white, width: 1.5),
                                                ),
                                                child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 10),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'Choose Profile Avatar',
                                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                                              ),
                                              const SizedBox(height: 6),
                                              SingleChildScrollView(
                                                scrollDirection: Axis.horizontal,
                                                child: Row(
                                                  children: List.generate(galleryAvatars.length, (idx) {
                                                    final isSelected = selectedAvatarIndex == idx;
                                                    return GestureDetector(
                                                      onTap: () => setModalState(() => selectedAvatarIndex = idx),
                                                      child: Container(
                                                        margin: const EdgeInsets.only(right: 8),
                                                        padding: const EdgeInsets.all(2),
                                                        decoration: BoxDecoration(
                                                          shape: BoxShape.circle,
                                                          border: Border.all(
                                                            color: isSelected ? activeAccent : Colors.transparent,
                                                            width: 2,
                                                          ),
                                                        ),
                                                        child: CircleAvatar(
                                                          radius: 14,
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

                                    // 3. Name Field
                                    TextField(
                                      controller: regNameController,
                                      decoration: InputDecoration(
                                        labelText: 'Full Name',
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

                                    // 4. Email Field
                                    TextField(
                                      controller: regEmailController,
                                      decoration: InputDecoration(
                                        labelText: 'Email Address',
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

                                    // 5. Phone & Age Row
                                    Row(
                                      children: [
                                        Expanded(
                                          flex: 3,
                                          child: TextField(
                                            controller: regPhoneController,
                                            decoration: InputDecoration(
                                              labelText: 'Phone',
                                              prefixIcon: const Icon(Icons.phone_outlined, size: 18),
                                              filled: true,
                                              fillColor: const Color(0xFFF8FAFC),
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(12),
                                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                              ),
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          flex: 2,
                                          child: TextField(
                                            controller: regAgeController,
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
                                    const SizedBox(height: 12),

                                    // 6. Gender Selector
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
                                              selectedColor: activeAccent.withValues(alpha: 0.15),
                                              labelStyle: TextStyle(color: isSelected ? activeAccent : AppTheme.textDark),
                                              onSelected: (val) {
                                                if (val) setModalState(() => selectedGender = g);
                                              },
                                            );
                                          }).toList(),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),

                                    // 7. Blood Group Quick Chips
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
                                              selectedColor: activeAccent,
                                              labelStyle: TextStyle(color: isSelected ? Colors.white : AppTheme.textDark, fontWeight: FontWeight.bold),
                                              onSelected: (val) {
                                                if (val) setModalState(() => selectedBloodGroup = bg);
                                              },
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                    const SizedBox(height: 12),

                                    // 8. Password Field with Visibility Toggle
                                    TextField(
                                      controller: regPasswordController,
                                      obscureText: !showRegPassword,
                                      decoration: InputDecoration(
                                        labelText: 'Set Password',
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
                                    const SizedBox(height: 6),

                                    // Password Strength Bar
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Container(
                                            height: 4,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF22C55E),
                                              borderRadius: BorderRadius.circular(2),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        const Text(
                                          'Strong Password',
                                          style: TextStyle(fontSize: 10, color: Color(0xFF16A34A), fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),

                                    // Terms & Privacy Checkbox
                                    Row(
                                      children: [
                                        SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: Checkbox(
                                            value: agreeTerms,
                                            activeColor: activeAccent,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                            onChanged: (val) => setModalState(() => agreeTerms = val ?? true),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        const Expanded(
                                          child: Text(
                                            'I agree to DentaGuru Terms & Privacy Policy',
                                            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),

                                    // Submit Registration Button
                                    ElevatedButton.icon(
                                      icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                                      label: const Text('Create Account', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: agreeTerms ? activeAccent : Colors.grey,
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
                                                  content: Text('🎉 Welcome ${regNameController.text}! Your $selectedRole Account is ready.'),
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

  Widget _buildRoleChip({
    required String title,
    required IconData icon,
    required bool isSelected,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(
            color: isSelected ? activeColor.withValues(alpha: 0.12) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? activeColor : const Color(0xFFE2E8F0),
              width: isSelected ? 1.8 : 1.0,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? activeColor : AppTheme.textMuted, size: 18),
              const SizedBox(height: 4),
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? activeColor : AppTheme.textDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.softBlueBg,
      body: Container(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(
                  child: DentaGuruLogo(height: 64),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Multi-Vendor Dental Healthcare Ecosystem',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 30),

                // 1. Patient Portal Section
                _buildPortalCard(
                  context,
                  title: 'Patient Portal',
                  icon: Icons.person_rounded,
                  accentColor: AppTheme.primaryBlue,
                  defaultEmail: 'sarah.jenkins@dentaguru.com',
                  targetRoute: '/patient',
                ),
                const SizedBox(height: 14),

                // 2. Dentist Portal Section
                _buildPortalCard(
                  context,
                  title: 'Dentist Portal',
                  icon: Icons.medical_services_rounded,
                  accentColor: const Color(0xFF0284C7),
                  defaultEmail: 'dr.rodriguez@dentaguru.com',
                  targetRoute: '/dentist',
                ),
                const SizedBox(height: 14),

                // 3. Admin Dashboard Section
                _buildPortalCard(
                  context,
                  title: 'Admin Dashboard',
                  icon: Icons.admin_panel_settings_rounded,
                  accentColor: AppTheme.brandOrange,
                  defaultEmail: 'admin@dentaguru.com',
                  targetRoute: '/admin',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPortalCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color accentColor,
    required String defaultEmail,
    required String targetRoute,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accentColor, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textDark),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              // Side by Side Login Button
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.login_rounded, size: 16),
                  label: const Text('Sign In', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _showAuthDialog(
                    context,
                    portalTitle: '$title Sign In',
                    defaultEmail: defaultEmail,
                    targetRoute: targetRoute,
                    accentColor: accentColor,
                    portalIcon: icon,
                    initialTab: 0,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Side by Side Register Button
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.person_add_rounded, size: 16),
                  label: const Text('Register', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: accentColor, width: 1.5),
                    foregroundColor: accentColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _showAuthDialog(
                    context,
                    portalTitle: '$title Register',
                    defaultEmail: defaultEmail,
                    targetRoute: targetRoute,
                    accentColor: accentColor,
                    portalIcon: icon,
                    initialTab: 1,
                  ),
                ),
              ),
            ],
          ),
        ],
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
