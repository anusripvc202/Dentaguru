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
  void _showLoginDialog(
    BuildContext context, {
    required String portalTitle,
    required String defaultEmail,
    required String targetRoute,
    required Color accentColor,
    required IconData portalIcon,
  }) {
    final emailController = TextEditingController(text: defaultEmail);
    final passwordController = TextEditingController(text: 'password123');

    showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.white,
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                            'Sign in to access your dashboard',
                            style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: emailController,
                  decoration: InputDecoration(
                    labelText: 'Email Address',
                    prefixIcon: const Icon(Icons.email_outlined, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  ),
                ),
                const SizedBox(height: 22),
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
        );
      },
    );
  }

  void _showRegisterDialog(BuildContext context) {
    String selectedBloodGroup = 'O Positive';
    String profileImage = 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=150';
    final nameController = TextEditingController(text: 'Sarah Jenkins');
    final emailController = TextEditingController(text: 'sarah.jenkins@dentaguru.com');
    final phoneController = TextEditingController(text: '+1 202 555 0142');
    final ageController = TextEditingController(text: '28 Years');
    final passwordController = TextEditingController(text: 'password123');

    final galleryAvatars = [
      'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=150',
      'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150',
      'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=150',
    ];
    int avatarIndex = 0;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              backgroundColor: Colors.white,
              elevation: 6,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header Title
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.person_add_rounded, color: AppTheme.primaryBlue, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'Patient Registration',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.textDark),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Create your DentaGuru health profile',
                                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Gallery Profile Image Picker
                    Center(
                      child: GestureDetector(
                        onTap: () {
                          setModalState(() {
                            avatarIndex = (avatarIndex + 1) % galleryAvatars.length;
                            profileImage = galleryAvatars[avatarIndex];
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Selected profile image from Gallery!'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                        child: Stack(
                          children: [
                            CircleAvatar(
                              radius: 38,
                              backgroundColor: AppTheme.softBlueCard,
                              backgroundImage: NetworkImage(profileImage),
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: AppTheme.primaryBlue,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Center(
                      child: Text(
                        'Tap photo to add image from Gallery',
                        style: TextStyle(fontSize: 11, color: AppTheme.primaryBlue, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Name Field
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon: const Icon(Icons.person_outline_rounded, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Email Field
                    TextField(
                      controller: emailController,
                      decoration: InputDecoration(
                        labelText: 'Email Address',
                        prefixIcon: const Icon(Icons.email_outlined, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Phone Field
                    TextField(
                      controller: phoneController,
                      decoration: InputDecoration(
                        labelText: 'Phone Number',
                        prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Blood Group & Age Fields (Row)
                    Row(
                      children: [
                        // Blood Group Dropdown
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<String>(
                            value: selectedBloodGroup,
                            decoration: InputDecoration(
                              labelText: 'Blood Group',
                              prefixIcon: const Icon(Icons.bloodtype_outlined, size: 20),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                            ),
                            items: [
                              'O Positive',
                              'A Positive',
                              'B Positive',
                              'AB Positive',
                              'O Negative',
                              'A Negative',
                              'B Negative',
                              'AB Negative',
                            ].map((bg) {
                              return DropdownMenuItem(
                                value: bg,
                                child: Text(bg, style: const TextStyle(fontSize: 13)),
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
                        const SizedBox(width: 10),

                        // Age Field
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: ageController,
                            decoration: InputDecoration(
                              labelText: 'Age',
                              prefixIcon: const Icon(Icons.cake_outlined, size: 20),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Password Field
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 22),

                    // Submit Registration Button
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Welcome ${nameController.text}! Account Registered Successfully.'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                        context.go('/patient');
                      },
                      child: const Text('Register Account', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ],
                ),
              ),
            );
          },
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
                const SizedBox(height: 12),
                const Text(
                  'Multi-Vendor Dental Healthcare Ecosystem',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 36),

                // 1. Patient Portal Button
                ElevatedButton.icon(
                  icon: const Icon(Icons.person),
                  label: const Text('Access Patient Portal', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => _showLoginDialog(
                    context,
                    portalTitle: 'Patient Portal Sign In',
                    defaultEmail: 'sarah.jenkins@dentaguru.com',
                    targetRoute: '/patient',
                    accentColor: AppTheme.primaryBlue,
                    portalIcon: Icons.person_outline_rounded,
                  ),
                ),
                const SizedBox(height: 14),

                // 2. Dentist Portal Button
                ElevatedButton.icon(
                  icon: const Icon(Icons.medical_services),
                  label: const Text('Access Dentist Portal', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => _showLoginDialog(
                    context,
                    portalTitle: 'Dentist Practitioner Sign In',
                    defaultEmail: 'dr.rodriguez@dentaguru.com',
                    targetRoute: '/dentist',
                    accentColor: const Color(0xFF0284C7),
                    portalIcon: Icons.medical_services_outlined,
                  ),
                ),
                const SizedBox(height: 14),

                // 3. Admin Dashboard Button
                ElevatedButton.icon(
                  icon: const Icon(Icons.admin_panel_settings),
                  label: const Text('Access Admin Dashboard', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.brandOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => _showLoginDialog(
                    context,
                    portalTitle: 'Super Admin Portal Sign In',
                    defaultEmail: 'admin@dentaguru.com',
                    targetRoute: '/admin',
                    accentColor: AppTheme.brandOrange,
                    portalIcon: Icons.admin_panel_settings_outlined,
                  ),
                ),
                const SizedBox(height: 14),

                // 4. Register Patient Account Button
                OutlinedButton.icon(
                  icon: const Icon(Icons.person_add_rounded),
                  label: const Text('Register Patient Account', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: AppTheme.primaryBlue, width: 1.5),
                    foregroundColor: AppTheme.primaryBlue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => _showRegisterDialog(context),
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
