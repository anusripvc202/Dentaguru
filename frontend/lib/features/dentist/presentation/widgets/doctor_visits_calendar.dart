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
  final bool embeddedInScreen;

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
    this.embeddedInScreen = false,
  });

  @override
  State<DoctorVisitsCalendarSection> createState() => _DoctorVisitsCalendarSectionState();
}

class _DoctorVisitsCalendarSectionState extends State<DoctorVisitsCalendarSection> {
  late DateTime _selectedDate;
  late DateTime _displayedMonth;
  String _calendarViewMode = 'Monthly'; // 'Monthly' | 'Weekly'
  String _selectedTypeFilter = 'All'; // 'All' | 'Online' | 'In-Person'
  String _selectedStatusFilter = 'All'; // 'All' | 'Pending' | 'Accepted' | 'Completed' | 'Rejected' | 'Rescheduled'
  bool _referredOnlyFilter = false;

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
      consultationType: _selectedTypeFilter == 'All' ? null : _selectedTypeFilter,
      status: _selectedStatusFilter == 'All' ? null : _selectedStatusFilter.toUpperCase().replaceAll('-', '_'),
      referredOnly: _referredOnlyFilter ? true : null,
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

  void _resetAllFilters() {
    setState(() {
      _selectedTypeFilter = 'All';
      _selectedStatusFilter = 'All';
      _referredOnlyFilter = false;
    });
    _fetchCalendarFromBackend();
  }

  bool get _hasActiveFilters =>
      _selectedTypeFilter != 'All' || _selectedStatusFilter != 'All' || _referredOnlyFilter;

  /// Classifies a local [PatientConsultationRequest] with strictly mutually exclusive status and consultation type flags.
  ({
    String rawStatus,
    bool isCompleted,
    bool isAccepted,
    bool isAwaitingPending,
    bool isRejected,
    bool isCancelledOnly,
    bool isCancelled,
    bool isNoShow,
    bool isRescheduled,
    bool isInProgress,
    bool actuallyVisited,
    String consultType,
    bool isOnline,
    bool isInPerson,
  }) _classifyLocalRequest(PatientConsultationRequest req) {
    final rawStatus = req.status.trim().toUpperCase();
    final isCompleted = rawStatus == 'COMPLETED';
    final isRejected = rawStatus == 'REJECTED' || rawStatus == 'DECLINED';
    final isCancelledOnly = rawStatus == 'CANCELLED' || rawStatus == 'CANCELED';
    final isCancelled = isCancelledOnly || isRejected;
    final isNoShow = rawStatus == 'NO_SHOW' || rawStatus == 'NOSHOW' || rawStatus == 'NO-SHOW';
    final isRescheduled = rawStatus == 'RESCHEDULED';
    final isInProgress = rawStatus == 'IN_PROGRESS' || rawStatus == 'IN PROGRESS' || rawStatus == 'STARTED';
    final isAccepted = rawStatus == 'ACCEPTED' ||
        rawStatus == 'CONFIRMED' ||
        rawStatus == 'APPROVED' ||
        rawStatus == 'DENTIST_ACCEPTED' ||
        isInProgress ||
        rawStatus == 'DELAYED';
    final isAwaitingPending = !isCompleted && !isCancelled && !isNoShow && !isRescheduled && !isAccepted;
    final actuallyVisited = !isCancelled &&
        !isNoShow &&
        (isCompleted ||
            isInProgress ||
            (req.actualStartAt != null && req.actualStartAt!.trim().isNotEmpty) ||
            (req.actualEndAt != null && req.actualEndAt!.trim().isNotEmpty));

    // Never assume consultation type — inspect explicit consultationMode first, then problemCategory
    final rawModeSource = (req.consultationMode != null && req.consultationMode!.trim().isNotEmpty)
        ? req.consultationMode!.trim()
        : req.problemCategory;
    final consultType = BookingRulesConfig.normalizeConsultationMode(rawModeSource);
    final isOnline = consultType == 'Online';
    return (
      rawStatus: rawStatus,
      isCompleted: isCompleted,
      isAccepted: isAccepted,
      isAwaitingPending: isAwaitingPending,
      isRejected: isRejected,
      isCancelledOnly: isCancelledOnly,
      isCancelled: isCancelled,
      isNoShow: isNoShow,
      isRescheduled: isRescheduled,
      isInProgress: isInProgress,
      actuallyVisited: actuallyVisited,
      consultType: consultType,
      isOnline: isOnline,
      isInPerson: !isOnline,
    );
  }

