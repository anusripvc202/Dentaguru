import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/services/api_service.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/services/session_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/denta_guru_logo.dart';
import 'admin_referrals_screen.dart';

class AdminProfileScreen extends StatefulWidget {
  const AdminProfileScreen({super.key});

  @override
  State<AdminProfileScreen> createState() => _AdminProfileScreenState();
}

class _AdminProfileScreenState extends State<AdminProfileScreen> {
  final PatientProblemService _problemService = PatientProblemService();

  static const String clinicalHelplineNumber = '+911800200100';

  bool _isSavingProfile = false;

  @override
  void initState() {
    super.initState();
    _problemService.addListener(_onServiceChanged);
    _problemService.syncAdminReferralsFromApi();
  }

  @override
  void dispose() {
    _problemService.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  // ── Resolve Admin Details ──

  String _resolveAdminName() {
    final session = SessionService().currentSession;
    if (session?.name != null && session!.name!.trim().isNotEmpty) {
      return session.name!.trim();
    }
    User? supaUser;
    try {
      supaUser = Supabase.instance.client.auth.currentUser;
    } catch (_) {}
    final supaName = supaUser?.userMetadata?['name']?.toString();
    if (supaName != null && supaName.trim().isNotEmpty) {
      return supaName.trim();
    }
    if (session?.email != null && session!.email!.trim().isNotEmpty) {
      final emailPrefix = session.email!.split('@').first;
      return emailPrefix.isNotEmpty ? emailPrefix : 'Admin';
    }
    return 'Admin';
  }

  String _resolveAdminPhone() {
    final session = SessionService().currentSession;
    if (session?.phone != null && session!.phone!.trim().isNotEmpty) {
      return session.phone!.trim();
    }
    User? supaUser;
    try {
      supaUser = Supabase.instance.client.auth.currentUser;
    } catch (_) {}
    if (supaUser?.phone != null && supaUser!.phone!.trim().isNotEmpty) {
      return supaUser.phone!.trim();
    }
    final metaPhone = session?.metadata['phone']?.toString();
    if (metaPhone != null && metaPhone.trim().isNotEmpty) {
      return metaPhone.trim();
    }
    return '';
  }

  String _resolveAdminLocation() {
    final session = SessionService().currentSession;
    final metaLoc = session?.metadata['location']?.toString() ??
        session?.metadata['city']?.toString();
    if (metaLoc != null && metaLoc.trim().isNotEmpty) {
      return metaLoc.trim();
    }
    User? supaUser;
    try {
      supaUser = Supabase.instance.client.auth.currentUser;
    } catch (_) {}
    final supaLoc = supaUser?.userMetadata?['location']?.toString() ??
        supaUser?.userMetadata?['city']?.toString();
    if (supaLoc != null && supaLoc.trim().isNotEmpty) {
      return supaLoc.trim();
    }
    return 'Not specified';
  }

  String _getInitials(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return 'AD';
    final parts = clean.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return clean.substring(0, clean.length >= 2 ? 2 : 1).toUpperCase();
  }

  // ── Edit Profile Modal Sheet ──

  Future<void> _showEditAdminProfileSheet(BuildContext context) async {
    final initialName = _resolveAdminName();
    final initialPhone = _resolveAdminPhone();
    final initialLocation = _resolveAdminLocation();

    final nameCtrl = TextEditingController(text: initialName);
    final phoneCtrl = TextEditingController(text: initialPhone);
    final locationCtrl = TextEditingController(text: initialLocation);
    final formKey = GlobalKey<FormState>();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
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
                          width: 44,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFFCBD5E1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Edit Profile',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Update administrator contact and location information',
                        style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        key: const Key('admin_edit_name_input'),
                        controller: nameCtrl,
                        decoration: InputDecoration(
                          labelText: 'Admin Full Name',
                          hintText: 'Enter your full name',
                          prefixIcon: const Icon(Icons.person_outline_rounded, color: Color(0xFF64748B)),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
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
                            borderSide: const BorderSide(color: AppTheme.gsNavy, width: 1.5),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter administrator name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        key: const Key('admin_edit_phone_input'),
                        controller: phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: 'Phone Number',
                          hintText: '+919550686566',
                          prefixIcon: const Icon(Icons.phone_outlined, color: Color(0xFF64748B)),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
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
                            borderSide: const BorderSide(color: AppTheme.gsNavy, width: 1.5),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter contact number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        key: const Key('admin_edit_location_input'),
                        controller: locationCtrl,
                        decoration: InputDecoration(
                          labelText: 'Location / City',
                          hintText: 'e.g. Warangal',
                          prefixIcon: const Icon(Icons.location_on_outlined, color: Color(0xFF64748B)),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
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
                            borderSide: const BorderSide(color: AppTheme.gsNavy, width: 1.5),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter administrator location';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          key: const Key('admin_save_profile_button'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.gsNavy,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: _isSavingProfile
                              ? null
                              : () async {
                                  if (!formKey.currentState!.validate()) return;
                                  setSheetState(() => _isSavingProfile = true);
                                  setState(() => _isSavingProfile = true);

                                  final updatedName = nameCtrl.text.trim();
                                  final updatedPhone = phoneCtrl.text.trim();
                                  final updatedLoc = locationCtrl.text.trim();

                                  // 1. Update Persistent Session
                                  await SessionService().updateSessionUser(
                                    name: updatedName,
                                    phone: updatedPhone,
                                    additionalMetadata: {
                                      'location': updatedLoc,
                                      'city': updatedLoc,
                                    },
                                  );

                                  // 2. Direct Supabase Cloud Update
                                  try {
                                    final currentUserId = SessionService().currentSession?.userId;
                                    if (currentUserId != null && currentUserId.isNotEmpty) {
                                      await Supabase.instance.client
                                          .from('users')
                                          .update({
                                            'name': updatedName,
                                            'phone': updatedPhone,
                                            'raw_user_meta_data': {
                                              'name': updatedName,
                                              'phone': updatedPhone,
                                              'location': updatedLoc,
                                              'city': updatedLoc,
                                            },
                                          })
                                          .eq('id', currentUserId);
                                    }
                                  } catch (e) {
                                    debugPrint('Supabase direct profile update notice: $e');
                                  }

                                  if (mounted) {
                                    setState(() {
                                      _isSavingProfile = false;
                                    });
                                  }
                                  if (sheetCtx.mounted) {
                                    Navigator.pop(sheetCtx);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Profile updated successfully.'),
                                        backgroundColor: AppTheme.gsNavy,
                                      ),
                                    );
                                  }
                                },
                          child: _isSavingProfile
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Text(
                                  'Save changes',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
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
      },
    );
  }

