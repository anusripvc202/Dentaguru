import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../../core/constants/booking_rules_config.dart';
import '../../../../core/models/referral_model.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/theme/app_theme.dart';

class DoctorVisitsCalendarSection extends StatefulWidget {
  final String doctorId;
  final String doctorName;
  final String doctorSpecialty;
  final List<PatientConsultationRequest> assignedAppointments;
  final List<PatientReferral> receivedReferrals;
  final DateTime? initialSelectedDate;
  final ValueChanged<DateTime>? onDateSelected;
  final void Function(PatientConsultationRequest request)? onOpenConsultationDetails;
  final void Function(PatientConsultationRequest request)? onOpenPrescription;
  final bool canViewPatientContact;
  final bool canAccessConsultationDetails;
  final bool canAccessPrescription;

  const DoctorVisitsCalendarSection({
    super.key,
    required this.doctorId,
    required this.doctorName,
    this.doctorSpecialty = 'General Medicine',
    required this.assignedAppointments,
    required this.receivedReferrals,
    this.initialSelectedDate,
    this.onDateSelected,
    this.onOpenConsultationDetails,
    this.onOpenPrescription,
    this.canViewPatientContact = true,
    this.canAccessConsultationDetails = true,
    this.canAccessPrescription = true,
  });

  @override
  State<DoctorVisitsCalendarSection> createState() => _DoctorVisitsCalendarSectionState();
}

class _DoctorVisitsCalendarSectionState extends State<DoctorVisitsCalendarSection> {
  late DateTime _selectedDate;
  late DateTime _displayedMonth;
  String _selectedTypeFilter = 'All'; // 'All' | 'In-Person' | 'Online'
  String _selectedStatusFilter = 'All'; // 'All' | 'Completed' | 'Pending' | 'Cancelled' | 'No-Show'

  Map<String, dynamic>? _remoteCalendarData;
  bool _isLoadingRemote = false;

  static const List<String> _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static const List<String> _weekdayHeaders = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  void initState() {
    super.initState();
    final base = widget.initialSelectedDate ?? (BookingRulesConfig.debugNowOverride ?? DateTime.now());
    _selectedDate = DateTime(base.year, base.month, base.day);
    _displayedMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
    _fetchCalendarFromBackend();
  }