  String _formatCalendarStatusDisplay(String rawStatus) {
    final s = rawStatus.trim().toUpperCase();
    if (s == 'ACCEPTED' || s == 'CONFIRMED' || s == 'APPROVED' || s == 'DENTIST_ACCEPTED') {
      return 'Accepted';
    }
    if (s == 'COMPLETED') return 'Completed';
    if (s == 'REJECTED' || s == 'DECLINED') return 'Rejected';
    if (s == 'RESCHEDULED') return 'Rescheduled';
    if (s == 'CANCELLED' || s == 'CANCELED') return 'Cancelled';
    if (s == 'NO_SHOW' || s == 'NOSHOW' || s == 'NO-SHOW') return 'No-Show';
    if (s == 'IN_PROGRESS' || s == 'IN PROGRESS' || s == 'STARTED') return 'In Progress';
    if (s == 'DELAYED') return 'Delayed';
    return 'Pending';
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

  dynamic _lookupPatientProfileImage(PatientConsultationRequest req) {
    final allPatients = PatientProblemService().allPatients;
    if (allPatients.isEmpty) return null;
    final pid = (req.patientId ?? '').trim();
    final digits = req.patientPhone.replaceAll(RegExp(r'\D'), '');
    final ph10 = digits.length >= 10 ? digits.substring(digits.length - 10) : digits;

    for (final p in allPatients) {
      final pDigits = p.phone.replaceAll(RegExp(r'\D'), '');
      final pPh10 = pDigits.length >= 10 ? pDigits.substring(pDigits.length - 10) : pDigits;
      final matches = (pid.isNotEmpty && p.id == pid) || (ph10.length == 10 && pPh10 == ph10);
      if (matches) {
        if (p.photoBytes != null && p.photoBytes!.isNotEmpty) {
          return base64Encode(p.photoBytes!);
        }
        if (p.profileImageUrl != null && p.profileImageUrl!.trim().isNotEmpty) {
          return p.profileImageUrl!.trim();
        }
      }
    }
    return null;
  }

  Map<String, dynamic> _computeEffectiveAggregation() {
    if (_remoteCalendarData != null && _remoteCalendarData!['success'] == true) {
      return _remoteCalendarData!;
    }

    final targetYmd = _formatYmd(_selectedDate);
    final targetYm = _formatYm(_displayedMonth);

    // Filter strictly to appointments assigned to this doctor (fail closed)
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
      return false;
    }).toList();

    // Filter strictly to referrals assigned to this doctor and deduplicate by referral ID
    final seenRefIds = <String>{};
    final ownReferrals = widget.receivedReferrals.where((ref) {
      bool isMine = false;
      if (docIdClean.isNotEmpty && ref.doctorId.trim().isNotEmpty) {
        isMine = ref.doctorId.trim() == docIdClean;
      } else if (docNameClean.isNotEmpty && ref.doctorName.trim().isNotEmpty) {
        final rDoc = ref.doctorName
            .replaceAll(RegExp(r'^dr\.?\s*', caseSensitive: false), '')
            .trim()
            .toLowerCase();
        isMine = rDoc == docNameClean;
      }
      if (!isMine) return false;
      final rid = ref.id.trim();
      if (rid.isNotEmpty && !seenRefIds.add(rid)) return false;
      return true;
    }).toList();

    // Build referral tracking entries (strictly separate from appointments; never double-counted)
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

