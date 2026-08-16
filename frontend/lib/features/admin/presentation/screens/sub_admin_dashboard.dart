import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/permissions.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/theme/app_theme.dart';

class SubAdminDashboardScreen extends StatefulWidget {
  const SubAdminDashboardScreen({super.key});

  @override
  State<SubAdminDashboardScreen> createState() => _SubAdminDashboardScreenState();
}

class _SubAdminDashboardScreenState extends State<SubAdminDashboardScreen>
    with TickerProviderStateMixin {
  final PatientProblemService _service = PatientProblemService();

  int _selectedTabIndex = 0;
  Timer? _autoSyncTimer;
  RealtimeChannel? _realtimeChannel;

  late AnimationController _entryController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // Search and Filter states
  String _patientSearch = '';
  String _dentistSearch = '';
  String _requestSearch = '';

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceUpdate);

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(parent: _entryController, curve: Curves.easeOut);
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entryController, curve: Curves.easeOutCubic));
    _entryController.forward();

    // Auto-sync every 5 seconds
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _service.syncAllDataFromApi();
    });

    // Supabase Realtime Listener
    try {
      _realtimeChannel = Supabase.instance.client
          .channel('sub_admin_realtime')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'patient_problem_requests',
            callback: (payload) {
              if (mounted) _service.syncProblemRequestsFromApi();
            },
          )
          .subscribe();
    } catch (_) {}

    _service.syncAllDataFromApi();
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    if (_realtimeChannel != null) {
      try {
        Supabase.instance.client.removeChannel(_realtimeChannel!);
      } catch (_) {}
    }
    _entryController.dispose();
    _service.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  List<_NavModule> _getPermittedModules() {
    final List<_NavModule> list = [];

    if (_service.hasPermission(AppPermissions.assignmentView)) {
      list.add(const _NavModule(
        key: 'assignments',
        label: 'Doctor Assignments',
        icon: Icons.assignment_turned_in_rounded,
        badgeCountKey: 'assignments',
      ));
    }

    if (_service.hasPermission(AppPermissions.problemView)) {
      list.add(const _NavModule(
        key: 'problems',
        label: 'Inquiry Pool',
        icon: Icons.chat_bubble_outline_rounded,
        badgeCountKey: 'problems',
      ));
    }

    if (_service.hasPermission(AppPermissions.patientView)) {
      list.add(const _NavModule(
        key: 'patients',
        label: 'Patients',
        icon: Icons.people_alt_rounded,
      ));
    }

    if (_service.hasPermission(AppPermissions.dentistView)) {
      list.add(const _NavModule(
        key: 'dentists',
        label: 'Dentists & Clinics',
        icon: Icons.medical_services_rounded,
      ));
    }

    if (_service.hasPermission(AppPermissions.appointmentView)) {
      list.add(const _NavModule(
        key: 'appointments',
        label: 'Appointments',
        icon: Icons.calendar_month_rounded,
      ));
    }

    if (_service.hasPermission(AppPermissions.reportView)) {
      list.add(const _NavModule(
        key: 'reports',
        label: 'Overview & Reports',
        icon: Icons.analytics_rounded,
      ));
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final permittedModules = _getPermittedModules();

    if (_selectedTabIndex >= permittedModules.length) {
      _selectedTabIndex = 0;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: _buildSubAdminAppBar(context),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: Column(
            children: [
              _buildSubAdminHeader(),
              if (permittedModules.isEmpty)
                Expanded(child: _buildNoPermissionsRestrictedState())
              else ...[
                _buildModuleTabBar(permittedModules),
                Expanded(child: _buildSelectedModuleContent(permittedModules[_selectedTabIndex].key)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildSubAdminAppBar(BuildContext context) {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.white,
      titleSpacing: 16,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF818CF8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.shield_outlined, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DentaGuru Sub-Admin',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark),
              ),
              Text(
                'Role-Based Workspace',
                style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Sync Data',
          icon: const Icon(Icons.sync_rounded, color: Color(0xFF6366F1)),
          onPressed: () async {
            await _service.syncAllDataFromApi();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('⚡ Sub-Admin data synchronized with cloud.'),
                  duration: Duration(seconds: 1),
                  backgroundColor: Color(0xFF6366F1),
                ),
              );
            }
          },
        ),
        IconButton(
          tooltip: 'Log Out',
          icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
          onPressed: () => _handleLogout(context),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildSubAdminHeader() {
    final name = _service.subAdminName.isNotEmpty ? _service.subAdminName : 'Sub-Admin';
    final email = _service.subAdminEmail;
    final permsCount = _service.subAdminPermissions.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.15))),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.15),
            radius: 20,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : 'S',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF6366F1), fontSize: 16),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEDE9FE),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Sub-Admin',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF6D28D9)),
                      ),
                    ),
                  ],
                ),
                if (email.isNotEmpty)
                  Text(
                    email,
                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_open_rounded, size: 12, color: Color(0xFF16A34A)),
                const SizedBox(width: 4),
                Text(
                  '$permsCount Active Role${permsCount == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF16A34A)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModuleTabBar(List<_NavModule> modules) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: List.generate(modules.length, (idx) {
            final mod = modules[idx];
            final isSelected = _selectedTabIndex == idx;

            int badgeCount = 0;
            if (mod.badgeCountKey == 'assignments') {
              badgeCount = _service.requests.where((r) => r.assignedDoctorId == null || r.assignedDoctorId!.isEmpty).length;
            } else if (mod.badgeCountKey == 'problems') {
              badgeCount = _service.requests.length;
            }

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _selectedTabIndex = idx),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF6366F1) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        mod.icon,
                        size: 16,
                        color: isSelected ? Colors.white : const Color(0xFF64748B),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        mod.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? Colors.white : const Color(0xFF475569),
                        ),
                      ),
                      if (badgeCount > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.white : const Color(0xFF6366F1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$badgeCount',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? const Color(0xFF6366F1) : Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildSelectedModuleContent(String moduleKey) {
    switch (moduleKey) {
      case 'assignments':
        return _buildAssignmentsModule();
      case 'problems':
        return _buildProblemsModule();
      case 'patients':
        return _buildPatientsModule();
      case 'dentists':
        return _buildDentistsModule();
      case 'appointments':
        return _buildAppointmentsModule();
      case 'reports':
        return _buildReportsModule();
      default:
        return const Center(child: Text('Module not available.'));
    }
  }

  // ==========================================
  // MODULE 1: DOCTOR ASSIGNMENT & REFERRALS
  // ==========================================
  Widget _buildAssignmentsModule() {
    final canAssign = _service.hasPermission(AppPermissions.assignmentCreate);
    final allRequests = _service.requests;
    final filtered = allRequests.where((r) {
      final pName = r.patientName.isNotEmpty ? r.patientName : 'Patient';
      final pCity = r.getDisplayCity(_service.allPatients);
      final pPin = r.getDisplayPincode(_service.allPatients);
      final matchSearch = _requestSearch.isEmpty ||
          pName.toLowerCase().contains(_requestSearch.toLowerCase()) ||
          r.problemDescription.toLowerCase().contains(_requestSearch.toLowerCase()) ||
          pCity.toLowerCase().contains(_requestSearch.toLowerCase()) ||
          pPin.toLowerCase().contains(_requestSearch.toLowerCase());
      return matchSearch;
    }).toList();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            onChanged: (v) => setState(() => _requestSearch = v),
            decoration: InputDecoration(
              hintText: 'Search patient, city, pincode...',
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            ),
          ),
          const SizedBox(height: 14),
          if (filtered.isEmpty)
            _buildEmptyCard('No consultation requests found for assignment.', Icons.check_circle_outline_rounded)
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (ctx, idx) {
                final req = filtered[idx];
                final isAssigned = req.assignedDoctorId != null && req.assignedDoctorId!.isNotEmpty;
                final pName = req.patientName.isNotEmpty ? req.patientName : 'Patient';
                final displayCity = req.getDisplayCity(_service.allPatients);
                final displayPincode = req.getDisplayPincode(_service.allPatients);

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isAssigned ? const Color(0xFFE2E8F0) : const Color(0xFF6366F1).withValues(alpha: 0.3)),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.1),
                                  child: Text(pName.isNotEmpty ? pName[0].toUpperCase() : 'P', style: const TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    pName,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isAssigned ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              isAssigned ? '✓ Doctor Assigned' : '⏳ Pending Doctor',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isAssigned ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        req.problemDescription,
                        style: const TextStyle(fontSize: 13, color: AppTheme.textDark),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (displayCity.isNotEmpty) ...[
                            const Icon(Icons.location_on_outlined, size: 14, color: AppTheme.textMuted),
                            const SizedBox(width: 4),
                            Text('$displayCity ${displayPincode.isNotEmpty ? "($displayPincode)" : ""}', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                            const SizedBox(width: 12),
                          ],
                          if (req.patientPhone.isNotEmpty) ...[
                            const Icon(Icons.phone_outlined, size: 14, color: AppTheme.textMuted),
                            const SizedBox(width: 4),
                            Text(req.patientPhone, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                          ],
                        ],
                      ),
                      if (isAssigned) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFBBF7D0)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Assigned Doctor: ${req.assignedDoctorName ?? "Specialist"} (${req.assignedDoctorSpecialty ?? "Dentistry"})',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (canAssign) ...[
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.person_pin_rounded, size: 16),
                            label: Text(
                              isAssigned ? 'Change Assigned Doctor' : 'Assign Nearby Doctor',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            ),
                            onPressed: () => _showAssignDoctorModal(ctx, req),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ==========================================
  // MODULE 2: PATIENT PROBLEMS POOL
  // ==========================================
  Widget _buildProblemsModule() {
    final canUpdate = _service.hasPermission(AppPermissions.problemUpdate);
    final requests = _service.requests;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (requests.isEmpty)
            _buildEmptyCard('No inquiries in the problem pool.', Icons.chat_bubble_outline_rounded)
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: requests.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (ctx, idx) {
                final req = requests[idx];
                final pName = req.patientName.isNotEmpty ? req.patientName : 'Patient';

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              pName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: req.status.toLowerCase().contains('review') || req.status.toLowerCase().contains('suggest') || req.status.toLowerCase().contains('assign')
                                  ? const Color(0xFFDCFCE7)
                                  : const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              req.status.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: req.status.toLowerCase().contains('review') || req.status.toLowerCase().contains('suggest') || req.status.toLowerCase().contains('assign')
                                    ? const Color(0xFF16A34A)
                                    : const Color(0xFFD97706),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(req.problemDescription, style: const TextStyle(fontSize: 13, color: AppTheme.textDark)),
                      const SizedBox(height: 8),
                      Text('Severity: ${req.severity.toUpperCase()} • Category: ${req.problemCategory}',
                          style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                      if (canUpdate) ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            icon: const Icon(Icons.check_rounded, size: 16),
                            label: const Text('Mark Reviewed', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            onPressed: () async {
                              await _service.markAdminReviewed(req.id);
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(content: Text('✓ Marked as reviewed.'), backgroundColor: Color(0xFF10B981)),
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ==========================================
  // MODULE 3: PATIENT DIRECTORY
  // ==========================================
  Widget _buildPatientsModule() {
    final patients = _service.allPatients.where((p) {
      final match = _patientSearch.isEmpty ||
          p.name.toLowerCase().contains(_patientSearch.toLowerCase()) ||
          p.email.toLowerCase().contains(_patientSearch.toLowerCase()) ||
          p.phone.toLowerCase().contains(_patientSearch.toLowerCase()) ||
          p.city.toLowerCase().contains(_patientSearch.toLowerCase());
      return match;
    }).toList();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            onChanged: (v) => setState(() => _patientSearch = v),
            decoration: InputDecoration(
              hintText: 'Search patients by name, email, phone, city...',
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            ),
          ),
          const SizedBox(height: 14),
          if (patients.isEmpty)
            _buildEmptyCard('No patients match your search.', Icons.people_outline_rounded)
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: patients.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (ctx, idx) {
                final p = patients[idx];
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.1),
                        child: Text(p.name.isNotEmpty ? p.name[0].toUpperCase() : 'P',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF6366F1))),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name.isNotEmpty ? p.name : 'Registered Patient',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                                overflow: TextOverflow.ellipsis),
                            Text('✉️ ${p.email} • 📞 ${p.phone}',
                                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                overflow: TextOverflow.ellipsis),
                            if (p.city.isNotEmpty)
                              Text('📍 ${p.city} ${p.pincode.isNotEmpty ? "(${p.pincode})" : ""}',
                                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                  overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ==========================================
  // MODULE 4: DENTIST & CLINIC DIRECTORY
  // ==========================================
  Widget _buildDentistsModule() {
    final doctors = _service.allDoctors.where((d) {
      final match = _dentistSearch.isEmpty ||
          d.name.toLowerCase().contains(_dentistSearch.toLowerCase()) ||
          d.specialty.toLowerCase().contains(_dentistSearch.toLowerCase()) ||
          d.clinicName.toLowerCase().contains(_dentistSearch.toLowerCase()) ||
          d.city.toLowerCase().contains(_dentistSearch.toLowerCase());
      return match;
    }).toList();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            onChanged: (v) => setState(() => _dentistSearch = v),
            decoration: InputDecoration(
              hintText: 'Search dentists by name, specialty, clinic, city...',
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            ),
          ),
          const SizedBox(height: 14),
          if (doctors.isEmpty)
            _buildEmptyCard('No dentists found.', Icons.medical_services_outlined)
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: doctors.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (ctx, idx) {
                final d = doctors[idx];
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.12),
                        child: const Icon(Icons.medical_services_rounded, color: Color(0xFF10B981), size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(d.name,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                                overflow: TextOverflow.ellipsis),
                            Text('🩺 ${d.specialty} • 🏥 ${d.clinicName}',
                                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                overflow: TextOverflow.ellipsis),
                            Text('📍 ${d.city} (${d.pincode}) • 📞 ${d.phone}',
                                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ==========================================
  // MODULE 5: APPOINTMENTS
  // ==========================================
  Widget _buildAppointmentsModule() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildEmptyCard('Appointment schedules and status monitoring are active.', Icons.calendar_month_outlined),
        ],
      ),
    );
  }

  // ==========================================
  // MODULE 6: REPORTS & OVERVIEW
  // ==========================================
  Widget _buildReportsModule() {
    final totalPatients = _service.allPatients.length;
    final totalDoctors = _service.allDoctors.length;
    final totalRequests = _service.requests.length;
    final assignedCount = _service.requests.where((r) => r.assignedDoctorId != null && r.assignedDoctorId!.isNotEmpty).length;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Platform Statistics Overview', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildMetricCard('Total Patients', '$totalPatients', const Color(0xFF6366F1), Icons.people_alt_rounded)),
              const SizedBox(width: 10),
              Expanded(child: _buildMetricCard('Verified Doctors', '$totalDoctors', const Color(0xFF10B981), Icons.medical_services_rounded)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _buildMetricCard('Total Inquiries', '$totalRequests', const Color(0xFFF59E0B), Icons.chat_bubble_outline_rounded)),
              const SizedBox(width: 10),
              Expanded(child: _buildMetricCard('Assigned Referrals', '$assignedCount', const Color(0xFF8B5CF6), Icons.assignment_turned_in_rounded)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w500)),
              Icon(icon, color: color, size: 18),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildEmptyCard(String message, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 36, color: const Color(0xFF94A3B8)),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppTheme.textMuted)),
        ],
      ),
    );
  }

  Widget _buildNoPermissionsRestrictedState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFFFEF3C7),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_person_rounded, size: 40, color: Color(0xFFD97706)),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Modules Assigned',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your Sub-Admin account is active, but you do not currently have any permissions configured.\n\nPlease reach out to the Primary Admin to grant access to platform modules.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted, height: 1.5),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Refresh Permissions', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => _service.syncAllDataFromApi(),
            ),
          ],
        ),
      ),
    );
  }

  void _showAssignDoctorModal(BuildContext context, PatientConsultationRequest req) {
    DoctorModel? selectedDoctor = _service.allDoctors.isNotEmpty ? _service.allDoctors.first : null;
    String searchKeyword = '';
    String pincodeFilter = req.getDisplayPincode(_service.allPatients);
    final notesCtrl = TextEditingController(text: 'Assigned for specialized dental evaluation.');
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final doctors = _service.allDoctors.where((d) {
              final search = searchKeyword.toLowerCase();
              final matchesKeyword = search.isEmpty ||
                  d.name.toLowerCase().contains(search) ||
                  d.specialty.toLowerCase().contains(search) ||
                  d.clinicName.toLowerCase().contains(search) ||
                  d.city.toLowerCase().contains(search);

              final matchesPincode = pincodeFilter.isEmpty || d.pincode.contains(pincodeFilter.trim());

              return matchesKeyword && (pincodeFilter.isEmpty || matchesPincode);
            }).toList();

            final displayCity = req.getDisplayCity(_service.allPatients);
            final displayPincode = req.getDisplayPincode(_service.allPatients);

            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Assign Doctor to Patient', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
                        IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(dialogCtx).pop()),
                      ],
                    ),
                    const Divider(),
                    Text('Patient: ${req.patientName} • City: $displayCity ($displayPincode)', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            onChanged: (v) => setModalState(() => searchKeyword = v),
                            decoration: InputDecoration(
                              hintText: 'Search doctor, specialty...',
                              prefixIcon: const Icon(Icons.search_rounded, size: 16),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 120,
                          child: TextField(
                            controller: TextEditingController(text: pincodeFilter),
                            onChanged: (v) => setModalState(() => pincodeFilter = v),
                            decoration: InputDecoration(
                              hintText: 'Pincode',
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: doctors.isEmpty
                          ? const Center(child: Text('No matching doctors found.', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)))
                          : ListView.separated(
                              itemCount: doctors.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (c, i) {
                                final doc = doctors[i];
                                final isSelected = selectedDoctor?.id == doc.id;
                                return InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () => setModalState(() => selectedDoctor = doc),
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: isSelected ? const Color(0xFFEEF2FF) : const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: isSelected ? const Color(0xFF6366F1) : const Color(0xFFE2E8F0)),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                                          color: isSelected ? const Color(0xFF6366F1) : Colors.grey,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(doc.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                              Text('${doc.specialty} • ${doc.clinicName} (📍 ${doc.city} - ${doc.pincode})',
                                                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: notesCtrl,
                      decoration: InputDecoration(
                        labelText: 'Admin Referral Notes',
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton.icon(
                      icon: isSubmitting
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check_circle_rounded, size: 18),
                      label: Text(isSubmitting ? 'Assigning...' : 'Confirm Assignment'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: (selectedDoctor == null || isSubmitting)
                          ? null
                          : () async {
                              setModalState(() => isSubmitting = true);
                              await _service.assignDoctorToRequest(
                                requestId: req.id,
                                doctor: selectedDoctor!,
                                adminNotes: notesCtrl.text.trim(),
                              );
                              setModalState(() => isSubmitting = false);
                              if (!dialogCtx.mounted) return;
                              Navigator.of(dialogCtx).pop();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('🎉 Doctor ${selectedDoctor!.name} assigned successfully!'),
                                    backgroundColor: const Color(0xFF10B981),
                                  ),
                                );
                              }
                            },
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

  void _handleLogout(BuildContext context) {
    _service.clearSubAdminSession();
    context.go('/auth');
  }
}

class _NavModule {
  final String key;
  final String label;
  final IconData icon;
  final String? badgeCountKey;

  const _NavModule({
    required this.key,
    required this.label,
    required this.icon,
    this.badgeCountKey,
  });
}
