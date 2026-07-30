import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/denta_guru_logo.dart';
import '../../../../core/services/patient_problem_service.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _selectedNavIndex = 0; // 0: Dashboard, 1: Clinics, 2: Dentists, 3: Patients, 4: Appointments, 5: Revenue, 6: Reports, 7: Reviews, 8: Settings
  final PatientProblemService _problemService = PatientProblemService();

  @override
  void initState() {
    super.initState();
    _problemService.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    _problemService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  void _showAssignDoctorDialog(BuildContext context, PatientConsultationRequest req) {
    String selectedDoctor = 'Dr. Sarah Jenkins (Orthodontics)';
    final adminNotesController = TextEditingController();

    final doctorsMap = {
      'Dr. Sarah Jenkins (Orthodontics)': 'Orthodontics',
      'Dr. Michael Chen (Endodontics & Root Canal)': 'Endodontics',
      'Dr. Elena Rodriguez (Pediatric & General Dentistry)': 'General Dentistry',
      'Dr. Robert Vance (Oral & Maxillofacial Surgery)': 'Oral Surgery',
    };

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final doctorNameOnly = selectedDoctor.split(' (').first;
            final doctorSpecialty = doctorsMap[selectedDoctor] ?? 'General Dentistry';

            final waText = "🏥 *DentaGuru Clinical Recommendation*\n\n"
                "Dear *${req.patientName}*,\n"
                "Our Clinical Admin team has reviewed your reported dental problem:\n"
                "📌 *Issue*: ${req.problemCategory}\n"
                "⚡ *Severity*: ${req.severity}\n\n"
                "👨‍⚕️ *Recommended Doctor*: *$doctorNameOnly* ($doctorSpecialty)\n\n"
                "Tap link to confirm appointment: https://dentaguru.com/app/book?dr=${req.id}";

            return Dialog(
              backgroundColor: Colors.white,
              elevation: 20,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 480),
                padding: const EdgeInsets.all(20),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.mark_chat_read_rounded, color: Color(0xFF10B981), size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Suggest Doctor for ${req.patientName}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textDark),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Issue: ${req.problemCategory} • Severity: ${req.severity}',
                                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                  overflow: TextOverflow.ellipsis,
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

                      // Select Doctor Dropdown
                      DropdownButtonFormField<String>(
                        initialValue: selectedDoctor,
                        decoration: InputDecoration(
                          labelText: 'Select Specialized Dentist',
                          labelStyle: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.primaryBlue, fontSize: 12),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 2)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        items: doctorsMap.keys.map((doc) => DropdownMenuItem(value: doc, child: Text(doc, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)))).toList(),
                        onChanged: (val) {
                          if (val != null) setModalState(() => selectedDoctor = val);
                        },
                      ),
                      const SizedBox(height: 14),

                      // WhatsApp Live Message Box
                      const Text('WhatsApp Notification Message Preview:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppTheme.textDark)),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF86EFAC)),
                        ),
                        child: Text(
                          waText,
                          style: const TextStyle(fontSize: 11, color: Color(0xFF14532D), height: 1.35, fontFamily: 'monospace'),
                        ),
                      ),
                      const SizedBox(height: 18),

                      ElevatedButton.icon(
                        icon: const Icon(Icons.send_rounded, size: 16),
                        label: const Text('Send WhatsApp Notification', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          _problemService.assignDoctorToRequest(
                            requestId: req.id,
                            doctorName: doctorNameOnly,
                            specialty: doctorSpecialty,
                            adminNotes: adminNotesController.text,
                          );

                          final waUrl = Uri.parse("https://wa.me/?text=${Uri.encodeComponent(waText)}");
                          try {
                            if (await canLaunchUrl(waUrl)) {
                              await launchUrl(waUrl, mode: LaunchMode.externalApplication);
                            }
                          } catch (e) {
                            debugPrint('WhatsApp launcher info: $e');
                          }

                          Navigator.of(dialogContext).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('📱 WhatsApp notification sent to ${req.patientName} & $doctorNameOnly!'),
                              backgroundColor: const Color(0xFF10B981),
                              duration: const Duration(seconds: 3),
                            ),
                          );
                        },
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Use container width constraints to strictly determine Desktop side-by-side mode (requires >= 950px width!)
        final isDesktop = constraints.maxWidth >= 950;

        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          appBar: isDesktop
              ? null
              : AppBar(
                  backgroundColor: Colors.white,
                  elevation: 1,
                  title: const DentaGuruLogo(height: 30),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.logout_rounded, color: AppTheme.statusCancelText, size: 20),
                      tooltip: 'Log Out',
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Logged out successfully.')),
                        );
                        context.go('/');
                      },
                    ),
                  ],
                ),
          drawer: isDesktop ? null : Drawer(child: _buildSidebarContent()),
          body: Row(
            children: [
              // Sidebar Menu with Accordion Dropdowns ONLY when container width >= 950px
              if (isDesktop)
                Container(
                  width: 250,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(right: BorderSide(color: Color(0xFFE2E8F0))),
                  ),
                  child: _buildSidebarContent(),
                ),

              // Main Content Panel Area
              Expanded(
                child: Column(
                  children: [
                    // Desktop Header Bar
                    if (isDesktop)
                      Container(
                        height: 64,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _getNavTitle(),
                                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const Text(
                                    'DentaGuru Clinical Admin Portal',
                                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDCFCE7),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text('Admin Mode', style: TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.bold, fontSize: 11)),
                                ),
                                const SizedBox(width: 12),
                                IconButton(
                                  icon: const Icon(Icons.logout_rounded, color: AppTheme.statusCancelText, size: 20),
                                  tooltip: 'Log Out',
                                  onPressed: () => context.go('/'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                    // Mobile Horizontal Navigation Bar Pills (When container is < 950px)
                    if (!isDesktop)
                      Container(
                        height: 48,
                        color: Colors.white,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: Row(
                            children: [
                              _buildMobileNavPill(0, 'Dashboard', Icons.grid_view_rounded),
                              _buildMobileNavPill(3, 'Patients', Icons.people_outline_rounded),
                              _buildMobileNavPill(1, 'Clinics', Icons.local_hospital_outlined),
                              _buildMobileNavPill(2, 'Dentists', Icons.medical_services_outlined),
                              _buildMobileNavPill(5, 'Revenue', Icons.account_balance_wallet_outlined),
                            ],
                          ),
                        ),
                      ),

                    // Active Panel View
                    Expanded(
                      child: _buildSelectedPanel(),
                    ),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: isDesktop
              ? null
              : BottomNavigationBar(
                  currentIndex: _getBottomNavIndex(),
                  selectedItemColor: AppTheme.primaryBlue,
                  unselectedItemColor: AppTheme.textMuted,
                  selectedFontSize: 11,
                  unselectedFontSize: 11,
                  onTap: (index) {
                    setState(() {
                      if (index == 0) _selectedNavIndex = 0; // Dashboard
                      if (index == 1) _selectedNavIndex = 3; // Patients
                      if (index == 2) _selectedNavIndex = 5; // Revenue
                    });
                  },
                  items: const [
                    BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'Dashboard'),
                    BottomNavigationBarItem(icon: Icon(Icons.people_alt_rounded), label: 'Patients'),
                    BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet_rounded), label: 'Revenue'),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildMobileNavPill(int index, String label, IconData icon) {
    final isSelected = _selectedNavIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedNavIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryBlue : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: isSelected ? Colors.white : AppTheme.textMedium),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: isSelected ? Colors.white : AppTheme.textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _getBottomNavIndex() {
    if (_selectedNavIndex == 3) return 1;
    if (_selectedNavIndex == 5) return 2;
    return 0;
  }

  String _getNavTitle() {
    switch (_selectedNavIndex) {
      case 0:
        return 'Dashboard Overview';
      case 1:
        return 'Clinics Directory';
      case 2:
        return 'Dentists & Specialists';
      case 3:
        return 'Patients Directory';
      case 4:
        return 'Appointments Schedule';
      case 5:
        return 'Revenue & Financials';
      case 6:
        return 'Reports & Analytics';
      case 7:
        return 'Patient Reviews';
      case 8:
        return 'System Settings';
      default:
        return 'Admin Dashboard';
    }
  }

  // ==========================================
  // SIDEBAR WITH ACCORDION DROPDOWN CATEGORIES
  // ==========================================
  Widget _buildSidebarContent() {
    final pendingCount = _problemService.requests.where((r) => r.status == "Pending Admin Review").length;

    return Column(
      children: [
        const SizedBox(height: 18),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: DentaGuruLogo(height: 36),
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            children: [
              // CATEGORY 1: OVERVIEW & CONSULTATIONS DROPDOWN
              _buildSidebarDropdownCategory(
                categoryTitle: 'Overview & Care',
                categoryIcon: Icons.dashboard_customize_rounded,
                initiallyExpanded: true,
                children: [
                  _buildSubNavItem(0, Icons.grid_view_rounded, 'Dashboard Overview'),
                  _buildSubNavItem(0, Icons.mark_chat_read_rounded, 'Patient Problems', badgeCount: pendingCount),
                ],
              ),
              const SizedBox(height: 8),

              // CATEGORY 2: CLINICAL MANAGEMENT DROPDOWN
              _buildSidebarDropdownCategory(
                categoryTitle: 'Clinical Operations',
                categoryIcon: Icons.local_hospital_rounded,
                initiallyExpanded: true,
                children: [
                  _buildSubNavItem(1, Icons.domain_rounded, 'Clinics Directory'),
                  _buildSubNavItem(2, Icons.medical_services_rounded, 'Dentists & Specialists'),
                ],
              ),
              const SizedBox(height: 8),

              // CATEGORY 3: PATIENT CARE DROPDOWN
              _buildSidebarDropdownCategory(
                categoryTitle: 'Patient Operations',
                categoryIcon: Icons.people_alt_rounded,
                initiallyExpanded: false,
                children: [
                  _buildSubNavItem(3, Icons.person_search_rounded, 'Patients Directory'),
                  _buildSubNavItem(4, Icons.calendar_month_rounded, 'Appointments'),
                  _buildSubNavItem(7, Icons.star_rounded, 'Patient Reviews'),
                ],
              ),
              const SizedBox(height: 8),

              // CATEGORY 4: FINANCIALS & ANALYTICS DROPDOWN
              _buildSidebarDropdownCategory(
                categoryTitle: 'Financials & Reports',
                categoryIcon: Icons.account_balance_wallet_rounded,
                initiallyExpanded: false,
                children: [
                  _buildSubNavItem(5, Icons.payments_rounded, 'Revenue & Payments'),
                  _buildSubNavItem(6, Icons.bar_chart_rounded, 'Reports & Analytics'),
                ],
              ),
              const SizedBox(height: 8),

              // CATEGORY 5: SYSTEM ADMIN DROPDOWN
              _buildSidebarDropdownCategory(
                categoryTitle: 'System Settings',
                categoryIcon: Icons.admin_panel_settings_rounded,
                initiallyExpanded: false,
                children: [
                  _buildSubNavItem(8, Icons.settings_rounded, 'General Settings'),
                  _buildSubNavItem(8, Icons.security_rounded, 'Role & Permissions'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSidebarDropdownCategory({
    required String categoryTitle,
    required IconData categoryIcon,
    required List<Widget> children,
    bool initiallyExpanded = false,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          childrenPadding: const EdgeInsets.only(bottom: 6),
          leading: Icon(categoryIcon, size: 18, color: AppTheme.primaryBlue),
          title: Text(
            categoryTitle,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
          children: children,
        ),
      ),
    );
  }

  Widget _buildSubNavItem(int index, IconData icon, String title, {int badgeCount = 0}) {
    final isSelected = _selectedNavIndex == index;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.primaryBlue : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        leading: Icon(
          icon,
          size: 16,
          color: isSelected ? Colors.white : AppTheme.textMedium,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.white : AppTheme.textMedium,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 12,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        trailing: badgeCount > 0
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$badgeCount',
                  style: TextStyle(
                    color: isSelected ? AppTheme.primaryBlue : Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : null,
        onTap: () {
          setState(() {
            _selectedNavIndex = index;
          });
        },
      ),
    );
  }

  Widget _buildSelectedPanel() {
    switch (_selectedNavIndex) {
      case 0:
        return _buildDashboardPanel();
      case 3:
        return _buildPatientsPanel();
      case 5:
        return _buildRevenuePanel();
      default:
        return _buildDashboardPanel();
    }
  }

  // ==========================================
  // PANEL 1: ADMIN DASHBOARD (RESPONSIVE & OVERFLOW FREE)
  // ==========================================
  Widget _buildDashboardPanel() {
    final requests = _problemService.requests;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // KPI Stat Metrics Grid (Adaptable crossAxisCount & childAspectRatio)
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final crossCount = w > 750 ? 4 : (w > 420 ? 2 : 1);
              final childRatio = w > 750 ? 1.5 : (w > 420 ? 1.6 : 2.6);

              return GridView.count(
                crossAxisCount: crossCount,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: childRatio,
                children: [
                  const _KpiCard(
                    title: 'Total Active Patients',
                    value: '1,284',
                    growth: '+12.4% growth',
                    accentColor: AppTheme.primaryBlue,
                    icon: Icons.people_alt_rounded,
                  ),
                  _KpiCard(
                    title: 'Pending Consultations',
                    value: '${requests.where((r) => r.status == "Pending Admin Review").length}',
                    growth: 'Requires Action',
                    accentColor: const Color(0xFFD97706),
                    icon: Icons.pending_actions_rounded,
                  ),
                  const _KpiCard(
                    title: 'Total Revenue',
                    value: '₹24,85,200',
                    growth: '+15.3% growth',
                    accentColor: const Color(0xFF10B981),
                    icon: Icons.account_balance_wallet_rounded,
                  ),
                  const _KpiCard(
                    title: 'Partner Clinics',
                    value: '156',
                    growth: '+11.9% expansion',
                    accentColor: const Color(0xFF8B5CF6),
                    icon: Icons.local_hospital_rounded,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),

          // PATIENT PROBLEM CONSULTATIONS CONTAINER
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '🩺 Patient Problem Consultations',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Review symptoms & assign doctor via WhatsApp',
                            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.mark_chat_read_rounded, size: 14, color: Color(0xFF16A34A)),
                          SizedBox(width: 4),
                          Text(
                            'WhatsApp',
                            style: TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                if (requests.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('No patient consultation requests submitted.', style: TextStyle(color: AppTheme.textMuted)),
                  )
                else
                  Column(
                    children: requests.map((req) {
                      final isPending = req.status == 'Pending Admin Review';

                      return LayoutBuilder(
                        builder: (context, cardConstraints) {
                          final isNarrow = cardConstraints.maxWidth < 520;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isPending ? const Color(0xFFF59E0B) : const Color(0xFFCBD5E1),
                                width: isPending ? 1.5 : 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: isPending ? const Color(0xFFFEF3C7) : const Color(0xFFDCFCE7),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        isPending ? Icons.pending_actions_rounded : Icons.check_circle_rounded,
                                        color: isPending ? const Color(0xFFD97706) : const Color(0xFF16A34A),
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            req.patientName,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            '📞 Phone: ${req.patientPhone}',
                                            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: req.severity == 'Severe'
                                            ? const Color(0xFFFEE2E2)
                                            : req.severity == 'Moderate'
                                                ? const Color(0xFFFEF3C7)
                                                : const Color(0xFFDBEAFE),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '${req.severity}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: req.severity == 'Severe'
                                              ? const Color(0xFF991B1B)
                                              : req.severity == 'Moderate'
                                                  ? const Color(0xFF92400E)
                                                  : AppTheme.primaryBlue,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),

                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Issue: ${req.problemCategory}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppTheme.primaryBlue),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  req.problemDescription,
                                  style: const TextStyle(fontSize: 12, color: AppTheme.textDark, height: 1.3),
                                ),

                                if (req.assignedDoctorName != null) ...[
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF0FDF4),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0xFF86EFAC)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.verified_user_rounded, color: Color(0xFF16A34A), size: 16),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Assigned: ${req.assignedDoctorName} (${req.assignedDoctorSpecialty})',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF14532D)),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],

                                const SizedBox(height: 12),

                                SizedBox(
                                  width: isNarrow ? double.infinity : null,
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.mark_chat_read_rounded, size: 16),
                                    label: Text(
                                      isPending ? '🟢 Suggest Doctor & Launch WhatsApp' : '💬 Resend WhatsApp Link',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isPending ? const Color(0xFF10B981) : AppTheme.primaryBlue,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      elevation: 1,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    onPressed: () => _showAssignDoctorDialog(context, req),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Charts Row
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 750) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: _buildAppointmentOverviewCard()),
                    const SizedBox(width: 14),
                    Expanded(flex: 2, child: _buildAppointmentsByStatusCard()),
                  ],
                );
              }
              return Column(
                children: [
                  _buildAppointmentOverviewCard(),
                  const SizedBox(height: 14),
                  _buildAppointmentsByStatusCard(),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAppointmentOverviewCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Appointment Overview',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textDark),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 160,
            width: double.infinity,
            child: CustomPaint(
              painter: _AreaCurvePainter(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('Apr', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              Text('May', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              Text('Jun', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              Text('Jul', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              Text('Aug', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              Text('Sep', style: TextStyle(fontSize: 11, color: AppTheme.primaryBlue, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAppointmentsByStatusCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Appointments by Status',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textDark),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 100,
                height: 100,
                child: CustomPaint(
                  painter: _DonutChartPainter(
                    slices: const [
                      _DonutSlice(pct: 0.65, color: Color(0xFF0D9488)),
                      _DonutSlice(pct: 0.25, color: Color(0xFF0052CC)),
                      _DonutSlice(pct: 0.10, color: Color(0xFF60A5FA)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    _LegendRow(color: Color(0xFF0D9488), label: 'Completed', value: '65%'),
                    SizedBox(height: 8),
                    _LegendRow(color: Color(0xFF0052CC), label: 'Scheduled', value: '25%'),
                    SizedBox(height: 8),
                    _LegendRow(color: Color(0xFF60A5FA), label: 'Cancelled', value: '10%'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================
  // PANEL 2: PATIENTS MANAGEMENT DATA TABLE
  // ==========================================
  Widget _buildPatientsPanel() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Patients Directory',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textDark),
              ),
              ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.add, size: 16, color: Colors.white),
                label: const Text('Add Patient', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  elevation: 1,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Name', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Age', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Phone', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Last Visit', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: [
                  _buildDataRow('Jane Smith', '28', '+1 202 555 0132', 'Oct 12, 2023', 'Active', const Color(0xFFDCFCE7), const Color(0xFF16A34A)),
                  _buildDataRow('Michael Ross', '45', '+1 202 555 0107', 'Sep 28, 2023', 'Follow-up', const Color(0xFFDBEAFE), const Color(0xFF2563EB)),
                  _buildDataRow('Alice Wong', '32', '+1 202 555 0155', 'Aug 15, 2023', 'Inactive', const Color(0xFFF1F5F9), const Color(0xFF64748B)),
                  _buildDataRow('David Kim', '19', '+1 202 555 0177', '--', 'New', const Color(0xFFFFEDD5), const Color(0xFFF97316)),
                  _buildDataRow('Emma Johnson', '27', '+1 202 555 0133', 'Oct 10, 2023', 'Active', const Color(0xFFDCFCE7), const Color(0xFF16A34A)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  DataRow _buildDataRow(String name, String age, String phone, String lastVisit, String status, Color bg, Color text) {
    return DataRow(
      cells: [
        DataCell(
          Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: AppTheme.softBlueCard,
                child: Text(name[0], style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
              ),
              const SizedBox(width: 8),
              Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
        ),
        DataCell(Text(age, style: const TextStyle(fontSize: 12))),
        DataCell(Text(phone, style: const TextStyle(fontSize: 12))),
        DataCell(Text(lastVisit, style: const TextStyle(fontSize: 12))),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
            child: Text(status, style: TextStyle(color: text, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // PANEL 3: REVENUE OVERVIEW & PAYMENTS
  // ==========================================
  Widget _buildRevenuePanel() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Revenue & Financial Analytics',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textDark),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 750) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: _buildMonthRevenueCard()),
                    const SizedBox(width: 14),
                    Expanded(flex: 2, child: _buildRevenueByServiceCard()),
                  ],
                );
              }
              return Column(
                children: [
                  _buildMonthRevenueCard(),
                  const SizedBox(height: 14),
                  _buildRevenueByServiceCard(),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMonthRevenueCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Total Monthly Revenue', style: TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Row(
            children: const [
              Text('₹24,85,200', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
              SizedBox(width: 10),
              Text('+15.3%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildBarColumn('Fri', 0.4, false),
              _buildBarColumn('Sat', 0.55, false),
              _buildBarColumn('Sun', 0.45, false),
              _buildBarColumn('Mon', 0.7, false),
              _buildBarColumn('Tue', 0.95, true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueByServiceCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Revenue by Service Category', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 100,
                height: 100,
                child: CustomPaint(
                  painter: _DonutChartPainter(
                    slices: const [
                      _DonutSlice(pct: 0.35, color: Color(0xFF0D9488)),
                      _DonutSlice(pct: 0.25, color: Color(0xFF0052CC)),
                      _DonutSlice(pct: 0.20, color: Color(0xFF3B82F6)),
                      _DonutSlice(pct: 0.20, color: Color(0xFF93C5FD)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  children: const [
                    _LegendRow(color: Color(0xFF0D9488), label: 'Cleaning', value: '35%'),
                    SizedBox(height: 8),
                    _LegendRow(color: Color(0xFF0052CC), label: 'Root Canal', value: '25%'),
                    SizedBox(height: 8),
                    _LegendRow(color: Color(0xFF3B82F6), label: 'Implants', value: '20%'),
                    SizedBox(height: 8),
                    _LegendRow(color: Color(0xFF93C5FD), label: 'Others', value: '20%'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBarColumn(String day, double pct, bool isHighlight) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: 20,
          height: 90 * pct,
          decoration: BoxDecoration(
            color: isHighlight ? AppTheme.primaryBlue : AppTheme.softBlueCard,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          day,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
            color: isHighlight ? AppTheme.primaryBlue : AppTheme.textMuted,
          ),
        ),
      ],
    );
  }
}

// KPI STAT CARD WIDGET (OVERFLOW PROOF WITH FITTED BOX)
class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final String growth;
  final Color accentColor;
  final IconData icon;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.growth,
    required this.accentColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: accentColor),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textDark),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            growth,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: accentColor),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}

// LEGEND ROW WIDGET
class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;
  final String value;

  const _LegendRow({required this.color, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textDark, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
        ),
        Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
      ],
    );
  }
}

// Custom Painter for Smooth Area Curve Chart
class _AreaCurvePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = AppTheme.primaryBlue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          AppTheme.primaryBlue.withValues(alpha: 0.2),
          AppTheme.primaryBlue.withValues(alpha: 0.0),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = Path()
      ..moveTo(0, size.height * 0.7)
      ..cubicTo(size.width * 0.2, size.height * 0.5, size.width * 0.35, size.height * 0.8, size.width * 0.5, size.height * 0.45)
      ..cubicTo(size.width * 0.65, size.height * 0.2, size.width * 0.8, size.height * 0.5, size.width, size.height * 0.15);

    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Donut Slice & Custom Painter
class _DonutSlice {
  final double pct;
  final Color color;
  const _DonutSlice({required this.pct, required this.color});
}

class _DonutChartPainter extends CustomPainter {
  final List<_DonutSlice> slices;
  const _DonutChartPainter({required this.slices});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    double startAngle = -1.57;

    for (final slice in slices) {
      final sweepAngle = slice.pct * 2 * 3.14159;
      final paint = Paint()
        ..color = slice.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 20;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 10),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
