import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/patient_problem_service.dart';

class BookVisitFlowDialog extends StatefulWidget {
  final DoctorModel? preselectedDoctor;
  final VoidCallback? onBookingSuccess;

  const BookVisitFlowDialog({
    super.key,
    this.preselectedDoctor,
    this.onBookingSuccess,
  });

  static Future<void> show(
    BuildContext context, {
    DoctorModel? preselectedDoctor,
    VoidCallback? onBookingSuccess,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => BookVisitFlowDialog(
        preselectedDoctor: preselectedDoctor,
        onBookingSuccess: onBookingSuccess,
      ),
    );
  }

  @override
  State<BookVisitFlowDialog> createState() => _BookVisitFlowDialogState();
}

class _BookVisitFlowDialogState extends State<BookVisitFlowDialog> {
  final PatientProblemService _patientService = PatientProblemService();

  // Step state: 1: Select Doctor, 2: Date & Slot, 3: Reason, 4: Review, 5: Success
  int _currentStep = 1;

  // Step 1: Doctor Selection
  DoctorModel? _selectedDoctor;
  String _doctorSearchQuery = '';
  String _selectedSpecialtyFilter = 'All';

  // Step 2: Date & Slot
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  String? _selectedTimeSlot;

  // Step 3: Reason & Symptoms
  String _selectedCategory = 'Routine Dental Checkup';
  final TextEditingController _symptomsController = TextEditingController();
  String _selectedSeverity = 'Mild';

  // Step 4 & 5: Submission & Status
  bool _isSubmitting = false;
  String? _errorMessage;

  static const List<String> _specialtyFilters = [
    'All',
    'General Dentistry',
    'Orthodontics',
    'Periodontics',
    'Endodontics',
    'Prosthodontics',
    'Oral & Maxillofacial Surgery',
    'Pediatric Dentistry',
  ];

  static const List<String> _categories = [
    'Routine Dental Checkup',
    'Toothache & Cold Sensitivity',
    'Teeth Cleaning & Whitening',
    'Bleeding Gums & Swelling',
    'Cavity & Dental Filling',
    'Wisdom Tooth Pain',
    'Aligners & Braces Adjustment',
    'Root Canal Treatment',
    'Dental Implants Consultation',
    'Other Dental Problem',
  ];