  @override
  void didUpdateWidget(covariant DoctorVisitsCalendarSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSelectedDate != null &&
        oldWidget.initialSelectedDate != widget.initialSelectedDate) {
      final d = widget.initialSelectedDate!;
      final clean = DateTime(d.year, d.month, d.day);
      if (_formatYmd(clean) != _formatYmd(_selectedDate)) {
        _selectedDate = clean;
        _displayedMonth = DateTime(clean.year, clean.month, 1);
        _fetchCalendarFromBackend();
      }
    } else if (oldWidget.doctorId != widget.doctorId) {
      _fetchCalendarFromBackend();
    }
  }

  String _formatYmd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _formatYm(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

  Future<void> _fetchCalendarFromBackend() async {
    if (widget.doctorId.trim().isEmpty) return;
    setState(() => _isLoadingRemote = true);
    final res = await ApiService().fetchDoctorVisitsCalendar(
      doctorId: widget.doctorId,
      date: _formatYmd(_selectedDate),
      month: _formatYm(_displayedMonth),
      consultationType: _selectedTypeFilter,
      status: _selectedStatusFilter == 'All' ? null : _selectedStatusFilter.toUpperCase().replaceAll('-', '_'),
    );
    if (!mounted) return;
    setState(() {
      _isLoadingRemote = false;
      if (res['success'] == true) {
        _remoteCalendarData = res;
      } else {
        _remoteCalendarData = null;
      }
    });
  }

  void _selectDate(DateTime date) {
    final clean = DateTime(date.year, date.month, date.day);
    setState(() {
      _selectedDate = clean;
      _displayedMonth = DateTime(clean.year, clean.month, 1);
    });
    widget.onDateSelected?.call(clean);
    _fetchCalendarFromBackend();
  }

  void _changeMonth(int deltaMonths) {
    final nextMonth = DateTime(_displayedMonth.year, _displayedMonth.month + deltaMonths, 1);
    setState(() {
      _displayedMonth = nextMonth;
    });
    _fetchCalendarFromBackend();
  }

  void _jumpToToday() {
    final now = BookingRulesConfig.debugNowOverride ?? DateTime.now();
    _selectDate(DateTime(now.year, now.month, now.day));
  }

  Future<void> _pickCustomDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime(2030, 12, 31),
    );
    if (picked != null && mounted) {
      _selectDate(picked);
    }
  }

  /// Classifies a local [PatientConsultationRequest] consistently with backend `_classifyCalendarAppointment`.
  ({
    String rawStatus,
    bool isCompleted,
    bool isCancelled,
    bool isNoShow,
    bool isInProgress,
    bool isPending,
    bool actuallyVisited,
    String consultType,
    bool isOnline,
    bool isInPerson,
  }) _classifyLocalRequest(PatientConsultationRequest req) {
    final rawStatus = req.status.trim().toUpperCase();
    final isCompleted = rawStatus == 'COMPLETED';
    final isCancelled = rawStatus == 'CANCELLED' || rawStatus == 'CANCELED' || rawStatus == 'REJECTED';
    final isNoShow = rawStatus == 'NO_SHOW' || rawStatus == 'NOSHOW' || rawStatus == 'NO-SHOW';
    final isInProgress = rawStatus == 'IN_PROGRESS' || rawStatus == 'IN PROGRESS' || rawStatus == 'STARTED';
    final isPending = !isCompleted && !isCancelled && !isNoShow;
    final actuallyVisited = !isCancelled &&
        !isNoShow &&
        (isCompleted ||
            isInProgress ||
            (req.actualStartAt != null && req.actualStartAt!.trim().isNotEmpty) ||
            (req.actualEndAt != null && req.actualEndAt!.trim().isNotEmpty));
    final consultType = BookingRulesConfig.normalizeConsultationMode(
      req.consultationMode ?? req.problemCategory,
    );
    final isOnline = consultType == 'Online';
    return (
      rawStatus: rawStatus,
      isCompleted: isCompleted,
      isCancelled: isCancelled,
      isNoShow: isNoShow,
      isInProgress: isInProgress,
      isPending: isPending,
      actuallyVisited: actuallyVisited,
      consultType: consultType,
      isOnline: isOnline,
      isInPerson: !isOnline,
    );
  }

  String _requestYmd(PatientConsultationRequest req) {
    if (req.confirmedDate != null && req.confirmedDate!.trim().isNotEmpty) {
      return ApiService.toAsiaKolkataYmd(req.confirmedDate!);
    }
    return ApiService.toAsiaKolkataYmd(req.submittedAt);
  }

  String _uniquePatientKey(PatientConsultationRequest req) {
    final pid = (req.patientId ?? '').trim();
    if (pid.isNotEmpty) return 'id:$pid';
    final digits = req.patientPhone.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 10) return 'ph:${digits.substring(digits.length - 10)}';
    return 'appt:${req.id}';
  }

  Map<String, dynamic> _computeEffectiveAggregation() {
    if (_remoteCalendarData != null && _remoteCalendarData!['success'] == true) {
      return _remoteCalendarData!;
    }

    final targetYmd = _formatYmd(_selectedDate);
    final targetYm = _formatYm(_displayedMonth);

    // Filter strictly to appointments assigned to this doctor
    final docIdClean = widget.doctorId.trim();
    final docNameClean = widget.doctorName
        .replaceAll(RegExp(r'^dr\.?\s*', caseSensitive: false), '')
        .trim()
        .toLowerCase();

    final ownAppointments = widget.assignedAppointments.where((req) {
      if (docIdClean.isNotEmpty &&
          req.assignedDoctorId != null &&
          req.assignedDoctorId!.trim().isNotEmpty) {
        return req.assignedDoctorId!.trim() == docIdClean;
      }
      if (docNameClean.isNotEmpty &&
          req.assignedDoctorName != null &&
          req.assignedDoctorName!.trim().isNotEmpty) {
        final rDoc = req.assignedDoctorName!
            .replaceAll(RegExp(r'^dr\.?\s*', caseSensitive: false), '')
            .trim()
            .toLowerCase();
        return rDoc == docNameClean;
      }
      return true;
    }).toList();

    final ownReferrals = widget.receivedReferrals.where((ref) {
      if (docIdClean.isNotEmpty && ref.doctorId.trim().isNotEmpty) {
        return ref.doctorId.trim() == docIdClean;
      }
      if (docNameClean.isNotEmpty && ref.doctorName.trim().isNotEmpty) {
        final rDoc = ref.doctorName
            .replaceAll(RegExp(r'^dr\.?\s*', caseSensitive: false), '')
            .trim()
            .toLowerCase();
        return rDoc == docNameClean;
      }
      return true;
    }).toList();

    // Build referral tracking entries (strictly separate from completed visits unless an appointment confirms it)
    final referralByPatientId = <String, Map<String, dynamic>>{};
    final referralByPhone10 = <String, Map<String, dynamic>>{};
    final allReferralEntries = <Map<String, dynamic>>[];

    for (final ref in ownReferrals) {
      final refYmd = ApiService.toAsiaKolkataYmd(ref.referralDate);
      final refPid = (ref.referredPatientId ?? '').trim();
      final refPh10 = ref.referredPatientMobile.replaceAll(RegExp(r'\D'), '');
      final cleanPh10 = refPh10.length >= 10 ? refPh10.substring(refPh10.length - 10) : refPh10;

      final matchedAppts = ownAppointments.where((a) {
        final aPid = (a.patientId ?? '').trim();
        final aDigits = a.patientPhone.replaceAll(RegExp(r'\D'), '');
        final aPh10 = aDigits.length >= 10 ? aDigits.substring(aDigits.length - 10) : aDigits;

        if (refPid.isNotEmpty && aPid.isNotEmpty) return refPid == aPid;
        if (cleanPh10.length == 10 && aPh10.length == 10) return cleanPh10 == aPh10;
        return false;
      }).toList();

      final nonCancelled = matchedAppts.where((a) {
        final cls = _classifyLocalRequest(a);
        return !cls.isCancelled;
      }).toList();
      final completedAppt = nonCancelled.where((a) => _classifyLocalRequest(a).isCompleted).firstOrNull;
      final activeAppt = completedAppt ?? nonCancelled.firstOrNull;

      final entry = <String, dynamic>{
        'referralId': ref.id,
        'referredPatientId': ref.referredPatientId,
        'referredPatientName': ref.referredPatientName,
        'referredPatientMobile': ref.referredPatientMobile,
        'referringPatientId': ref.referrerPatientId,
        'referringPatientName': ref.referrerPatientName,
        'referringPatientPhone': ref.referrerPatientPhone,
        'isReferredByPatient': !ref.referrerPatientName.toLowerCase().startsWith('dr'),
        'referredDoctorId': ref.doctorId,
        'referredDoctorName': ref.doctorName,
        'specialty': ref.requiredSpecialist.isNotEmpty ? ref.requiredSpecialist : ref.doctorSpecialty,
        'referralDate': refYmd,
        'referralStatus': ref.status,
        'hasBookedAppointment': nonCancelled.isNotEmpty,
        'bookedAppointmentId': activeAppt?.id,
        'bookedAppointmentDate': activeAppt != null ? _requestYmd(activeAppt) : null,
        'bookedAppointmentStatus': activeAppt?.status,
        'hasCompletedConsultation': completedAppt != null,
      };
      allReferralEntries.add(entry);
      if (refPid.isNotEmpty) referralByPatientId[refPid] = entry;
      if (cleanPh10.length == 10) referralByPhone10[cleanPh10] = entry;
    }

    // Monthly calendar map
    final monthlyCalendar = <String, Map<String, dynamic>>{};
    Map<String, dynamic> ensureDay(String ymd) {
      return monthlyCalendar.putIfAbsent(
        ymd,
        () => <String, dynamic>{
          'date': ymd,
          'totalAppointments': 0,
          'actualPatientVisits': 0,
          'completedConsultations': 0,
          'pendingConsultations': 0,
          'cancelledAppointments': 0,
          'noShowAppointments': 0,
          'onlineConsultations': 0,
          'inPersonConsultations': 0,
          'patientReferralsReceived': 0,
          'hasCompleted': false,
          'hasPending': false,
          'hasCancelled': false,
          'hasNoShow': false,
          'hasReferrals': false,
          '_visitedSet': <String>{},
        },
      );
    }

    for (final req in ownAppointments) {
      final ymd = _requestYmd(req);
      if (!ymd.startsWith(targetYm)) continue;
      final bucket = ensureDay(ymd);
      final cls = _classifyLocalRequest(req);
      bucket['totalAppointments'] = (bucket['totalAppointments'] as int) + 1;
      if (cls.actuallyVisited) {
        (bucket['_visitedSet'] as Set<String>).add(_uniquePatientKey(req));
      }
      if (cls.isCompleted) {
        bucket['completedConsultations'] = (bucket['completedConsultations'] as int) + 1;
        bucket['hasCompleted'] = true;
      } else if (cls.isCancelled) {
        bucket['cancelledAppointments'] = (bucket['cancelledAppointments'] as int) + 1;
        bucket['hasCancelled'] = true;
      } else if (cls.isNoShow) {
        bucket['noShowAppointments'] = (bucket['noShowAppointments'] as int) + 1;
        bucket['hasNoShow'] = true;
      } else if (cls.isPending) {
        bucket['pendingConsultations'] = (bucket['pendingConsultations'] as int) + 1;
        bucket['hasPending'] = true;
      }
      if (cls.isOnline) {
        bucket['onlineConsultations'] = (bucket['onlineConsultations'] as int) + 1;
      } else {
        bucket['inPersonConsultations'] = (bucket['inPersonConsultations'] as int) + 1;
      }
    }

    for (final refEntry in allReferralEntries) {
      final ymd = (refEntry['referralDate'] ?? '').toString();
      if (!ymd.startsWith(targetYm)) continue;
      final bucket = ensureDay(ymd);
      bucket['patientReferralsReceived'] = (bucket['patientReferralsReceived'] as int) + 1;
      bucket['hasReferrals'] = true;
    }

    for (final bucket in monthlyCalendar.values) {
      bucket['actualPatientVisits'] = (bucket['_visitedSet'] as Set<String>).length;
      bucket.remove('_visitedSet');
    }

    // Selected Date visits & stats
    final apptsOnSelectedDate = ownAppointments.where((req) {
      if (_requestYmd(req) != targetYmd) return false;
      final cls = _classifyLocalRequest(req);
      if (_selectedTypeFilter != 'All' && cls.consultType != _selectedTypeFilter) {
        return false;
      }
      if (_selectedStatusFilter != 'All') {
        if (_selectedStatusFilter == 'Completed' && !cls.isCompleted) return false;
        if (_selectedStatusFilter == 'Pending' && !cls.isPending) return false;
        if (_selectedStatusFilter == 'Cancelled' && !cls.isCancelled) return false;
        if (_selectedStatusFilter == 'No-Show' && !cls.isNoShow) return false;
      }
      return true;
    }).toList();

    final visitedOnDate = <String>{};
    int completedCount = 0;
    int pendingCount = 0;
    int cancelledCount = 0;
    int noShowCount = 0;
    int onlineCount = 0;
    int inPersonCount = 0;

    final visitsList = <Map<String, dynamic>>[];
    for (final req in apptsOnSelectedDate) {
      final cls = _classifyLocalRequest(req);
      if (cls.actuallyVisited) {
        visitedOnDate.add(_uniquePatientKey(req));
      }
      if (cls.isCompleted) {
        completedCount++;
      } else if (cls.isCancelled) {
        cancelledCount++;
      } else if (cls.isNoShow) {
        noShowCount++;
      } else if (cls.isPending) {
        pendingCount++;
      }
      if (cls.isOnline) {
        onlineCount++;
      } else {
        inPersonCount++;
      }

      final pid = (req.patientId ?? '').trim();
      final digits = req.patientPhone.replaceAll(RegExp(r'\D'), '');
      final ph10 = digits.length >= 10 ? digits.substring(digits.length - 10) : digits;
      final matchedRef = (pid.isNotEmpty ? referralByPatientId[pid] : null) ??
          (ph10.length == 10 ? referralByPhone10[ph10] : null);

      visitsList.add({
        'appointmentId': req.id,
        'id': req.id,
        'patientId': req.patientId,
        'patientName': req.patientName,
        'patientProfileImage': null,
        'patientPhone': widget.canViewPatientContact ? req.patientPhone : null,
        'patientCity': req.city,
        'consultationDate': targetYmd,
        'consultationTime': req.confirmedTimeSlot ?? '10:00 AM',
        'scheduledEndTime': req.scheduledEndTime,
        'consultationType': cls.consultType,
        'specialty': (req.assignedDoctorSpecialty != null && req.assignedDoctorSpecialty!.trim().isNotEmpty)
            ? req.assignedDoctorSpecialty!
            : widget.doctorSpecialty,
        'treatment': req.problemCategory,
        'status': cls.rawStatus,
        'actuallyVisited': cls.actuallyVisited,
        'referralSource': matchedRef != null
            ? {
                'referralId': matchedRef['referralId'],
                'referringPatientName': matchedRef['referringPatientName'],
                'referringPatientPhone': widget.canViewPatientContact ? matchedRef['referringPatientPhone'] : null,
                'referralDate': matchedRef['referralDate'],
                'referralStatus': matchedRef['referralStatus'],
              }
            : null,
        'canViewPatientContact': widget.canViewPatientContact,
        'canAccessConsultationDetails': widget.canAccessConsultationDetails,
        'canAccessPrescription': widget.canAccessPrescription,
        '_rawRequest': req,
      });
    }

    final referralsOnDate = allReferralEntries.where((r) => r['referralDate'] == targetYmd).toList();

    return {
      'success': true,
      'selectedDate': targetYmd,
      'month': targetYm,
      'monthlyCalendar': monthlyCalendar,
      'selectedDateStats': {
        'date': targetYmd,
        'totalAppointments': apptsOnSelectedDate.length,
        'actualPatientVisits': visitedOnDate.length,
        'completedConsultations': completedCount,
        'pendingConsultations': pendingCount,
        'cancelledAppointments': cancelledCount,
        'noShowAppointments': noShowCount,
        'onlineConsultations': onlineCount,
        'inPersonConsultations': inPersonCount,
        'patientReferralsReceived': referralsOnDate.length,
        'patientsReferredByOtherPatients':
            referralsOnDate.where((r) => r['isReferredByPatient'] == true).length,
        'totalReferralsAllTime': allReferralEntries.length,
      },
      'visits': visitsList,
      'referralsOnDate': referralsOnDate,
      'allReferrals': allReferralEntries,
    };
  }

  @override
  Widget build(BuildContext context) {
    final agg = _computeEffectiveAggregation();
    final stats = Map<String, dynamic>.from((agg['selectedDateStats'] as Map?) ?? const {});
    final monthlyCal = Map<String, dynamic>.from((agg['monthlyCalendar'] as Map?) ?? const {});
    final visits = ((agg['visits'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final referralsOnDate = ((agg['referralsOnDate'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final allReferrals = ((agg['allReferrals'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final displayedReferrals = referralsOnDate.isNotEmpty ? referralsOnDate : allReferrals;

    final selectedDateYmd = _formatYmd(_selectedDate);

    return Container(
      key: const Key('doctor_visits_calendar_section'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header + Today Shortcut + Date Picker
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: AppTheme.gsNavy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.calendar_month_rounded, color: AppTheme.gsNavy, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Doctor Visits & Referrals Calendar',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Selected Date: $selectedDateYmd (IST)',
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              TextButton(
                key: const Key('doctor_calendar_today_btn'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: _jumpToToday,
                child: const Text('Go to Today', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                key: const Key('doctor_calendar_date_picker_btn'),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
                tooltip: 'Select Date',
                icon: const Icon(Icons.edit_calendar_outlined, size: 18, color: AppTheme.gsNavy),
                onPressed: _pickCustomDate,
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Month Navigation Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  key: const Key('doctor_calendar_prev_month_btn'),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_left_rounded, color: AppTheme.gsNavy),
                  onPressed: () => _changeMonth(-1),
                ),
                Flexible(
                  child: Text(
                    '${_monthNames[_displayedMonth.month - 1]} ${_displayedMonth.year}',
                    key: const Key('doctor_calendar_month_label'),
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  key: const Key('doctor_calendar_next_month_btn'),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_right_rounded, color: AppTheme.gsNavy),
                  onPressed: () => _changeMonth(1),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Monthly Calendar Grid
          _buildMonthGrid(monthlyCal),
          const SizedBox(height: 8),

          // Legend for Calendar Activity Indicators
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _buildLegendDot(const Color(0xFF16A34A), 'Completed'),
              _buildLegendDot(const Color(0xFF2563EB), 'Pending / Confirmed'),
              _buildLegendDot(const Color(0xFFDC2626), 'Cancelled / No-Show'),
              _buildLegendDot(const Color(0xFF7C3AED), 'Referral'),
            ],
          ),
          const Divider(height: 22, color: Color(0xFFE2E8F0)),

          // Filters (Consultation Type & Status)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Text(
                  'Mode:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF475569)),
                ),
                const SizedBox(width: 6),
                ...['All', 'In-Person', 'Online'].map((mode) {
                  final selected = _selectedTypeFilter == mode;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      key: Key('doctor_calendar_mode_filter_$mode'),
                      label: Text(mode, style: const TextStyle(fontSize: 11.5)),
                      selected: selected,
                      selectedColor: AppTheme.gsNavy,
                      labelStyle: TextStyle(
                        color: selected ? Colors.white : const Color(0xFF334155),
                        fontWeight: FontWeight.w600,
                      ),
                      onSelected: (_) {
                        setState(() => _selectedTypeFilter = mode);
                        _fetchCalendarFromBackend();
                      },
                    ),
                  );
                }),
                const SizedBox(width: 8),
                const Text(
                  'Status:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF475569)),
                ),
                const SizedBox(width: 6),
                ...['All', 'Completed', 'Pending', 'Cancelled', 'No-Show'].map((st) {
                  final selected = _selectedStatusFilter == st;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      key: Key('doctor_calendar_status_filter_$st'),
                      label: Text(st, style: const TextStyle(fontSize: 11.5)),
                      selected: selected,
                      selectedColor: AppTheme.primaryBlue,
                      labelStyle: TextStyle(
                        color: selected ? Colors.white : const Color(0xFF334155),
                        fontWeight: FontWeight.w600,
                      ),
                      onSelected: (_) {
                        setState(() => _selectedStatusFilter = st);
                        _fetchCalendarFromBackend();
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 12),

          if (_isLoadingRemote)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: LinearProgressIndicator(minHeight: 2),
            ),

          // Selected Date Doctor Metrics Grid (All 10 Phase 1 Metrics)
          const Text(
            'Daily Visit & Referral Summary',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildStatTile(
                key: const Key('doctor_cal_stat_total_appointments'),
                label: 'Total Appts',
                value: '${stats['totalAppointments'] ?? 0}',
                color: AppTheme.gsNavy,
                icon: Icons.event_note_rounded,
              ),
              _buildStatTile(
                key: const Key('doctor_cal_stat_actual_visits'),
                label: 'Actual Visits',
                value: '${stats['actualPatientVisits'] ?? 0}',
                color: const Color(0xFF0F766E),
                icon: Icons.how_to_reg_rounded,
              ),
              _buildStatTile(
                key: const Key('doctor_cal_stat_completed'),
                label: 'Completed',
                value: '${stats['completedConsultations'] ?? 0}',
                color: const Color(0xFF16A34A),
                icon: Icons.check_circle_outline_rounded,
              ),
              _buildStatTile(
                key: const Key('doctor_cal_stat_pending'),
                label: 'Pending',
                value: '${stats['pendingConsultations'] ?? 0}',
                color: const Color(0xFF2563EB),
                icon: Icons.schedule_rounded,
              ),
              _buildStatTile(
                key: const Key('doctor_cal_stat_cancelled'),
                label: 'Cancelled',
                value: '${stats['cancelledAppointments'] ?? 0}',
                color: const Color(0xFFDC2626),
                icon: Icons.cancel_outlined,
              ),
              _buildStatTile(
                key: const Key('doctor_cal_stat_no_show'),
                label: 'No-Show',
                value: '${stats['noShowAppointments'] ?? 0}',
                color: const Color(0xFFD97706),
                icon: Icons.person_off_outlined,
              ),
              _buildStatTile(
                key: const Key('doctor_cal_stat_online'),
                label: 'Online',
                value: '${stats['onlineConsultations'] ?? 0}',
                color: const Color(0xFF0284C7),
                icon: Icons.videocam_outlined,
              ),
              _buildStatTile(
                key: const Key('doctor_cal_stat_in_person'),
                label: 'In-Person',
                value: '${stats['inPersonConsultations'] ?? 0}',
                color: const Color(0xFF4F46E5),
                icon: Icons.local_hospital_outlined,
              ),
              _buildStatTile(
                key: const Key('doctor_cal_stat_referrals_received'),
                label: 'Referrals Received',
                value: '${stats['patientReferralsReceived'] ?? 0}',
                color: const Color(0xFF7C3AED),
                icon: Icons.share_outlined,
              ),
              _buildStatTile(
                key: const Key('doctor_cal_stat_patient_to_patient_referrals'),
                label: 'Referred by Patients',
                value: '${stats['patientsReferredByOtherPatients'] ?? 0}',
                color: const Color(0xFF9333EA),
                icon: Icons.group_add_outlined,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Detailed Patient Visit List for Selected Date
          Row(
            children: [
              Expanded(
                child: Text(
                  'Patient Visits on $selectedDateYmd (${visits.length})',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (visits.isEmpty)
            Container(
              key: const Key('doctor_calendar_empty_visits_state'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.event_busy_outlined, size: 28, color: Color(0xFF94A3B8)),
                  const SizedBox(height: 6),
                  Text(
                    'No patient visits scheduled on $selectedDateYmd.',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF475569),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            Column(
              children: visits.map(_buildVisitCard).toList(),
            ),

          // Phase 4: Separate Referral Tracking Section
          const SizedBox(height: 16),
          Container(
            key: const Key('doctor_calendar_referrals_section'),
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFAF5FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE9D5FF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.swap_calls_rounded, size: 18, color: Color(0xFF7C3AED)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        referralsOnDate.isNotEmpty
                            ? 'Patient Referrals on $selectedDateYmd (${referralsOnDate.length})'
                            : 'Assigned Patient Referrals (${displayedReferrals.length})',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF581C87),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Tracked separately from actual patient visits until a booked consultation is completed.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF6B21A8)),
                ),
                const SizedBox(height: 8),
                if (displayedReferrals.isEmpty)
                  const Text(
                    'No patient referrals recorded for this doctor.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  )
                else
                  ...displayedReferrals.map(_buildReferralTrackingCard),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthGrid(Map<String, dynamic> monthlyCal) {
    final firstDayOfMonth = DateTime(_displayedMonth.year, _displayedMonth.month, 1);
    final daysInMonth = DateTime(_displayedMonth.year, _displayedMonth.month + 1, 0).day;
    final leadingEmpty = firstDayOfMonth.weekday - 1; // Mon = 0 .. Sun = 6
    final totalCells = leadingEmpty + daysInMonth;
    final selectedYmd = _formatYmd(_selectedDate);
    final todayYmd = _formatYmd(BookingRulesConfig.debugNowOverride ?? DateTime.now());

    return Column(
      children: [
        Row(
          children: _weekdayHeaders
              .map(
                (w) => Expanded(
                  child: Center(
                    child: Text(
                      w,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 6),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: totalCells,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: 1.05,
          ),
          itemBuilder: (context, index) {
            if (index < leadingEmpty) {
              return const SizedBox.shrink();
            }
            final dayNum = index - leadingEmpty + 1;
            final cellDate = DateTime(_displayedMonth.year, _displayedMonth.month, dayNum);
            final cellYmd = _formatYmd(cellDate);
            final isSelected = cellYmd == selectedYmd;
            final isToday = cellYmd == todayYmd;
            final dayInfo = monthlyCal[cellYmd] is Map
                ? Map<String, dynamic>.from(monthlyCal[cellYmd] as Map)
                : null;
            final totalAppts = int.tryParse('${dayInfo?['totalAppointments'] ?? 0}') ?? 0;
            final hasCompleted = dayInfo?['hasCompleted'] == true ||
                (int.tryParse('${dayInfo?['completedConsultations'] ?? 0}') ?? 0) > 0;
            final hasPending = dayInfo?['hasPending'] == true ||
                (int.tryParse('${dayInfo?['pendingConsultations'] ?? 0}') ?? 0) > 0;
            final hasCancelled = dayInfo?['hasCancelled'] == true ||
                dayInfo?['hasNoShow'] == true ||
                (int.tryParse('${dayInfo?['cancelledAppointments'] ?? 0}') ?? 0) > 0 ||
                (int.tryParse('${dayInfo?['noShowAppointments'] ?? 0}') ?? 0) > 0;
            final hasReferrals = dayInfo?['hasReferrals'] == true ||
                (int.tryParse('${dayInfo?['patientReferralsReceived'] ?? 0}') ?? 0) > 0;

            return InkWell(
              key: Key('doctor_calendar_day_$cellYmd'),
              onTap: () => _selectDate(cellDate),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.gsNavy
                      : totalAppts > 0
                          ? const Color(0xFFEFF6FF)
                          : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? AppTheme.gsNavy
                        : isToday
                            ? AppTheme.primaryBlue
                            : totalAppts > 0
                                ? const Color(0xFFBFDBFE)
                                : const Color(0xFFE2E8F0),
                    width: isToday || isSelected ? 1.4 : 1.0,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$dayNum',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected || totalAppts > 0 ? FontWeight.w800 : FontWeight.w600,
                        color: isSelected ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    if (hasCompleted || hasPending || hasCancelled || hasReferrals)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (hasCompleted) _dot(isSelected ? Colors.greenAccent : const Color(0xFF16A34A)),
                            if (hasPending) _dot(isSelected ? Colors.lightBlueAccent : const Color(0xFF2563EB)),
                            if (hasCancelled) _dot(isSelected ? Colors.orangeAccent : const Color(0xFFDC2626)),
                            if (hasReferrals) _dot(isSelected ? Colors.purpleAccent : const Color(0xFF7C3AED)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _dot(Color color) {
    return Container(
      width: 5,
      height: 5,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _buildLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF475569))),
      ],
    );
  }

  Widget _buildStatTile({
    required Key key,
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      key: key,
      width: 138,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  label,
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisitCard(Map<String, dynamic> visit) {
    final apptId = (visit['appointmentId'] ?? visit['id'] ?? '').toString();
    final patientName = (visit['patientName'] ?? 'Patient').toString();
    final consultDate = (visit['consultationDate'] ?? '').toString();
    final consultTime = (visit['consultationTime'] ?? '').toString();
    final consultType = (visit['consultationType'] ?? 'In-Person').toString();
    final specialty = (visit['specialty'] ?? widget.doctorSpecialty).toString();
    final statusRaw = (visit['status'] ?? 'PENDING').toString();
    final statusLabel = BookingRulesConfig.formatAppointmentStatusLabel(statusRaw);
    final actuallyVisited = visit['actuallyVisited'] == true;
    final phone = (visit['patientPhone'] ?? '').toString().trim();
    final refSource = visit['referralSource'] is Map
        ? Map<String, dynamic>.from(visit['referralSource'] as Map)
        : null;
    final rawReq = visit['_rawRequest'] is PatientConsultationRequest
        ? visit['_rawRequest'] as PatientConsultationRequest
        : null;

    return Container(
      key: Key('doctor_calendar_visit_card_$apptId'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildPatientAvatar(patientName, visit['patientProfileImage']),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$patientName • #$apptId',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '$consultDate at $consultTime',
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              _statusBadge(statusLabel, actuallyVisited),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _infoPill(
                consultType == 'Online' ? Icons.videocam_outlined : Icons.local_hospital_outlined,
                consultType,
                consultType == 'Online' ? const Color(0xFF0284C7) : const Color(0xFF4F46E5),
              ),
              _infoPill(Icons.medical_services_outlined, specialty, AppTheme.gsNavy),
              if (actuallyVisited)
                _infoPill(Icons.verified_user_outlined, 'Visited', const Color(0xFF0F766E)),
              if (widget.canViewPatientContact && phone.isNotEmpty)
                _infoPill(Icons.phone_outlined, phone, const Color(0xFF334155)),
            ],
          ),
          if (refSource != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF3E8FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_pin_circle_outlined, size: 14, color: Color(0xFF7C3AED)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Referred by: ${refSource['referringPatientName'] ?? 'Patient'}'
                      '${(refSource['referringPatientPhone'] ?? '').toString().isNotEmpty ? ' (${refSource['referringPatientPhone']})' : ''}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6B21A8),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (rawReq != null &&
              ((widget.canAccessConsultationDetails && widget.onOpenConsultationDetails != null) ||
                  (widget.canAccessPrescription && widget.onOpenPrescription != null))) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (widget.canAccessConsultationDetails && widget.onOpenConsultationDetails != null)
                  OutlinedButton.icon(
                    key: Key('doctor_calendar_visit_details_btn_$apptId'),
                    onPressed: () => widget.onOpenConsultationDetails!(rawReq),
                    icon: const Icon(Icons.description_outlined, size: 14),
                    label: const Text('Consultation Details', style: TextStyle(fontSize: 11.5)),
                  ),
                if (widget.canAccessPrescription && widget.onOpenPrescription != null)
                  OutlinedButton.icon(
                    key: Key('doctor_calendar_visit_rx_btn_$apptId'),
                    onPressed: () => widget.onOpenPrescription!(rawReq),
                    icon: const Icon(Icons.medication_outlined, size: 14),
                    label: const Text('E-Prescription', style: TextStyle(fontSize: 11.5)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReferralTrackingCard(Map<String, dynamic> ref) {
    final refId = (ref['referralId'] ?? ref['id'] ?? '').toString();
    final referredName = (ref['referredPatientName'] ?? 'Referred Patient').toString();
    final referringName = (ref['referringPatientName'] ?? 'Referring Patient').toString();
    final referringPhone = (ref['referringPatientPhone'] ?? '').toString();
    final docName = (ref['referredDoctorName'] ?? widget.doctorName).toString();
    final refDate = (ref['referralDate'] ?? '').toString();
    final refStatus = (ref['referralStatus'] ?? 'Pending').toString();
    final hasBooked = ref['hasBookedAppointment'] == true;
    final hasCompleted = ref['hasCompletedConsultation'] == true;

    return Container(
      key: Key('doctor_calendar_referral_card_$refId'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE9D5FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Referred: $referredName • By: $referringName${referringPhone.isNotEmpty && widget.canViewPatientContact ? ' ($referringPhone)' : ''}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3E8FF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  refStatus,
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF6B21A8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Doctor: $docName • Referral Date: $refDate',
            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _infoPill(
                hasBooked ? Icons.event_available_rounded : Icons.event_busy_outlined,
                hasBooked ? 'Booked Appointment: Yes' : 'Booked Appointment: No',
                hasBooked ? const Color(0xFF2563EB) : const Color(0xFF64748B),
              ),
              _infoPill(
                hasCompleted ? Icons.check_circle_outline_rounded : Icons.hourglass_bottom_rounded,
                hasCompleted ? 'Completed Visit: Yes' : 'Completed Visit: No',
                hasCompleted ? const Color(0xFF16A34A) : const Color(0xFFD97706),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPatientAvatar(String name, dynamic rawImage) {
    final str = (rawImage ?? '').toString().trim();
    if (str.isNotEmpty && str != 'null') {
      try {
        if (!str.startsWith('http')) {
          final clean = str.contains(',') ? str.split(',').last.trim() : str;
          final bytes = base64Decode(clean);
          if (bytes.isNotEmpty) {
            return CircleAvatar(radius: 18, backgroundImage: MemoryImage(bytes));
          }
        }
      } catch (_) {}
    }
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'P';
    return CircleAvatar(
      radius: 18,
      backgroundColor: AppTheme.gsNavy.withValues(alpha: 0.12),
      child: Text(
        initial,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.gsNavy),
      ),
    );
  }

  Widget _statusBadge(String label, bool actuallyVisited) {
    final upper = label.toUpperCase();
    Color bg = const Color(0xFFDBEAFE);
    Color fg = const Color(0xFF1E40AF);
    if (upper.contains('COMPLETED')) {
      bg = const Color(0xFFDCFCE7);
      fg = const Color(0xFF166534);
    } else if (upper.contains('CANCEL') || upper.contains('REJECT')) {
      bg = const Color(0xFFFEE2E2);
      fg = const Color(0xFF991B1B);
    } else if (upper.contains('NO-SHOW') || upper.contains('NO_SHOW')) {
      bg = const Color(0xFFFEF3C7);
      fg = const Color(0xFF92400E);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        label,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }

  Widget _infoPill(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
