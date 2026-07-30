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

    final regNameController = TextEditingController(text: 'Sarah Jenkins');
    final regEmailController = TextEditingController(text: 'sarah.jenkins@dentaguru.com');
    final regPhoneController = TextEditingController(text: '+1 202 555 0142');
    final regAgeController = TextEditingController(text: '28 Years');
    final regPasswordController = TextEditingController(text: 'password123');
    String selectedBloodGroup = 'O Positive';
    String profileImage = 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=150';

    final galleryAvatars = [
      'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=150',
      'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150',
      'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=150',
    ];
    int avatarIndex = 0;

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
                elevation: 6,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Portal Header Info
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(portalIcon, color: accentColor, size: 24),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    portalTitle,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 17,
                                      color: AppTheme.textDark,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Access your DentaGuru health portal',
                                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Side by Side Tab Switcher (Sign In & Register)
                        Container(
                          height: 46,
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
                        const SizedBox(height: 20),

                        // Tab Contents
                        SizedBox(
                          height: 380,
                          child: TabBarView(
                            children: [
                              // ----------------- TAB 1: SIGN IN FORM -----------------
                              SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    const SizedBox(height: 10),
                                    TextField(
                                      controller: loginEmailController,
                                      decoration: InputDecoration(
                                        labelText: 'Email Address',
                                        prefixIcon: const Icon(Icons.email_outlined, size: 20),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    TextField(
                                      controller: loginPasswordController,
                                      obscureText: true,
                                      decoration: InputDecoration(
                                        labelText: 'Password',
                                        prefixIcon: const Icon(Icons.lock_outline, size: 20),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: accentColor,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      onPressed: () {
                                        Navigator.of(dialogContext).pop();
                                        context.go(targetRoute);
                                      },
                                      child: const Text('Sign In', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                    ),
                                  ],
                                ),
                              ),

                              // ----------------- TAB 2: REGISTER FORM -----------------
                              SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    // Avatar Picker
                                    Center(
                                      child: GestureDetector(
                                        onTap: () {
                                          setModalState(() {
                                            avatarIndex = (avatarIndex + 1) % galleryAvatars.length;
                                            profileImage = galleryAvatars[avatarIndex];
                                          });
                                        },
                                        child: Stack(
                                          children: [
                                            CircleAvatar(
                                              radius: 30,
                                              backgroundColor: AppTheme.softBlueCard,
                                              backgroundImage: NetworkImage(profileImage),
                                            ),
                                            Positioned(
                                              right: 0,
                                              bottom: 0,
                                              child: Container(
                                                padding: const EdgeInsets.all(5),
                                                decoration: BoxDecoration(
                                                  color: accentColor,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 12),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Center(
                                      child: Text(
                                        'Tap photo to select profile image',
                                        style: TextStyle(fontSize: 10, color: accentColor, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    const SizedBox(height: 12),

                                    TextField(
                                      controller: regNameController,
                                      decoration: InputDecoration(
                                        labelText: 'Full Name',
                                        prefixIcon: const Icon(Icons.person_outline_rounded, size: 18),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                      ),
                                    ),
                                    const SizedBox(height: 10),

                                    TextField(
                                      controller: regEmailController,
                                      decoration: InputDecoration(
                                        labelText: 'Email Address',
                                        prefixIcon: const Icon(Icons.email_outlined, size: 18),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                      ),
                                    ),
                                    const SizedBox(height: 10),

                                    Row(
                                      children: [
                                        Expanded(
                                          flex: 3,
                                          child: DropdownButtonFormField<String>(
                                            value: selectedBloodGroup,
                                            decoration: InputDecoration(
                                              labelText: 'Blood Group',
                                              prefixIcon: const Icon(Icons.bloodtype_outlined, size: 18),
                                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                                            ),
                                            items: [
                                              'O Positive',
                                              'A Positive',
                                              'B Positive',
                                              'AB Positive',
                                              'O Negative',
                                              'A Negative',
                                            ].map((bg) {
                                              return DropdownMenuItem(
                                                value: bg,
                                                child: Text(bg, style: const TextStyle(fontSize: 12)),
                                              );
                                            }).toList(),
                                            onChanged: (val) {
                                              if (val != null) {
                                                setModalState(() {
                                                  selectedBloodGroup = val;
                                                });
                                              }
                                            },
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
                                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),

                                    TextField(
                                      controller: regPasswordController,
                                      obscureText: true,
                                      decoration: InputDecoration(
                                        labelText: 'Password',
                                        prefixIcon: const Icon(Icons.lock_outline, size: 18),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                      ),
                                    ),
                                    const SizedBox(height: 16),

                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: accentColor,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      onPressed: () {
                                        Navigator.of(dialogContext).pop();
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Welcome ${regNameController.text}! Account Registered.'),
                                            duration: const Duration(seconds: 2),
                                          ),
                                        );
                                        context.go(targetRoute);
                                      },
                                      child: const Text('Register Account', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    ),
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
