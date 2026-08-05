import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/denta_guru_logo.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/services/api_service.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> with TickerProviderStateMixin {
  int _selectedNavIndex = 0; // 0: Dashboard, 1: Clinics, 2: Dentists, 3: Patients, 4: Appointments, 5: Revenue, 6: Reports, 7: Reviews, 8: Settings
  final PatientProblemService _problemService = PatientProblemService();

  late AnimationController _entryController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _pulseScaleAnimation;

  @override
  void initState() {
    super.initState();
    _problemService.addListener(_onServiceUpdate);

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
    _problemService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  void _showAssignDoctorDialog(BuildContext context, PatientConsultationRequest req, {DoctorModel? preSelectedDoctor}) {
    int currentStep = 1; // 1: Patient Problem, 2: Select Doctor, 3: Review & Send
    DoctorModel? selectedDoctor = preSelectedDoctor ?? (_problemService.allDoctors.isNotEmpty ? _problemService.allDoctors.first : null);
    String searchKeyword = '';
    String selectedSpecialtyFilter = 'All';
    final adminNotesController = TextEditingController(
      text: 'Recommended for specialized clinical evaluation and care.',
    );

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            // Filter doctors based on search & specialty
            final filteredDoctors = _problemService.allDoctors.where((doc) {
              final matchesSearch = doc.name.toLowerCase().contains(searchKeyword.toLowerCase()) ||
                  doc.specialty.toLowerCase().contains(searchKeyword.toLowerCase()) ||
                  doc.clinicName.toLowerCase().contains(searchKeyword.toLowerCase());
              final matchesSpecialty = selectedSpecialtyFilter == 'All' ||
                  doc.specialty.toLowerCase().contains(selectedSpecialtyFilter.toLowerCase());
              return matchesSearch && matchesSpecialty;
            }).toList();

            if (selectedDoctor == null && filteredDoctors.isNotEmpty) {
              selectedDoctor = filteredDoctors.first;
            }

            final clinicAddr = (selectedDoctor?.clinicAddress != null && selectedDoctor!.clinicAddress.trim().isNotEmpty)
                ? selectedDoctor!.clinicAddress.trim()
                : '123 Healthcare Blvd, Medical Hub, Suite 400';
            final doctorPhone = selectedDoctor?.phone ?? '+1 202 555 0100';
            final caseFee = selectedDoctor?.getFeeForCategory(req.problemCategory) ?? '\$75';
            final waText = "🏥 *DentaGuru Clinical Recommendation*\n\n"
                "Dear *${req.patientName}*,\n"
                "Our Clinical Admin team has evaluated your reported problem:\n"
                "📌 *Issue*: ${req.problemCategory} (${req.severity} Severity)\n\n"
                "👨‍⚕️ *Recommended Doctor*: *${selectedDoctor?.name}*\n"
                "🎓 *Specialty*: ${selectedDoctor?.specialty}\n"
                "💰 *Estimated Fee (${req.problemCategory})*: $caseFee\n"
                "🏥 *Clinic*: ${selectedDoctor?.clinicName}\n"
                "📍 *Clinic Address*: $clinicAddr\n"
                "📞 *Contact Phone*: $doctorPhone\n"
                "💡 *Admin Guidance*: ${adminNotesController.text}";

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              backgroundColor: Colors.white,
              elevation: 20,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 580, maxHeight: 680),
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Modal Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.person_add_alt_1_rounded, color: AppTheme.primaryBlue, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Doctor Assignment Wizard • ${req.patientName}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                              Text(
                                'Ticket ${req.id} • ${req.problemCategory}',
                                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
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
                    const SizedBox(height: 14),

                    // RESPONSIVE STEP INDICATOR PIPELINE (GUARANTEED SINGLE LINE & NO OVERFLOW)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: LayoutBuilder(
                        builder: (context, stepConstraints) {
                          final isSmallScreen = stepConstraints.maxWidth < 420;

                          return Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: _buildStepBadge(1, isSmallScreen ? 'Patient' : 'Patient Problem', currentStep == 1, currentStep > 1),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 2),
                                child: Icon(Icons.chevron_right_rounded, size: 14, color: Color(0xFF94A3B8)),
                              ),
                              Expanded(
                                flex: 3,
                                child: _buildStepBadge(2, isSmallScreen ? 'Doctor' : 'Select Doctor', currentStep == 2, currentStep > 2),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 2),
                                child: Icon(Icons.chevron_right_rounded, size: 14, color: Color(0xFF94A3B8)),
                              ),
                              Expanded(
                                flex: 3,
                                child: _buildStepBadge(3, 'Dispatch', currentStep == 3, false),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),

                    // STEP 1: PATIENT PROBLEM DETAILS
                    if (currentStep == 1)
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
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
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '👤 Patient: ${req.patientName}',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: req.severity == 'Severe' ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            'Severity: ${req.severity}',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: req.severity == 'Severe' ? const Color(0xFF991B1B) : const Color(0xFF92400E),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 4,
                                      children: [
                                        Text('📞 Contact: ${req.patientPhone}', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                                        Text('📌 Category: ${req.problemCategory}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryBlue)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),

                              const Text('Patient Reported Symptoms & Notes:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textDark)),
                              const SizedBox(height: 6),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFCBD5E1)),
                                ),
                                child: Text(
                                  req.problemDescription,
                                  style: const TextStyle(fontSize: 12, color: AppTheme.textMedium, height: 1.4),
                                ),
                              ),
                              const SizedBox(height: 16),

                              ElevatedButton.icon(
                                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                                label: const Text(
                                  'Step 2: Choose Doctor from Master List',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primaryBlue,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size.fromHeight(46),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: () => setModalState(() => currentStep = 2),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // STEP 2: SELECT DOCTOR FROM ALL DOCTORS DIRECTORY
                    if (currentStep == 2)
                      Expanded(
                        child: Column(
                          children: [
                            // Search bar
                            TextField(
                              onChanged: (val) => setModalState(() => searchKeyword = val),
                              decoration: InputDecoration(
                                hintText: 'Search doctor by name, specialty or clinic...',
                                prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppTheme.textMuted),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                              ),
                            ),
                            const SizedBox(height: 10),

                            // Specialty Filters
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: ['All', 'Orthodontics', 'Endodontics', 'General', 'Surgery', 'Periodontics'].map((spec) {
                                  final isSel = selectedSpecialtyFilter == spec;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: ChoiceChip(
                                      label: Text(spec, style: TextStyle(fontSize: 11, fontWeight: isSel ? FontWeight.bold : FontWeight.normal)),
                                      selected: isSel,
                                      selectedColor: AppTheme.primaryBlue.withValues(alpha: 0.15),
                                      labelStyle: TextStyle(color: isSel ? AppTheme.primaryBlue : AppTheme.textDark),
                                      onSelected: (val) {
                                        if (val) setModalState(() => selectedSpecialtyFilter = spec);
                                      },
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                            const SizedBox(height: 10),

                            // Doctors List
                            Expanded(
                              child: filteredDoctors.isEmpty
                                  ? Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const Icon(Icons.person_search_rounded, size: 40, color: AppTheme.textMuted),
                                            const SizedBox(height: 8),
                                            const Text(
                                              'No Doctors Found',
                                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                                            ),
                                            const SizedBox(height: 4),
                                            const Text(
                                              'No doctor matches your filter or search criteria.',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                            ),
                                            const SizedBox(height: 12),
                                            ElevatedButton.icon(
                                              onPressed: () {
                                                Navigator.of(dialogContext).pop();
                                                _showRegisterDoctorModal(context);
                                              },
                                              icon: const Icon(Icons.person_add_rounded, size: 16),
                                              label: const Text('Register Doctor Now', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: AppTheme.primaryBlue,
                                                foregroundColor: Colors.white,
                                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                  : ListView.builder(
                                      itemCount: filteredDoctors.length,
                                      itemBuilder: (context, idx) {
                                        final doc = filteredDoctors[idx];
                                        final isSelected = selectedDoctor?.id == doc.id;
                                        final isSpecialtyMatch = req.problemCategory.toLowerCase().contains(doc.specialty.toLowerCase().split(' ').first);

                                        return GestureDetector(
                                          onTap: () => setModalState(() => selectedDoctor = doc),
                                          child: Container(
                                            margin: const EdgeInsets.only(bottom: 10),
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
                                              borderRadius: BorderRadius.circular(14),
                                              border: Border.all(
                                                color: isSelected ? AppTheme.primaryBlue : const Color(0xFFE2E8F0),
                                                width: isSelected ? 2 : 1,
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                Radio<String>(
                                                  value: doc.id,
                                                  groupValue: selectedDoctor?.id,
                                                  activeColor: AppTheme.primaryBlue,
                                                  onChanged: (val) => setModalState(() => selectedDoctor = doc),
                                                ),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          Expanded(
                                                            child: Text(
                                                              doc.name,
                                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                                                              overflow: TextOverflow.ellipsis,
                                                              maxLines: 1,
                                                            ),
                                                          ),
                                                          if (isSpecialtyMatch) ...[
                                                            const SizedBox(width: 4),
                                                            Container(
                                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                              decoration: BoxDecoration(
                                                                color: const Color(0xFFDCFCE7),
                                                                borderRadius: BorderRadius.circular(6),
                                                              ),
                                                              child: const Text('Matched Specialty', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF16A34A))),
                                                            ),
                                                          ],
                                                        ],
                                                      ),
                                                      Text(
                                                        '${doc.specialty} • ${doc.qualification}',
                                                        style: const TextStyle(fontSize: 11, color: AppTheme.primaryBlue),
                                                        overflow: TextOverflow.ellipsis,
                                                        maxLines: 1,
                                                      ),
                                                      Text(
                                                        '🏥 ${doc.clinicName} • 💰 ${doc.getFeeForCategory(req.problemCategory)} (${req.problemCategory}) • ⭐ ${doc.rating}',
                                                        style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                                                        overflow: TextOverflow.ellipsis,
                                                        maxLines: 1,
                                                      ),
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

                            Row(
                              children: [
                                OutlinedButton(
                                  onPressed: () => setModalState(() => currentStep = 1),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: const Text('Back'),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                                    label: const Text(
                                      'Step 3: Review & Dispatch',
                                      style: TextStyle(fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.primaryBlue,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    onPressed: () {
                                      if (selectedDoctor == null) {
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a doctor.')));
                                        return;
                                      }
                                      setModalState(() => currentStep = 3);
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                    // STEP 3: CONFIRMATION & DISPATCH
                    if (currentStep == 3)
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Doctor summary card
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppTheme.primaryBlue.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  children: [
                                    const CircleAvatar(
                                      backgroundColor: AppTheme.primaryBlue,
                                      child: Icon(Icons.medical_services_rounded, color: Colors.white, size: 20),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            selectedDoctor?.name ?? '',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                          Text(
                                            '${selectedDoctor?.specialty}',
                                            style: const TextStyle(fontSize: 11, color: AppTheme.primaryBlue),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                          Text(
                                            '🏥 ${selectedDoctor?.clinicName} • 📍 ${selectedDoctor?.clinicAddress} • 📞 ${selectedDoctor?.phone}',
                                            style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),

                              const Text('Admin Clinical Guidance / Recommendation Note:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textDark)),
                              const SizedBox(height: 6),
                              TextField(
                                controller: adminNotesController,
                                maxLines: 2,
                                onChanged: (val) => setModalState(() {}),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: const Color(0xFFF8FAFC),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  contentPadding: const EdgeInsets.all(12),
                                ),
                              ),
                              const SizedBox(height: 14),

                              // WhatsApp Preview Card
                              Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDCFCE7).withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: const Color(0xFF86EFAC)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF15803D),
                                        borderRadius: BorderRadius.only(
                                          topLeft: Radius.circular(13),
                                          topRight: Radius.circular(13),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 15),
                                          const SizedBox(width: 8),
                                          const Expanded(
                                            child: Text(
                                              'WhatsApp Message Preview',
                                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                                            ),
                                          ),
                                          InkWell(
                                            onTap: () {
                                              Clipboard.setData(ClipboardData(text: waText));
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Message preview copied to clipboard!'), duration: Duration(seconds: 2)),
                                              );
                                            },
                                            child: const Row(
                                              children: [
                                                Icon(Icons.copy_rounded, color: Colors.white, size: 12),
                                                SizedBox(width: 4),
                                                Text('Copy', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Text(
                                        waText,
                                        style: const TextStyle(fontSize: 11, color: Color(0xFF14532D), height: 1.4, fontFamily: 'monospace'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),

                              Row(
                                children: [
                                  OutlinedButton(
                                    onPressed: () => setModalState(() => currentStep = 2),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    child: const Text('Back'),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      icon: const Icon(Icons.send_rounded, size: 16),
                                      label: const Text(
                                        'Send Doctor Recommendation',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF10B981),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 13),
                                        elevation: 2,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      onPressed: () async {
                                        if (selectedDoctor == null) return;
                                        _problemService.assignDoctorToRequest(
                                          requestId: req.id,
                                          doctor: selectedDoctor!,
                                          adminNotes: adminNotesController.text.trim(),
                                        );

                                        final cleanPhone = req.patientPhone.replaceAll(RegExp(r'[^0-9]'), '');
                                        final waUrl = Uri.parse(cleanPhone.isNotEmpty
                                            ? "https://wa.me/$cleanPhone?text=${Uri.encodeComponent(waText)}"
                                            : "https://wa.me/?text=${Uri.encodeComponent(waText)}");
                                        try {
                                          await launchUrl(waUrl, mode: LaunchMode.externalApplication);
                                        } catch (e) {
                                          debugPrint('WhatsApp launcher info: $e');
                                        }

                                        if (!context.mounted) return;
                                        Navigator.of(dialogContext).pop();
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('📱 Doctor recommendation sent to ${req.patientName} & ${selectedDoctor?.name}!'),
                                            backgroundColor: const Color(0xFF10B981),
                                            duration: const Duration(seconds: 3),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
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

  Widget _buildStepBadge(int stepNum, String title, bool isActive, bool isDone) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: isActive
            ? AppTheme.primaryBlue.withValues(alpha: 0.1)
            : (isDone ? const Color(0xFFDCFCE7) : Colors.transparent),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: isDone
                  ? const Color(0xFF10B981)
                  : isActive
                      ? AppTheme.primaryBlue
                      : const Color(0xFFCBD5E1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: isDone
                  ? const Icon(Icons.check_rounded, color: Colors.white, size: 12)
                  : Text('$stepNum', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive || isDone ? FontWeight.bold : FontWeight.w500,
                color: isActive ? AppTheme.primaryBlue : (isDone ? const Color(0xFF15803D) : AppTheme.textMuted),
              ),
            ),
          ),
        ],
      ),
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
                                ScaleTransition(
                                  scale: _pulseScaleAnimation,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFDCFCE7),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text('Admin Mode', style: TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.bold, fontSize: 11)),
                                  ),
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
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        child: _buildSelectedPanel(),
                      ),
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
      case 2:
        return _buildDentistsPanel();
      case 3:
        return _buildPatientsPanel();
      case 5:
        return _buildRevenuePanel();
      default:
        return _buildDashboardPanel();
    }
  }

  void _showRegisterDoctorModal(BuildContext context) {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final licenseCtrl = TextEditingController();
    final clinicCtrl = TextEditingController();
    final expCtrl = TextEditingController(text: '5');
    final feeCtrl = TextEditingController(text: '\$75');
    String selectedSpecialty = 'General Dentistry';

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 480, maxHeight: 660),
                padding: const EdgeInsets.all(22),
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
                              color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.person_add_alt_1_rounded, color: AppTheme.primaryBlue, size: 22),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Register New Doctor', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textDark)),
                                Text('Admin Doctor Onboarding • DentaGuru Platform', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
                            onPressed: () => Navigator.of(dialogContext).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      TextField(
                        controller: nameCtrl,
                        decoration: InputDecoration(
                          labelText: 'Doctor Full Name',
                          hintText: 'e.g. Dr. Jane Miller',
                          prefixIcon: const Icon(Icons.person_outline, size: 18),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 10),

                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: emailCtrl,
                              decoration: InputDecoration(
                                labelText: 'Email Address',
                                hintText: 'e.g. jane@dentaguru.com',
                                prefixIcon: const Icon(Icons.email_outlined, size: 18),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: phoneCtrl,
                              decoration: InputDecoration(
                                labelText: 'Phone Number',
                                hintText: 'e.g. +1 202 555 0199',
                                prefixIcon: const Icon(Icons.phone_outlined, size: 18),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      DropdownButtonFormField<String>(
                        initialValue: selectedSpecialty,
                        decoration: InputDecoration(
                          labelText: 'Specialization',
                          prefixIcon: const Icon(Icons.medical_services_outlined, size: 18),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        items: [
                          'General Dentistry',
                          'Orthodontics',
                          'Endodontics',
                          'Periodontics',
                          'Pediatric Dentistry',
                          'Oral & Maxillofacial Surgery',
                          'Cosmetic Dentistry',
                        ].map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 13)))).toList(),
                        onChanged: (val) {
                          if (val != null) setModalState(() => selectedSpecialty = val);
                        },
                      ),
                      const SizedBox(height: 10),

                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: licenseCtrl,
                              decoration: InputDecoration(
                                labelText: 'License Number',
                                hintText: 'e.g. DEN-88490',
                                prefixIcon: const Icon(Icons.badge_outlined, size: 18),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: expCtrl,
                              decoration: InputDecoration(
                                labelText: 'Years Exp.',
                                hintText: '5',
                                prefixIcon: const Icon(Icons.work_history_outlined, size: 18),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: clinicCtrl,
                              decoration: InputDecoration(
                                labelText: 'Practice / Clinic Name',
                                hintText: 'e.g. Apex Care Dental',
                                prefixIcon: const Icon(Icons.location_city_outlined, size: 18),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: feeCtrl,
                              decoration: InputDecoration(
                                labelText: 'Fee',
                                hintText: '\$75',
                                prefixIcon: const Icon(Icons.payments_outlined, size: 18),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      ElevatedButton.icon(
                        icon: const Icon(Icons.check_circle_rounded, size: 18),
                        label: const Text('Register Doctor to Admin Panel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          final expYears = int.tryParse(expCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 5;
                          final doctor = _problemService.registerDoctor(
                            name: nameCtrl.text,
                            email: emailCtrl.text,
                            phone: phoneCtrl.text,
                            licenseNumber: licenseCtrl.text,
                            specialty: selectedSpecialty,
                            clinicName: clinicCtrl.text,
                            experienceYears: expYears,
                            consultationFee: feeCtrl.text,
                          );

                          Navigator.of(dialogContext).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('👨‍⚕️ Registered ${doctor.name} successfully! Visible in Admin Directory.'),
                              backgroundColor: const Color(0xFF10B981),
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

  // ==========================================
  // PANEL 2: MASTER DENTISTS DIRECTORY (ALL DOCTORS)
  // ==========================================
  Widget _buildDentistsPanel() {
    final doctors = _problemService.allDoctors;
    final requests = _problemService.requests;
    final PatientConsultationRequest? pendingRequest = requests.where((r) => r.status == 'Pending Admin Review').firstOrNull ?? requests.firstOrNull;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Card
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
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.medical_services_rounded, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '👨‍⚕️ Master Dentists Directory & Specialist Assignment',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'All verified dental specialists registered on DentaGuru • Match patient problems directly',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Statistics Header
          Row(
            children: [
              _buildMiniStatCard('Total Dentists', '${doctors.length}', Icons.badge_rounded, AppTheme.primaryBlue),
              const SizedBox(width: 12),
              _buildMiniStatCard('Available Now', '${doctors.where((d) => d.status == 'Available').length}', Icons.check_circle_rounded, const Color(0xFF10B981)),
              const SizedBox(width: 12),
              _buildMiniStatCard('Avg Rating', '4.85 ⭐', Icons.star_rounded, const Color(0xFFF59E0B)),
            ],
          ),
          const SizedBox(height: 20),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'All Registered Doctors & Specialists',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.person_add_rounded, size: 16),
                label: const Text('Register Doctor', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _showRegisterDoctorModal(context),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Grid of Doctors
          LayoutBuilder(
            builder: (context, constraints) {
              final crossCount = constraints.maxWidth > 750 ? 2 : 1;

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: doctors.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossCount,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  mainAxisExtent: 260,
                ),
                itemBuilder: (context, index) {
                  final doc = doctors[index];
                  final isAvailable = doc.status == 'Available';

                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
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
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.12),
                              child: Text(
                                doc.name.replaceAll('Dr.', '').trim().split(' ').last[0],
                                style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue, fontSize: 16),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    doc.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    doc.specialty,
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryBlue),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '${doc.qualification} • ${doc.experienceYears} yrs exp',
                                    style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isAvailable ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                doc.status,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isAvailable ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 16, color: Color(0xFFF1F5F9)),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('🏥 ${doc.clinicName}', style: const TextStyle(fontSize: 11, color: AppTheme.textMedium, fontWeight: FontWeight.w500)),
                            Text('Fee: ${doc.consultationFee}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Lic: ${doc.licenseNumber}',
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF59E0B)),
                            const SizedBox(width: 3),
                            Text('${doc.rating}', style: const TextStyle(fontSize: 11, color: AppTheme.textDark, fontWeight: FontWeight.w600)),
                            const Spacer(),
                            Text('Slots: ${doc.nextAvailableSlots.first}', style: const TextStyle(fontSize: 10, color: Color(0xFF10B981), fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '📞 ${doc.phone} • ✉️ ${doc.email}',
                          style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Spacer(),

                        ElevatedButton.icon(
                          icon: const Icon(Icons.recommend_rounded, size: 14),
                          label: const Text('Suggest Doctor to Patient Problem', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryBlue,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(38),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: pendingRequest != null
                              ? () => _showAssignDoctorDialog(context, pendingRequest, preSelectedDoctor: doc)
                              : null,
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStatCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 10, color: AppTheme.textMuted), overflow: TextOverflow.ellipsis),
                  Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textDark), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // PANEL 1: ADMIN DASHBOARD (RESPONSIVE & OVERFLOW FREE)
  // ==========================================
  Widget _buildDashboardPanel() {
    final requests = _problemService.requests;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: SingleChildScrollView(
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
                  _KpiCard(
                    title: 'Total Active Patients',
                    value: '${requests.map((r) => r.patientName).toSet().length}',
                    growth: requests.isNotEmpty ? '+100% active' : 'Live Sync',
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
                  _KpiCard(
                    title: 'Assigned Specialists',
                    value: '${_problemService.allDoctors.length}',
                    growth: 'Verified Doctors',
                    accentColor: const Color(0xFF10B981),
                    icon: Icons.account_balance_wallet_rounded,
                  ),
                  _KpiCard(
                    title: 'Partner Clinics',
                    value: '${_problemService.allDoctors.map((d) => d.clinicName).toSet().length}',
                    growth: 'Network Clinics',
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
                                            '📞 Phone: ${(req.patientPhone.isNotEmpty && req.patientPhone != '+1 202 555 0142' && req.patientPhone != 'Not Provided') ? req.patientPhone : (_problemService.currentPatient.phone.isNotEmpty ? _problemService.currentPatient.phone : '9063663180')}',
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
                                        req.severity,
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
    ),
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

  final List<Map<String, String>> _adminPatientsList = [];

  void _showAddPatientDialog() {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final ageCtrl = TextEditingController(text: '28');
    final passwordCtrl = TextEditingController(text: 'Password123!');

    showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.person_add_rounded, color: AppTheme.primaryBlue, size: 22),
                    ),
                    const SizedBox(width: 10),
                    const Text('Register New Patient', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: AppTheme.textDark)),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Patient Full Name', prefixIcon: Icon(Icons.person_outline_rounded)),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email Address', prefixIcon: Icon(Icons.email_outlined)),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: phoneCtrl,
                        decoration: const InputDecoration(labelText: 'Phone Number', prefixIcon: Icon(Icons.phone_outlined)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: ageCtrl,
                        decoration: const InputDecoration(labelText: 'Age', prefixIcon: Icon(Icons.cake_outlined)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: passwordCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Set Account Password', prefixIcon: Icon(Icons.lock_outline)),
                ),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                  label: const Text('Register & Save Patient in Supabase', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    final name = nameCtrl.text.trim().isEmpty ? 'New Patient' : nameCtrl.text.trim();
                    final email = emailCtrl.text.trim().isEmpty ? 'patient_${DateTime.now().millisecondsSinceEpoch}@dentaguru.com' : emailCtrl.text.trim();
                    final phone = phoneCtrl.text.trim().isEmpty ? '+12025550000' : phoneCtrl.text.trim();
                    final age = ageCtrl.text.trim().isEmpty ? '28' : ageCtrl.text.trim();
                    final pass = passwordCtrl.text.trim().isEmpty ? 'Password123!' : passwordCtrl.text.trim();

                    final res = await ApiService().registerUser(
                      name: name,
                      email: email,
                      password: pass,
                      phone: phone,
                      role: 'Patient',
                    );

                    setState(() {
                      _adminPatientsList.insert(0, {
                        'name': name,
                        'age': age,
                        'phone': phone,
                        'email': email,
                        'lastVisit': 'Just now',
                        'status': 'Active',
                      });
                    });

                    _problemService.updatePatientProfile(
                      name: name,
                      email: email,
                      phone: phone,
                      age: age,
                      gender: 'Female',
                      bloodGroup: 'O Positive (O+)',
                      emergencyContact: phone,
                    );

                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(res['success'] == true
                              ? '🎉 Registered $name in Supabase Database!'
                              : '🎉 Patient $name registered!'),
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
  }

  // ==========================================
  // PANEL 2: PATIENTS MANAGEMENT DATA TABLE
  // ==========================================
  Widget _buildPatientsPanel() {
    final patientEntries = List<Map<String, String>>.from(_adminPatientsList);
    
    // Check logged in patient
    if (_problemService.currentPatient.name.isNotEmpty &&
        !patientEntries.any((p) => p['email'] == _problemService.currentPatient.email)) {
      patientEntries.add({
        'name': _problemService.currentPatient.name,
        'age': _problemService.currentPatient.age,
        'phone': _problemService.currentPatient.phone,
        'email': _problemService.currentPatient.email,
        'lastVisit': 'Today',
        'status': 'Active',
      });
    }

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
                onPressed: _showAddPatientDialog,
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

          if (patientEntries.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.people_outline_rounded, size: 42, color: AppTheme.textMuted),
                  const SizedBox(height: 10),
                  const Text('No Registered Patients Found', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark)),
                  const SizedBox(height: 4),
                  const Text('Click "+ Add Patient" above to register a patient directly into Supabase database.',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                ],
              ),
            )
          else
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
                  rows: patientEntries.map((patient) {
                    final String name = patient['name'] ?? 'Patient';
                    final String age = patient['age'] ?? '28';
                    final String phone = patient['phone'] ?? '--';
                    final String lastVisit = patient['lastVisit'] ?? 'Today';
                    final String status = patient['status'] ?? 'Active';
                    return _buildDataRow(name, age, phone, lastVisit, status, const Color(0xFFDCFCE7), const Color(0xFF16A34A));
                  }).toList(),
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
