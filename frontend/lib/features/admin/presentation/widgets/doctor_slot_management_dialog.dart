import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/models/doctor_availability.dart';

class DoctorSlotManagementDialog extends StatefulWidget {
  final DoctorModel? initialDoctor;
  final bool isDoctorSelfManage;

  const DoctorSlotManagementDialog({
    super.key,
    this.initialDoctor,
    this.isDoctorSelfManage = false,
  });

  static Future<void> show(
    BuildContext context, {
    DoctorModel? initialDoctor,
    bool isDoctorSelfManage = false,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => DoctorSlotManagementDialog(
        initialDoctor: initialDoctor,
        isDoctorSelfManage: isDoctorSelfManage,
      ),
    );
  }

  @override
  State<DoctorSlotManagementDialog> createState() => _DoctorSlotManagementDialogState();
}

class _DoctorSlotManagementDialogState extends State<DoctorSlotManagementDialog> {
  final PatientProblemService _service = PatientProblemService();

  DoctorModel? _selectedDoctor;
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  String _startTime = '09:00 AM';
  String _endTime = '05:00 PM';
  int _slotDuration = 30;

  bool _isBlocked = false;
  final TextEditingController _blockedReasonController = TextEditingController();
  final TextEditingController _customSlotController = TextEditingController();

  List<String> _slots = [];
  List<String> _bookedSlots = [];
  bool _isLoading = false;
  bool _isSaving = false;
  String? _statusMessage;

  final List<String> _startTimes = [
    '08:00 AM',
    '08:30 AM',
    '09:00 AM',
    '09:30 AM',
    '10:00 AM',
    '11:00 AM',
    '12:00 PM',
  ];

