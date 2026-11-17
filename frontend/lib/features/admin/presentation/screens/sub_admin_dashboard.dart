import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/permissions.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/services/session_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../widgets/gs_health_admin_overview.dart';

class SubAdminDashboardScreen extends StatefulWidget {
  const SubAdminDashboardScreen({super.key});

  @override
  State<SubAdminDashboardScreen> createState() => _SubAdminDashboardScreenState();
}

class _SubAdminDashboardScreenState extends State<SubAdminDashboardScreen>
    with TickerProviderStateMixin {
  final PatientProblemService _service = PatientProblemService();

  int _selectedTabIndex = 0;
  bool _isOverviewLoading = false;
  String? _overviewError;
  List<AdminAppointmentItem> _overviewAppointments = const [];
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

    _refreshOverviewData();
  }

  Future<void> _refreshOverviewData() async {
    if (mounted) {
      setState(() {
        _isOverviewLoading = true;
        _overviewError = null;
      });
    }
    try {
      await _service.syncAllDataFromApi();
      List<AdminAppointmentItem> items = const [];
      if (_service.hasPermission(AppPermissions.appointmentView)) {
        final rows = await ApiService().fetchAllAppointmentsForAdmin();
        items = rows
            .whereType<Map>()
            .map(
              (r) => AdminAppointmentItem.fromRow(
                r,
                patients: _service.allPatients,
                doctors: _service.allDoctors,
              ),
            )
            .toList();
      }
      if (!mounted) return;
      setState(() {
        _overviewAppointments = items;
        _isOverviewLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _overviewError = e.toString().replaceFirst('Exception: ', '');
        _isOverviewLoading = false;
      });
    }
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
        label: 'Doctors & Clinics',
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
    final tabs = permittedModules.isEmpty
        ? const <_NavModule>[]
        : <_NavModule>[
            const _NavModule(
              key: 'overview',
              label: 'Overview',
              icon: Icons.grid_view_rounded,
            ),
            ...permittedModules,
          ];

    if (_selectedTabIndex >= tabs.length) {
      _selectedTabIndex = 0;
    }

    final subAdminNotifs = _service.appNotifications
        .where((n) => n.recipientRole == 'Sub-Admin' || n.recipientRole == 'Admin' || n.recipientId == 'ALL_ADMINS')
        .toList();
    final unreadCount = subAdminNotifs.where((n) => !n.isRead).length;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: null,
        body: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: Column(
              children: [
                GsHealthAdminHeader(
                  subtitle: 'Sub-Admin console',
                  title: 'GS HEALTH',
                  unreadCount: unreadCount,
                  onNotifications: () => showAdminNotificationsSheet(
                    context,
                    notifications: subAdminNotifs,
                    onMarkAllRead: () => _service.markAllNotificationsRead('Sub-Admin'),
                  ),
                  onProfile: () => _showSubAdminProfileSheet(context),
                ),
                _buildAssignedDistrictsHeaderBar(),
                if (tabs.isEmpty)
                  Expanded(child: _buildNoPermissionsRestrictedState())
                else ...[
                  if (_selectedTabIndex != 0) _buildModuleTabBar(tabs),
                  Expanded(
                    child: _buildSelectedModuleContent(tabs[_selectedTabIndex].key, tabs),
                  ),
                ],
              ],
            ),
          ),
        ),
        bottomNavigationBar: tabs.isEmpty ? null : _buildSubAdminBottomNav(tabs),
      ),
    );
  }

  Widget _buildAssignedDistrictsHeaderBar() {
    final districts = _service.subAdminDistricts;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF012A58),
      child: Row(
        children: [
          const Icon(Icons.location_on_rounded, color: Color(0xFFFE3434), size: 16),
          const SizedBox(width: 6),
          const Text(
            'Assigned Territory: ',
            style: TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.bold),
          ),
          Expanded(
            child: districts.isEmpty
                ? const Text(
                    'All Districts (Global Jurisdiction)',
                    style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: districts.map((d) {
                        final name = (d['name'] ?? 'District').toString();
                        return Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            name,
                            style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                          ),
                        );
                      }).toList(),
                    ),
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
                    color: isSelected ? AppTheme.gsNavy : const Color(0xFFF1F5F9),
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

  Widget _buildSelectedModuleContent(String moduleKey, List<_NavModule> tabs) {
    switch (moduleKey) {
      case 'overview':
        return _buildSubAdminOverview(tabs);
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

  void _showRestrictedMessage(String area) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Access restricted: your Sub-Admin role cannot open $area.'),
          backgroundColor: AppTheme.gsRed,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _switchToModuleKey(List<_NavModule> tabs, String moduleKey, String restrictedLabel) {
    final idx = tabs.indexWhere((t) => t.key == moduleKey);
    if (idx >= 0) {
      setState(() => _selectedTabIndex = idx);
    } else {
      _showRestrictedMessage(restrictedLabel);
    }
  }

  int _subAdminBottomNavIndex(List<_NavModule> tabs) {
    if (_selectedTabIndex < 0 || _selectedTabIndex >= tabs.length) return 0;
    final key = tabs[_selectedTabIndex].key;
    if (key == 'assignments' || key == 'problems') return 1;
    if (key == 'dentists') return 2;
    if (key == 'patients') return 3;
    return 0;
  }

  Widget _buildSubAdminBottomNav(List<_NavModule> tabs) {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      backgroundColor: Colors.white,
      currentIndex: _subAdminBottomNavIndex(tabs),
      selectedItemColor: AppTheme.gsNavy,
      unselectedItemColor: AppTheme.textMuted,
      selectedFontSize: 11,
      unselectedFontSize: 11,
      selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
      onTap: (index) {
        if (index == 0) {
          setState(() => _selectedTabIndex = 0);
        } else if (index == 1) {
          if (_service.hasPermission(AppPermissions.assignmentView)) {
            _switchToModuleKey(tabs, 'assignments', 'requests & assignments');
          } else {
            _switchToModuleKey(tabs, 'problems', 'requests & inquiry pool');
          }
        } else if (index == 2) {
          _switchToModuleKey(tabs, 'dentists', 'doctors directory');
        } else if (index == 3) {
          _switchToModuleKey(tabs, 'patients', 'patients directory');
        }
      },
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.grid_view_outlined),
          activeIcon: Icon(Icons.grid_view_rounded),
          label: 'Overview',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.inbox_outlined),
          activeIcon: Icon(Icons.inbox_rounded),
          label: 'Requests',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.medical_services_outlined),
          activeIcon: Icon(Icons.medical_services_rounded),
          label: 'Doctors',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.people_outline_rounded),
          activeIcon: Icon(Icons.people_alt_rounded),
          label: 'Patients',
        ),
      ],
    );
  }

  Widget _buildSubAdminOverview(List<_NavModule> tabs) {
    final canAssignView = _service.hasPermission(AppPermissions.assignmentView);
    final canAssignCreate = _service.hasPermission(AppPermissions.assignmentCreate);
    final canProblemView = _service.hasPermission(AppPermissions.problemView);
    final canPatientView = _service.hasPermission(AppPermissions.patientView);
    final canDentistView = _service.hasPermission(AppPermissions.dentistView);
    final canAppointmentView = _service.hasPermission(AppPermissions.appointmentView);
    final canReportView = _service.hasPermission(AppPermissions.reportView);

    final filteredRequests = _service.getRequestsForCurrentRole();
    final filteredPatients = _service.getPatientsForCurrentRole();
    final filteredDoctors = _service.getDentistsForCurrentRole();

    final waiting = waitingConsultationRequests(filteredRequests);
    final pendingDocs = filteredDoctors.where(isPendingVerificationDoctor).toList();
    final ads = sponsoredAdsForOverview();

    return GsHealthAdminOverview(
      isLoading: _isOverviewLoading,
      errorMessage: _overviewError,
      onRetry: _refreshOverviewData,
      onRefresh: _refreshOverviewData,
      waitingCount: (canAssignView || canProblemView || canAssignCreate) ? waiting.length : 0,
      assignRestricted: !canAssignCreate,
      onAssign: canAssignCreate
          ? () {
              if (canAssignView) {
                _switchToModuleKey(tabs, 'assignments', 'requests');
              } else if (canProblemView) {
                _switchToModuleKey(tabs, 'problems', 'inquiry pool');
              } else if (waiting.isNotEmpty) {
                _showAssignDoctorModal(context, waiting.first);
              }
            }
          : null,
      stats: [
        AdminStatCardData(
          id: 'waiting',
          label: 'Requests awaiting a doctor',
          value: (canAssignView || canProblemView) ? waiting.length : null,
          restricted: !(canAssignView || canProblemView),
          icon: Icons.hourglass_bottom_rounded,
          accentRed: true,
          onTap: () {
            if (canAssignView) {
              _switchToModuleKey(tabs, 'assignments', 'requests');
            } else if (canProblemView) {
              _switchToModuleKey(tabs, 'problems', 'inquiry pool');
            } else {
              _showRestrictedMessage('consultation requests');
            }
          },
        ),
        AdminStatCardData(
          id: 'pending_doctors',
          label: 'Doctors pending verification',
          value: canDentistView ? pendingDocs.length : null,
          restricted: !canDentistView,
          icon: Icons.verified_user_outlined,
          accentRed: pendingDocs.isNotEmpty,
          onTap: () => canDentistView
              ? _switchToModuleKey(tabs, 'dentists', 'doctors directory')
              : _showRestrictedMessage('doctors directory'),
        ),
        AdminStatCardData(
          id: 'patients',
          label: 'Patients',
          value: canPatientView ? filteredPatients.length : null,
          restricted: !canPatientView,
          icon: Icons.people_outline_rounded,
          onTap: () => canPatientView
              ? _switchToModuleKey(tabs, 'patients', 'patients directory')
              : _showRestrictedMessage('patients directory'),
        ),
        AdminStatCardData(
          id: 'dentists',
          label: 'Doctors',
          value: canDentistView ? filteredDoctors.length : null,
          restricted: !canDentistView,
          icon: Icons.medical_services_outlined,
          onTap: () => canDentistView
              ? _switchToModuleKey(tabs, 'dentists', 'doctors directory')
              : _showRestrictedMessage('doctors directory'),
        ),
        AdminStatCardData(
          id: 'clinics',
          label: 'Clinics',
          value: (canDentistView || canReportView) ? _service.allClinics.length : null,
          restricted: !(canDentistView || canReportView),
          icon: Icons.local_hospital_outlined,
          accentRed: true,
          onTap: () {
            if (canDentistView) {
              _switchToModuleKey(tabs, 'dentists', 'doctors & clinics');
            } else if (canReportView) {
              _switchToModuleKey(tabs, 'reports', 'reports');
            } else {
              _showRestrictedMessage('clinics');
            }
          },
        ),
        AdminStatCardData(
          id: 'appointments',
          label: 'Appointments',
          value: canAppointmentView ? _overviewAppointments.length : null,
          restricted: !canAppointmentView,
          icon: Icons.calendar_today_outlined,
          onTap: () => canAppointmentView
              ? _switchToModuleKey(tabs, 'appointments', 'appointments')
              : _showRestrictedMessage('appointments'),
        ),
      ],
      clinicsAction: AdminQuickActionData(
        id: 'clinics_owners',
        label: 'Clinics & owners',
        icon: Icons.star_border_rounded,
        restricted: !canDentistView,
        onTap: () => canDentistView
            ? _switchToModuleKey(tabs, 'dentists', 'clinics & doctors')
            : _showRestrictedMessage('clinics & owners'),
      ),
      referralsAction: AdminQuickActionData(
        id: 'referrals',
        label: 'Referrals',
        icon: Icons.medical_information_outlined,
        restricted: !canAssignView,
        onTap: () => canAssignView
            ? _switchToModuleKey(tabs, 'assignments', 'referrals')
            : _showRestrictedMessage('referrals'),
      ),
      sponsoredAction: AdminQuickActionData(
        id: 'sponsored_ads',
        label: 'Sponsored ads',
        icon: Icons.campaign_outlined,
        restricted: true,
        onTap: () => _showRestrictedMessage('sponsored ads management'),
      ),
      smsAction: AdminQuickActionData(
        id: 'sms_login',
        label: 'SMS login',
        icon: Icons.chat_bubble_outline_rounded,
        restricted: true,
        onTap: () => _showRestrictedMessage('SMS login management'),
      ),
      ads: ads,
      appointments: canAppointmentView ? _overviewAppointments : const [],
      appointmentsRestricted: !canAppointmentView,
      canViewPhone: canPatientView,
      onAppointmentTap: canAppointmentView
          ? (item) => showAdminAppointmentDetailsSheet(
                context,
                item,
                canViewPhone: canPatientView,
                onOpenSchedule: () => _switchToModuleKey(tabs, 'appointments', 'appointments'),
              )
          : null,
      footer: tabs.length > 1 ? _buildModuleTabBar(tabs) : null,
    );
  }

  void _showSubAdminProfileSheet(BuildContext outerContext) {
    final name = _service.subAdminName.isNotEmpty ? _service.subAdminName : 'Sub-Admin';
    final email = _service.subAdminEmail.isNotEmpty ? _service.subAdminEmail : 'No email configured';
    final perms = _service.subAdminPermissions;

    showModalBottomSheet<void>(
      context: outerContext,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.gsNavy.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.verified_user_rounded, color: AppTheme.gsNavy),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.gsNavy),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          email,
                          style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(sheetCtx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Granted permissions (${perms.length})',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.gsNavy),
              ),
              const SizedBox(height: 8),
              if (perms.isEmpty)
                const Text(
                  'No module permissions assigned. Contact Primary Admin.',
                  style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: perms
                      .map(
                        (p) => Chip(
                          label: Text(p, style: const TextStyle(fontSize: 11.5, color: AppTheme.gsNavy, fontWeight: FontWeight.w600)),
                          backgroundColor: const Color(0xFFF1F5F9),
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                          visualDensity: VisualDensity.compact,
                        ),
                      )
                      .toList(),
                ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.logout_rounded, color: AppTheme.gsRed),
                  label: const Text(
                    'Sign out',
                    style: TextStyle(color: AppTheme.gsRed, fontWeight: FontWeight.w800),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.gsRed),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () {
                    Navigator.of(sheetCtx).pop();
                    _handleLogout(outerContext);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // MODULE 1: DOCTOR ASSIGNMENT & REFERRALS
  // ==========================================
  Widget _buildAssignmentsModule() {
    final canAssign = _service.hasPermission(AppPermissions.assignmentCreate);
    final allRequests = _service.getRequestsForCurrentRole();
    final rolePatients = _service.getPatientsForCurrentRole();
    final filtered = allRequests.where((r) {
      final pName = r.patientName.isNotEmpty ? r.patientName : 'Patient';
      final pCity = r.getDisplayCity(rolePatients);
      final pPin = r.getDisplayPincode(rolePatients);
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
            textInputAction: TextInputAction.search,
            style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13.5, fontWeight: FontWeight.w500),
            cursorColor: AppTheme.primaryBlue,
            onSubmitted: (_) => FocusScope.of(context).unfocus(),
            decoration: InputDecoration(
              hintText: 'Search patient, city, pincode...',
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              suffixIcon: IconButton(
                icon: const Icon(Icons.keyboard_hide_rounded, size: 18, color: AppTheme.textMuted),
                tooltip: 'Hide Keyboard',
                onPressed: () => FocusScope.of(context).unfocus(),
              ),
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

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: canAssign ? () => _showAssignDoctorModal(ctx, req) : null,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
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
                                      'Assigned Doctor: ${req.assignedDoctorName ?? "Specialist"} (${req.assignedDoctorSpecialty ?? "General Medicine"})',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (canAssign) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: Icon(isAssigned ? Icons.swap_horiz_rounded : Icons.person_pin_rounded, size: 16),
                                label: Text(
                                  isAssigned ? 'Change Assigned Doctor' : 'Assign Nearby Specialist Doctor',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF6366F1),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  elevation: 1,
                                ),
                                onPressed: () => _showAssignDoctorModal(ctx, req),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
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
    final requests = _service.getRequestsForCurrentRole();

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
    final patients = _service.getPatientsForCurrentRole().where((p) {
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
            style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13.5, fontWeight: FontWeight.w500),
            cursorColor: AppTheme.primaryBlue,
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
    final doctors = _service.getDentistsForCurrentRole().where((d) {
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
            style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13.5, fontWeight: FontWeight.w500),
            cursorColor: AppTheme.primaryBlue,
            decoration: InputDecoration(
              hintText: 'Search doctors by name, specialty, clinic, city...',
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            ),
          ),
          const SizedBox(height: 14),
          if (doctors.isEmpty)
            _buildEmptyCard('No doctors found.', Icons.medical_services_outlined)
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
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                        tooltip: 'Delete Doctor',
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (dialogCtx) => AlertDialog(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              title: Row(
                                children: [
                                  const Icon(Icons.delete_forever_rounded, color: Colors.red, size: 22),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text('Delete ${d.name}?', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                                ],
                              ),
                              content: Text('Are you sure you want to delete ${d.name} (${d.specialty}) from the platform?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: const Text('Cancel')),
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.delete_forever_rounded, size: 16),
                                  label: const Text('Delete Doctor', style: TextStyle(fontWeight: FontWeight.bold)),
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                  onPressed: () async {
                                    Navigator.of(dialogCtx).pop();
                                    await _service.deleteDoctor(d.id);
                                    if (mounted) {
                                      setState(() {});
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('🗑️ ${d.name} deleted successfully.'), backgroundColor: Colors.red),
                                      );
                                    }
                                  },
                                ),
                              ],
                            ),
                          );
                        },
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
    if (!_service.hasPermission(AppPermissions.appointmentView)) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: _buildEmptyCard('Your role does not include viewing appointments.', Icons.lock_outline_rounded),
      );
    }
    final canViewPhone = _service.hasPermission(AppPermissions.patientView);
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: _overviewAppointments.isEmpty
          ? _buildEmptyCard('No appointments yet.', Icons.calendar_month_outlined)
          : Column(
              children: _overviewAppointments
                  .map(
                    (a) => Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: ListTile(
                        title: Text(a.patientName, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.gsNavy)),
                        subtitle: Text(
                          [
                            if (a.dateRaw.isNotEmpty) a.dateRaw,
                            if (a.timeSlot.isNotEmpty) a.timeSlot,
                            if (a.dentistName.isNotEmpty) a.dentistName,
                            if (canViewPhone && a.phone.isNotEmpty) a.phone,
                          ].join(' · '),
                        ),
                        trailing: Text(a.status.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.gsNavy)),
                        onTap: () => showAdminAppointmentDetailsSheet(
                          context,
                          a,
                          canViewPhone: canViewPhone,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
    );
  }

  // ==========================================
  // MODULE 6: REPORTS & OVERVIEW
  // ==========================================
  Widget _buildReportsModule() {
    final rolePatients = _service.getPatientsForCurrentRole();
    final roleDoctors = _service.getDentistsForCurrentRole();
    final roleRequests = _service.getRequestsForCurrentRole();
    final totalPatients = rolePatients.length;
    final totalDoctors = roleDoctors.length;
    final totalRequests = roleRequests.length;
    final assignedCount = roleRequests.where((r) => r.assignedDoctorId != null && r.assignedDoctorId!.isNotEmpty).length;

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
    final notesCtrl = TextEditingController(text: 'Assigned for specialized medical evaluation.');
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
                            style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                            cursorColor: AppTheme.primaryBlue,
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
                            style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                            cursorColor: AppTheme.primaryBlue,
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
                      style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                      cursorColor: AppTheme.primaryBlue,
                      decoration: InputDecoration(
                        labelText: 'Admin Referral Notes',
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.chat_rounded, size: 15),
                            label: const Text('WhatsApp', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 11),
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

                                    String rawPhone = req.patientPhone.replaceAll(RegExp(r'[^0-9]'), '');
                                    if (rawPhone.startsWith('0') && rawPhone.length == 11) {
                                      rawPhone = '91${rawPhone.substring(1)}';
                                    } else if (rawPhone.length == 10) {
                                      rawPhone = '91$rawPhone';
                                    }

                                    final waText = "🦷 *GS HEALTH Referral Update*\n\nHello ${req.patientName},\nYour consultation request for *${req.problemCategory}* has been assigned to *${selectedDoctor!.name}* (${selectedDoctor!.specialty}) at *${selectedDoctor!.clinicName}*.\n\n📍 Clinic: ${selectedDoctor!.clinicAddress}\n📞 Contact: ${selectedDoctor!.phone}\n\nOur team is here to assist your smile journey!";
                                    final waUrl = Uri.parse(rawPhone.isNotEmpty
                                        ? "https://wa.me/$rawPhone?text=${Uri.encodeComponent(waText)}"
                                        : "https://wa.me/?text=${Uri.encodeComponent(waText)}");
                                    try {
                                      await launchUrl(waUrl, mode: LaunchMode.externalApplication);
                                    } catch (_) {}

                                    if (!dialogCtx.mounted) return;
                                    Navigator.of(dialogCtx).pop();
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('📱 Doctor ${selectedDoctor!.name} assigned & WhatsApp launched!'),
                                          backgroundColor: const Color(0xFF10B981),
                                        ),
                                      );
                                    }
                                  },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.sms_rounded, size: 15),
                            label: const Text('SMS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 11),
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

                                    String rawPhone = req.patientPhone.replaceAll(RegExp(r'[^0-9]'), '');
                                    if (rawPhone.startsWith('0') && rawPhone.length == 11) {
                                      rawPhone = '91${rawPhone.substring(1)}';
                                    } else if (rawPhone.length == 10) {
                                      rawPhone = '91$rawPhone';
                                    }

                                    final smsText = "GS HEALTH: Hello ${req.patientName}, your medical consultation request for ${req.problemCategory} has been assigned to ${selectedDoctor!.name} (${selectedDoctor!.specialty}) at ${selectedDoctor!.clinicName}. Phone: ${selectedDoctor!.phone}";
                                    final smsUrl = Uri.parse(rawPhone.isNotEmpty
                                        ? "sms:$rawPhone?body=${Uri.encodeComponent(smsText)}"
                                        : "sms:?body=${Uri.encodeComponent(smsText)}");
                                    try {
                                      await launchUrl(smsUrl, mode: LaunchMode.externalApplication);
                                    } catch (_) {}

                                    if (!dialogCtx.mounted) return;
                                    Navigator.of(dialogCtx).pop();
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('✉️ Doctor ${selectedDoctor!.name} assigned & SMS opened!'),
                                          backgroundColor: const Color(0xFF2563EB),
                                        ),
                                      );
                                    }
                                  },
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
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
                          child: isSubmitting
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Assign', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ],
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

  void _handleLogout(BuildContext context) async {
    await SessionService().clearSession();
    _service.clearSubAdminSession();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Logged out of Sub-Admin workspace.'),
        duration: Duration(seconds: 2),
      ),
    );
    context.go('/login');
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
