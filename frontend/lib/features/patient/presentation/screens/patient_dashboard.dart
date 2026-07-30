import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/denta_guru_logo.dart';
import '../../../../core/services/patient_problem_service.dart';

class PatientDashboardScreen extends StatefulWidget {
  const PatientDashboardScreen({super.key});

  @override
  State<PatientDashboardScreen> createState() => _PatientDashboardScreenState();
}

class _PatientDashboardScreenState extends State<PatientDashboardScreen> {
  int _currentIndex = 0;
  final PatientProblemService _patientService = PatientProblemService();

  @override
  void initState() {
    super.initState();
    _patientService.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    _patientService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  void _showReportProblemDialog(BuildContext context) {
    final descriptionController = TextEditingController();
    String selectedCategory = 'Toothache & Sensitivity';
    String selectedSeverity = 'Moderate';

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 440),
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.health_and_safety_rounded, color: AppTheme.primaryBlue, size: 24),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Report Dental Problem',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: AppTheme.textDark),
                              ),
                              Text(
                                'Submit symptoms for Admin review & Doctor suggestion',
                                style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Problem Category Dropdown
                    DropdownButtonFormField<String>(
                      initialValue: selectedCategory,
                      decoration: InputDecoration(
                        labelText: 'Dental Issue Category',
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      items: [
                        'Toothache & Sensitivity',
                        'Bleeding Gums & Swelling',
                        'Wisdom Tooth Pain',
                        'Aligners & Braces Adjustment',
                        'Tooth Decay / Cavity',
                        'Teeth Cleaning & Whitening',
                      ].map((cat) => DropdownMenuItem(value: cat, child: Text(cat, style: const TextStyle(fontSize: 13)))).toList(),
                      onChanged: (val) => setModalState(() => selectedCategory = val ?? selectedCategory),
                    ),
                    const SizedBox(height: 12),

                    // Symptom Description
                    TextField(
                      controller: descriptionController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Describe Symptoms & Pain Duration',
                        hintText: 'e.g. Severe throbbing pain in lower molar when eating hot/cold foods...',
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Pain Severity Chips
                    const Text('Pain Severity Level:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppTheme.textMuted)),
                    const SizedBox(height: 6),
                    Row(
                      children: ['Mild', 'Moderate', 'Severe'].map((sev) {
                        final isSelected = selectedSeverity == sev;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(sev, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                            selected: isSelected,
                            selectedColor: sev == 'Severe'
                                ? Colors.red.shade100
                                : sev == 'Moderate'
                                    ? Colors.orange.shade100
                                    : Colors.blue.shade100,
                            labelStyle: TextStyle(
                              color: sev == 'Severe'
                                  ? Colors.red.shade900
                                  : sev == 'Moderate'
                                      ? Colors.orange.shade900
                                      : AppTheme.primaryBlue,
                            ),
                            onSelected: (val) {
                              if (val) setModalState(() => selectedSeverity = sev);
                            },
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),

                    ElevatedButton.icon(
                      icon: const Icon(Icons.send_rounded, size: 18),
                      label: const Text('Submit Problem to Admin', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        if (descriptionController.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please enter a description of your symptoms.')),
                          );
                          return;
                        }
                        _patientService.submitProblem(
                          problemCategory: selectedCategory,
                          problemDescription: descriptionController.text.trim(),
                          severity: selectedSeverity,
                        );
                        Navigator.of(dialogContext).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('✅ Dental problem submitted! Admin will suggest a doctor shortly.'),
                            backgroundColor: Color(0xFF10B981),
                            duration: Duration(seconds: 3),
                          ),
                        );
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

  @override
  Widget build(BuildContext context) {
    final patient = _patientService.currentPatient;

    return Scaffold(
      backgroundColor: AppTheme.softBlueBg,
      appBar: AppBar(
        backgroundColor: AppTheme.softBlueBg,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const DentaGuruLogo(height: 42),
        actions: [
          if (_currentIndex == 0)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.primaryBlue, width: 1.5),
                ),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: AppTheme.primaryBlue.withOpacity(0.1),
                  backgroundImage: patient.photoBytes != null ? MemoryImage(patient.photoBytes!) : null,
                  child: patient.photoBytes == null
                      ? Text(
                          patient.name.isNotEmpty ? patient.name[0].toUpperCase() : 'P',
                          style: const TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold, fontSize: 14),
                        )
                      : null,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 12),
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
        ],
      ),
      body: _buildCurrentTab(),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
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
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.calendar_today_outlined),
              activeIcon: Icon(Icons.calendar_month_rounded, color: AppTheme.primaryBlue),
              label: 'Appointments',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.folder_outlined),
              activeIcon: Icon(Icons.folder_rounded, color: AppTheme.primaryBlue),
              label: 'Records',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline_rounded),
              activeIcon: Icon(Icons.person_rounded, color: AppTheme.primaryBlue),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentTab() {
    switch (_currentIndex) {
      case 0:
        return _buildHomeTab();
      case 1:
        return _buildAppointmentsTab();
      case 2:
        return _buildRecordsTab();
      case 3:
        return _buildProfileTab();
      default:
        return _buildHomeTab();
    }
  }

  // ==========================================
  // TAB 1: HOME TAB
  // ==========================================
  Widget _buildHomeTab() {
    final patient = _patientService.currentPatient;
    final requests = _patientService.requests;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logged-In Greeting Header
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hello, ${patient.name}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${patient.email} • ${patient.bloodGroup}',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
              const Text('👋', style: TextStyle(fontSize: 22)),
            ],
          ),
          const SizedBox(height: 16),

          // Report Dental Problem Banner Button
          InkWell(
            onTap: () => _showReportProblemDialog(context),
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0284C7).withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.add_alert_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Have a Dental Problem?',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Report symptoms to Admin & get recommended a specialized Doctor',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 16),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Section: Reported Problems & Admin Doctor Suggestions
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text(
                'Reported Problems & Doctor Suggestions',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (requests.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFEEF2F6)),
              ),
              child: const Center(
                child: Text('No dental problems reported yet. Tap above to report.', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
              ),
            )
          else
            Column(
              children: requests.map((req) {
                final isSuggested = req.status == 'Doctor Suggested';
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isSuggested ? const Color(0xFF10B981) : const Color(0xFFEEF2F6), width: isSuggested ? 1.5 : 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              req.problemCategory,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isSuggested ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              req.status,
                              style: TextStyle(
                                color: isSuggested ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        req.problemDescription,
                        style: const TextStyle(fontSize: 12, color: AppTheme.textMedium),
                      ),
                      if (isSuggested) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFBBF7D0)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '👨‍⚕️ Admin Suggested: ${req.assignedDoctorName}',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF14532D)),
                                    ),
                                    Text(
                                      'Specialty: ${req.assignedDoctorSpecialty} • WhatsApp notification sent!',
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF15803D)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),
          const SizedBox(height: 20),

          // "Your Next Visit" Card
          _buildNextVisitCard(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

          // "Your Next Visit" Card
          _buildNextVisitCard(),
          const SizedBox(height: 24),

          // Quick Actions
          const Text(
            'Quick Actions',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark),
          ),
          const SizedBox(height: 14),
          _buildQuickActionsRow(),
          const SizedBox(height: 24),

          // Recent Treatments Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent Treatments',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark),
              ),
              TextButton(
                onPressed: () {},
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'View All',
                  style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Treatment Items
          _buildTreatmentItem(
            icon: Icons.medical_information_outlined,
            title: 'Wisdom Tooth Extraction',
            subtitle: 'Sep 12, 2023 • Dr. Elena Rodriguez',
          ),
          const SizedBox(height: 10),
          _buildTreatmentItem(
            icon: Icons.clean_hands_outlined,
            title: 'Deep Cleaning',
            subtitle: 'Jun 05, 2023 • Dr. Marcus Chen',
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildNextVisitCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEEF2F6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Title & Confirmed Badge
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your Next Visit',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Oct 24, 2023',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textDark,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '09:30 AM - 10:15 AM',
                          style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.statusConfirmedBg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Confirmed',
                        style: TextStyle(
                          color: AppTheme.statusConfirmedText,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFF1F5F9)),

          // Doctor Info
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppTheme.softBlueCard,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.softBlueBorder),
                  ),
                  child: const Icon(Icons.person_outline_rounded, color: AppTheme.primaryBlue, size: 22),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Dr. Elena Rodriguez',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Routine Checkup & Cleaning',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Action Buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.softBlueCard,
                      foregroundColor: AppTheme.primaryBlue,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Reschedule', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsRow() {
    final actions = [
      {'icon': Icons.calendar_today_rounded, 'label': 'Book Visit'},
      {'icon': Icons.search_rounded, 'label': 'Find Dentist'},
      {'icon': Icons.qr_code_scanner_rounded, 'label': 'X-Rays'},
      {'icon': Icons.receipt_long_rounded, 'label': 'Billing'},
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: actions.map((act) {
        return Expanded(
          child: Column(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: AppTheme.softBlueCard,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(act['icon'] as IconData, color: AppTheme.primaryBlue, size: 24),
              ),
              const SizedBox(height: 8),
              Text(
                act['label'] as String,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textMedium),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTreatmentItem({required IconData icon, required String title, required String subtitle}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEF2F6)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.softBlueCard,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.primaryBlue, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted, size: 22),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 2: APPOINTMENTS / SCHEDULE TAB
  // ==========================================
  Widget _buildAppointmentsTab() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Schedule Header with Dropdown
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Schedule',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textDark),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: const [
                    Text('October 2023', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.textDark)),
                    SizedBox(width: 6),
                    Icon(Icons.calendar_today_outlined, size: 14, color: AppTheme.primaryBlue),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Horizontal Date Strip (Mon 23 - Fri 27)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildDateCard('Mon', '23', isSelected: true),
              _buildDateCard('Tue', '24', isSelected: false),
              _buildDateCard('Wed', '25', isSelected: false),
              _buildDateCard('Thu', '26', isSelected: false),
              _buildDateCard('Fri', '27', isSelected: false),
            ],
          ),
          const SizedBox(height: 24),

          // Section Title
          const Text(
            'UPCOMING APPOINTMENTS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
              color: AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 12),

          // Card 1: Root Canal Therapy
          _buildUpcomingCard(
            title: 'Root Canal Therapy',
            doctor: 'Dr. Sarah Jenkins',
            date: 'Oct 23, 2023',
            time: '09:30 AM',
            status: 'Confirmed',
            showCancel: false,
          ),
          const SizedBox(height: 14),

          // Card 2: Routine Cleaning
          _buildUpcomingCard(
            title: 'Routine Cleaning',
            doctor: 'Dr. Michael Chen',
            date: 'Nov 12, 2023',
            time: '02:00 PM',
            status: '',
            showCancel: true,
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildDateCard(String day, String date, {required bool isSelected}) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryBlue : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: isSelected ? null : Border.all(color: const Color(0xFFEEF2F6)),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.primaryBlue.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            Text(
              day,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white70 : AppTheme.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              date,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : AppTheme.textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpcomingCard({
    required String title,
    required String doctor,
    required String date,
    required String time,
    required String status,
    required bool showCancel,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEEF2F6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Title & Status Badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.softBlueCard,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.medical_services_outlined, color: AppTheme.primaryBlue, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark)),
                    const SizedBox(height: 2),
                    Text(doctor, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                  ],
                ),
              ),
              if (status.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.statusConfirmedBg,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    status,
                    style: const TextStyle(color: AppTheme.statusConfirmedText, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Date & Time Row
          Row(
            children: [
              const Icon(Icons.calendar_today_outlined, size: 14, color: AppTheme.textMuted),
              const SizedBox(width: 6),
              Text(date, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textDark)),
              const SizedBox(width: 20),
              const Icon(Icons.access_time_rounded, size: 14, color: AppTheme.textMuted),
              const SizedBox(width: 6),
              Text(time, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textDark)),
            ],
          ),
          const SizedBox(height: 14),

          // Action Row
          if (showCancel)
            Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                onTap: () {},
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.cancel_outlined, color: AppTheme.statusCancelText, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'Cancel',
                        style: TextStyle(color: AppTheme.statusCancelText, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Add to Calendar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.softBlueCard,
                      foregroundColor: AppTheme.primaryBlue,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Reschedule', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 3: MEDICAL RECORDS TAB
  // ==========================================
  Widget _buildRecordsTab() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Text(
            'Medical Records',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textDark),
          ),
          const SizedBox(height: 4),
          const Text(
            'Your complete clinical history and diagnostics.',
            style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
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
                hintText: 'Search by procedure, doctor, or drug...',
                hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                prefixIcon: Icon(Icons.search_rounded, color: AppTheme.textMuted),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Filter Chips
          Row(
            children: [
              _buildFilterChip('All Records', isSelected: true),
              const SizedBox(width: 8),
              _buildFilterChip('Summaries', isSelected: false),
              const SizedBox(width: 8),
              _buildFilterChip('X-Rays', isSelected: false),
            ],
          ),
          const SizedBox(height: 24),

          // Visit Summaries Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.assignment_outlined, size: 18, color: AppTheme.primaryBlue),
                  SizedBox(width: 6),
                  Text(
                    'Visit Summaries',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                  ),
                ],
              ),
              TextButton(
                onPressed: () {},
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                child: const Text('View All', style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Summary Cards
          _buildVisitSummaryCard(
            title: 'Deep Cleaning & Periodontal Check',
            date: 'Oct 24, 2023',
            doctor: 'Dr. Sarah Mitchell • Dental Wing A',
          ),
          const SizedBox(height: 10),
          _buildVisitSummaryCard(
            title: 'Wisdom Tooth Extraction Consultation',
            date: 'Aug 13, 2023',
            doctor: 'Dr. Robert Chen • Surgical Suite 4',
          ),
          const SizedBox(height: 24),

          // Lab Results (X-Rays) Section
          Row(
            children: const [
              Icon(Icons.grid_view_rounded, size: 18, color: AppTheme.primaryBlue),
              SizedBox(width: 6),
              Text(
                'Lab Results (X-Rays)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // X-Ray Cards Grid
          Row(
            children: [
              Expanded(
                child: _buildXRayCard('Full Panoramic Scan', 'Oct 24, 2023'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildXRayCard('Bitewing Left Molar', 'Aug 12, 2023'),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, {required bool isSelected}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildVisitSummaryCard({required String title, required String date, required String doctor}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEF2F6)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark)),
                const SizedBox(height: 4),
                Text(date, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textMuted)),
                const SizedBox(height: 2),
                Text(doctor, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted, size: 22),
        ],
      ),
    );
  }

  Widget _buildXRayCard(String title, String date) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEF2F6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image Box with Expand Icon
          Stack(
            children: [
              Container(
                height: 100,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Center(
                  child: Opacity(
                    opacity: 0.6,
                    child: Icon(Icons.medical_information_rounded, color: Colors.blue.shade200, size: 48),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.open_in_full_rounded, color: Colors.white, size: 14),
                ),
              ),
            ],
          ),

          // Label & Date
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark)),
                const SizedBox(height: 2),
                Text(date, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 4: PROFILE TAB
  // ==========================================
  Widget _buildProfileTab() {
    final patient = _patientService.currentPatient;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Column(
        children: [
          const SizedBox(height: 10),

          // Avatar with Edit Pencil Badge
          Stack(
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.softBlueCard,
                  border: Border.all(color: AppTheme.primaryBlue, width: 2.5),
                  image: patient.photoBytes != null
                      ? DecorationImage(
                          image: MemoryImage(patient.photoBytes!),
                          fit: BoxFit.cover,
                        )
                      : const DecorationImage(
                          image: NetworkImage('https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=150'),
                          fit: BoxFit.cover,
                        ),
                ),
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
                  child: const Icon(Icons.edit_rounded, color: Colors.white, size: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // User Name & Email
          Text(
            patient.name,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textDark),
          ),
          const SizedBox(height: 2),
          Text(
            patient.email,
            style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 20),

          // Stat Cards Row 1 (Blood Group & Age)
          Row(
            children: [
              Expanded(
                child: _buildProfileStatCard('BLOOD GROUP', patient.bloodGroup),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildProfileStatCard('AGE', '${patient.age} Years'),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Stat Cards Row 2 (Gender & Phone)
          Row(
            children: [
              Expanded(
                child: _buildProfileStatCard('GENDER', patient.gender),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildProfileStatCard('PHONE', patient.phone),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Option Items List
          _buildProfileOptionItem(Icons.contact_phone_outlined, 'Emergency Contact: ${patient.emergencyContact}'),
          const SizedBox(height: 10),
          _buildProfileOptionItem(Icons.shield_outlined, 'Insurance Details'),
          const SizedBox(height: 10),
          _buildProfileOptionItem(Icons.person_outline_rounded, 'Personal Information'),
          const SizedBox(height: 24),

          // Log Out Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Logged out successfully.'),
                    duration: Duration(seconds: 2),
                  ),
                );
                context.go('/');
              },
              icon: const Icon(Icons.logout_rounded, color: AppTheme.statusCancelText, size: 18),
              label: const Text(
                'Log Out',
                style: TextStyle(color: AppTheme.statusCancelText, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.statusCancelBg,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildProfileStatCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEF2F6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textMuted, letterSpacing: 0.8),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileOptionItem(IconData icon, String title) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEF2F6)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.softBlueCard,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppTheme.primaryBlue, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textDark),
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted, size: 20),
        ],
      ),
    );
  }
}