  static const List<String> _timeSlots = [
    '09:30 AM',
    '10:30 AM',
    '11:30 AM',
    '02:00 PM',
    '03:00 PM',
    '04:00 PM',
    '05:00 PM',
    '06:00 PM',
    '07:00 PM',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.preselectedDoctor != null) {
      _selectedDoctor = widget.preselectedDoctor;
      _currentStep = 2; // Jump directly to Date & Slot if doctor preselected
    }
    // Refresh live doctors in background
    _patientService.syncDoctorsFromApi();
  }

  @override
  void dispose() {
    _symptomsController.dispose();
    super.dispose();
  }

  // Helper to check if a specific time slot is already booked for this doctor
  bool _isSlotBooked(String slot) {
    if (_selectedDoctor == null) return false;
    final docId = _selectedDoctor!.id.isNotEmpty ? _selectedDoctor!.id : _selectedDoctor!.userId;
    final dateStr = _selectedDate.toIso8601String().split('T').first;

    for (final req in _patientService.requests) {
      final s = req.status.toUpperCase();
      if (s == 'CANCELLED' || s == 'REJECTED') continue;
      final reqDocId = req.assignedDoctorId ?? '';
      final reqDate = req.confirmedDate?.split('T').first ?? '';
      final reqSlot = (req.confirmedTimeSlot ?? '').trim();

      if ((reqDocId == docId || req.assignedDoctorName == _selectedDoctor!.name) &&
          reqDate == dateStr &&
          reqSlot.toLowerCase() == slot.toLowerCase()) {
        return true;
      }
    }
    return false;
  }

  String _formatDate(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${weekdays[dt.weekday - 1]}, ${dt.day.toString().padLeft(2, '0')} ${months[dt.month - 1]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        child: Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            leading: _currentStep > 1 && _currentStep < 5
                ? IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textDark),
                    onPressed: () {
                      setState(() {
                        if (_currentStep == 2 && widget.preselectedDoctor != null) {
                          Navigator.of(context).pop();
                        } else {
                          _currentStep--;
                          _errorMessage = null;
                        }
                      });
                    },
                  )
                : null,
            title: Text(
              _currentStep == 5
                  ? 'Booking Confirmed'
                  : 'Book Dental Visit ($_currentStep/4)',
              style: const TextStyle(
                color: AppTheme.textDark,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(4),
              child: LinearProgressIndicator(
                value: _currentStep / 5.0,
                backgroundColor: const Color(0xFFF1F5F9),
                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryBlue),
                minHeight: 3,
              ),
            ),
          ),
          body: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _buildCurrentStepView(),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStepView() {
    switch (_currentStep) {
      case 1:
        return _buildStep1SelectDoctor();
      case 2:
        return _buildStep2SelectDateAndSlot();
      case 3:
        return _buildStep3ReasonAndSymptoms();
      case 4:
        return _buildStep4ReviewAndConfirm();
      case 5:
        return _buildStep5Success();
      default:
        return const SizedBox.shrink();
    }
  }

  // ==========================================
  // STEP 1: SELECT DOCTOR
  // ==========================================
  Widget _buildStep1SelectDoctor() {
    final allDoctors = _patientService.allDoctors;
    final filteredDoctors = allDoctors.where((doc) {
      final matchesQuery = _doctorSearchQuery.isEmpty ||
          doc.name.toLowerCase().contains(_doctorSearchQuery.toLowerCase()) ||
          doc.specialty.toLowerCase().contains(_doctorSearchQuery.toLowerCase()) ||
          doc.clinicName.toLowerCase().contains(_doctorSearchQuery.toLowerCase());
      final matchesSpecialty = _selectedSpecialtyFilter == 'All' ||
          doc.specialty.toLowerCase() == _selectedSpecialtyFilter.toLowerCase();
      return matchesQuery && matchesSpecialty;
    }).toList();

    return Column(
      children: [
        // Search & Filter header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                decoration: InputDecoration(
                  hintText: 'Search doctor, specialty, or clinic...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppTheme.textMuted),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                ),
                onChanged: (val) => setState(() => _doctorSearchQuery = val.trim()),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 32,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _specialtyFilters.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (context, idx) {
                    final spec = _specialtyFilters[idx];
                    final isSelected = _selectedSpecialtyFilter == spec;
                    return ChoiceChip(
                      label: Text(spec),
                      selected: isSelected,
                      labelStyle: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? Colors.white : AppTheme.textDark,
                      ),
                      selectedColor: AppTheme.primaryBlue,
                      backgroundColor: const Color(0xFFF1F5F9),
                      side: BorderSide.none,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      onSelected: (_) => setState(() => _selectedSpecialtyFilter = spec),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFE2E8F0)),

        // Doctor Cards List
        Expanded(
          child: filteredDoctors.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.person_search_rounded, size: 40, color: AppTheme.textMuted),
                        SizedBox(height: 8),
                        Text(
                          'No doctors found matching criteria',
                          style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textDark),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Try clearing your search or selecting "All" specialties.',
                          style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredDoctors.length,
                  itemBuilder: (context, idx) {
                    final doc = filteredDoctors[idx];
                    final isSelected = _selectedDoctor?.id == doc.id;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected ? AppTheme.primaryBlue : const Color(0xFFE2E8F0),
                          width: isSelected ? 1.5 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          setState(() {
                            _selectedDoctor = doc;
                            _selectedTimeSlot = null; // reset slot on doctor change
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.12),
                                child: Text(
                                  doc.name.isNotEmpty
                                      ? doc.name.replaceAll('Dr.', '').replaceAll('Dr. ', '').trim()[0].toUpperCase()
                                      : 'D',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue, fontSize: 16),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            doc.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                              color: AppTheme.textDark,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (isSelected)
                                          const Icon(Icons.check_circle_rounded, color: AppTheme.primaryBlue, size: 20),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFDCFCE7),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            doc.specialty,
                                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                                          ),
                                        ),
                                        if (doc.experienceYears > 0)
                                          Text(
                                            '${doc.experienceYears}+ Yrs exp',
                                            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                          ),
                                      ],
                                    ),
                                    if (doc.clinicName.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          const Icon(Icons.local_hospital_outlined, size: 13, color: AppTheme.textMuted),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              doc.clinicName,
                                              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),

        // Bottom Continue button
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _selectedDoctor == null
                  ? null
                  : () => setState(() => _currentStep = 2),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Next: Select Date & Time', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // STEP 2: SELECT DATE & TIME SLOT
  // ==========================================
  Widget _buildStep2SelectDateAndSlot() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Doctor summary banner
          if (_selectedDoctor != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.15),
                    child: Text(
                      _selectedDoctor!.name.isNotEmpty
                          ? _selectedDoctor!.name.replaceAll('Dr.', '').replaceAll('Dr. ', '').trim()[0].toUpperCase()
                          : 'D',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedDoctor!.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF1E3A8A)),
                        ),
                        Text(
                          '${_selectedDoctor!.specialty} • ${_selectedDoctor!.clinicName.isNotEmpty ? _selectedDoctor!.clinicName : "DentaGuru Clinic"}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF2563EB)),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _currentStep = 1),
                    child: const Text('Change', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Date Selection Section
          const Text('1. Select Appointment Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark)),
          const SizedBox(height: 8),

          // Horizontal Date Selector (Next 14 Days)
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 14,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, idx) {
                final date = DateTime.now().add(Duration(days: idx + 1));
                final isSelected = date.year == _selectedDate.year &&
                    date.month == _selectedDate.month &&
                    date.day == _selectedDate.day;
                const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

                return InkWell(
                  onTap: () {
                    setState(() {
                      _selectedDate = date;
                      _selectedTimeSlot = null; // reset slot on date change
                    });
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 58,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.primaryBlue : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? AppTheme.primaryBlue : const Color(0xFFE2E8F0),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          weekdays[date.weekday - 1],
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white.withValues(alpha: 0.9) : AppTheme.textMuted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          date.day.toString().padLeft(2, '0'),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white : AppTheme.textDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Selected Date: ${_formatDate(_selectedDate)}',
            style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 20),

          // Time Slot Selection Section
          const Text('2. Select Available Time Slot', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark)),
          const SizedBox(height: 10),

          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _timeSlots.map((slot) {
              final isBooked = _isSlotBooked(slot);
              final isSelected = _selectedTimeSlot == slot;

              return SizedBox(
                width: 135,
                child: InkWell(
                  onTap: isBooked
                      ? null
                      : () => setState(() => _selectedTimeSlot = slot),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    decoration: BoxDecoration(
                      color: isBooked
                          ? const Color(0xFFF1F5F9)
                          : isSelected
                              ? AppTheme.primaryBlue
                              : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isBooked
                            ? const Color(0xFFE2E8F0)
                            : isSelected
                                ? AppTheme.primaryBlue
                                : const Color(0xFFCBD5E1),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isBooked
                              ? Icons.block_rounded
                              : isSelected
                                  ? Icons.check_circle_rounded
                                  : Icons.access_time_rounded,
                          size: 14,
                          color: isBooked
                              ? const Color(0xFF94A3B8)
                              : isSelected
                                  ? Colors.white
                                  : AppTheme.primaryBlue,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            slot,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isBooked
                                  ? const Color(0xFF94A3B8)
                                  : isSelected
                                      ? Colors.white
                                      : AppTheme.textDark,
                              decoration: isBooked ? TextDecoration.lineThrough : null,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          // Next button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _selectedTimeSlot == null
                  ? null
                  : () => setState(() => _currentStep = 3),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Next: Reason for Visit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // STEP 3: REASON & SYMPTOMS
  // ==========================================
  Widget _buildStep3ReasonAndSymptoms() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Dental Issue / Consultation Reason', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark)),
          const SizedBox(height: 8),

          DropdownButtonFormField<String>(
            initialValue: _selectedCategory,
            isExpanded: true,
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
            ),
            items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (val) => setState(() => _selectedCategory = val ?? _selectedCategory),
          ),
          const SizedBox(height: 16),

          const Text('Describe Symptoms / Notes (Optional)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark)),
          const SizedBox(height: 8),

          TextField(
            controller: _symptomsController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'e.g. Mild pain when drinking cold water, noticed slight swelling since yesterday...',
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
            ),
          ),
          const SizedBox(height: 16),

          const Text('Pain Severity Level:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark)),
          const SizedBox(height: 8),

          Row(
            children: ['Mild', 'Moderate', 'Severe'].map((sev) {
              final isSelected = _selectedSeverity == sev;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: InkWell(
                    onTap: () => setState(() => _selectedSeverity = sev),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? (sev == 'Severe' ? const Color(0xFFFEE2E2) : sev == 'Moderate' ? const Color(0xFFFFEDD5) : const Color(0xFFDBEAFE))
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? (sev == 'Severe' ? const Color(0xFFEF4444) : sev == 'Moderate' ? const Color(0xFFF97316) : const Color(0xFF3B82F6))
                              : const Color(0xFFCBD5E1),
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          sev,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                            color: isSelected
                                ? (sev == 'Severe' ? const Color(0xFF991B1B) : sev == 'Moderate' ? const Color(0xFF9A3412) : const Color(0xFF1E40AF))
                                : AppTheme.textDark,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => setState(() => _currentStep = 4),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Next: Review Booking Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // STEP 4: REVIEW & CONFIRM
  // ==========================================
  Widget _buildStep4ReviewAndConfirm() {
    final patient = _patientService.currentPatient;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Review Appointment Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark)),
          const SizedBox(height: 12),

          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF991B1B)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Detailed Summary Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildSummaryRow(
                  icon: Icons.person_rounded,
                  label: 'Doctor',
                  value: _selectedDoctor?.name ?? 'Attending Specialist',
                  subValue: _selectedDoctor?.specialty,
                ),
                const Divider(height: 18, color: Color(0xFFF1F5F9)),
                _buildSummaryRow(
                  icon: Icons.local_hospital_rounded,
                  label: 'Clinic',
                  value: _selectedDoctor?.clinicName.isNotEmpty == true ? _selectedDoctor!.clinicName : 'DentaGuru Clinic',
                  subValue: _selectedDoctor?.clinicAddress,
                ),
                const Divider(height: 18, color: Color(0xFFF1F5F9)),
                _buildSummaryRow(
                  icon: Icons.calendar_today_rounded,
                  label: 'Date & Time',
                  value: _formatDate(_selectedDate),
                  subValue: _selectedTimeSlot ?? '10:00 AM',
                ),
                const Divider(height: 18, color: Color(0xFFF1F5F9)),
                _buildSummaryRow(
                  icon: Icons.medical_services_rounded,
                  label: 'Reason for Visit',
                  value: _selectedCategory,
                  subValue: _symptomsController.text.trim().isNotEmpty
                      ? _symptomsController.text.trim()
                      : 'Severity: $_selectedSeverity',
                ),
                const Divider(height: 18, color: Color(0xFFF1F5F9)),
                _buildSummaryRow(
                  icon: Icons.account_circle_rounded,
                  label: 'Patient',
                  value: patient.name.isNotEmpty ? patient.name : 'Registered Patient',
                  subValue: patient.phone.isNotEmpty ? patient.phone : null,
                ),
                const Divider(height: 18, color: Color(0xFFF1F5F9)),
                _buildSummaryRow(
                  icon: Icons.payments_rounded,
                  label: 'Consultation Fee',
                  value: _selectedDoctor?.consultationFee.isNotEmpty == true
                      ? '₹${_selectedDoctor!.consultationFee}'
                      : '₹500',
                  subValue: 'Pay at clinic during visit',
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Confirm button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSubmitting ? null : _submitBooking,
              icon: _isSubmitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.check_circle_rounded, size: 18),
              label: Text(
                _isSubmitting ? 'Confirming Booking...' : 'Confirm & Book Appointment',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow({
    required IconData icon,
    required String label,
    required String value,
    String? subValue,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: AppTheme.primaryBlue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppTheme.primaryBlue, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              const SizedBox(height: 1),
              Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark)),
              if (subValue != null && subValue.isNotEmpty) ...[
                const SizedBox(height: 1),
                Text(subValue, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================
  // STEP 5: SUCCESS CONFIRMATION
  // ==========================================
  Widget _buildStep5Success() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF86EFAC), width: 2),
              ),
              child: const Icon(Icons.check_rounded, color: Color(0xFF15803D), size: 48),
            ),
            const SizedBox(height: 18),
            const Text(
              'Visit Booked Successfully!',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19, color: AppTheme.textDark),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Your appointment with ${_selectedDoctor?.name ?? "your dentist"} is scheduled for ${_formatDate(_selectedDate)} at ${_selectedTimeSlot ?? ""}.',
              style: const TextStyle(fontSize: 13, color: AppTheme.textMuted, height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onBookingSuccess?.call();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('View in My Appointments', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Submission handler
  Future<void> _submitBooking() async {
    if (_selectedDoctor == null || _selectedTimeSlot == null) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final docId = _selectedDoctor!.id.isNotEmpty ? _selectedDoctor!.id : _selectedDoctor!.userId;
    final dateStr = _selectedDate.toIso8601String();

    try {
      final res = await _patientService.bookAppointment(
        dentistId: docId,
        clinicId: '',
        date: dateStr,
        timeSlot: _selectedTimeSlot!,
        treatment: _selectedCategory,
        symptoms: _symptomsController.text.trim(),
      );

      if (!mounted) return;

      if (res['success'] == true) {
        setState(() {
          _isSubmitting = false;
          _currentStep = 5; // Move to Success Step
        });
      } else {
        setState(() {
          _isSubmitting = false;
          _errorMessage = res['message']?.toString() ?? 'Unable to confirm booking. Please try another time slot.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'Booking failed: $e';
      });
    }
  }
}