  final List<String> _endTimes = [
    '03:00 PM',
    '04:00 PM',
    '05:00 PM',
    '06:00 PM',
    '07:00 PM',
    '08:00 PM',
    '09:00 PM',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialDoctor != null) {
      _selectedDoctor = widget.initialDoctor;
    } else if (_service.allDoctors.isNotEmpty) {
      _selectedDoctor = _service.allDoctors.first;
    }
    _loadAvailabilityForSelectedDoctorAndDate();
  }

  @override
  void dispose() {
    _blockedReasonController.dispose();
    _customSlotController.dispose();
    super.dispose();
  }

  Future<void> _loadAvailabilityForSelectedDoctorAndDate() async {
    if (_selectedDoctor == null) return;
    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    try {
      final avail = await _service.getDoctorAvailability(_selectedDoctor!.id, _selectedDate);
      if (mounted) {
        setState(() {
          _isBlocked = avail.isBlocked;
          _blockedReasonController.text = avail.blockedReason ?? 'Doctor on Leave / Clinic Closed';
          _startTime = _startTimes.contains(avail.startTime) ? avail.startTime : '09:00 AM';
          _endTime = _endTimes.contains(avail.endTime) ? avail.endTime : '05:00 PM';
          _slotDuration = avail.slotDurationMinutes;
          _slots = List<String>.from(avail.allSlots);
          _bookedSlots = List<String>.from(avail.bookedSlots);
          if (_slots.isEmpty && !_isBlocked) {
            _slots = _service.generateTimeSlots(
              startTime: _startTime,
              endTime: _endTime,
              durationMinutes: _slotDuration,
            );
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Failed to load availability: $e';
        });
      }
    }
  }

  void _generateSlots() {
    final generated = _service.generateTimeSlots(
      startTime: _startTime,
      endTime: _endTime,
      durationMinutes: _slotDuration,
    );
    setState(() {
      _slots = generated;
    });
  }

  void _addCustomSlot() {
    final text = _customSlotController.text.trim();
    if (text.isEmpty) return;
    if (!_slots.contains(text)) {
      setState(() {
        _slots.add(text);
        _customSlotController.clear();
      });
    }
  }

  Future<void> _saveAvailability() async {
    if (_selectedDoctor == null) return;
    setState(() {
      _isSaving = true;
      _statusMessage = null;
    });

    final success = await _service.publishDoctorAvailability(
      doctorId: _selectedDoctor!.id,
      date: _selectedDate,
      slots: _slots,
      startTime: _startTime,
      endTime: _endTime,
      slotDurationMinutes: _slotDuration,
      isBlocked: _isBlocked,
      blockedReason: _isBlocked ? _blockedReasonController.text.trim() : null,
    );

    if (mounted) {
      setState(() {
        _isSaving = false;
        _statusMessage = success
            ? '✓ Doctor schedule published successfully!'
            : '⚠️ Could not save schedule. Please try again.';
      });

      if (success) {
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) Navigator.of(context).pop();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final allDoctors = _service.allDoctors;
    final dateStr = '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 720),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFF0F172A),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.isDoctorSelfManage ? 'My Consultation Schedule & Slots' : 'Doctor Slot Management',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Configure working hours, non-overlapping slots & block dates',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Select Doctor (if Admin)
                          if (!widget.isDoctorSelfManage && allDoctors.length > 1) ...[
                            const Text('Select Doctor', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark)),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<DoctorModel>(
                                  isExpanded: true,
                                  value: _selectedDoctor,
                                  items: allDoctors.map((doc) {
                                    return DropdownMenuItem<DoctorModel>(
                                      value: doc,
                                      child: Text(
                                        '${doc.name} (${doc.specialty})',
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() => _selectedDoctor = val);
                                      _loadAvailabilityForSelectedDoctorAndDate();
                                    }
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ] else if (_selectedDoctor != null) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.15),
                                    child: const Icon(Icons.person, color: AppTheme.primaryBlue, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _selectedDoctor!.name,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          '${_selectedDoctor!.specialty} • ${_selectedDoctor!.clinicName.isNotEmpty ? _selectedDoctor!.clinicName : "DentaGuru"}',
                                          style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // 2. Date Selection
                          const Text('Consultation Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark)),
                          const SizedBox(height: 6),
                          InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _selectedDate,
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(const Duration(days: 90)),
                              );
                              if (picked != null) {
                                setState(() => _selectedDate = picked);
                                _loadAvailabilityForSelectedDoctorAndDate();
                              }
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.event_rounded, color: AppTheme.primaryBlue, size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      dateStr,
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                    ),
                                  ),
                                  const Icon(Icons.arrow_drop_down, color: AppTheme.textMuted),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // 3. Date Block Toggle
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _isBlocked ? const Color(0xFFFEF2F2) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _isBlocked ? const Color(0xFFFCA5A5) : const Color(0xFFE2E8F0)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      _isBlocked ? Icons.block_rounded : Icons.check_circle_outline_rounded,
                                      color: _isBlocked ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _isBlocked ? 'Date Blocked (Unavailable / Holiday)' : 'Doctor Available on this date',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: _isBlocked ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                                        ),
                                      ),
                                    ),
                                    Switch(
                                      value: _isBlocked,
                                      activeColor: const Color(0xFFDC2626),
                                      onChanged: (val) {
                                        setState(() => _isBlocked = val);
                                      },
                                    ),
                                  ],
                                ),
                                if (_isBlocked) ...[
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _blockedReasonController,
                                    decoration: InputDecoration(
                                      hintText: 'Enter reason (e.g. Weekly Off, Conference, Holiday)',
                                      filled: true,
                                      fillColor: Colors.white,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    ),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          if (!_isBlocked) ...[
                            // 4. Hours & Slot Duration
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Start Time', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textMuted)),
                                      const SizedBox(height: 4),
                                      DropdownButtonFormField<String>(
                                        value: _startTime,
                                        isExpanded: true,
                                        decoration: InputDecoration(
                                          filled: true,
                                          fillColor: const Color(0xFFF8FAFC),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                        items: _startTimes.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 12)))).toList(),
                                        onChanged: (val) => setState(() => _startTime = val ?? _startTime),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('End Time', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textMuted)),
                                      const SizedBox(height: 4),
                                      DropdownButtonFormField<String>(
                                        value: _endTime,
                                        isExpanded: true,
                                        decoration: InputDecoration(
                                          filled: true,
                                          fillColor: const Color(0xFFF8FAFC),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                        items: _endTimes.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 12)))).toList(),
                                        onChanged: (val) => setState(() => _endTime = val ?? _endTime),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                SizedBox(
                                  width: 90,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Duration', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textMuted)),
                                      const SizedBox(height: 4),
                                      DropdownButtonFormField<int>(
                                        value: _slotDuration,
                                        decoration: InputDecoration(
                                          filled: true,
                                          fillColor: const Color(0xFFF8FAFC),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                        items: const [
                                          DropdownMenuItem(value: 15, child: Text('15m', style: TextStyle(fontSize: 12))),
                                          DropdownMenuItem(value: 30, child: Text('30m', style: TextStyle(fontSize: 12))),
                                          DropdownMenuItem(value: 45, child: Text('45m', style: TextStyle(fontSize: 12))),
                                          DropdownMenuItem(value: 60, child: Text('60m', style: TextStyle(fontSize: 12))),
                                        ],
                                        onChanged: (val) => setState(() => _slotDuration = val ?? 30),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Generate Button
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _generateSlots,
                                icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                                label: const Text('Auto-Generate Slots from Hours', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.primaryBlue,
                                  side: const BorderSide(color: AppTheme.primaryBlue),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // 5. Configured Slots Chips
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Published Slots (${_slots.length})',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                                ),
                                if (_bookedSlots.isNotEmpty)
                                  Text(
                                    '${_bookedSlots.length} Booked',
                                    style: const TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.bold, fontSize: 11),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            if (_slots.isEmpty)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: const Center(
                                  child: Text('No slots configured yet. Click Auto-Generate or add custom slots below.', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                                ),
                              )
                            else
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _slots.map((s) {
                                  final isBooked = _bookedSlots.any((b) => b.trim().toLowerCase() == s.trim().toLowerCase());
                                  return Chip(
                                    label: Text(
                                      isBooked ? '$s (Booked)' : s,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isBooked ? const Color(0xFFB45309) : const Color(0xFF15803D),
                                      ),
                                    ),
                                    backgroundColor: isBooked ? const Color(0xFFFEF3C7) : const Color(0xFFDCFCE7),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      side: BorderSide(color: isBooked ? const Color(0xFFFDE68A) : const Color(0xFFBBF7D0)),
                                    ),
                                    deleteIcon: isBooked ? null : const Icon(Icons.close_rounded, size: 14),
                                    onDeleted: isBooked
                                        ? null
                                        : () {
                                            setState(() => _slots.remove(s));
                                          },
                                  );
                                }).toList(),
                              ),
                            const SizedBox(height: 12),

                            // 6. Custom Slot Input
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _customSlotController,
                                    decoration: InputDecoration(
                                      hintText: 'Add custom slot (e.g. 07:30 PM)',
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    ),
                                    style: const TextStyle(fontSize: 12),
                                    onSubmitted: (_) => _addCustomSlot(),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: _addCustomSlot,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0F172A),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  ),
                                  child: const Text('Add Slot', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ],

                          if (_statusMessage != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _statusMessage!.startsWith('✓') ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: _statusMessage!.startsWith('✓') ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA)),
                              ),
                              child: Text(
                                _statusMessage!,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: _statusMessage!.startsWith('✓') ? const Color(0xFF047857) : const Color(0xFFB91C1C),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _saveAvailability,
                      icon: _isSaving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save_rounded, size: 18),
                      label: Text(
                        _isSaving ? 'Publishing...' : 'Publish Doctor Schedule',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

