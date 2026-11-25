import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/services/session_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/denta_guru_logo.dart';
import '../../../patient/presentation/widgets/referred_patients_sheet.dart';
import '../widgets/gs_health_clinic_views.dart';

class ClinicProfileScreen extends StatefulWidget {
  const ClinicProfileScreen({super.key});

  @override
  State<ClinicProfileScreen> createState() => _ClinicProfileScreenState();
}

class _ClinicProfileScreenState extends State<ClinicProfileScreen> {
  final PatientProblemService _problemService = PatientProblemService();

  static const String clinicalHelplineNumber = '+911800200100';

  bool _isSavingProfile = false;

  @override
  void initState() {
    super.initState();
    _problemService.addListener(_onServiceChanged);
    _problemService.syncClinicsFromApi();
    _problemService.syncDoctorsFromApi();
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

  // ── Resolve Data Helpers ──

  ClinicModel? _resolveCurrentClinic() {
    final session = SessionService().currentSession;
    final authClinicId = _problemService.authenticatedClinicId.trim();
    final authClinicName = _problemService.authenticatedClinicName.trim();

    // 1. Try matching by ID in allClinics
    if (authClinicId.isNotEmpty) {
      for (final c in _problemService.allClinics) {
        if (c.id == authClinicId) return c;
      }
    }

    // 2. Try matching by Name in allClinics
    if (authClinicName.isNotEmpty) {
      for (final c in _problemService.allClinics) {
        if (c.clinicName.trim().toLowerCase() == authClinicName.toLowerCase()) {
          return c;
        }
      }
    }

    // 3. Try matching by session user ID or clinic metadata
    if (session != null) {
      final sessionClinicName = session.metadata['clinicName']?.toString() ??
          session.metadata['clinic_name']?.toString() ??
          '';
      if (sessionClinicName.isNotEmpty) {
        for (final c in _problemService.allClinics) {
          if (c.clinicName.trim().toLowerCase() == sessionClinicName.trim().toLowerCase()) {
            return c;
          }
        }
      }
      for (final c in _problemService.allClinics) {
        if (c.userId.isNotEmpty && c.userId == session.userId) {
          return c;
        }
      }
    }

    if (_problemService.allClinics.isNotEmpty) {
      return _problemService.allClinics.first;
    }

    return null;
  }

  String _resolveManagerName(ClinicModel? clinic) {
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
    if (clinic != null && clinic.clinicName.trim().isNotEmpty) {
      final base = clinic.clinicName.replaceAll('Dental Clinic', '').replaceAll('Clinic', '').trim();
      return base.isNotEmpty ? '$base Clinic Manager' : 'Clinic Manager';
    }
    return _problemService.authenticatedClinicName.trim().isNotEmpty
        ? '${_problemService.authenticatedClinicName.trim()} Manager'
        : 'Clinic Manager';
  }

  String _resolveManagerPhone(ClinicModel? clinic) {
    final session = SessionService().currentSession;
    if (_problemService.authenticatedClinicPhone.trim().isNotEmpty) {
      return _problemService.authenticatedClinicPhone.trim();
    }
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
    if (clinic != null && clinic.phone.trim().isNotEmpty) {
      return clinic.phone.trim();
    }
    return '';
  }

  String _resolveManagerLocation(ClinicModel? clinic) {
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
    if (clinic != null && clinic.location.trim().isNotEmpty) {
      final loc = clinic.location.trim();
      if (loc.contains(',')) {
        return loc.split(',').last.trim();
      }
      return loc;
    }
    if (_problemService.authenticatedClinicLocation.trim().isNotEmpty) {
      final loc = _problemService.authenticatedClinicLocation.trim();
      if (loc.contains(',')) {
        return loc.split(',').last.trim();
      }
      return loc;
    }
    return '';
  }

  String _getInitials(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return 'CM';
    final parts = clean.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return clean.substring(0, clean.length >= 2 ? 2 : 1).toUpperCase();
  }

  // ── Edit Clinic Manager Profile ──

  Future<void> _showEditManagerProfileSheet(BuildContext context) async {
    final clinic = _resolveCurrentClinic();
    final initialName = _resolveManagerName(clinic);
    final initialPhone = _resolveManagerPhone(clinic);
    final initialLocation = _resolveManagerLocation(clinic);

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
                        'Update clinic manager contact and location information',
                        style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        key: const Key('clinic_edit_name_input'),
                        controller: nameCtrl,
                        decoration: InputDecoration(
                          labelText: 'Manager Name',
                          hintText: 'e.g. Bandra Clinic Manager',
                          prefixIcon: const Icon(Icons.person_outline_rounded),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter manager name' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        key: const Key('clinic_edit_phone_input'),
                        controller: phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: 'Registered Mobile Number',
                          hintText: 'e.g. +919000000100',
                          prefixIcon: const Icon(Icons.phone_outlined),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter phone number' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        key: const Key('clinic_edit_location_input'),
                        controller: locationCtrl,
                        decoration: InputDecoration(
                          labelText: 'City / Location',
                          hintText: 'e.g. Mumbai',
                          prefixIcon: const Icon(Icons.location_on_outlined),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter location' : null,
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          key: const Key('clinic_save_profile_button'),
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
                                      'managerName': updatedName,
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

                                  // 3. Update Clinic Cache in PatientProblemService
                                  if (clinic != null) {
                                    await _problemService.updateClinicDetails(
                                      clinicId: clinic.id,
                                      clinicName: clinic.clinicName,
                                      location: clinic.location,
                                    );
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
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF012A58),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
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

  // ── Edit Clinic Details ──

  Future<void> _openEditClinicDetailsSheet(BuildContext context) async {
    final clinic = _resolveCurrentClinic();
    final cId = clinic?.id ?? _problemService.authenticatedClinicId;
    final cName = (clinic?.clinicName.trim().isNotEmpty == true)
        ? clinic!.clinicName.trim()
        : _problemService.authenticatedClinicName.trim();
    final cLoc = (clinic?.location.trim().isNotEmpty == true)
        ? clinic!.location.trim()
        : _problemService.authenticatedClinicLocation.trim();
    final cCover = clinic?.coverImageUrl ?? _problemService.authenticatedClinicCoverUrl;

    await showEditClinicDetailsSheet(
      context: context,
      clinicId: cId,
      initialName: cName,
      initialLocation: cLoc,
      initialCoverUrl: cCover,
      onOpenDepartments: () {},
      onOpenProcedureRates: () {},
      onSave: ({
        required String name,
        required String location,
        required String coverUrl,
      }) async {
        final messenger = ScaffoldMessenger.maybeOf(context);
        await _problemService.updateClinicDetails(
          clinicId: cId,
          clinicName: name,
          location: location,
          previousClinicName: cName,
          coverImageUrl: coverUrl,
        );
        if (mounted) {
          setState(() {});
          messenger?.showSnackBar(
            const SnackBar(
              content: Text('Clinic details saved.'),
              backgroundColor: AppTheme.gsNavy,
            ),
          );
        }
      },
    );
  }

  // ── Patient Referrals ──

  void _openPatientReferrals(BuildContext context) {
    final clinic = _resolveCurrentClinic();
    final clinicName = clinic?.clinicName ?? _problemService.authenticatedClinicName;
    final referrals = _problemService.clinicReferralsFor(clinicName: clinicName);

    showClinicReferralsSheet(
      context: context,
      clinicName: clinicName.isNotEmpty ? clinicName : 'Clinic Facility',
      referrals: referrals,
      onOpenReferralDirectory: () => ReferredPatientsSheet.show(context),
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
          'Log out of Clinic Account?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        content: const Text(
          'Are you sure you want to log out from this clinic management portal session?',
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
    await _problemService.clearClinicSession();
    await SessionService().clearSession();

    if (!mounted || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Signed out from Clinic account.'),
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
            'GS HEALTH CLINIC PARTNER TERMS OF SERVICE\n\n'
            '1. Clinic Facilities & Listings\n'
            'Participating clinics must maintain accurate operational hours, doctor associations, and facility disclosures on the GS HEALTH platform.\n\n'
            '2. Patient Data & E-Prescriptions\n'
            'All patient records, referrals, and diagnostic files received are strictly confidential and governed by Indian Medical Council & Telemedicine Practice Guidelines.\n\n'
            '3. Specialist Referrals & Consultations\n'
            'Referrals transmitted through the GS HEALTH network must be acknowledged promptly by authorized clinical personnel.',
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
            '1. Information Collection\n'
            'We collect clinic operational information, manager contact credentials, and verified doctor rosters to provide streamlined appointment management and patient referral exchange.\n\n'
            '2. Storage & Encryption\n'
            'All medical records, patient consultation requests, and diagnostic scans are protected with end-to-end encryption in compliance with healthcare data protection standards.\n\n'
            '3. Third-Party Sharing\n'
            'Clinical data is never sold or shared with non-authorized commercial entities.',
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

  // ── Delete Account Flow ──

  Future<void> _confirmAndDeleteClinicAccount(BuildContext context) async {
    final clinic = _resolveCurrentClinic();
    final clinicId = clinic?.id ?? _problemService.authenticatedClinicId;
    final clinicName = clinic?.clinicName ?? _problemService.authenticatedClinicName;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Delete clinic account?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        content: const Text(
          'Are you sure you want to permanently delete your GS HEALTH Clinic account, facility records, and practice listings? This action cannot be undone.',
          style: TextStyle(fontSize: 14, color: Color(0xFF475569), height: 1.4),
        ),
        actions: [
          TextButton(
            key: const Key('cancel_delete_clinic_account_button'),
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.gsNavy),
            ),
          ),
          ElevatedButton(
            key: const Key('confirm_delete_clinic_account_button'),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFE3434),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Delete account', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _problemService.deleteCurrentClinicAccount(
      clinicId: clinicId,
      clinicName: clinicName,
    );
    await SessionService().clearSession();

    if (!mounted || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Your Clinic account has been permanently deleted.'),
        backgroundColor: AppTheme.gsNavy,
      ),
    );
    try {
      context.go('/login');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final clinic = _resolveCurrentClinic();
    final clinicId = clinic?.id ?? _problemService.authenticatedClinicId;
    final clinicName = (clinic?.clinicName.trim().isNotEmpty == true)
        ? clinic!.clinicName.trim()
        : (_problemService.authenticatedClinicName.trim().isNotEmpty
            ? _problemService.authenticatedClinicName.trim()
            : 'Clinic Profile');
    final clinicAddress = (clinic?.location.trim().isNotEmpty == true)
        ? clinic!.location.trim()
        : (_problemService.authenticatedClinicLocation.trim().isNotEmpty
            ? _problemService.authenticatedClinicLocation.trim()
            : 'Location not specified');
    final isFeatured = _problemService.isClinicFeaturedFor(
      clinicId,
      clinicName,
      modelValue: clinic?.isFeatured ?? false,
    );

    final managerName = _resolveManagerName(clinic);
    final managerPhone = _resolveManagerPhone(clinic);
    final managerLocation = _resolveManagerLocation(clinic);
    final initials = _getInitials(managerName);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        bottom: true,
        child: SingleChildScrollView(
          key: const Key('clinic_profile_scroll_view'),
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top Header Navigation ──
              Row(
                children: [
                  InkWell(
                    key: const Key('clinic_profile_back_button'),
                    onTap: () {
                      if (Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      } else {
                        context.go('/clinic');
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

              // ── 1. Profile Header Card (Clinic Manager) ──
              Container(
                key: const Key('clinic_manager_profile_card'),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    // Avatar with BC initials
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
                      managerName,
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
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0x14012A58),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Clinic',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF012A58),
                        ),
                      ),
                    ),
                    if (managerPhone.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.phone_outlined, size: 16, color: Color(0xFF64748B)),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              managerPhone.startsWith('+') ? managerPhone : '+$managerPhone',
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
                    if (managerLocation.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.location_on_outlined, size: 16, color: Color(0xFF64748B)),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              managerLocation,
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
                        key: const Key('clinic_edit_profile_button'),
                        onPressed: () => _showEditManagerProfileSheet(context),
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

              // ── 2. Clinic Details Card ──
              Container(
                key: const Key('clinic_facility_details_card'),
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CLINIC',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF64748B),
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      clinicName,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined, size: 16, color: Color(0xFF64748B)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            clinicAddress,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF64748B),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    // Featured Clinic Badge (Only if clinic is actually featured)
                    if (isFeatured) ...[
                      const SizedBox(height: 12),
                      Container(
                        key: const Key('clinic_featured_badge'),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0x14FE3434),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0x40FE3434)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.star_rounded, size: 14, color: Color(0xFFFE3434)),
                            SizedBox(width: 4),
                            Text(
                              'FEATURED CLINIC',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFFE3434),
                                letterSpacing: 0.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    // Edit Clinic Details Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        key: const Key('clinic_edit_details_button'),
                        onPressed: () => _openEditClinicDetailsSheet(context),
                        icon: const Icon(Icons.apartment_rounded, size: 18, color: Color(0xFF0F172A)),
                        label: const Text(
                          'Edit clinic details',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white,
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── 3. Patient Referrals Menu Card ──
              InkWell(
                key: const Key('clinic_patient_referrals_button'),
                onTap: () => _openPatientReferrals(context),
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
                          'Patient referrals',
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

              // ── 4. Need Help Support Card ──
              Container(
                key: const Key('clinic_helpline_card'),
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

              // ── 5. Account Action Buttons ──

              // Log out Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  key: const Key('clinic_logout_button'),
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

              // Terms of Use
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  key: const Key('clinic_terms_button'),
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

              // Privacy Policy
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  key: const Key('clinic_privacy_button'),
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
              const SizedBox(height: 10),

              // Delete My Account
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  key: const Key('clinic_delete_account_button'),
                  onPressed: () => _confirmAndDeleteClinicAccount(context),
                  icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFF0F172A), size: 18),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ── 6. GS HEALTH Footer Logo ──
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
