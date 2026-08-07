import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/denta_guru_logo.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/widgets/products_dropdown_menu.dart';

class DentistTimelineScreen extends StatefulWidget {
  const DentistTimelineScreen({super.key});

  @override
  State<DentistTimelineScreen> createState() => _DentistTimelineScreenState();
}

class _DentistTimelineScreenState extends State<DentistTimelineScreen> with TickerProviderStateMixin {
  int _currentIndex = 0;
  final PatientProblemService _patientService = PatientProblemService();

  late AnimationController _entryController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _pulseScaleAnimation;

  @override
  void initState() {
    super.initState();
    _patientService.addListener(_onServiceUpdate);

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
    ));

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _pulseScaleAnimation = Tween<double>(begin: 0.94, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _entryController.forward();
  }

  @override
  void dispose() {
    _entryController.dispose();
    _pulseController.dispose();
    _patientService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  void _showUpdateMyFeeAndSlotsDialog(BuildContext context) {
    final currentDoc = _patientService.currentDoctor ?? _patientService.allDoctors.first;
    final feeCtrl = TextEditingController(text: currentDoc.consultationFee);
    final slotCtrl = TextEditingController(
      text: currentDoc.nextAvailableSlots.isNotEmpty ? currentDoc.nextAvailableSlots.first : 'Today, 2:00 PM',
    );

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.edit_calendar_rounded, color: AppTheme.primaryBlue, size: 22),
              SizedBox(width: 8),
              Text('Update My Fee & Time Slots', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: feeCtrl,
                decoration: InputDecoration(
                  labelText: 'My Consultation Fee',
                  hintText: 'e.g. \$85',
                  prefixIcon: const Icon(Icons.payments_outlined),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: slotCtrl,
                decoration: InputDecoration(
                  labelText: 'Next Available Time Slot',
                  hintText: 'e.g. Today, 4:00 PM',
                  prefixIcon: const Icon(Icons.access_time_rounded),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: const Text('Cancel')),
            ElevatedButton.icon(
              icon: const Icon(Icons.check_circle_rounded, size: 16),
              label: const Text('Save & Publish', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                _patientService.updateDoctorFeeAndSlots(
                  doctorId: currentDoc.id,
                  consultationFee: feeCtrl.text.trim(),
                  availableSlot: slotCtrl.text.trim(),
                );
                Navigator.of(dialogCtx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('🎉 Your fee is now ${feeCtrl.text.trim()} & slot updated to ${slotCtrl.text.trim()}!'),
                    backgroundColor: const Color(0xFF10B981),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  void _showAcceptAndScheduleModal(BuildContext context, PatientConsultationRequest req) {
    final currentDoc = _patientService.currentDoctor;
    final defaultSlot = currentDoc?.nextAvailableSlots.isNotEmpty == true
        ? currentDoc!.nextAvailableSlots.first
        : 'Today, 2:30 PM';
    final slotCtrl = TextEditingController(text: req.confirmedTimeSlot ?? defaultSlot);

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.event_available_rounded, color: Color(0xFF10B981), size: 24),
              SizedBox(width: 8),
              Text('Accept & Set Time Slot', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Patient: ${req.patientName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text('Category: ${req.problemCategory}', style: const TextStyle(fontSize: 12, color: AppTheme.primaryBlue)),
              const SizedBox(height: 14),
              TextField(
                controller: slotCtrl,
                decoration: InputDecoration(
                  labelText: 'Set Confirmed Time Slot',
                  hintText: 'e.g. Today, 3:30 PM',
                  prefixIcon: const Icon(Icons.access_time_filled_rounded, color: AppTheme.primaryBlue),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.check_circle_rounded, size: 16),
              label: const Text('Confirm & Save Slot', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final chosenSlot = slotCtrl.text.trim().isNotEmpty ? slotCtrl.text.trim() : 'Today, 2:30 PM';
                await _patientService.acceptReferralByDentist(req.id, timeSlot: chosenSlot);
                if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('🎉 Accepted ${req.patientName}\'s consultation for $chosenSlot! Saved to Supabase DB.'),
                      backgroundColor: const Color(0xFF10B981),
                    ),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _showPrescriptionModal(BuildContext context, String patientName) {
    final medController = TextEditingController(text: 'Amoxicillin 500mg');
    final dosageController = TextEditingController(text: '1 Capsule every 8 hours after meals');
    final durationController = TextEditingController(text: '7 Days');

    showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          child: Padding(
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
                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.receipt_long_rounded, color: Color(0xFF10B981), size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Issue E-Prescription', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: AppTheme.textDark)),
                          Text('Patient: $patientName', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: medController,
                  decoration: InputDecoration(
                    labelText: 'Medication Name & Strength',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dosageController,
                  decoration: InputDecoration(
                    labelText: 'Dosage Instructions',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: durationController,
                  decoration: InputDecoration(
                    labelText: 'Treatment Duration',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle_rounded, size: 18),
                  label: const Text('Send Digital E-Prescription to Patient', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    final medName = medController.text.trim();
                    final dosage = dosageController.text.trim();
                    final duration = durationController.text.trim();

                    final newRecord = {
                      'id': 'REC-${DateTime.now().millisecondsSinceEpoch}',
                      'type': 'prescription',
                      'title': 'Digital Prescription Slips',
                      'subtitle': 'Active Prescription (${medName.isNotEmpty ? medName : 'Amoxicillin 500mg'})',
                      'doctorName': _patientService.currentDoctor?.name ?? 'Dentist Practitioner',
                      'clinicName': _patientService.currentDoctor?.clinicName ?? 'DentaGuru Clinic',
                      'date': DateTime.now().toString().split(' ').first,
                      'items': [
                        {
                          'name': medName.isNotEmpty ? medName : 'Amoxicillin 500mg',
                          'dosage': dosage.isNotEmpty ? dosage : '1 Capsule every 8 hours after meals',
                          'duration': duration.isNotEmpty ? duration : '7 Days',
                          'status': 'Active',
                        }
                      ],
                    };

                    _patientService.addMedicalRecord(newRecord);

                    await ApiService().createMedicalRecord(
                      patientId: _patientService.currentPatient.id,
                      type: 'prescription',
                      title: 'Digital Prescription Slips',
                      subtitle: 'Active Prescription (${medName.isNotEmpty ? medName : 'Amoxicillin 500mg'})',
                      doctorName: _patientService.currentDoctor?.name ?? 'Dentist Practitioner',
                      clinicName: _patientService.currentDoctor?.clinicName ?? 'DentaGuru Clinic',
                      items: [
                        {
                          'name': medName.isNotEmpty ? medName : 'Amoxicillin 500mg',
                          'dosage': dosage.isNotEmpty ? dosage : '1 Capsule every 8 hours after meals',
                          'duration': duration.isNotEmpty ? duration : '7 Days',
                          'status': 'Active',
                        }
                      ],
                    );

                    if (context.mounted) {
                      Navigator.of(dialogContext).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('💊 Digital E-Prescription issued to $patientName! Live in Patient Health Locker.'),
                          backgroundColor: const Color(0xFF10B981),
                          duration: const Duration(seconds: 3),
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
  }

  void _showNotificationsModal(BuildContext context, String role) {
    showDialog(
      context: context,
      builder: (dialogCtx) {
        final notifs = _patientService.appNotifications.where((n) => n.recipientRole == role || n.recipientRole == 'ALL').toList();

        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440, maxHeight: 520),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.notifications_active_rounded, color: AppTheme.primaryBlue, size: 22),
                        SizedBox(width: 8),
                        Text('In-App Notifications', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(dialogCtx).pop()),
                  ],
                ),
                const Divider(height: 20),
                if (notifs.isEmpty)
                  const Expanded(
                    child: Center(
                      child: Text('No new notifications.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      itemCount: notifs.length,
                      itemBuilder: (ctx, idx) {
                        final n = notifs[idx];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(n.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryBlue)),
                              const SizedBox(height: 2),
                              Text(n.message, style: const TextStyle(fontSize: 11, color: AppTheme.textDark)),
                              const SizedBox(height: 4),
                              Text(
                                '${n.timestamp.hour}:${n.timestamp.minute.toString().padLeft(2, '0')}',
                                style: const TextStyle(fontSize: 9, color: Colors.grey),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.softBlueBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.05),
        automaticallyImplyLeading: false,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            DentaGuruLogo(height: 36),
            SizedBox(height: 2),
            Text(
              'Dentist Practitioner Workspace',
              style: TextStyle(fontSize: 10, color: AppTheme.textMuted, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 6),
            child: ProductsDropdownMenu(),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              children: [
                Builder(
                  builder: (context) {
                    final notifs = _patientService.appNotifications.where((n) => n.recipientRole == 'Dentist').toList();
                    final unreadCount = notifs.where((n) => !n.isRead).length;

                    return Stack(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.notifications_none_rounded, color: AppTheme.textDark, size: 24),
                          onPressed: () => _showNotificationsModal(context, 'Dentist'),
                        ),
                        if (unreadCount > 0)
                          Positioned(
                            right: 6,
                            top: 6,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle),
                              child: Text(
                                '$unreadCount',
                                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 22),
                  tooltip: 'Log Out',
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Logged out of Dentist workspace.')),
                    );
                    context.go('/');
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: _buildCurrentTab(),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
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
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
          onTap: (index) => setState(() => _currentIndex = index),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined),
              activeIcon: Icon(Icons.dashboard_rounded, color: AppTheme.primaryBlue),
              label: 'Timeline',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people_outline_rounded),
              activeIcon: Icon(Icons.people_rounded, color: AppTheme.primaryBlue),
              label: 'Patients',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.receipt_long_outlined),
              activeIcon: Icon(Icons.receipt_long_rounded, color: AppTheme.primaryBlue),
              label: 'Prescriptions',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart_rounded),
              activeIcon: Icon(Icons.bar_chart_rounded, color: AppTheme.primaryBlue),
              label: 'Analytics',
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
        return _buildPrescriptionsTab();
      case 3:
        return _buildAnalyticsTab();
      default:
        return _buildDashboardTab();
    }
  }

  // ==========================================
  // TAB 1: DENTIST TIMELINE & QUEUE DASHBOARD
  // ==========================================
  Widget _buildDashboardTab() {
    final requests = _patientService.requests;
    final currentDoc = _patientService.currentDoctor;
    final docName = currentDoc?.name ?? 'Dentist Practitioner';
    final docSpecialty = currentDoc?.specialty ?? 'Dental Specialist';
    final clinicName = currentDoc?.clinicName ?? 'Registered Clinic';
    final photoBytes = currentDoc?.photoBytes;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Doctor Profile Greeting Banner
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.brandOrange, width: 2),
                      ),
                      child: photoBytes != null
                          ? CircleAvatar(
                              radius: 24,
                              backgroundImage: MemoryImage(photoBytes),
                            )
                          : const CircleAvatar(
                              radius: 24,
                              backgroundColor: AppTheme.primaryBlue,
                              child: Text('DR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                            ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$docName 🩺',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.brandOrange.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  docSpecialty,
                                  style: const TextStyle(fontSize: 10, color: AppTheme.brandOrange, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '• $clinicName',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_calendar_rounded, color: Colors.white, size: 22),
                      tooltip: 'Update Consultation Fee & Available Slots',
                      onPressed: () => _showUpdateMyFeeAndSlotsDialog(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 2. Animated Practice Stat Boxes Row
              Builder(
                builder: (context) {
                  final currentDoc = _patientService.currentDoctor;
                  final docNameClean = currentDoc?.name.replaceAll('Dr. ', '').trim().toLowerCase() ?? '';

                  final myAssigned = requests.where((req) {
                    if (req.assignedDoctorId != null && currentDoc != null && req.assignedDoctorId == currentDoc.id) return true;
                    if (req.assignedDoctorName != null && docNameClean.isNotEmpty && req.assignedDoctorName!.toLowerCase().contains(docNameClean)) return true;
                    if (currentDoc == null && req.assignedDoctorName != null && req.assignedDoctorName!.isNotEmpty) return true;
                    return false;
                  }).toList();

                  return Row(
                    children: [
                      _buildQuickStatBox(
                        icon: Icons.groups_rounded,
                        count: '${myAssigned.length}',
                        label: "My Assigned Patients",
                        accentColor: AppTheme.primaryBlue,
                      ),
                      const SizedBox(width: 10),
                      _buildQuickStatBox(
                        icon: Icons.receipt_long_rounded,
                        count: '${myAssigned.where((r) => r.status == 'Doctor Suggested').length}',
                        label: 'Pending My Accept',
                        accentColor: const Color(0xFF10B981),
                      ),
                      const SizedBox(width: 10),
                      _buildQuickStatBox(
                        icon: Icons.star_rounded,
                        count: '${currentDoc?.rating ?? 5.0} ⭐',
                        label: 'Satisfaction',
                        accentColor: AppTheme.brandOrange,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),

              // 3. Quick Practitioner Actions Bar
              const Text('Practitioner Tools', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
              const SizedBox(height: 10),

              Row(
                children: [
                  _buildActionChip(
                    icon: Icons.receipt_long_rounded,
                    title: 'New E-Prescription',
                    color: const Color(0xFF10B981),
                    onTap: () => _showPrescriptionModal(context, requests.isNotEmpty ? requests.first.patientName : 'Patient'),
                  ),
                  const SizedBox(width: 10),
                  _buildActionChip(
                    icon: Icons.view_in_ar_rounded,
                    title: '3D Teeth Logger',
                    color: AppTheme.brandOrange,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('🦷 Opening 3D Teeth Mapping Logger...')),
                      );
                    },
                  ),
                  const SizedBox(width: 10),
                  _buildActionChip(
                    icon: Icons.local_hospital_rounded,
                    title: 'Queue Filter',
                    color: AppTheme.primaryBlue,
                    onTap: () {},
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 4. Section: Admin Assigned Patients Stream
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Admin Assigned Patients', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
                  ScaleTransition(
                    scale: _pulseScaleAnimation,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.sensors_rounded, size: 12, color: Color(0xFF10B981)),
                          SizedBox(width: 4),
                          Text('LIVE SYNC', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Builder(
                builder: (context) {
                  final currentDoc = _patientService.currentDoctor;
                  final docNameClean = currentDoc?.name.replaceAll('Dr. ', '').trim().toLowerCase() ?? '';

                  final myAssignedRequests = requests.where((req) {
                    // Strict filtering: Only show requests assigned to this specific doctor
                    if (req.assignedDoctorId != null && currentDoc != null && req.assignedDoctorId == currentDoc.id) {
                      return true;
                    }
                    if (req.assignedDoctorName != null && docNameClean.isNotEmpty && req.assignedDoctorName!.toLowerCase().contains(docNameClean)) {
                      return true;
                    }
                    if (currentDoc == null && req.assignedDoctorName != null && req.assignedDoctorName!.isNotEmpty) {
                      return true;
                    }
                    return false;
                  }).toList();

                  if (myAssignedRequests.isEmpty) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFEEF2F6)),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.person_search_rounded, size: 36, color: Colors.grey),
                          SizedBox(height: 8),
                          Text('No Patient Consultations Assigned Yet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          SizedBox(height: 4),
                          Text(
                            'Only patients assigned to your profile by the Super Admin will appear here for your review.',
                            style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }

                  return Column(
                    children: myAssignedRequests.map((req) {
                      final bool isConfirmed = req.status == 'Confirmed' || req.status == 'Accepted';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: isConfirmed ? const Color(0xFF10B981) : const Color(0xFF0284C7), width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: (isConfirmed ? const Color(0xFF10B981) : const Color(0xFF0284C7)).withValues(alpha: 0.08),
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
                                Expanded(
                                  child: Text(
                                    (req.patientName.contains('-') && req.patientName.length > 20)
                                        ? (_patientService.currentPatient.name.isNotEmpty ? _patientService.currentPatient.name : 'Patient')
                                        : req.patientName,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: req.severity == 'Severe' ? Colors.red.shade100 : Colors.orange.shade100,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${req.severity} Severity',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: req.severity == 'Severe' ? Colors.red.shade900 : Colors.orange.shade900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text('📌 Category: ${req.problemCategory}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
                            const SizedBox(height: 4),
                            Text('Symptoms: "${req.problemDescription}"', style: const TextStyle(fontSize: 12, color: AppTheme.textMedium, height: 1.35)),
                            if (req.adminNotes != null && req.adminNotes!.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text('📝 Admin Note: ${req.adminNotes}', style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: AppTheme.textMuted)),
                            ],
                            const SizedBox(height: 12),

                            if (isConfirmed) ...[
                              if (req.confirmedTimeSlot != null && req.confirmedTimeSlot!.isNotEmpty) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.access_time_filled_rounded, size: 14, color: AppTheme.primaryBlue),
                                      const SizedBox(width: 6),
                                      Text('Confirmed Slot: ${req.confirmedTimeSlot}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.primaryBlue)),
                                    ],
                                  ),
                                ),
                              ],
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      icon: const Icon(Icons.receipt_long_rounded, size: 14),
                                      label: const Text('Issue E-Prescription', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF10B981),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 10),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      onPressed: () => _showPrescriptionModal(context, req.patientName),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0xFF10B981)),
                                    ),
                                    child: const Row(
                                      children: [
                                        Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF10B981)),
                                        SizedBox(width: 4),
                                        Text('Accepted', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF10B981))),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ] else
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      icon: const Icon(Icons.close_rounded, size: 14, color: Color(0xFFEF4444)),
                                      label: const Text('Decline Referral', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFFEF4444))),
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(color: Color(0xFFEF4444)),
                                        padding: const EdgeInsets.symmetric(vertical: 10),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      onPressed: () {
                                        _patientService.declineReferralByDentist(req.id);
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('⚠️ Declined referral for ${req.patientName}. Returned to Admin pool.'),
                                            backgroundColor: const Color(0xFFEF4444),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      icon: const Icon(Icons.event_available_rounded, size: 14),
                                      label: const Text('Accept & Set Slot', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF10B981),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 10),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      onPressed: () => _showAcceptAndScheduleModal(context, req),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 20),

              // 5. Daily Consultation Timeline Queue
              const Text("Today's Patient Schedule", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
              const SizedBox(height: 12),

              Builder(
                builder: (context) {
                  final currentDoc = _patientService.currentDoctor;
                  final docNameClean = currentDoc?.name.replaceAll('Dr. ', '').trim().toLowerCase() ?? '';

                  final acceptedForMe = requests.where((req) {
                    final bool isMine = (req.assignedDoctorId != null && currentDoc != null && req.assignedDoctorId == currentDoc.id) ||
                        (req.assignedDoctorName != null && docNameClean.isNotEmpty && req.assignedDoctorName!.toLowerCase().contains(docNameClean)) ||
                        (currentDoc == null && req.assignedDoctorName != null && req.assignedDoctorName!.isNotEmpty);
                    return isMine && (req.status == 'Confirmed' || req.status == 'Accepted');
                  }).toList();

                  if (acceptedForMe.isEmpty) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFEEF2F6)),
                      ),
                      child: const Center(
                        child: Text('No accepted appointments scheduled in queue for today.', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                      ),
                    );
                  }

                  return Column(
                    children: acceptedForMe.map((req) {
                      return _buildTimelineNode(
                        time: req.confirmedTimeSlot ?? 'Today, 2:30 PM',
                        name: req.patientName,
                        procedure: req.problemCategory,
                        status: 'Accepted',
                        statusColor: const Color(0xFF10B981),
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickStatBox({
    required IconData icon,
    required String count,
    required String label,
    required Color accentColor,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
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
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accentColor, size: 18),
            ),
            const SizedBox(height: 10),
            Text(
              count,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: accentColor),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: AppTheme.textMuted, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionChip({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textDark),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimelineNode({
    required String time,
    required String name,
    required String procedure,
    required String status,
    required Color statusColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              time,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: statusColor),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (name.contains('-') && name.length > 20)
                      ? (_patientService.currentPatient.name.isNotEmpty ? _patientService.currentPatient.name : 'Patient')
                      : name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(procedure, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor)),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 2: PATIENTS TAB
  // ==========================================
  Widget _buildPatientsTab() {
    final requests = _patientService.requests;
    final patient = _patientService.currentPatient;
    final currentDoc = _patientService.currentDoctor;
    final docNameClean = currentDoc?.name.replaceAll('Dr. ', '').trim().toLowerCase() ?? '';

    final myPatients = requests.where((req) {
      if (req.assignedDoctorId != null && currentDoc != null && req.assignedDoctorId == currentDoc.id) return true;
      if (req.assignedDoctorName != null && docNameClean.isNotEmpty && req.assignedDoctorName!.toLowerCase().contains(docNameClean)) return true;
      return false;
    }).toList();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Patient Medical Directory', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
          const SizedBox(height: 4),
          const Text('Access patient electronic dental records & X-rays', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          const SizedBox(height: 16),
          if (myPatients.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Center(
                child: Text('No patient records assigned to your profile.', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
              ),
            )
          else
            ...myPatients.map((req) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildPatientListTile(
                  name: req.patientName,
                  age: '${patient.age.isNotEmpty ? patient.age : '28'} Yrs',
                  blood: patient.bloodGroup.isNotEmpty ? patient.bloodGroup : 'O+',
                  issue: req.problemCategory,
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildPatientListTile({required String name, required String age, required String blood, required String issue}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 20,
            backgroundColor: AppTheme.softBlueBg,
            child: Icon(Icons.person_outline_rounded, color: AppTheme.primaryBlue, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark)),
                const SizedBox(height: 2),
                Text('$age • Blood: $blood • $issue', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppTheme.textMuted),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 3: PRESCRIPTIONS TAB
  // ==========================================
  Widget _buildPrescriptionsTab() {
    return FutureBuilder<List<dynamic>>(
      future: ApiService().fetchMedicalRecords(),
      builder: (context, snapshot) {
        final records = (snapshot.data ?? []).where((r) => r['type'] == 'prescription').toList();

        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('E-Prescription Records', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
              const SizedBox(height: 4),
              const Text('Issued digital medication slips', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              const SizedBox(height: 16),
              if (records.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Center(
                    child: Text('No digital e-prescriptions issued yet.', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                  ),
                )
              else
                ...records.map((rec) {
                  final List items = rec['items'] is List ? rec['items'] : [];
                  final medStr = items.map((i) => i['name'] ?? '').join(', ');
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
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
                            Text(rec['doctorName'] ?? 'Attending Doctor', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark)),
                            Text(rec['date'] ?? '', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text('💊 ${medStr.isNotEmpty ? medStr : 'Active Medication'}', style: const TextStyle(fontSize: 12, color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                      ],
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  // ==========================================
  // TAB 4: ANALYTICS TAB
  // ==========================================
  Widget _buildAnalyticsTab() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Practice Analytics', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
          const SizedBox(height: 4),
          const Text('Monthly consultations and procedure statistics', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        Text('148', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
                        Text('Monthly Consults', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                      ],
                    ),
                    Column(
                      children: [
                        Text('98.4%', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                        Text('Positive Feedback', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