  // ── Referrals Navigation ──

  void _openReferralsScreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AdminReferralsScreen()),
    );
  }

  // ── Call Helpline ──

  Future<void> _callHelpline() async {
    const helpline = clinicalHelplineNumber;
    final uri = Uri.parse('tel:$helpline');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Helpline: $helpline (24/7 Clinical Care Helpline)'),
              backgroundColor: AppTheme.gsNavy,
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Helpline: $helpline (24/7 Clinical Care Helpline)'),
            backgroundColor: AppTheme.gsNavy,
          ),
        );
      }
    }
  }

  // ── Logout Flow ──

  Future<void> _confirmAndSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Log out of Admin Account?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        content: const Text(
          'Are you sure you want to log out from this GS HEALTH Admin portal session?',
          style: TextStyle(fontSize: 14, color: Color(0xFF475569), height: 1.4),
        ),
        actions: [
          TextButton(
            key: const Key('cancel_logout_button'),
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.gsNavy),
            ),
          ),
          ElevatedButton(
            key: const Key('confirm_logout_button'),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFE3434),
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
    ApiService().clearAuthToken();
    _problemService.clearSubAdminSession();

    if (!mounted || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Signed out from Admin account.'),
        backgroundColor: AppTheme.gsNavy,
      ),
    );
    try {
      context.go('/login');
    } catch (_) {}
  }

  // ── Terms & Privacy Dialogs ──

  void _showTermsDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Terms of Use',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
        ),
        content: const SingleChildScrollView(
          child: Text(
            'GS HEALTH CLINICAL ADMINISTRATOR TERMS OF SERVICE\n\n'
            '1. Administrator Access & Roles\n'
            'Authorized administrators must ensure strictly authenticated operations when auditing patient cases, doctor rosters, coordinator credentials, and facility records.\n\n'
            '2. Patient Data & Clinical Confidentiality\n'
            'All medical records, specialist referrals, diagnostic files, and patient health information are strictly confidential and governed by Indian Medical Council & Telemedicine Practice Guidelines.\n\n'
            '3. Referral Management & Assignment\n'
            'Referrals transmitted across the GS HEALTH clinical network must be audited, assigned, and tracked in compliance with healthcare data protection standards.',
            style: TextStyle(fontSize: 13.5, color: Color(0xFF334155), height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.gsNavy)),
          ),
        ],
      ),
    );
  }

  void _showPrivacyDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Privacy Policy',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
        ),
        content: const SingleChildScrollView(
          child: Text(
            'GS HEALTH CLINICAL PRIVACY POLICY\n\n'
            '1. Information Governance\n'
            'We collect and protect administrative credentials, verified healthcare practitioner registrations, and clinical encounter metrics to support quality care delivery.\n\n'
            '2. Storage & Security\n'
            'All medical records, specialist consultations, and diagnostic records are protected with industry-standard encryption protocols and strict role-based access control.\n\n'
            '3. Third-Party Restrictions\n'
            'Clinical and patient data is strictly safeguarded and never sold or disclosed to non-authorized entities.',
            style: TextStyle(fontSize: 13.5, color: Color(0xFF334155), height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.gsNavy)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final adminName = _resolveAdminName();
    final adminPhone = _resolveAdminPhone();
    final adminLocation = _resolveAdminLocation();
    final initials = _getInitials(adminName);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        bottom: true,
        child: SingleChildScrollView(
          key: const Key('admin_profile_scroll_view'),
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top Header Navigation ──
              Row(
                children: [
                  InkWell(
                    key: const Key('admin_profile_back_button'),
                    onTap: () {
                      if (Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      } else {
                        context.go('/admin');
                      }
                    },
                    borderRadius: BorderRadius.circular(22),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: const Center(
                        child: Icon(Icons.chevron_left_rounded, color: Color(0xFF0F172A), size: 28),
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
                      letterSpacing: -0.4,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // ── 1. Admin Profile Card ──
              Container(
                key: const Key('admin_profile_card'),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    // Avatar with SK initials
                    Container(
                      width: 86,
                      height: 86,
                      decoration: const BoxDecoration(
                        color: Color(0x14012A58),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          initials,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF012A58),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      adminName,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.3,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    // Role Badge: Admin
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0x14012A58),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Admin',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF012A58),
                        ),
                      ),
                    ),
                    if (adminPhone.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.phone_outlined, size: 16, color: Color(0xFF64748B)),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              adminPhone.startsWith('+') ? adminPhone : '+$adminPhone',
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF475569),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (adminLocation.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.location_on_outlined, size: 16, color: Color(0xFF64748B)),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              adminLocation,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF64748B),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 18),
                    // Edit Profile Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        key: const Key('admin_edit_profile_button'),
                        onPressed: () => _showEditAdminProfileSheet(context),
                        icon: const Icon(Icons.edit_note_rounded, size: 20, color: Color(0xFF1E293B)),
                        label: const Text(
                          'Edit profile',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0x14012A58),
                          elevation: 0,
                          side: const BorderSide(color: Color(0x40012A58)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── 2. Referrals Menu Card ──
              InkWell(
                key: const Key('admin_referrals_menu_button'),
                onTap: () => _openReferralsScreen(context),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.alt_route_rounded, color: Color(0xFF012A58), size: 20),
                      SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Referrals',
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, size: 22, color: Color(0xFF94A3B8)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── 3. Need Help Support Card ──
              Container(
                key: const Key('admin_helpline_card'),
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'NEED HELP?',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF64748B),
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: _callHelpline,
                      child: const Text(
                        'Call our 24/7 clinical care helpline for medical emergencies, appointments and consultations.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF475569),
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── 4. Account Action Buttons ──

              // Log out Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  key: const Key('admin_logout_button'),
                  onPressed: () => _confirmAndSignOut(context),
                  icon: const Icon(Icons.logout_rounded, color: Color(0xFFFE3434), size: 18),
                  label: const Text(
                    'Log out',
                    style: TextStyle(
                      color: Color(0xFFFE3434),
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0x14FE3434),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Terms of Use Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  key: const Key('admin_terms_button'),
                  onPressed: () => _showTermsDialog(context),
                  icon: const Icon(Icons.description_outlined, color: Color(0xFF0F172A), size: 18),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Privacy Policy Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  key: const Key('admin_privacy_button'),
                  onPressed: () => _showPrivacyDialog(context),
                  icon: const Icon(Icons.shield_outlined, color: Color(0xFF0F172A), size: 18),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ── 5. GS HEALTH Footer Logo ──
              const Center(
                child: GsHealthLogo(
                  height: 32,
                  alignment: Alignment.center,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