      final nonCancelled = matchedAppts.where((a) => !_classifyLocalRequest(a).isCancelled).toList();
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
        'clinicalComplaint': ref.clinicalComplaint,
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
          'acceptedAppointments': 0,
          'pendingAppointments': 0,
          'completedConsultations': 0,
          'rejectedAppointments': 0,
          'rescheduledAppointments': 0,
          'cancelledAppointments': 0,
          'noShowAppointments': 0,
          'onlineConsultations': 0,
          'inPersonConsultations': 0,
          'patientReferralsReceived': 0,
          'hasCompleted': false,
          'hasAccepted': false,
          'hasPending': false,
          'hasRejected': false,
          'hasRescheduled': false,
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
      } else if (cls.isRejected) {
        bucket['rejectedAppointments'] = (bucket['rejectedAppointments'] as int) + 1;
        bucket['hasRejected'] = true;
        bucket['hasCancelled'] = true;
      } else if (cls.isCancelledOnly) {
        bucket['cancelledAppointments'] = (bucket['cancelledAppointments'] as int) + 1;
        bucket['hasCancelled'] = true;
      } else if (cls.isNoShow) {
        bucket['noShowAppointments'] = (bucket['noShowAppointments'] as int) + 1;
        bucket['hasNoShow'] = true;
      } else if (cls.isRescheduled) {
        bucket['rescheduledAppointments'] = (bucket['rescheduledAppointments'] as int) + 1;
        bucket['hasRescheduled'] = true;
        bucket['hasPending'] = true;
      } else if (cls.isAccepted) {
        bucket['acceptedAppointments'] = (bucket['acceptedAppointments'] as int) + 1;
        bucket['hasAccepted'] = true;
        bucket['hasPending'] = true;
      } else if (cls.isAwaitingPending) {
        bucket['pendingAppointments'] = (bucket['pendingAppointments'] as int) + 1;
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

    // All appointments on selected date (used for accurate daily summary stats)
    final allApptsOnSelectedDate = ownAppointments.where((req) => _requestYmd(req) == targetYmd).toList();
    allApptsOnSelectedDate.sort((a, b) {
      final ma = BookingRulesConfig.parseClockSlotMinutes(a.confirmedTimeSlot ?? '') ?? 9999;
      final mb = BookingRulesConfig.parseClockSlotMinutes(b.confirmedTimeSlot ?? '') ?? 9999;
      return ma.compareTo(mb);
    });

    final visitedOnDate = <String>{};
    int completedCount = 0;
    int acceptedCount = 0;
    int pendingCount = 0;
    int rejectedCount = 0;
    int rescheduledCount = 0;
    int cancelledCount = 0;
    int noShowCount = 0;
    int onlineCount = 0;
    int inPersonCount = 0;
    int referredApptsCount = 0;

    final visitsList = <Map<String, dynamic>>[];

    for (final req in allApptsOnSelectedDate) {
      final cls = _classifyLocalRequest(req);
      if (cls.actuallyVisited) {
        visitedOnDate.add(_uniquePatientKey(req));
      }
      if (cls.isCompleted) {
        completedCount++;
      } else if (cls.isRejected) {
        rejectedCount++;
      } else if (cls.isCancelledOnly) {
        cancelledCount++;
      } else if (cls.isNoShow) {
        noShowCount++;
      } else if (cls.isRescheduled) {
        rescheduledCount++;
      } else if (cls.isAccepted) {
        acceptedCount++;
      } else if (cls.isAwaitingPending) {
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
      if (matchedRef != null) {
        referredApptsCount++;
      }

      // Apply UI filters to displayed visit cards
      if (_selectedTypeFilter != 'All' && cls.consultType != _selectedTypeFilter) {
        continue;
      }
      if (_selectedStatusFilter != 'All') {
        if (_selectedStatusFilter == 'Completed' && !cls.isCompleted) continue;
        if (_selectedStatusFilter == 'Accepted' && !cls.isAccepted) continue;
        if (_selectedStatusFilter == 'Pending' && !cls.isAwaitingPending) continue;
        if (_selectedStatusFilter == 'Rejected' && !cls.isRejected) continue;
        if (_selectedStatusFilter == 'Rescheduled' && !cls.isRescheduled) continue;
        if (_selectedStatusFilter == 'Cancelled' && !cls.isCancelledOnly) continue;
        if (_selectedStatusFilter == 'No-Show' && !cls.isNoShow) continue;
      }
      if (_referredOnlyFilter && matchedRef == null) {
        continue;
      }

      visitsList.add({
        'appointmentId': req.id,
        'id': req.id,
        'patientId': req.patientId,
        'patientName': req.patientName,
        'patientProfileImage': _lookupPatientProfileImage(req),
        'patientPhone': widget.canViewPatientContact ? req.patientPhone : null,
        'patientCity': req.city,
        'consultationDate': targetYmd,
        'consultationTime': (req.confirmedTimeSlot != null && req.confirmedTimeSlot!.trim().isNotEmpty)
            ? req.confirmedTimeSlot!.trim()
            : 'Time TBD',
        'scheduledEndTime': req.scheduledEndTime,
        'consultationType': cls.consultType,
        'specialty': (req.assignedDoctorSpecialty != null && req.assignedDoctorSpecialty!.trim().isNotEmpty)
            ? req.assignedDoctorSpecialty!
            : widget.doctorSpecialty,
        'clinicName': req.assignedDoctorClinic ?? '',
        'treatment': req.problemCategory,
        'problemDescription': req.problemDescription.trim().isNotEmpty
            ? req.problemDescription.trim()
            : req.problemCategory,
        'symptoms': req.symptoms.trim(),
        'status': cls.rawStatus,
        'actuallyVisited': cls.actuallyVisited,
        'isReferred': matchedRef != null,
        'referralSource': matchedRef != null
            ? {
                'referralId': matchedRef['referralId'],
                'referringPatientName': matchedRef['referringPatientName'],
                'referringPatientPhone': widget.canViewPatientContact ? matchedRef['referringPatientPhone'] : null,
                'referralDate': matchedRef['referralDate'],
                'referralStatus': matchedRef['referralStatus'],
                'clinicalComplaint': matchedRef['clinicalComplaint'],
              }
            : null,
        'canViewPatientContact': widget.canViewPatientContact,
        'canAccessConsultationDetails': widget.canAccessConsultationDetails,
        'canAccessPrescription': widget.canAccessPrescription,
        '_rawRequest': req,
      });
    }

    // Referrals strictly associated with the selected date (deduplicated)
    final referralsOnDate = allReferralEntries.where((r) => r['referralDate'] == targetYmd).toList();
    int acceptedRefs = 0;
    int pendingRefs = 0;
    int rejectedRefs = 0;
    int completedRefVisits = 0;
    for (final r in referralsOnDate) {
      final st = (r['referralStatus'] ?? 'Pending').toString().trim().toUpperCase();
      if (st == 'ACCEPTED' || st == 'CONFIRMED' || st == 'APPROVED') {
        acceptedRefs++;
      } else if (st == 'REJECTED' || st == 'DECLINED' || st == 'CANCELLED') {
        rejectedRefs++;
      } else if (st != 'COMPLETED') {
        pendingRefs++;
      }
      if (r['hasCompletedConsultation'] == true || st == 'COMPLETED') {
        completedRefVisits++;
      }
    }

    return {
      'success': true,
      'selectedDate': targetYmd,
      'month': targetYm,
      'monthlyCalendar': monthlyCalendar,
      'selectedDateStats': {
        'date': targetYmd,
        'totalAppointments': allApptsOnSelectedDate.length,
        'actualPatientVisits': visitedOnDate.length,
        'acceptedAppointments': acceptedCount,
        'pendingAppointments': pendingCount,
        'completedConsultations': completedCount,
        'rejectedAppointments': rejectedCount,
        'rescheduledAppointments': rescheduledCount,
        'cancelledAppointments': cancelledCount,
        'noShowAppointments': noShowCount,
        'onlineConsultations': onlineCount,
        'inPersonConsultations': inPersonCount,
        'referredAppointments': referredApptsCount,
        'patientReferralsReceived': referralsOnDate.length,
        'acceptedReferrals': acceptedRefs,
        'pendingReferrals': pendingRefs,
        'rejectedReferrals': rejectedRefs,
        'completedReferredVisits': completedRefVisits,
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

    final selectedDateYmd = _formatYmd(_selectedDate);
    final totalOnDate = int.tryParse('${stats['totalAppointments'] ?? 0}') ?? 0;

    return Container(
      key: const Key('doctor_visits_calendar_section'),
      width: double.infinity,
      padding: EdgeInsets.all(widget.embeddedInScreen ? 14 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
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
                      'Appointments Calendar',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Selected Date: $selectedDateYmd (IST)',
                      key: const Key('doctor_calendar_selected_date_label'),
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
                child: const Text('Today', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
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
                  tooltip: 'Previous Month',
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
                  tooltip: 'Next Month',
                  icon: const Icon(Icons.chevron_right_rounded, color: AppTheme.gsNavy),
                  onPressed: () => _changeMonth(1),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Calendar View Switcher (Monthly / Weekly)
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  key: const Key('doctor_calendar_mode_monthly'),
                  label: const Text('Monthly View', overflow: TextOverflow.ellipsis),
                  selected: _calendarViewMode == 'Monthly',
                  onSelected: (_) => setState(() => _calendarViewMode = 'Monthly'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  key: const Key('doctor_calendar_mode_weekly'),
                  label: const Text('Weekly View', overflow: TextOverflow.ellipsis),
                  selected: _calendarViewMode == 'Weekly',
                  onSelected: (_) => setState(() => _calendarViewMode = 'Weekly'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Monthly or Weekly Calendar Grid with Appointment Counts & Today Highlight
          if (_calendarViewMode == 'Weekly')
            _buildWeeklyStrip(monthlyCal)
          else
            _buildMonthGrid(monthlyCal),
          const SizedBox(height: 8),

          // Doctor Schedule Overview for Selected Date (Working Hours, Breaks, Blocked Times & Released Slots)
          _buildSelectedDateScheduleOverview(agg, selectedDateYmd),
          const SizedBox(height: 8),

          // Calendar Legend
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _buildLegendDot(const Color(0xFF16A34A), 'Completed'),
              _buildLegendDot(const Color(0xFF2563EB), 'Accepted / Pending'),
              _buildLegendDot(const Color(0xFFDC2626), 'Rejected / Cancelled'),
              _buildLegendDot(const Color(0xFF7C3AED), 'Referral'),
            ],
          ),
          const Divider(height: 22, color: Color(0xFFE2E8F0)),

          if (_isLoadingRemote)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(minHeight: 2),
            ),

          // Selected Date Daily Appointment Summary
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Daily Appointment Summary',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                selectedDateYmd,
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF64748B)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildStatTile(
                key: const Key('doctor_cal_stat_total_appointments'),
                label: 'Total Visits',
                value: '${stats['totalAppointments'] ?? 0}',
                color: AppTheme.gsNavy,
                icon: Icons.event_note_rounded,
              ),
              _buildStatTile(
                key: const Key('doctor_cal_stat_accepted'),
                label: 'Accepted',
                value: '${stats['acceptedAppointments'] ?? 0}',
                color: const Color(0xFF0284C7),
                icon: Icons.thumb_up_alt_outlined,
              ),
              _buildStatTile(
                key: const Key('doctor_cal_stat_pending'),
                label: 'Pending',
                value: '${stats['pendingAppointments'] ?? 0}',
                color: const Color(0xFFD97706),
                icon: Icons.schedule_rounded,
              ),
              _buildStatTile(
                key: const Key('doctor_cal_stat_completed'),
                label: 'Completed',
                value: '${stats['completedConsultations'] ?? 0}',
                color: const Color(0xFF16A34A),
                icon: Icons.check_circle_outline_rounded,
              ),
              _buildStatTile(
                key: const Key('doctor_cal_stat_rejected'),
                label: 'Rejected',
                value: '${stats['rejectedAppointments'] ?? 0}',
                color: const Color(0xFFDC2626),
                icon: Icons.block_rounded,
              ),
              _buildStatTile(
                key: const Key('doctor_cal_stat_rescheduled'),
                label: 'Rescheduled',
                value: '${stats['rescheduledAppointments'] ?? 0}',
                color: const Color(0xFF7C3AED),
                icon: Icons.update_rounded,
              ),
              _buildStatTile(
                key: const Key('doctor_cal_stat_online'),
                label: 'Online',
                value: '${stats['onlineConsultations'] ?? 0}',
                color: const Color(0xFF0369A1),
                icon: Icons.videocam_rounded,
              ),
              _buildStatTile(
                key: const Key('doctor_cal_stat_in_person'),
                label: 'In-Person',
                value: '${stats['inPersonConsultations'] ?? 0}',
                color: const Color(0xFF4F46E5),
                icon: Icons.local_hospital_rounded,
              ),
              _buildStatTile(
                key: const Key('doctor_cal_stat_actual_visits'),
                label: 'Unique Visited',
                value: '${stats['actualPatientVisits'] ?? 0}',
                color: const Color(0xFF0F766E),
                icon: Icons.how_to_reg_rounded,
              ),
              _buildStatTile(
                key: const Key('doctor_cal_stat_cancelled'),
                label: 'Cancelled',
                value: '${stats['cancelledAppointments'] ?? 0}',
                color: const Color(0xFFB91C1C),
                icon: Icons.cancel_outlined,
              ),
              _buildStatTile(
                key: const Key('doctor_cal_stat_no_show'),
                label: 'No-Show',
                value: '${stats['noShowAppointments'] ?? 0}',
                color: const Color(0xFFB45309),
                icon: Icons.person_off_outlined,
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Filters Bar: All, Pending, Accepted, Completed, Rejected, Rescheduled, Online, In-Person, Referred
          const Text(
            'Filter Appointments',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF475569)),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip(
                  key: const Key('doctor_calendar_filter_All'),
                  label: 'All',
                  selected: !_hasActiveFilters,
                  selectedColor: AppTheme.gsNavy,
                  onTap: _resetAllFilters,
                ),
                ...['Pending', 'Accepted', 'Completed', 'Rejected', 'Rescheduled'].map((st) {
                  final selected = _selectedStatusFilter == st;
                  return _buildFilterChip(
                    key: Key('doctor_calendar_status_filter_$st'),
                    label: st,
                    selected: selected,
                    selectedColor: AppTheme.gsNavy,
                    onTap: () {
                      setState(() => _selectedStatusFilter = selected ? 'All' : st);
                      _fetchCalendarFromBackend();
                    },
                  );
                }),
                _buildFilterChip(
                  key: const Key('doctor_calendar_mode_filter_Online'),
                  label: 'Online',
                  icon: Icons.videocam_rounded,
                  selected: _selectedTypeFilter == 'Online',
                  selectedColor: const Color(0xFF0369A1),
                  onTap: () {
                    setState(() => _selectedTypeFilter = _selectedTypeFilter == 'Online' ? 'All' : 'Online');
                    _fetchCalendarFromBackend();
                  },
                ),
                _buildFilterChip(
                  key: const Key('doctor_calendar_mode_filter_In-Person'),
                  label: 'In-Person',
                  icon: Icons.local_hospital_rounded,
                  selected: _selectedTypeFilter == 'In-Person',
                  selectedColor: const Color(0xFF4F46E5),
                  onTap: () {
                    setState(() => _selectedTypeFilter = _selectedTypeFilter == 'In-Person' ? 'All' : 'In-Person');
                    _fetchCalendarFromBackend();
                  },
                ),
                _buildFilterChip(
                  key: const Key('doctor_calendar_filter_Referred'),
                  label: 'Referred',
                  icon: Icons.swap_calls_rounded,
                  selected: _referredOnlyFilter,
                  selectedColor: const Color(0xFF7C3AED),
                  onTap: () {
                    setState(() => _referredOnlyFilter = !_referredOnlyFilter);
                    _fetchCalendarFromBackend();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

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
              if (_hasActiveFilters)
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: _resetAllFilters,
                  child: const Text('Clear Filters', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (visits.isEmpty)
            Container(
              key: const Key('doctor_calendar_empty_visits_state'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
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
                    totalOnDate == 0
                        ? 'No appointments scheduled for this date.'
                        : 'No appointments match the selected filter on $selectedDateYmd.',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF475569),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (totalOnDate == 0)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'Select another highlighted date on the calendar to review patient visits.',
                        style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            )
          else
            Column(
              children: visits.map(_buildVisitCard).toList(),
            ),

          // Dedicated Referral Tracking Section (Strictly Separated from Regular Appointments)
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
                        'Referral Tracking • $selectedDateYmd (${referralsOnDate.length})',
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
                  'Tracked separately from regular appointments. Each referral is counted once.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF6B21A8)),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _buildMiniRefMetric(
                      key: const Key('doctor_cal_stat_referrals_received'),
                      label: 'Received',
                      value: '${stats['patientReferralsReceived'] ?? referralsOnDate.length}',
                      color: const Color(0xFF7C3AED),
                    ),
                    _buildMiniRefMetric(
                      key: const Key('doctor_cal_ref_stat_accepted'),
                      label: 'Accepted',
                      value: '${stats['acceptedReferrals'] ?? 0}',
                      color: const Color(0xFF0284C7),
                    ),
                    _buildMiniRefMetric(
                      key: const Key('doctor_cal_ref_stat_pending'),
                      label: 'Pending',
                      value: '${stats['pendingReferrals'] ?? 0}',
                      color: const Color(0xFFD97706),
                    ),
                    _buildMiniRefMetric(
                      key: const Key('doctor_cal_ref_stat_rejected'),
                      label: 'Rejected',
                      value: '${stats['rejectedReferrals'] ?? 0}',
                      color: const Color(0xFFDC2626),
                    ),
                    _buildMiniRefMetric(
                      key: const Key('doctor_cal_ref_stat_completed'),
                      label: 'Completed Visits',
                      value: '${stats['completedReferredVisits'] ?? 0}',
                      color: const Color(0xFF16A34A),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (referralsOnDate.isEmpty)
                  Text(
                    'No referrals recorded for $selectedDateYmd.',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  )
                else
                  ...referralsOnDate.map(_buildReferralTrackingCard),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required Key key,
    required String label,
    IconData? icon,
    required bool selected,
    required Color selectedColor,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        key: key,
        avatar: icon != null
            ? Icon(icon, size: 14, color: selected ? Colors.white : selectedColor)
            : null,
        label: Text(label, style: const TextStyle(fontSize: 11.5)),
        selected: selected,
        selectedColor: selectedColor,
        backgroundColor: const Color(0xFFF8FAFC),
        side: BorderSide(color: selected ? selectedColor : const Color(0xFFCBD5E1)),
        labelStyle: TextStyle(
          color: selected ? Colors.white : const Color(0xFF334155),
          fontWeight: FontWeight.w700,
        ),
        onSelected: (_) => onTap(),
      ),
    );
  }

  Widget _buildMiniRefMetric({
    required Key key,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
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
            childAspectRatio: 0.88,
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
                dayInfo?['hasAccepted'] == true ||
                (int.tryParse('${dayInfo?['pendingAppointments'] ?? 0}') ?? 0) > 0 ||
                (int.tryParse('${dayInfo?['acceptedAppointments'] ?? 0}') ?? 0) > 0 ||
                (int.tryParse('${dayInfo?['pendingConsultations'] ?? 0}') ?? 0) > 0;
            final hasCancelled = dayInfo?['hasCancelled'] == true ||
                dayInfo?['hasRejected'] == true ||
                dayInfo?['hasNoShow'] == true ||
                (int.tryParse('${dayInfo?['rejectedAppointments'] ?? 0}') ?? 0) > 0 ||
                (int.tryParse('${dayInfo?['cancelledAppointments'] ?? 0}') ?? 0) > 0 ||
                (int.tryParse('${dayInfo?['noShowAppointments'] ?? 0}') ?? 0) > 0;
            final hasReferrals = dayInfo?['hasReferrals'] == true ||
                (int.tryParse('${dayInfo?['patientReferralsReceived'] ?? 0}') ?? 0) > 0;

            return InkWell(
              key: Key('doctor_calendar_day_$cellYmd'),
              onTap: () => _selectDate(cellDate),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.gsNavy
                      : isToday
                          ? const Color(0xFFFEF2F2)
                          : totalAppts > 0
                              ? const Color(0xFFEFF6FF)
                              : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? AppTheme.gsNavy
                        : isToday
                            ? AppTheme.gsRed
                            : totalAppts > 0
                                ? const Color(0xFF93C5FD)
                                : const Color(0xFFE2E8F0),
                    width: isToday || isSelected ? 1.6 : 1.0,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$dayNum',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: isSelected || isToday || totalAppts > 0 ? FontWeight.w800 : FontWeight.w600,
                        color: isSelected
                            ? Colors.white
                            : isToday
                                ? AppTheme.gsRed
                                : const Color(0xFF0F172A),
                      ),
                    ),
                    if (totalAppts > 0)
                      Container(
                        key: Key('doctor_calendar_day_count_$cellYmd'),
                        margin: const EdgeInsets.only(top: 1),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.white.withValues(alpha: 0.22) : AppTheme.gsNavy,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$totalAppts',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.1,
                          ),
                        ),
                      )
                    else if (hasCompleted || hasPending || hasCancelled || hasReferrals)
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
                    if (totalAppts > 0 && hasReferrals)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: _dot(isSelected ? Colors.purpleAccent : const Color(0xFF7C3AED)),
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
      width: 102,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: color, height: 1.1),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  label,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                  maxLines: 1,
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
    final patientId = (visit['patientId'] ?? '').toString().trim();
    final patientName = (visit['patientName'] ?? 'Patient').toString();
    final consultDate = (visit['consultationDate'] ?? '').toString();
    final consultTime = (visit['consultationTime'] ?? '').toString();
    final endTime = (visit['scheduledEndTime'] ?? '').toString().trim();
    final consultType = (visit['consultationType'] ?? 'In-Person').toString();
    final isOnline = consultType.toLowerCase() == 'online';
    final specialty = (visit['specialty'] ?? widget.doctorSpecialty).toString();
    final clinicName = (visit['clinicName'] ?? '').toString().trim();
    final statusRaw = (visit['status'] ?? 'PENDING').toString();
    final statusLabel = _formatCalendarStatusDisplay(statusRaw);
    final actuallyVisited = visit['actuallyVisited'] == true;
    final phone = (visit['patientPhone'] ?? '').toString().trim();
    final problemText = (visit['problemDescription'] ?? visit['treatment'] ?? '').toString().trim();
    final symptomsText = (visit['symptoms'] ?? '').toString().trim();
    final refSource = visit['referralSource'] is Map
        ? Map<String, dynamic>.from(visit['referralSource'] as Map)
        : null;
    final rawReq = visit['_rawRequest'] is PatientConsultationRequest
        ? visit['_rawRequest'] as PatientConsultationRequest
        : null;

    final timeDisplay = endTime.isNotEmpty ? '$consultDate • $consultTime – $endTime' : '$consultDate • $consultTime';

    return Container(
      key: Key('doctor_calendar_visit_card_$apptId'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: refSource != null ? const Color(0xFFD8B4FE) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPatientAvatar(patientName, visit['patientProfileImage']),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            patientName,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (refSource != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3E8FF),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFD8B4FE)),
                            ),
                            child: const Text(
                              'Referred',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF7C3AED),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      patientId.isNotEmpty ? 'Patient ID: $patientId' : 'Appointment #$apptId',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF475569),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      timeDisplay,
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              _statusBadge(statusLabel, actuallyVisited),
            ],
          ),
          const SizedBox(height: 8),

          // Consultation Type (Online vs In-Person with distinct icons) + Details Pills
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _infoPill(
                isOnline ? Icons.videocam_rounded : Icons.local_hospital_rounded,
                isOnline ? 'Online Consultation' : 'In-Person Consultation',
                isOnline ? const Color(0xFF0369A1) : const Color(0xFF4F46E5),
              ),
              _infoPill(Icons.medical_services_outlined, specialty, AppTheme.gsNavy),
              if (clinicName.isNotEmpty && !isOnline)
                _infoPill(Icons.location_on_outlined, clinicName, const Color(0xFF334155)),
              if (actuallyVisited)
                _infoPill(Icons.verified_user_outlined, 'Visited', const Color(0xFF0F766E)),
              if (widget.canViewPatientContact && phone.isNotEmpty)
                _infoPill(Icons.phone_outlined, phone, const Color(0xFF334155)),
            ],
          ),

          // Patient Problem / Reason for Consultation
          if (problemText.isNotEmpty || symptomsText.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (problemText.isNotEmpty)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.assignment_outlined, size: 13.5, color: Color(0xFF475569)),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            'Reason: $problemText',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1E293B),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  if (symptomsText.isNotEmpty &&
                      symptomsText.toLowerCase() != 'none' &&
                      symptomsText.toLowerCase() != problemText.toLowerCase())
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        'Symptoms: $symptomsText',
                        style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ],

          // Referral Info Banner (only when genuinely referred)
          if (refSource != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFF3E8FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE9D5FF)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.person_pin_circle_outlined, size: 14, color: Color(0xFF7C3AED)),
                      const SizedBox(width: 5),
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
                      const SizedBox(width: 6),
                      _referralStatusPill((refSource['referralStatus'] ?? 'Pending').toString()),
                    ],
                  ),
                  if ((refSource['referralDate'] ?? '').toString().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Referral Status: ${refSource['referralStatus'] ?? 'Pending'} • Date: ${refSource['referralDate']}',
                        style: const TextStyle(fontSize: 10.5, color: Color(0xFF7E22CE)),
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

  Widget _referralStatusPill(String status) {
    final upper = status.trim().toUpperCase();
    Color bg = const Color(0xFFFEF3C7);
    Color fg = const Color(0xFF92400E);
    if (upper == 'ACCEPTED' || upper == 'CONFIRMED' || upper == 'APPROVED') {
      bg = const Color(0xFFDBEAFE);
      fg = const Color(0xFF1E40AF);
    } else if (upper == 'COMPLETED') {
      bg = const Color(0xFFDCFCE7);
      fg = const Color(0xFF166534);
    } else if (upper == 'REJECTED' || upper == 'DECLINED') {
      bg = const Color(0xFFFEE2E2);
      fg = const Color(0xFF991B1B);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        status,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: fg),
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
              const SizedBox(width: 6),
              _referralStatusPill(refStatus),
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
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'P';
    Widget fallbackAvatar() => CircleAvatar(
          radius: 20,
          backgroundColor: AppTheme.gsNavy.withValues(alpha: 0.12),
          child: Text(
            initial,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.gsNavy),
          ),
        );

    final str = (rawImage ?? '').toString().trim();
    if (str.isNotEmpty && str.toLowerCase() != 'null') {
      if (str.startsWith('http://') || str.startsWith('https://')) {
        return ClipOval(
          child: Image.network(
            str,
            width: 40,
            height: 40,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => fallbackAvatar(),
          ),
        );
      }
      try {
        final clean = str.contains(',') ? str.split(',').last.trim() : str;
        final bytes = base64Decode(clean);
        if (bytes.isNotEmpty) {
          return CircleAvatar(radius: 20, backgroundImage: MemoryImage(bytes));
        }
      } catch (_) {}
    }
    return fallbackAvatar();
  }

  Widget _statusBadge(String label, bool actuallyVisited) {
    final upper = label.toUpperCase();
    Color bg = const Color(0xFFFEF3C7);
    Color fg = const Color(0xFF92400E);
    if (upper.contains('COMPLETED')) {
      bg = const Color(0xFFDCFCE7);
      fg = const Color(0xFF166534);
    } else if (upper.contains('ACCEPTED') || upper.contains('CONFIRMED') || upper.contains('PROGRESS')) {
      bg = const Color(0xFFDBEAFE);
      fg = const Color(0xFF1E40AF);
    } else if (upper.contains('RESCHEDUL')) {
      bg = const Color(0xFFF3E8FF);
      fg = const Color(0xFF6B21A8);
    } else if (upper.contains('CANCEL') || upper.contains('REJECT')) {
      bg = const Color(0xFFFEE2E2);
      fg = const Color(0xFF991B1B);
    } else if (upper.contains('NO-SHOW') || upper.contains('NO_SHOW')) {
      bg = const Color(0xFFFFEDD5);
      fg = const Color(0xFF9A3412);
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

  Widget _buildWeeklyStrip(Map<String, dynamic> monthlyCal) {
    final nowRef = BookingRulesConfig.debugNowOverride ?? DateTime.now();
    final todayYmd = _formatYmd(DateTime(nowRef.year, nowRef.month, nowRef.day));
    final selectedYmd = _formatYmd(_selectedDate);
    final weekStart = _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1));

    return Container(
      key: const Key('doctor_calendar_weekly_view'),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: List.generate(7, (idx) {
          final day = weekStart.add(Duration(days: idx));
          final ymd = _formatYmd(day);
          final isSelected = ymd == selectedYmd;
          final isToday = ymd == todayYmd;
          final bucket = monthlyCal[ymd] is Map ? Map<String, dynamic>.from(monthlyCal[ymd] as Map) : null;
          final count = int.tryParse('${bucket?['totalAppointments'] ?? 0}') ?? 0;

          return Expanded(
            child: InkWell(
              key: Key('doctor_weekly_cell_$ymd'),
              onTap: () => _selectDate(day),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.gsNavy
                      : (isToday ? const Color(0xFFEFF6FF) : Colors.white),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? AppTheme.gsNavy
                        : (isToday ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0)),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _weekdayHeaders[idx],
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? Colors.white70 : const Color(0xFF64748B),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${day.day}',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: isSelected ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: count > 0
                            ? (isSelected ? Colors.white.withValues(alpha: 0.2) : const Color(0xFFDBEAFE))
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        count > 0 ? '$count' : '·',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: isSelected
                              ? Colors.white
                              : (count > 0 ? const Color(0xFF1D4ED8) : const Color(0xFF94A3B8)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildSelectedDateScheduleOverview(Map<String, dynamic> agg, String selectedDateYmd) {
    final schedMap = agg['schedule'] is Map ? Map<String, dynamic>.from(agg['schedule'] as Map) : null;
    final releasedList = agg['releasedSlots'] is List
        ? (agg['releasedSlots'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : const <Map<String, dynamic>>[];

    final startStr = (schedMap?['startTime'] ?? '09:00 AM').toString();
    final endStr = (schedMap?['endTime'] ?? '05:00 PM').toString();
    final inPersonDur = int.tryParse('${schedMap?['inPersonDurationMinutes'] ?? schedMap?['slotDurationMinutes'] ?? 30}') ?? 30;
    final onlineDur = int.tryParse('${schedMap?['onlineDurationMinutes'] ?? 20}') ?? 20;
    final breaks = schedMap?['breaks'] is List
        ? (schedMap!['breaks'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : const <Map<String, dynamic>>[];
    final blockedRanges = schedMap?['selectedDateBlockedSlots'] is List
        ? (schedMap!['selectedDateBlockedSlots'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : const <Map<String, dynamic>>[];
    final isDateBlocked = schedMap?['selectedDateBlocked'] == true;

    return Container(
      key: const Key('doctor_calendar_schedule_overview'),
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDateBlocked ? const Color(0xFFFEF2F2) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDateBlocked ? const Color(0xFFFECACA) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isDateBlocked ? Icons.event_busy_rounded : Icons.schedule_rounded,
                size: 15,
                color: isDateBlocked ? const Color(0xFFDC2626) : AppTheme.gsNavy,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isDateBlocked
                      ? 'Date Blocked ($selectedDateYmd): ${schedMap?['selectedDateBlockedReason'] ?? 'On Leave'}'
                      : 'Schedule ($selectedDateYmd • IST): $startStr – $endStr',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: isDateBlocked ? const Color(0xFF991B1B) : const Color(0xFF0F172A),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _infoPill(Icons.local_hospital_outlined, 'In-Person ${inPersonDur}m', AppTheme.gsNavy),
              _infoPill(Icons.videocam_outlined, 'Online ${onlineDur}m', const Color(0xFF0284C7)),
              for (final b in breaks)
                _infoPill(
                  Icons.coffee_rounded,
                  'Break ${b['startTime'] ?? ''}–${b['endTime'] ?? ''}',
                  const Color(0xFFD97706),
                ),
              for (final bl in blockedRanges)
                _infoPill(
                  Icons.block_rounded,
                  'Blocked ${bl['startTime'] ?? ''}–${bl['endTime'] ?? ''}',
                  const Color(0xFFDC2626),
                ),
              if (releasedList.isNotEmpty)
                _infoPill(
                  Icons.bolt_rounded,
                  '${releasedList.length} Released Slot(s)',
                  const Color(0xFF16A34A),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoPill(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12.5, color: color),
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
