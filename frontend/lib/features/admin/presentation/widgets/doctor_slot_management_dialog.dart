import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/models/doctor_availability.dart';

class DoctorSlotManagementDialog extends StatefulWidget {
  final DoctorModel? initialDoctor;
  final bool isDoctorSelfManage;
  final bool initialBlockDateMode;

  const DoctorSlotManagementDialog({
    super.key,
    this.initialDoctor,
    this.isDoctorSelfManage = false,
    this.initialBlockDateMode = false,
  });

  static Future<void> show(
    BuildContext context, {
    DoctorModel? initialDoctor,
    bool isDoctorSelfManage = false,
    bool initialBlockDateMode = false,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => DoctorSlotManagementDialog(
        initialDoctor: initialDoctor,
        isDoctorSelfManage: isDoctorSelfManage,
        initialBlockDateMode: initialBlockDateMode,
      ),
    );
  }

  @override
  State<DoctorSlotManagementDialog> createState() => _DoctorSlotManagementDialogState();
}

class _DoctorSlotManagementDialogState extends State<DoctorSlotManagementDialog> {
  final PatientProblemService _service = PatientProblemService();

  late int _activeTabIndex; // 0 = Working Days & Slots, 1 = Block Date / Mark Holiday
  DoctorModel? _selectedDoctor;
  DateTime _selectedDate = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  ).add(const Duration(days: 1));
  String _startTime = '09:00 AM';
  String _endTime = '05:00 PM';
  int _slotDuration = 30;

  bool _hasBreak = true;
  String _breakStartTime = '01:00 PM';
  String _breakEndTime = '02:00 PM';
  List<String> _selectedWorkingDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
  bool _applyBatchWorkingDays = true;

  bool _isBlocked = false;
  List<DoctorAvailabilityModel> _blockedDates = [];
  final Set<String> _multiBlockSelection = <String>{};
  int _existingAppointmentsOnDate = 0;

  final TextEditingController _blockedReasonController = TextEditingController();
  final TextEditingController _customSlotController = TextEditingController();

  List<String> _slots = [];
  List<String> _bookedSlots = [];
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isTogglingBlock = false;
  String? _statusMessage;
  bool _statusIsError = false;

  final List<String> _allWeekDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const Map<String, String> _fullToShortDay = {
    'monday': 'Mon',
    'mon': 'Mon',
    'tuesday': 'Tue',
    'tue': 'Tue',
    'wednesday': 'Wed',
    'wed': 'Wed',
    'thursday': 'Thu',
    'thu': 'Thu',
    'friday': 'Fri',
    'fri': 'Fri',
    'saturday': 'Sat',
    'sat': 'Sat',
    'sunday': 'Sun',
    'sun': 'Sun',
  };
  static const Map<String, String> _shortToFullDay = {
    'Mon': 'Monday',
    'Tue': 'Tuesday',
    'Wed': 'Wednesday',
    'Thu': 'Thursday',
    'Fri': 'Friday',
    'Sat': 'Saturday',
    'Sun': 'Sunday',
  };

  final List<String> _startTimes = [
    '06:00 AM',
    '06:30 AM',
    '07:00 AM',
    '07:30 AM',
    '08:00 AM',
    '08:30 AM',
    '09:00 AM',
    '09:30 AM',
    '10:00 AM',
    '10:30 AM',
    '11:00 AM',
    '11:30 AM',
    '12:00 PM',
    '01:00 PM',
    '02:00 PM',
  ];

  final List<String> _endTimes = [
    '12:00 PM',
    '01:00 PM',
    '02:00 PM',
    '03:00 PM',
    '04:00 PM',
    '05:00 PM',
    '06:00 PM',
    '07:00 PM',
    '08:00 PM',
    '09:00 PM',
    '10:00 PM',
  ];

  final List<String> _breakStartTimes = [
    '11:30 AM',
    '12:00 PM',
    '12:30 PM',
    '01:00 PM',
    '01:30 PM',
    '02:00 PM',
    '02:30 PM',
    '03:00 PM',
  ];

  final List<String> _breakEndTimes = [
    '12:30 PM',
    '01:00 PM',
    '01:30 PM',
    '02:00 PM',
    '02:30 PM',
    '03:00 PM',
    '03:30 PM',
    '04:00 PM',
  ];

  @override
  void initState() {
    super.initState();
    _activeTabIndex = widget.initialBlockDateMode ? 1 : 0;
    if (widget.initialDoctor != null) {
      _selectedDoctor = widget.initialDoctor;
    } else if (widget.isDoctorSelfManage && _service.currentDoctor != null) {
      _selectedDoctor = _service.currentDoctor;
    } else if (_service.allDoctors.isNotEmpty) {
      _selectedDoctor = _service.allDoctors.first;
    }
    _blockedReasonController.text = 'Doctor on Leave / Clinic Closed';
    _loadAvailabilityForSelectedDoctorAndDate(loadScheduleAndBlocked: true);
  }

  @override
  void dispose() {
    _blockedReasonController.dispose();
    _customSlotController.dispose();
    super.dispose();
  }

  String _formatDateIso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  List<String> _toShortWeekDays(List<String> days) {
    final mapped = <String>[];
    for (final raw in days) {
      final s = _fullToShortDay[raw.trim().toLowerCase()];
      if (s != null && !mapped.contains(s)) mapped.add(s);
    }
    return mapped.isNotEmpty ? mapped : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
  }

  int _timeToMinutes(String timeStr) {
    final parts = timeStr.trim().split(' ');
    if (parts.length < 2) return 0;
    final tp = parts[0].split(':');
    int h = int.tryParse(tp[0]) ?? 0;
    final m = int.tryParse(tp.length > 1 ? tp[1] : '0') ?? 0;
    final p = parts[1].toUpperCase();
    if (p == 'PM' && h < 12) h += 12;
    if (p == 'AM' && h == 12) h = 0;
    return h * 60 + m;
  }

  List<String> _dropdownOptions(List<String> base, String current) {
    if (current.trim().isEmpty || base.contains(current)) return base;
    return [current, ...base];
  }

  Future<void> _loadAvailabilityForSelectedDoctorAndDate({bool loadScheduleAndBlocked = false}) async {
    if (_selectedDoctor == null) return;
    final docId = _selectedDoctor!.id.isNotEmpty ? _selectedDoctor!.id : _selectedDoctor!.userId;
    if (docId.isEmpty) return;

    setState(() {
      _isLoading = true;
      _statusMessage = null;
      _statusIsError = false;
    });

    try {
      DoctorScheduleModel? schedule;
      List<DoctorAvailabilityModel>? blockedList;
      if (loadScheduleAndBlocked) {
        schedule = await _service.getDoctorSchedule(docId);
        blockedList = await _service.getBlockedDates(docId);
      }
      final avail = await _service.getDoctorAvailability(docId, _selectedDate);

      if (!mounted) return;
      setState(() {
        if (blockedList != null) {
          _blockedDates = blockedList;
        }
        final dateStr = _formatDateIso(_selectedDate);
        final blockedMatch = _blockedDates.where((b) => b.date == dateStr).firstOrNull;
        _isBlocked = avail.isBlocked || blockedMatch != null;
        _blockedReasonController.text =
            (avail.blockedReason?.trim().isNotEmpty == true)
                ? avail.blockedReason!
                : (blockedMatch?.blockedReason?.trim().isNotEmpty == true
                    ? blockedMatch!.blockedReason!
                    : 'Doctor on Leave / Clinic Closed');

        final effectiveWorkingDays = (schedule != null && schedule.workingDays.isNotEmpty)
            ? schedule.workingDays
            : avail.workingDays;
        if (effectiveWorkingDays.isNotEmpty) {
          _selectedWorkingDays = _toShortWeekDays(effectiveWorkingDays);
        }

        final candidateStart = (schedule != null && schedule.isConfigured) ? schedule.startTime : avail.startTime;
        final candidateEnd = (schedule != null && schedule.isConfigured) ? schedule.endTime : avail.endTime;
        final candidateDur = (schedule != null && schedule.isConfigured) ? schedule.slotDurationMinutes : avail.slotDurationMinutes;
        final candidateHasBreak = (schedule != null && schedule.isConfigured) ? schedule.hasBreak : avail.hasBreak;
        final candidateBreakStart = (schedule != null && schedule.isConfigured) ? schedule.breakStartTime : avail.breakStartTime;
        final candidateBreakEnd = (schedule != null && schedule.isConfigured) ? schedule.breakEndTime : avail.breakEndTime;

        if (candidateStart.trim().isNotEmpty) _startTime = candidateStart;
        if (candidateEnd.trim().isNotEmpty) _endTime = candidateEnd;
        if ([15, 30, 45, 60].contains(candidateDur)) _slotDuration = candidateDur;
        _hasBreak = candidateHasBreak;
        if (candidateBreakStart != null && candidateBreakStart.trim().isNotEmpty) {
          _breakStartTime = candidateBreakStart;
        }
        if (candidateBreakEnd != null && candidateBreakEnd.trim().isNotEmpty) {
          _breakEndTime = candidateBreakEnd;
        }

        _slots = List<String>.from(avail.allSlots);
        _bookedSlots = List<String>.from(avail.bookedSlots);
        _existingAppointmentsOnDate = _bookedSlots.length;
        if (_slots.isEmpty && !_isBlocked) {
          _slots = _service.generateTimeSlots(
            startTime: _startTime,
            endTime: _endTime,
            durationMinutes: _slotDuration,
            breakStartTime: _hasBreak ? _breakStartTime : null,
            breakEndTime: _hasBreak ? _breakEndTime : null,
          );
        }
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusIsError = true;
          _statusMessage = 'Failed to load availability: $e';
        });
      }
    }
  }

  Future<void> _handleToggleDateBlocked(bool val) async {
    if (_selectedDoctor == null || _isTogglingBlock) return;
    final docId = _selectedDoctor!.id.isNotEmpty ? _selectedDoctor!.id : _selectedDoctor!.userId;
    final dateStr = _formatDateIso(_selectedDate);
    final previous = _isBlocked;

    setState(() {
      _isTogglingBlock = true;
      _isBlocked = val;
      _statusMessage = null;
      _statusIsError = false;
    });

    final reasonText = _blockedReasonController.text.trim().isNotEmpty
        ? _blockedReasonController.text.trim()
        : 'Doctor on Leave / Clinic Closed';

    final res = await _service.toggleBlockedDate(
      doctorId: docId,
      date: _selectedDate,
      isBlocked: val,
      reason: reasonText,
    );

    if (!mounted) return;
    if (res['success'] == true) {
      final updatedBlocked = _service.getCachedBlockedDates(docId);
      final refreshedAvail = await _service.getDoctorAvailability(docId, _selectedDate);
      final existingCount = int.tryParse((res['existingAppointmentsCount'] ?? '0').toString()) ?? _bookedSlots.length;
      if (!mounted) return;
      setState(() {
        _isTogglingBlock = false;
        _blockedDates = List<DoctorAvailabilityModel>.from(updatedBlocked);
        _isBlocked = val;
        _existingAppointmentsOnDate = existingCount;
        if (!val) {
          _slots = refreshedAvail.allSlots.isNotEmpty
              ? List<String>.from(refreshedAvail.allSlots)
              : _service.generateTimeSlots(
                  startTime: _startTime,
                  endTime: _endTime,
                  durationMinutes: _slotDuration,
                  breakStartTime: _hasBreak ? _breakStartTime : null,
                  breakEndTime: _hasBreak ? _breakEndTime : null,
                );
        }
        _statusIsError = false;
        _statusMessage = val
            ? (existingCount > 0
                ? '✓ Date $dateStr blocked! ($existingCount existing appointment(s) remain preserved; new bookings prevented.)'
                : '✓ Date $dateStr marked as blocked & saved to database!')
            : '✓ Date $dateStr unblocked and available for bookings.';
      });
    } else {
      setState(() {
        _isTogglingBlock = false;
        _isBlocked = previous;
        _statusIsError = true;
        _statusMessage = '⚠️ ${res['message'] ?? 'Failed to update blocked date status. Please try again.'}';
      });
    }
  }

  Future<void> _handleBlockMultipleDates() async {
    if (_selectedDoctor == null || _multiBlockSelection.isEmpty || _isTogglingBlock) return;
    final docId = _selectedDoctor!.id.isNotEmpty ? _selectedDoctor!.id : _selectedDoctor!.userId;
    final datesToBlock = _multiBlockSelection.map((s) {
      final parts = s.split('-');
      return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
    }).toList();

    setState(() {
      _isTogglingBlock = true;
      _statusMessage = null;
      _statusIsError = false;
    });

    final reasonText = _blockedReasonController.text.trim().isNotEmpty
        ? _blockedReasonController.text.trim()
        : 'Doctor on Leave / Clinic Closed';

    final res = await _service.toggleBlockedDate(
      doctorId: docId,
      date: datesToBlock.first,
      dates: datesToBlock,
      isBlocked: true,
      reason: reasonText,
    );

    if (!mounted) return;
    setState(() {
      _isTogglingBlock = false;
      if (res['success'] == true) {
        _blockedDates = List<DoctorAvailabilityModel>.from(_service.getCachedBlockedDates(docId));
        final selKey = _formatDateIso(_selectedDate);
        if (_blockedDates.any((b) => b.date == selKey)) {
          _isBlocked = true;
        }
        _multiBlockSelection.clear();
        _statusIsError = false;
        _statusMessage = '✓ ${datesToBlock.length} date(s) blocked and saved to database!';
      } else {
        _statusIsError = true;
        _statusMessage = '⚠️ ${res['message'] ?? 'Could not block selected dates.'}';
      }
    });
  }

  Future<void> _handleUnblockSpecificDate(String dateStr) async {
    if (_selectedDoctor == null || _isTogglingBlock) return;
    final docId = _selectedDoctor!.id.isNotEmpty ? _selectedDoctor!.id : _selectedDoctor!.userId;
    final parts = dateStr.split('-');
    if (parts.length != 3) return;
    final targetDate = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));

    setState(() {
      _isTogglingBlock = true;
      _statusMessage = null;
      _statusIsError = false;
    });

    final res = await _service.unblockDoctorDate(doctorId: docId, date: targetDate);
    if (!mounted) return;

    setState(() {
      _isTogglingBlock = false;
      if (res['success'] == true) {
        _blockedDates = List<DoctorAvailabilityModel>.from(_service.getCachedBlockedDates(docId));
        if (_formatDateIso(_selectedDate) == dateStr) {
          _isBlocked = false;
        }
        _statusIsError = false;
        _statusMessage = '✓ Date $dateStr removed from blocked dates.';
      } else {
        _statusIsError = true;
        _statusMessage = '⚠️ ${res['message'] ?? 'Failed to unblock date $dateStr.'}';
      }
    });
  }

  void _generateSlots() {
    if (_timeToMinutes(_endTime) <= _timeToMinutes(_startTime)) {
      setState(() {
        _slots = [];
        _statusIsError = true;
        _statusMessage = '⚠️ End time must be after start time.';
      });
      return;
    }
    if (_hasBreak && _timeToMinutes(_breakEndTime) <= _timeToMinutes(_breakStartTime)) {
      setState(() {
        _statusIsError = true;
        _statusMessage = '⚠️ Break end time must be after break start time.';
      });
      return;
    }

    final generated = _service.generateTimeSlots(
      startTime: _startTime,
      endTime: _endTime,
      durationMinutes: _slotDuration,
      breakStartTime: _hasBreak ? _breakStartTime : null,
      breakEndTime: _hasBreak ? _breakEndTime : null,
    );
    setState(() {
      _slots = generated;
      if (_statusIsError) {
        _statusMessage = null;
        _statusIsError = false;
      }
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
    if (_selectedDoctor == null || _isSaving) return;
    final docId = _selectedDoctor!.id.isNotEmpty ? _selectedDoctor!.id : _selectedDoctor!.userId;

    if (_timeToMinutes(_endTime) <= _timeToMinutes(_startTime)) {
      setState(() {
        _statusIsError = true;
        _statusMessage = '⚠️ End time must be after start time.';
      });
      return;
    }
    if (_hasBreak && _timeToMinutes(_breakEndTime) <= _timeToMinutes(_breakStartTime)) {
      setState(() {
        _statusIsError = true;
        _statusMessage = '⚠️ Lunch break end time must be after start time.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _statusMessage = null;
      _statusIsError = false;
    });

    final fullWorkingDays = _selectedWorkingDays
        .map((d) => _shortToFullDay[d] ?? d)
        .toList();

    // 1. Save persistent weekly schedule (Working Days, Hours, Lunch Break, Slot Duration)
    final schedRes = await _service.saveDoctorSchedule(
      doctorId: docId,
      workingDays: fullWorkingDays,
      startTime: _startTime,
      endTime: _endTime,
      slotDurationMinutes: _slotDuration,
      hasBreak: _hasBreak,
      breakStartTime: _hasBreak ? _breakStartTime : null,
      breakEndTime: _hasBreak ? _breakEndTime : null,
      slots: _isBlocked ? null : _slots,
      applyToUpcomingDays: _applyBatchWorkingDays,
    );

    // 2. Also publish for specific selected date / batch dates
    List<DateTime>? batchDates;
    if (_applyBatchWorkingDays && !_isBlocked) {
      const dayMap = {
        'Mon': DateTime.monday,
        'Tue': DateTime.tuesday,
        'Wed': DateTime.wednesday,
        'Thu': DateTime.thursday,
        'Fri': DateTime.friday,
        'Sat': DateTime.saturday,
        'Sun': DateTime.sunday,
      };
      final selectedInts = _selectedWorkingDays.map((d) => dayMap[d]).whereType<int>().toSet();
      batchDates = [];
      final now = DateTime.now();
      for (int i = 0; i < 14; i++) {
        final d = DateTime(now.year, now.month, now.day).add(Duration(days: i));
        final dKey = _formatDateIso(d);
        if (selectedInts.contains(d.weekday) && !_blockedDates.any((b) => b.date == dKey)) {
          batchDates.add(d);
        }
      }
    }

    final success = await _service.publishDoctorAvailability(
      doctorId: docId,
      date: _selectedDate,
      batchDates: batchDates,
      slots: _isBlocked ? const [] : _slots,
      startTime: _startTime,
      endTime: _endTime,
      slotDurationMinutes: _slotDuration,
      hasBreak: _hasBreak,
      breakStartTime: _hasBreak ? _breakStartTime : null,
      breakEndTime: _hasBreak ? _breakEndTime : null,
      workingDays: fullWorkingDays,
      isBlocked: _isBlocked,
      blockedReason: _isBlocked ? _blockedReasonController.text.trim() : null,
    );

    final ok = success || (schedRes['success'] == true);
    if (mounted) {
      setState(() {
        _isSaving = false;
        _statusIsError = !ok;
        _statusMessage = ok
            ? (_applyBatchWorkingDays && batchDates != null
                ? '✓ Schedule & slots saved for ${batchDates.length} working days!'
                : '✓ Doctor schedule published successfully!')
            : '⚠️ Could not save schedule. Please try again.';
      });

      if (ok) {
        Future.delayed(const Duration(milliseconds: 900), () {
          if (mounted) Navigator.of(context).pop();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final allDoctors = _service.allDoctors;
    final dateStr = _formatDateIso(_selectedDate);
    final blockedDateSet = _blockedDates.map((b) => b.date).toSet();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: double.maxFinite,
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 740),
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
                    child: Icon(
                      _activeTabIndex == 1 ? Icons.event_busy_rounded : Icons.calendar_month_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
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
                        Text(
                          _activeTabIndex == 1
                              ? 'Block specific holiday dates, view calendar & manage blocked dates'
                              : 'Configure working hours, non-overlapping slots & block dates',
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
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

            // Mode Switcher Tabs (Working Days & Slots | Block Date / Mark Holiday)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              color: const Color(0xFFF8FAFC),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      key: const Key('slot_tab_schedule'),
                      onTap: () => setState(() => _activeTabIndex = 0),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                        decoration: BoxDecoration(
                          color: _activeTabIndex == 0 ? AppTheme.primaryBlue : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _activeTabIndex == 0 ? AppTheme.primaryBlue : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.edit_calendar_rounded,
                              size: 15,
                              color: _activeTabIndex == 0 ? Colors.white : AppTheme.textDark,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Working Days & Slots',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: _activeTabIndex == 0 ? Colors.white : AppTheme.textDark,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      key: const Key('slot_tab_block_dates'),
                      onTap: () => setState(() => _activeTabIndex = 1),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                        decoration: BoxDecoration(
                          color: _activeTabIndex == 1 ? const Color(0xFFFE3434) : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _activeTabIndex == 1 ? const Color(0xFFFE3434) : const Color(0x40FE3434),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.block_rounded,
                              size: 15,
                              color: _activeTabIndex == 1 ? Colors.white : const Color(0xFFFE3434),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                _blockedDates.isNotEmpty
                                    ? 'Block Date (${_blockedDates.length})'
                                    : 'Block Date / Holiday',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: _activeTabIndex == 1 ? Colors.white : const Color(0xFFFE3434),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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
                                  value: allDoctors.contains(_selectedDoctor) ? _selectedDoctor : allDoctors.first,
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
                                      _loadAvailabilityForSelectedDoctorAndDate(loadScheduleAndBlocked: true);
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
                                          '${_selectedDoctor!.specialty} • ${_selectedDoctor!.clinicName.isNotEmpty ? _selectedDoctor!.clinicName : "GS HEALTH"}',
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

                          // Date Selection (shared by both modes)
                          const Text('Consultation Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark)),
                          const SizedBox(height: 6),
                          InkWell(
                            key: const Key('block_date_picker_btn'),
                            onTap: () async {
                              final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _selectedDate.isBefore(today) ? today : _selectedDate,
                                firstDate: today,
                                lastDate: today.add(const Duration(days: 180)),
                              );
                              if (picked != null) {
                                setState(() => _selectedDate = DateTime(picked.year, picked.month, picked.day));
                                _loadAvailabilityForSelectedDoctorAndDate();
                              }
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _isBlocked ? const Color(0x40FE3434) : const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.event_rounded,
                                    color: _isBlocked ? const Color(0xFFFE3434) : AppTheme.primaryBlue,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      dateStr,
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                    ),
                                  ),
                                  if (_isBlocked)
                                    Container(
                                      margin: const EdgeInsets.only(right: 6),
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0x14FE3434),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'BLOCKED',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFFFE3434),
                                        ),
                                      ),
                                    ),
                                  const Icon(Icons.arrow_drop_down, color: AppTheme.textMuted),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Date Block Toggle Card (Immediate DB Persistence ON/OFF)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _isBlocked ? const Color(0x14FE3434) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _isBlocked ? const Color(0x40FE3434) : const Color(0xFFE2E8F0)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      _isBlocked ? Icons.block_rounded : Icons.check_circle_outline_rounded,
                                      color: _isBlocked ? const Color(0xFFFE3434) : const Color(0xFFFE3434),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _isBlocked
                                                ? 'Date Blocked (Unavailable / Holiday)'
                                                : 'Doctor Available on this date',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                              color: _isBlocked ? const Color(0xFFFE3434) : const Color(0xFFFE3434),
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            _isTogglingBlock
                                                ? 'Saving blocked date status to database...'
                                                : (_isBlocked
                                                    ? 'Toggle OFF to unblock and reopen slots'
                                                    : 'Toggle ON to block date immediately'),
                                            style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_isTogglingBlock)
                                      const Padding(
                                        padding: EdgeInsets.only(right: 8),
                                        child: SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        ),
                                      ),
                                    Switch(
                                      key: const Key('date_blocked_toggle_switch'),
                                      value: _isBlocked,
                                      activeColor: const Color(0xFFFE3434),
                                      onChanged: _isTogglingBlock ? null : _handleToggleDateBlocked,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  key: const Key('blocked_reason_input'),
                                  controller: _blockedReasonController,
                                  decoration: InputDecoration(
                                    labelText: 'Holiday / Leave Reason',
                                    hintText: 'Enter reason (e.g. Weekly Off, Conference, Holiday)',
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  ),
                                  style: const TextStyle(fontSize: 12),
                                ),
                                if (_existingAppointmentsOnDate > 0) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0x14FE3434),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: const Color(0x40FE3434)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.info_outline_rounded, size: 15, color: Color(0xFFFE3434)),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            '$_existingAppointmentsOnDate existing booking(s) on this date will be preserved safely.',
                                            style: const TextStyle(fontSize: 11, color: Color(0xFFFE3434), fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          if (_activeTabIndex == 1) ...[
                            // Visual Doctor Calendar & Multi-Date Selector
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Doctor Calendar (Tap date to inspect or multi-select)',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (_multiBlockSelection.isNotEmpty)
                                  TextButton.icon(
                                    key: const Key('block_multiple_dates_btn'),
                                    onPressed: _isTogglingBlock ? null : _handleBlockMultipleDates,
                                    icon: const Icon(Icons.block_rounded, size: 15, color: Color(0xFFFE3434)),
                                    label: Text(
                                      'Block (${_multiBlockSelection.length}) Dates',
                                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFFFE3434)),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Container(
                              key: const Key('doctor_block_calendar_grid'),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: List.generate(21, (idx) {
                                  final now = DateTime.now();
                                  final dt = DateTime(now.year, now.month, now.day).add(Duration(days: idx));
                                  final dKey = _formatDateIso(dt);
                                  final isCurrentlySelected = dKey == dateStr;
                                  final isDateBlocked = blockedDateSet.contains(dKey);
                                  final inMultiSelect = _multiBlockSelection.contains(dKey);
                                  const wdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                                  final wday = wdays[dt.weekday - 1];

                                  return InkWell(
                                    key: Key('doctor_calendar_cell_$dKey'),
                                    onTap: () {
                                      setState(() {
                                        _selectedDate = dt;
                                      });
                                      _loadAvailabilityForSelectedDoctorAndDate();
                                    },
                                    onLongPress: isDateBlocked
                                        ? null
                                        : () {
                                            setState(() {
                                              if (inMultiSelect) {
                                                _multiBlockSelection.remove(dKey);
                                              } else {
                                                _multiBlockSelection.add(dKey);
                                              }
                                            });
                                          },
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      width: 68,
                                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                                      decoration: BoxDecoration(
                                        color: isDateBlocked
                                            ? const Color(0x14FE3434)
                                            : inMultiSelect
                                                ? const Color(0x14FE3434)
                                                : isCurrentlySelected
                                                    ? AppTheme.primaryBlue
                                                    : Colors.white,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: isCurrentlySelected
                                              ? AppTheme.primaryBlue
                                              : isDateBlocked
                                                  ? const Color(0xFFFE3434)
                                                  : inMultiSelect
                                                      ? const Color(0xFFFE3434)
                                                      : const Color(0xFFE2E8F0),
                                          width: isCurrentlySelected ? 2 : 1,
                                        ),
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            wday,
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: isCurrentlySelected && !isDateBlocked
                                                  ? Colors.white.withValues(alpha: 0.9)
                                                  : (isDateBlocked ? const Color(0xFFFE3434) : AppTheme.textMuted),
                                            ),
                                          ),
                                          Text(
                                            '${dt.day}/${dt.month}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: isCurrentlySelected && !isDateBlocked
                                                  ? Colors.white
                                                  : (isDateBlocked ? const Color(0xFFFE3434) : AppTheme.textDark),
                                            ),
                                          ),
                                          Text(
                                            isDateBlocked ? 'Blocked' : (inMultiSelect ? 'Queued' : 'Open'),
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w700,
                                              color: isCurrentlySelected && !isDateBlocked
                                                  ? Colors.white
                                                  : (isDateBlocked
                                                      ? const Color(0xFFFE3434)
                                                      : (inMultiSelect ? const Color(0xFFFE3434) : const Color(0xFFFE3434))),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Tip: Long-press open dates or add the selected date to block multiple dates at once.',
                                    style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
                                  ),
                                ),
                                if (!blockedDateSet.contains(dateStr))
                                  TextButton(
                                    key: const Key('queue_multi_block_date_btn'),
                                    onPressed: () {
                                      setState(() {
                                        if (_multiBlockSelection.contains(dateStr)) {
                                          _multiBlockSelection.remove(dateStr);
                                        } else {
                                          _multiBlockSelection.add(dateStr);
                                        }
                                      });
                                    },
                                    child: Text(
                                      _multiBlockSelection.contains(dateStr) ? 'Remove from Batch' : '+ Select for Batch',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // Previously Blocked Dates List
                            Text(
                              'Previously Blocked Dates (${_blockedDates.length})',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                            ),
                            const SizedBox(height: 8),
                            if (_blockedDates.isEmpty)
                              Container(
                                key: const Key('blocked_dates_empty_state'),
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: const Text(
                                  'No dates are currently blocked. Select a date above and toggle "Date Blocked" ON to mark a holiday.',
                                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                ),
                              )
                            else
                              Column(
                                key: const Key('blocked_dates_list'),
                                children: _blockedDates.map((b) {
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: const Color(0x14FE3434),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0x40FE3434)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.event_busy_rounded, size: 18, color: Color(0xFFFE3434)),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                b.date,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12.5,
                                                  color: Color(0xFFFE3434),
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              Text(
                                                b.blockedReason?.isNotEmpty == true
                                                    ? b.blockedReason!
                                                    : 'Doctor on Leave / Clinic Closed',
                                                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        TextButton.icon(
                                          key: Key('unblock_date_btn_${b.date}'),
                                          onPressed: _isTogglingBlock ? null : () => _handleUnblockSpecificDate(b.date),
                                          icon: const Icon(Icons.lock_open_rounded, size: 15, color: Color(0xFFFE3434)),
                                          label: const Text(
                                            'Unblock',
                                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFFFE3434)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                          ] else ...[
                            // 2. Working Days Selection (Tab 0: Working Days & Slots)
                            const Text('Configured Working Days', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark)),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: _allWeekDays.map((day) {
                                final isSelected = _selectedWorkingDays.contains(day);
                                return FilterChip(
                                  key: Key('working_day_chip_$day'),
                                  label: Text(
                                    day,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      color: isSelected ? Colors.white : AppTheme.textDark,
                                    ),
                                  ),
                                  selected: isSelected,
                                  selectedColor: AppTheme.primaryBlue,
                                  backgroundColor: const Color(0xFFF1F5F9),
                                  checkmarkColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  onSelected: (selected) {
                                    setState(() {
                                      if (selected) {
                                        if (!_selectedWorkingDays.contains(day)) {
                                          _selectedWorkingDays.add(day);
                                        }
                                      } else {
                                        if (_selectedWorkingDays.length > 1) {
                                          _selectedWorkingDays.remove(day);
                                        }
                                      }
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 16),

                            if (!_isBlocked) ...[
                              // 5. Hours & Slot Duration
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('Start Time', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textMuted)),
                                        const SizedBox(height: 4),
                                        DropdownButtonFormField<String>(
                                          key: const Key('schedule_start_time_dropdown'),
                                          value: _startTime,
                                          isExpanded: true,
                                          decoration: InputDecoration(
                                            filled: true,
                                            fillColor: const Color(0xFFF8FAFC),
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                          items: _dropdownOptions(_startTimes, _startTime)
                                              .map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 12))))
                                              .toList(),
                                          onChanged: (val) {
                                            setState(() => _startTime = val ?? _startTime);
                                            _generateSlots();
                                          },
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
                                          key: const Key('schedule_end_time_dropdown'),
                                          value: _endTime,
                                          isExpanded: true,
                                          decoration: InputDecoration(
                                            filled: true,
                                            fillColor: const Color(0xFFF8FAFC),
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                          items: _dropdownOptions(_endTimes, _endTime)
                                              .map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 12))))
                                              .toList(),
                                          onChanged: (val) {
                                            setState(() => _endTime = val ?? _endTime);
                                            _generateSlots();
                                          },
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
                                          key: const Key('schedule_duration_dropdown'),
                                          value: [15, 30, 45, 60].contains(_slotDuration) ? _slotDuration : 30,
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
                                          onChanged: (val) {
                                            setState(() => _slotDuration = val ?? 30);
                                            _generateSlots();
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // 6. Break Times Configuration (Excludes Break Period from Slots)
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
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
                                              Icon(Icons.coffee_rounded, size: 18, color: _hasBreak ? AppTheme.primaryBlue : AppTheme.textMuted),
                                              const SizedBox(width: 8),
                                              Flexible(
                                                child: Text(
                                                  'Include Break / Lunch Hours',
                                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: _hasBreak ? AppTheme.textDark : AppTheme.textMuted),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Switch(
                                          key: const Key('schedule_break_switch'),
                                          value: _hasBreak,
                                          activeColor: AppTheme.primaryBlue,
                                          onChanged: (val) {
                                            setState(() => _hasBreak = val);
                                            _generateSlots();
                                          },
                                        ),
                                      ],
                                    ),
                                    if (_hasBreak) ...[
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: DropdownButtonFormField<String>(
                                              key: const Key('schedule_break_start_dropdown'),
                                              value: _breakStartTime,
                                              decoration: InputDecoration(
                                                labelText: 'Break Start',
                                                filled: true,
                                                fillColor: Colors.white,
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                              ),
                                              items: _dropdownOptions(_breakStartTimes, _breakStartTime)
                                                  .map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 12))))
                                                  .toList(),
                                              onChanged: (val) {
                                                setState(() => _breakStartTime = val ?? _breakStartTime);
                                                _generateSlots();
                                              },
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: DropdownButtonFormField<String>(
                                              key: const Key('schedule_break_end_dropdown'),
                                              value: _breakEndTime,
                                              decoration: InputDecoration(
                                                labelText: 'Break End',
                                                filled: true,
                                                fillColor: Colors.white,
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                              ),
                                              items: _dropdownOptions(_breakEndTimes, _breakEndTime)
                                                  .map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 12))))
                                                  .toList(),
                                              onChanged: (val) {
                                                setState(() => _breakEndTime = val ?? _breakEndTime);
                                                _generateSlots();
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),

                              // 7. Batch Schedule Across Next 14 Days Checkbox
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: _applyBatchWorkingDays ? const Color(0x14012A58) : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: _applyBatchWorkingDays ? const Color(0x40012A58) : const Color(0xFFE2E8F0)),
                                ),
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: _applyBatchWorkingDays,
                                      activeColor: AppTheme.primaryBlue,
                                      onChanged: (val) => setState(() => _applyBatchWorkingDays = val ?? false),
                                    ),
                                    const SizedBox(width: 6),
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Apply schedule to selected working days for next 14 days', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                          Text('Synchronizes recurring hours across upcoming weeks', style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
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
                                      style: const TextStyle(color: Color(0xFFFE3434), fontWeight: FontWeight.bold, fontSize: 11),
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
                                          color: isBooked ? const Color(0xFFFE3434) : const Color(0xFF012A58),
                                        ),
                                      ),
                                      backgroundColor: isBooked ? const Color(0x14FE3434) : const Color(0x14012A58),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        side: BorderSide(color: isBooked ? const Color(0x40FE3434) : const Color(0x40012A58)),
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
                          ],

                          if (_statusMessage != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              key: const Key('slot_dialog_status_banner'),
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: !_statusIsError ? const Color(0x14012A58) : const Color(0x14FE3434),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: !_statusIsError ? const Color(0x40012A58) : const Color(0x40FE3434)),
                              ),
                              child: Text(
                                _statusMessage!,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: !_statusIsError ? const Color(0xFF012A58) : const Color(0xFFFE3434),
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
                      child: Text(_activeTabIndex == 1 ? 'Done' : 'Cancel'),
                    ),
                  ),
                  if (_activeTabIndex == 0) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        key: const Key('publish_doctor_schedule_btn'),
                        onPressed: _isSaving ? null : _saveAvailability,
                        icon: _isSaving
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save_rounded, size: 18),
                        label: Text(
                          _isSaving ? 'Publishing...' : 'Publish Doctor Schedule',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

