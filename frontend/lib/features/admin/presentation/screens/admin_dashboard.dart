import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/denta_guru_logo.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _selectedNavIndex = 0; // 0: Dashboard, 3: Patients, 5: Payments/Revenue

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: isDesktop
          ? null
          : AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              title: const DentaGuruLogo(height: 32),
              actions: [
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
      drawer: isDesktop ? null : Drawer(child: _buildSidebarContent()),
      body: Row(
        children: [
          // Sidebar Menu (Visible on Desktop Web)
          if (isDesktop)
            Container(
              width: 220,
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(right: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: _buildSidebarContent(),
            ),

          // Main View Panel Area
          Expanded(
            child: Column(
              children: [
                // Desktop Top Header Bar
                if (isDesktop)
                  Container(
                    height: 64,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _getNavTitle(),
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                        ),
                        Row(
                          children: [
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
                            const SizedBox(width: 8),
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: AppTheme.primaryBlue, width: 1.5),
                                image: const DecorationImage(
                                  image: NetworkImage('https://images.unsplash.com/photo-1559839734-2b71ea197ec2?w=150'),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                // Main Panel View Content
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
  }

  int _getBottomNavIndex() {
    if (_selectedNavIndex == 3) return 1;
    if (_selectedNavIndex == 5) return 2;
    return 0;
  }

  String _getNavTitle() {
    switch (_selectedNavIndex) {
      case 0:
        return 'Dashboard';
      case 1:
        return 'Clinics';
      case 2:
        return 'Dentists';
      case 3:
        return 'Patients';
      case 4:
        return 'Appointments';
      case 5:
        return 'Revenue Overview';
      case 6:
        return 'Reports';
      case 7:
        return 'Reviews';
      case 8:
        return 'Settings';
      default:
        return 'Dashboard';
    }
  }

  Widget _buildSidebarContent() {
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
        const SizedBox(height: 24),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            children: [
              _buildSidebarItem(0, Icons.grid_view_rounded, 'Dashboard'),
              _buildSidebarItem(1, Icons.local_hospital_outlined, 'Clinics'),
              _buildSidebarItem(2, Icons.medical_services_outlined, 'Dentists'),
              _buildSidebarItem(3, Icons.people_outline_rounded, 'Patients'),
              _buildSidebarItem(4, Icons.calendar_today_outlined, 'Appointments'),
              _buildSidebarItem(5, Icons.account_balance_wallet_outlined, 'Payments'),
              _buildSidebarItem(6, Icons.assessment_outlined, 'Reports'),
              _buildSidebarItem(7, Icons.star_outline_rounded, 'Reviews'),
              _buildSidebarItem(8, Icons.settings_outlined, 'Settings'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSidebarItem(int index, IconData icon, String title) {
    final isSelected = _selectedNavIndex == index;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.primaryBlue : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(
          icon,
          size: 18,
          color: isSelected ? Colors.white : AppTheme.textMedium,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.white : AppTheme.textMedium,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 13,
          ),
        ),
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
  // PANEL 1: ADMIN DASHBOARD
  // ==========================================
  Widget _buildDashboardPanel() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 4 Top Key Metrics Cards (Row of 4)
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 750;
              return GridView.count(
                crossAxisCount: isWide ? 4 : 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: isWide ? 1.6 : 1.4,
                children: const [
                  _KpiCard(title: 'Total Patients', value: '1,284', growth: '+12.4%'),
                  _KpiCard(title: 'Total Appointments', value: '3,842', growth: '+9.7%'),
                  _KpiCard(title: 'Total Revenue', value: '₹24,85,200', growth: '+15.3%'),
                  _KpiCard(title: 'Active Clinics', value: '156', growth: '+11.9%'),
                ],
              );
            },
          ),
          const SizedBox(height: 20),

          // 2 Charts Row Side-by-Side (Appointment Overview & Appointments by Status)
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 800) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: _buildAppointmentOverviewCard()),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: _buildAppointmentsByStatusCard()),
                  ],
                );
              }
              return Column(
                children: [
                  _buildAppointmentOverviewCard(),
                  const SizedBox(height: 16),
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
      padding: const EdgeInsets.all(20),
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
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 180,
            width: double.infinity,
            child: CustomPaint(
              painter: _AreaCurvePainter(),
            ),
          ),
          const SizedBox(height: 12),
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
      padding: const EdgeInsets.all(20),
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
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              // Donut Chart Graphic
              SizedBox(
                width: 120,
                height: 120,
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
              const SizedBox(width: 20),

              // Legend
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    _LegendRow(color: Color(0xFF0D9488), label: 'Completed', value: '65%'),
                    SizedBox(height: 12),
                    _LegendRow(color: Color(0xFF0052CC), label: 'Scheduled', value: '25%'),
                    SizedBox(height: 12),
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
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row with "Add Patient" Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Patients',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textDark),
              ),
              ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.add, size: 16, color: Colors.white),
                label: const Text('Add Patient', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Search Bar
          Container(
            width: 320,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const TextField(
              decoration: InputDecoration(
                hintText: 'Search patients...',
                hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                prefixIcon: Icon(Icons.search_rounded, color: AppTheme.textMuted),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Patient Data Table Container
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                // Table Headers Row
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                  ),
                  child: Row(
                    children: const [
                      Expanded(flex: 3, child: Text('Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textMuted))),
                      Expanded(flex: 1, child: Text('Age', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textMuted))),
                      Expanded(flex: 3, child: Text('Phone', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textMuted))),
                      Expanded(flex: 2, child: Text('Last Visit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textMuted))),
                      Expanded(flex: 2, child: Text('Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textMuted))),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),

                // Table Data Rows
                _buildPatientRow('Jane Smith', '28', '+1 202 555 0132', 'Oct 12, 2023', 'Active', const Color(0xFFDCFCE7), const Color(0xFF16A34A)),
                _buildPatientRow('Michael Ross', '45', '+1 202 555 0107', 'Sep 28, 2023', 'Follow-up', const Color(0xFFDBEAFE), const Color(0xFF2563EB)),
                _buildPatientRow('Alice Wong', '32', '+1 202 555 0155', 'Aug 15, 2023', 'Inactive', const Color(0xFFF1F5F9), const Color(0xFF64748B)),
                _buildPatientRow('David Kim', '19', '+1 202 555 0177', '--', 'New', const Color(0xFFFFEDD5), const Color(0xFFF97316)),
                _buildPatientRow('Emma Johnson', '27', '+1 202 555 0133', 'Oct 10, 2023', 'Active', const Color(0xFFDCFCE7), const Color(0xFF16A34A)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPatientRow(
    String name,
    String age,
    String phone,
    String lastVisit,
    String status,
    Color bg,
    Color text,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: AppTheme.softBlueCard,
                  child: Text(
                    name[0],
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                  ),
                ),
              ],
            ),
          ),
          Expanded(flex: 1, child: Text(age, style: const TextStyle(fontSize: 13, color: AppTheme.textMedium))),
          Expanded(flex: 3, child: Text(phone, style: const TextStyle(fontSize: 13, color: AppTheme.textMedium))),
          Expanded(flex: 2, child: Text(lastVisit, style: const TextStyle(fontSize: 13, color: AppTheme.textMedium))),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
                child: Text(status, style: TextStyle(color: text, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // PANEL 3: REVENUE OVERVIEW & PAYMENTS
  // ==========================================
  Widget _buildRevenuePanel() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Revenue Overview',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textDark),
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 800) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: _buildMonthRevenueCard()),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: _buildRevenueByServiceCard()),
                  ],
                );
              }
              return Column(
                children: [
                  _buildMonthRevenueCard(),
                  const SizedBox(height: 16),
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('This Month', style: TextStyle(fontSize: 12, color: AppTheme.textMuted, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Row(
            children: const [
              Text('₹24,85,200', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
              SizedBox(width: 10),
              Text('+15.3%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
            ],
          ),
          const SizedBox(height: 24),
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Revenue by Service', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
          const SizedBox(height: 20),
          Row(
            children: [
              SizedBox(
                width: 120,
                height: 120,
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
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: const [
                    _LegendRow(color: Color(0xFF0D9488), label: 'Cleaning', value: '35%'),
                    SizedBox(height: 10),
                    _LegendRow(color: Color(0xFF0052CC), label: 'Root Canal', value: '25%'),
                    SizedBox(height: 10),
                    _LegendRow(color: Color(0xFF3B82F6), label: 'Implants', value: '20%'),
                    SizedBox(height: 10),
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
          width: 22,
          height: 110 * pct,
          decoration: BoxDecoration(
            color: isHighlight ? AppTheme.primaryBlue : AppTheme.softBlueCard,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          day,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
            color: isHighlight ? AppTheme.primaryBlue : AppTheme.textMuted,
          ),
        ),
      ],
    );
  }
}

// KPI Stat Card Widget
class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final String growth;

  const _KpiCard({required this.title, required this.value, required this.growth});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
          const SizedBox(height: 4),
          Text(growth, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
        ],
      ),
    );
  }
}

// Legend Row Widget
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
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textDark, fontWeight: FontWeight.w500)),
        ),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
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

// Donut Slice Data Structure & Painter
class _DonutSlice {
  final double pct;
  final Color color;
  const _DonutSlice({required this.pct, required this.color});
}

class _DonutChartPainter extends CustomPainter {
  final List<_DonutSlice> slices;

  _DonutChartPainter({required this.slices});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const strokeWidth = 20.0;

    double startAngle = -1.5708; // -90 deg

    for (var slice in slices) {
      final sweepAngle = slice.pct * 6.28318; // 2 * pi

      final paint = Paint()
        ..color = slice.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - (strokeWidth / 2)),
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
