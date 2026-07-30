import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/denta_guru_logo.dart';

class DentistTimelineScreen extends StatefulWidget {
  const DentistTimelineScreen({super.key});

  @override
  State<DentistTimelineScreen> createState() => _DentistTimelineScreenState();
}

class _DentistTimelineScreenState extends State<DentistTimelineScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.softBlueBg,
      appBar: AppBar(
        backgroundColor: AppTheme.softBlueBg,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const DentaGuruLogo(height: 28),
            if (_currentIndex == 0)
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Text(
                  'Monday, Oct 24, 2023',
                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w500),
                ),
              ),
          ],
        ),
        actions: [
          if (_currentIndex == 0)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: GestureDetector(
                onTap: () {},
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.primaryBlue, width: 1.5),
                    image: const DecorationImage(
                      image: NetworkImage('https://images.unsplash.com/photo-1622253692010-333f2da6031d?w=150'),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                icon: Stack(
                  children: [
                    const Icon(Icons.notifications_none_rounded, color: AppTheme.primaryBlue, size: 26),
                    Positioned(
                      right: 2,
                      top: 2,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppTheme.brandOrange,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
                onPressed: () {},
              ),
            ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: AppTheme.statusCancelText, size: 22),
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
      body: _buildCurrentTab(),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          backgroundColor: Colors.white,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: AppTheme.primaryBlue,
          unselectedItemColor: AppTheme.textMuted,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home_rounded, color: AppTheme.primaryBlue),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people_outline_rounded),
              activeIcon: Icon(Icons.people_rounded, color: AppTheme.primaryBlue),
              label: 'Patients',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.calendar_today_outlined),
              activeIcon: Icon(Icons.calendar_month_rounded, color: AppTheme.primaryBlue),
              label: 'Appointments',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart_rounded),
              activeIcon: Icon(Icons.bar_chart_rounded, color: AppTheme.primaryBlue),
              label: 'More',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentTab() {
    switch (_currentIndex) {
      case 0:
        return _buildDashboardTab();
      case 1:
        return _buildPatientsTab();
      case 2:
        return _buildDashboardTab(); // Appointments view uses schedule timeline
      case 3:
        return _buildAnalyticsTab();
      default:
        return _buildDashboardTab();
    }
  }

  // ==========================================
  // TAB 1: DENTIST DASHBOARD TAB
  // ==========================================
  Widget _buildDashboardTab() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search Bar
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const TextField(
              decoration: InputDecoration(
                hintText: 'Search patient records...',
                hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                prefixIcon: Icon(Icons.search_rounded, color: AppTheme.textMuted),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 2 Side-by-Side Quick Stat Cards
          Row(
            children: [
              Expanded(
                child: _buildQuickStatBox(
                  icon: Icons.groups_outlined,
                  count: '12',
                  label: "Today's Patients",
                  accentColor: AppTheme.primaryBlue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildQuickStatBox(
                  icon: Icons.calendar_today_outlined,
                  count: '4',
                  label: 'Pending Consults',
                  accentColor: AppTheme.primaryBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Daily Timeline Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Daily Timeline',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textDark),
              ),
              TextButton(
                onPressed: () {},
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                child: Row(
                  children: const [
                    Text(
                      'Full Schedule',
                      style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.chevron_right_rounded, size: 18, color: AppTheme.primaryBlue),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Vertical Timeline Cards
          _buildTimelineNode(
            time: '08:30 AM',
            name: 'Eleanor Shellstrop',
            procedure: 'Routine Cleaning & X-Ray',
            isPrimaryButton: true,
            isLast: false,
          ),
          _buildTimelineNode(
            time: '10:15 AM',
            name: 'Chidi Anagonye',
            procedure: 'Consultation: Wisdom Teeth',
            isPrimaryButton: false,
            isLast: false,
          ),
          _buildTimelineNode(
            time: '01:15 PM',
            name: 'Tahani Al-Jamil',
            procedure: 'Emergency: Chipped Incisor',
            isPrimaryButton: false,
            isLast: true,
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildQuickStatBox({
    required IconData icon,
    required String count,
    required String label,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEF2F6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.softBlueCard,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accentColor, size: 20),
          ),
          const SizedBox(height: 14),
          Text(
            count,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppTheme.textDark),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineNode({
    required String time,
    required String name,
    required String procedure,
    required bool isPrimaryButton,
    required bool isLast,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline Node Indicator & Vertical Track Line
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: isPrimaryButton ? AppTheme.primaryBlue : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppTheme.primaryBlue,
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.access_time_filled_rounded,
                      size: 13,
                      color: isPrimaryButton ? Colors.white : AppTheme.primaryBlue,
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: const Color(0xFFCBD5E1),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Patient Appointment Card
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFEEF2F6)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Time Pill Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.softBlueCard,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      time,
                      style: const TextStyle(
                        color: AppTheme.primaryBlue,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Patient Name & Procedure
                  Text(
                    name,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    procedure,
                    style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 14),

                  // Button Action
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isPrimaryButton ? AppTheme.primaryBlue : AppTheme.softBlueCard,
                        foregroundColor: isPrimaryButton ? Colors.white : AppTheme.primaryBlue,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        isPrimaryButton ? 'View Patient Chart' : 'View Chart',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 2: PATIENT LIST TAB
  // ==========================================
  Widget _buildPatientsTab() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Title & Green "+ New Patient" Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Patients',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Manage your clinical records',
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.add, size: 16, color: Colors.white),
                label: const Text('New Patient', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Search Bar
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const TextField(
              decoration: InputDecoration(
                hintText: 'Search by name, ID or phone...',
                hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                prefixIcon: Icon(Icons.search_rounded, color: AppTheme.textMuted),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Filter Chips Row
          Row(
            children: [
              _buildPatientFilterChip('All (128)', isSelected: true),
              const SizedBox(width: 8),
              _buildPatientFilterChip('Active', isSelected: false),
              const SizedBox(width: 8),
              _buildPatientFilterChip('Follow-up', isSelected: false),
              const SizedBox(width: 8),
              _buildPatientFilterChip('New', isSelected: false),
            ],
          ),
          const SizedBox(height: 16),

          // Patient Cards
          _buildPatientListItemCard(
            initials: 'JS',
            name: 'Jane Smith',
            details: '28 years • Female',
            status: 'ACTIVE',
            statusBg: const Color(0xFFDCFCE7),
            statusText: const Color(0xFF16A34A),
            lastVisit: 'Oct 12, 2023',
            procedure: 'Teeth Whitening',
          ),
          const SizedBox(height: 12),
          _buildPatientListItemCard(
            initials: 'MR',
            name: 'Michael Ross',
            details: '45 years • Male',
            status: 'FOLLOW-UP',
            statusBg: const Color(0xFFDBEAFE),
            statusText: const Color(0xFF2563EB),
            lastVisit: 'Sep 28, 2023',
            procedure: 'Root Canal',
          ),
          const SizedBox(height: 12),
          _buildPatientListItemCard(
            initials: 'AW',
            name: 'Alice Wong',
            details: '32 years • Female',
            status: 'INACTIVE',
            statusBg: const Color(0xFFF1F5F9),
            statusText: const Color(0xFF64748B),
            lastVisit: 'Aug 15, 2023',
            procedure: 'Checkup',
          ),
          const SizedBox(height: 12),
          _buildPatientListItemCard(
            initials: 'DK',
            name: 'David Kim',
            details: '19 years • Male',
            status: 'NEW',
            statusBg: const Color(0xFFFFEDD5),
            statusText: const Color(0xFFF97316),
            lastVisit: 'Pending',
            procedure: 'Consultation',
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildPatientFilterChip(String label, {required bool isSelected}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.primaryBlue : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: isSelected ? null : Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.white : AppTheme.textMedium,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildPatientListItemCard({
    required String initials,
    required String name,
    required String details,
    required String status,
    required Color statusBg,
    required Color statusText,
    required String lastVisit,
    required String procedure,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEEF2F6)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppTheme.softBlueCard,
                child: Text(
                  initials,
                  style: const TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark)),
                    const SizedBox(height: 2),
                    Text(details, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  status,
                  style: TextStyle(color: statusText, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Last Visit', style: TextStyle(fontSize: 10, color: AppTheme.textMuted, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(lastVisit, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Procedure', style: TextStyle(fontSize: 10, color: AppTheme.textMuted, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(procedure, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 3: ANALYTICS TAB
  // ==========================================
  Widget _buildAnalyticsTab() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Analytics Overview',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textDark),
          ),
          const SizedBox(height: 2),
          const Text(
            'Clinical performance metrics for Sept 2023',
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 18),

          // 2 Key Performance Metric Cards
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  icon: Icons.access_time_rounded,
                  label: 'AVG CONSULTATION',
                  value: '24m 12s',
                  change: '-2.4% vs last week',
                  isPositive: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  icon: Icons.person_add_alt_1_rounded,
                  label: 'NEW PATIENTS',
                  value: '42',
                  change: '+12% vs last week',
                  isPositive: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Monthly Revenue Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFEEF2F6)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text('Monthly Revenue', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textDark)),
                        SizedBox(height: 2),
                        Text('Total earnings per month', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: const [
                        Text('\$142,850', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: AppTheme.primaryBlue)),
                        SizedBox(height: 2),
                        Text('+8.2% growth', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Month Bar Chart Visualization
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildBarColumn('Apr', 0.4, false),
                    _buildBarColumn('May', 0.55, false),
                    _buildBarColumn('Jun', 0.45, false),
                    _buildBarColumn('Jul', 0.7, false),
                    _buildBarColumn('Aug', 0.6, false),
                    _buildBarColumn('Sep', 0.9, true, tooltip: '\$134.2k'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Patient Volume Trend Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFEEF2F6)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Patient Volume', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textDark)),
                const SizedBox(height: 2),
                const Text('Daily patient appointments trend', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                const SizedBox(height: 20),

                // Wave Curve Chart Area Representation
                Container(
                  height: 110,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primaryBlue.withValues(alpha: 0.15),
                        AppTheme.primaryBlue.withValues(alpha: 0.01),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: CustomPaint(
                    painter: _WaveChartPainter(),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Text('Mon', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                    Text('Tue', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                    Text('Wed', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                    Text('Thu', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                    Text('Fri', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                    Text('Sep', style: TextStyle(fontSize: 11, color: AppTheme.primaryBlue, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required IconData icon,
    required String label,
    required String value,
    required String change,
    required bool isPositive,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEEF2F6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.softBlueCard,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: AppTheme.primaryBlue, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.textMuted, letterSpacing: 0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textDark),
          ),
          const SizedBox(height: 4),
          Text(
            change,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
          ),
        ],
      ),
    );
  }

  Widget _buildBarColumn(String month, double pct, bool isSelected, {String? tooltip}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (tooltip != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              tooltip,
              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
            ),
          ),
        Container(
          width: 24,
          height: 100 * pct,
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryBlue : AppTheme.softBlueCard,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          month,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? AppTheme.primaryBlue : AppTheme.textMuted,
          ),
        ),
      ],
    );
  }
}

// Wave Line Chart Painter for Patient Volume
class _WaveChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.primaryBlue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final path = Path()
      ..moveTo(0, size.height * 0.6)
      ..cubicTo(size.width * 0.2, size.height * 0.4, size.width * 0.35, size.height * 0.8, size.width * 0.5, size.height * 0.5)
      ..cubicTo(size.width * 0.65, size.height * 0.2, size.width * 0.8, size.height * 0.6, size.width, size.height * 0.2);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
