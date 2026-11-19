import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/services/session_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../patient/presentation/widgets/referred_patients_sheet.dart';
import 'dentist_timeline.dart';

typedef DentistProfileScreen = DoctorProfileScreen;

class DoctorProfileScreen extends StatefulWidget {
  const DoctorProfileScreen({super.key});

  @override
  State<DoctorProfileScreen> createState() => _DoctorProfileScreenState();
}

class _DoctorProfileScreenState extends State<DoctorProfileScreen> {
  final PatientProblemService _patientService = PatientProblemService();

  static const List<String> availableLanguages = [
    'English',
    'Hindi',
    'Marathi',
    'Tamil',
    'Telugu',
    'Kannada',
    'Malayalam',
    'Bengali',
    'Gujarati',
    'Punjabi',
    'Urdu',
    'Odia',
  ];

  static const String clinicalHelplineNumber = '+911800200100';

  bool _isSavingLanguages = false;

  @override
  void initState() {
    super.initState();
    _patientService.addListener(_onServiceChanged);
    _patientService.syncAllDataFromApi();
    _patientService.syncDoctorReferralsFromApi();
  }

  @override
  void dispose() {
    _patientService.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  DoctorModel _resolveCurrentDoctor() {
    final cur = _patientService.currentDoctor;
    if (cur != null) return cur;

    User? supaUser;
    try {
      supaUser = Supabase.instance.client.auth.currentUser;
    } catch (_) {}

    final session = SessionService().currentSession;
    final fallbackId = supaUser?.id ?? session?.userId ?? 'doc-session';
    final fallbackName = supaUser?.userMetadata?['name'] ?? session?.name ?? 'Dr. Ananya Rao';
    final fallbackPhone = supaUser?.phone ?? session?.phone ?? '+919000000001';
    final fallbackEmail = supaUser?.email ?? session?.email ?? '';

    // Check if doc exists in allDoctors
    for (final d in _patientService.allDoctors) {
      if (d.id == fallbackId || (d.userId.isNotEmpty && d.userId == fallbackId)) {
        return d;
      }
      if (d.phone.isNotEmpty && fallbackPhone.isNotEmpty && d.phone.replaceAll(RegExp(r'\D'), '') == fallbackPhone.replaceAll(RegExp(r'\D'), '')) {
        return d;
      }
    }

    return DoctorModel(
      id: fallbackId,
      userId: fallbackId,
      name: fallbackName,
      specialty: 'Endodontist',
      qualification: 'BDS, MDS (Endodontics)',
      experienceYears: 8,
      rating: 4.9,
      reviewCount: 38,
      clinicName: 'Bandra West Dental Clinic',
      phone: fallbackPhone,
      email: fallbackEmail,
      status: 'Available',
      verificationStatus: 'VERIFIED',
      nextAvailableSlots: const ['Today, 2:00 PM', 'Tomorrow, 10:30 AM'],
      consultationFee: '₹800',
      languages: const ['English', 'Hindi', 'Telugu'],
    );
  }

  Future<void> _toggleLanguage(String language, DoctorModel doc) async {
    if (_isSavingLanguages) return;

    final currentLangs = List<String>.from(doc.languages);
    if (currentLangs.contains(language)) {
      if (currentLangs.length <= 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('At least one consultation language is required.'),
            backgroundColor: AppTheme.gsNavy,
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }
      currentLangs.remove(language);
    } else {
      currentLangs.add(language);
    }

    setState(() {
      _isSavingLanguages = true;
    });

    try {
      await _patientService.updateDoctorProfessionalProfile(
        doctorId: doc.id,
        languages: currentLangs,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Consultation languages updated (${currentLangs.join(", ")})'),
            backgroundColor: AppTheme.gsNavy,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update languages: $e'),
            backgroundColor: AppTheme.gsRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingLanguages = false;
        });
      }
    }
  }

  Future<void> _showEditProfileDialog(BuildContext context, DoctorModel doc) async {
    final nameCtrl = TextEditingController(text: doc.name);
    final phoneCtrl = TextEditingController(text: doc.phone);
    final specialtyCtrl = TextEditingController(text: doc.specialty);
    final qualCtrl = TextEditingController(text: doc.qualification);
    final clinicCtrl = TextEditingController(text: doc.clinicName);
    final feeCtrl = TextEditingController(text: doc.consultationFee);
    final cityCtrl = TextEditingController(text: doc.city);

    final formKey = GlobalKey<FormState>();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Edit Doctor Profile',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Update your professional information on GS HEALTH',
                    style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Doctor Name',
                      prefixIcon: const Icon(Icons.person_outline_rounded),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter doctor name' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Registered Mobile Number',
                      prefixIcon: const Icon(Icons.phone_outlined),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter phone number' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: specialtyCtrl,
                    decoration: InputDecoration(
                      labelText: 'Specialization (e.g. Endodontist)',
                      prefixIcon: const Icon(Icons.medical_services_outlined),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter specialization' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: qualCtrl,
                    decoration: InputDecoration(
                      labelText: 'Qualifications (e.g. BDS, MDS)',
                      prefixIcon: const Icon(Icons.school_outlined),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter qualification' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: clinicCtrl,
                    decoration: InputDecoration(
                      labelText: 'Clinic / Hospital Name',
                      prefixIcon: const Icon(Icons.apartment_rounded),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter clinic name' : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: feeCtrl,
                          decoration: InputDecoration(
                            labelText: 'Consultation Fee',
                            prefixIcon: const Icon(Icons.currency_rupee_rounded),
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: cityCtrl,
                          decoration: InputDecoration(
                            labelText: 'City',
                            prefixIcon: const Icon(Icons.location_city_rounded),
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      key: const Key('save_doctor_profile_button'),
                      onPressed: () async {
                        if (!formKey.currentState!.validate()) return;
                        Navigator.of(sheetCtx).pop();

                        await _patientService.updateDoctorProfessionalProfile(
                          doctorId: doc.id,
                          name: nameCtrl.text.trim(),
                          phone: phoneCtrl.text.trim(),
                          specialty: specialtyCtrl.text.trim(),
                          qualification: qualCtrl.text.trim(),
                          clinicName: clinicCtrl.text.trim(),
                          consultationFee: feeCtrl.text.trim(),
                          city: cityCtrl.text.trim(),
                        );

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Doctor profile updated successfully.'),
                              backgroundColor: AppTheme.gsNavy,
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.gsNavy,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Save Changes',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showDoctorReviewsDialog(BuildContext context, DoctorModel doc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (innerCtx, scrollController) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: ListView(
                controller: scrollController,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Patient Reviews',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Verified feedback from consulted patients',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0x14FE3434),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0x40FE3434)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star_rounded, color: Color(0xFFFE3434), size: 18),
                                const SizedBox(width: 4),
                                Text(
                                  doc.rating.toStringAsFixed(1),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    color: Color(0xFFFE3434),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '(${doc.reviewCount})',
                                  style: const TextStyle(fontSize: 12, color: Color(0xFFFE3434)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            key: const Key('close_reviews_dialog_button'),
                            onPressed: () => Navigator.of(innerCtx).pop(),
                            icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF64748B)),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildReviewCard(
                    patientName: 'Riya Sharma',
                    date: 'Yesterday',
                    rating: 5,
                    comment: 'Dr. ${doc.name.replaceAll("Dr.", "").trim()} was exceptionally thorough and gentle during the root canal procedure. Highly recommended!',
                  ),
                  const SizedBox(height: 10),
                  _buildReviewCard(
                    patientName: 'Kunal Patel',
                    date: '3 days ago',
                    rating: 5,
                    comment: 'Prompt triage response and very clear explanation of post-procedure care.',
                  ),
                  const SizedBox(height: 10),
                  _buildReviewCard(
                    patientName: 'Sneha Rao',
                    date: 'Last week',
                    rating: 5,
                    comment: 'Clinic is hygienic and the consultation started right on schedule. Very satisfied with the treatment.',
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildReviewCard({
    required String patientName,
    required String date,
    required int rating,
    required String comment,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppTheme.gsNavy.withValues(alpha: 0.1),
                child: Text(
                  patientName[0].toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.gsNavy, fontSize: 13),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      patientName,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF0F172A)),
                    ),
                    Text(
                      date,
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ),
              Row(
                children: List.generate(
                  5,
                  (index) => Icon(
                    index < rating ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: const Color(0xFFFE3434),
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            comment,
            style: const TextStyle(fontSize: 13, color: Color(0xFF334155), height: 1.4),
          ),
        ],
      ),
    );
  }

  Future<void> _callHelpline(BuildContext context) async {
    final uri = Uri.parse('tel:$clinicalHelplineNumber');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Clinical care helpline: $clinicalHelplineNumber'),
              backgroundColor: AppTheme.gsNavy,
            ),
          );
        }
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Clinical care helpline: $clinicalHelplineNumber'),
            backgroundColor: AppTheme.gsNavy,
          ),
        );
      }
    }
  }

  void _showTermsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Terms of Use',
          key: Key('terms_dialog_title'),
          style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.gsNavy),
        ),
        content: const SingleChildScrollView(
          child: Text(
            'GS HEALTH Clinical Provider Terms of Use:\n\n'
            '1. Provider Conduct: Licensed doctors agree to maintain clinical confidentiality and uphold national dental medical council ethical codes.\n\n'
            '2. Digital Prescriptions: E-prescriptions issued through GS HEALTH carry legal validity under telemedicine guidelines.\n\n'
            '3. Patient Referrals: Inter-specialty referrals must be conducted with accurate patient notes and prompt specialist triage.\n\n'
            '4. Availability & Appointments: Verified practitioners agree to maintain accurate consultation schedules and respect booked time slots.',
            style: TextStyle(fontSize: 13.5, height: 1.5, color: Color(0xFF334155)),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('close_terms_dialog_button'),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close', style: TextStyle(color: AppTheme.gsNavy, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showPrivacyDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Privacy Policy',
          key: Key('privacy_dialog_title'),
          style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.gsNavy),
        ),
        content: const SingleChildScrollView(
          child: Text(
            'GS HEALTH Provider Privacy Policy:\n\n'
            '1. Provider Data: Personal phone numbers, license credentials, and medical degrees are encrypted and verified against medical registries.\n\n'
            '2. Consultation Security: Clinical chats, diagnostic scans, and appointment logs are end-to-end encrypted.\n\n'
            '3. Patient Access Control: Patient contact details are restricted exclusively to authorized and assigned doctors.',
            style: TextStyle(fontSize: 13.5, height: 1.5, color: Color(0xFF334155)),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('close_privacy_dialog_button'),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close', style: TextStyle(color: AppTheme.gsNavy, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Log out?',
          style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
        ),
        content: const Text(
          'Are you sure you want to log out of your doctor workspace? Unsaved changes will be lost.',
          style: TextStyle(fontSize: 14, color: Color(0xFF475569), height: 1.4),
        ),
        actions: [
          TextButton(
            key: const Key('cancel_logout_button'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.gsNavy)),
          ),
          ElevatedButton(
            key: const Key('confirm_logout_button'),
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.gsRed,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Log out', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await SessionService().clearSession();
    await _patientService.clearAllDataAndStorage();

    if (!mounted || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Logged out of Doctor workspace.'),
        backgroundColor: AppTheme.gsNavy,
        duration: Duration(seconds: 2),
      ),
    );
    try {
      context.go('/login');
    } catch (_) {}
  }

  Future<void> _confirmAndDeleteDoctorAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Delete my account?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        content: const Text(
          'Are you sure you want to permanently delete your GS HEALTH Doctor account, clinical profile, and practice listings? This action cannot be undone.',
          style: TextStyle(fontSize: 14, color: Color(0xFF475569), height: 1.4),
        ),
        actions: [
          TextButton(
            key: const Key('cancel_delete_account_button'),
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppTheme.gsNavy,
              ),
            ),
          ),
          ElevatedButton(
            key: const Key('confirm_delete_account_button'),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.gsRed,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text(
              'Delete account',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _patientService.deleteCurrentDoctorAccount();
    await SessionService().clearSession();

    if (!mounted || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Your Doctor account has been permanently deleted.'),
        backgroundColor: AppTheme.gsNavy,
      ),
    );
    try {
      context.go('/login');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final doc = _resolveCurrentDoctor();
    final selectedLangs = doc.languages.isNotEmpty ? doc.languages : const ['English'];

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Bar: Circular Back Button & Title
              Row(
                children: [
                  InkWell(
                    key: const Key('doctor_profile_back_button'),
                    onTap: () {
                      if (Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      } else {
                        context.go('/dentist');
                      }
                    },
                    borderRadius: BorderRadius.circular(22),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.chevron_left_rounded,
                          color: Color(0xFF0F172A),
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    'Profile',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // 1. Profile Header Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Avatar Squircle (Red / Doctor photo)
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: AppTheme.gsRed,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: doc.photoBytes != null && doc.photoBytes!.isNotEmpty
                            ? Image.memory(doc.photoBytes!, fit: BoxFit.cover)
                            : const Center(
                                child: Icon(
                                  Icons.person_rounded,
                                  color: Colors.white,
                                  size: 42,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Doctor Name
                    Text(
                      doc.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.3,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),

                    // Role Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: const Text(
                        'Doctor',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Registered Mobile Number with phone icon
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.phone_outlined,
                          size: 16,
                          color: Color(0xFF64748B),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            doc.phone.isNotEmpty ? doc.phone : '+91 90000 00001',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Edit Profile Button
                    OutlinedButton.icon(
                      key: const Key('doctor_profile_edit_button'),
                      onPressed: () => _showEditProfileDialog(context, doc),
                      icon: const Icon(
                        Icons.edit_outlined,
                        size: 16,
                        color: Color(0xFF0F172A),
                      ),
                      label: const Text(
                        'Edit profile',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: const Color(0xFFF8FAFC),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 2. Languages You Consult In Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          'LANGUAGES YOU CONSULT IN',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF64748B),
                            letterSpacing: 0.5,
                          ),
                        ),
                        Container(
                          key: const Key('doctor_profile_saved_languages_badge'),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0x14012A58),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'Saved: ${selectedLangs.join(", ")}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.gsNavy,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 10,
                      children: availableLanguages.map((lang) {
                        final isSelected = selectedLangs.contains(lang);
                        return InkWell(
                          key: Key('doctor_language_chip_$lang'),
                          onTap: () => _toggleLanguage(lang, doc),
                          borderRadius: BorderRadius.circular(22),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                            decoration: BoxDecoration(
                              color: isSelected ? AppTheme.gsNavy : Colors.white,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: isSelected ? AppTheme.gsNavy : const Color(0xFFE2E8F0),
                                width: 1.2,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: AppTheme.gsNavy.withValues(alpha: 0.15),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Text(
                              lang,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                color: isSelected ? Colors.white : const Color(0xFF1E293B),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 3. Practice Details Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PRACTICE',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF64748B),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Specialization
                    Text(
                      doc.specialty.isNotEmpty ? doc.specialty : 'General Dentistry',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Qualifications
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.school_outlined,
                          size: 18,
                          color: Color(0xFF64748B),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            doc.qualification.isNotEmpty ? doc.qualification : 'BDS, MDS',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Clinic Name
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.apartment_rounded,
                          size: 18,
                          color: Color(0xFF64748B),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            doc.clinicName.isNotEmpty ? doc.clinicName : 'GS HEALTH Care Center',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Languages Known Summary Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.translate_rounded,
                          size: 18,
                          color: Color(0xFF64748B),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Languages Known: ${selectedLangs.join(", ")}',
                            key: const Key('doctor_profile_languages_summary'),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF334155),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Verification Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0x14012A58),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0x40012A58)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            doc.verified ? Icons.check_circle_rounded : Icons.shield_outlined,
                            size: 15,
                            color: const Color(0xFFFE3434),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            doc.verified ? 'VERIFIED ON GS HEALTH' : 'PENDING VERIFICATION ON GS HEALTH',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF012A58),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 4. Profile Menu Card
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    _buildMenuItem(
                      key: const Key('doctor_profile_referrals_button'),
                      icon: Icons.hub_outlined,
                      title: 'Referrals',
                      onTap: () => ReferredPatientsSheet.show(context),
                    ),
                    const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
                    _buildMenuItem(
                      key: const Key('doctor_profile_refer_specialist_button'),
                      icon: Icons.person_add_outlined,
                      title: 'Refer to a specialist or clinic',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const DentistTimelineScreen(initialTabIndex: 3),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
                    _buildMenuItem(
                      key: const Key('doctor_profile_reviews_button'),
                      icon: Icons.star_outline_rounded,
                      title: 'Patient reviews',
                      onTap: () => _showDoctorReviewsDialog(context, doc),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 5. NEED HELP? Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: InkWell(
                  onTap: () => _callHelpline(context),
                  borderRadius: BorderRadius.circular(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'NEED HELP?',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF64748B),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.call_outlined,
                            size: 16,
                            color: AppTheme.gsNavy.withValues(alpha: 0.8),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Call our 24/7 clinical care helpline for medical emergencies, appointments and consultations.',
                        style: TextStyle(
                          fontSize: 13.5,
                          color: Color(0xFF334155),
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 6. Account Actions Stack
              Column(
                children: [
                  // Log Out Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      key: const Key('doctor_profile_logout_button'),
                      onPressed: () => _confirmLogout(context),
                      icon: const Icon(
                        Icons.logout_rounded,
                        color: AppTheme.gsRed,
                        size: 18,
                      ),
                      label: const Text(
                        'Log out',
                        style: TextStyle(
                          color: AppTheme.gsRed,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: AppTheme.gsRed.withValues(alpha: 0.08),
                        side: BorderSide(color: AppTheme.gsRed.withValues(alpha: 0.2)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Terms of Use
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      key: const Key('doctor_profile_terms_button'),
                      onPressed: () => _showTermsDialog(context),
                      icon: const Icon(
                        Icons.description_outlined,
                        color: Color(0xFF0F172A),
                        size: 18,
                      ),
                      label: const Text(
                        'Terms of Use',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Privacy Policy
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      key: const Key('doctor_profile_privacy_button'),
                      onPressed: () => _showPrivacyDialog(context),
                      icon: const Icon(
                        Icons.shield_outlined,
                        color: Color(0xFF0F172A),
                        size: 18,
                      ),
                      label: const Text(
                        'Privacy Policy',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Delete My Account
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      key: const Key('doctor_profile_delete_account_button'),
                      onPressed: () => _confirmAndDeleteDoctorAccount(context),
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: Color(0xFF0F172A),
                        size: 18,
                      ),
                      label: const Text(
                        'Delete my account',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required Key key,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: const Color(0xFF0F172A),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: Color(0xFF94A3B8),
            ),
          ],
        ),
      ),
    );
  }
}
