import 'package:flutter/material.dart';
import '../../../../core/constants/booking_rules_config.dart';
import '../../../../core/models/referral_model.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/patient_problem_service.dart';
import '../../../../core/theme/app_theme.dart';
import 'gs_health_admin_overview.dart';

class AdminGlobalVisitsCalendarSection extends StatefulWidget {
  final List<AdminAppointmentItem> appointments;
  final List<ClinicModel> clinics;
  final List<DoctorModel> doctors;
  final List<PatientProfile> patients;
  final List<PatientReferral> referrals;
  final bool isSubAdmin;
  final List<Map<String, dynamic>> assignedDistricts;
  final bool canViewPatientContact;
  final DateTime? initialSelectedDate;
  final ValueChanged<DateTime>? onDateSelected;

  const AdminGlobalVisitsCalendarSection({
    super.key,
    required this.appointments,
    required this.clinics,
    required this.doctors,
    required this.patients,
    required this.referrals,
    this.isSubAdmin = false,
    this.assignedDistricts = const [],
    this.canViewPatientContact = true,
    this.initialSelectedDate,
    this.onDateSelected,
  });

  @override
  State<AdminGlobalVisitsCalendarSection> createState() => _AdminGlobalVisitsCalendarSectionState();
}

class _AdminGlobalVisitsCalendarSectionState extends State<AdminGlobalVisitsCalendarSection> {
  late DateTime _selectedDate;
  late DateTime _displayedMonth;

  String _selectedHospitalFilter = 'All';
  String _selectedDoctorFilter = 'All';
  String _selectedSpecialtyFilter = 'All';
  String _selectedTypeFilter = 'All'; // 'All' | 'In-Person' | 'Online'
  String? _selectedDrilldownClinicKey;

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
    _fetchAdminCalendarFromBackend();
  }

  String _formatYmd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _formatYm(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

  Future<void> _fetchAdminCalendarFromBackend() async {
    setState(() => _isLoadingRemote = true);
    final res = await ApiService().fetchAdminGlobalVisitsCalendar(
      date: _formatYmd(_selectedDate),
      month: _formatYm(_displayedMonth),
      clinicId: _selectedHospitalFilter == 'All' ? null : _selectedHospitalFilter,
      doctorId: _selectedDoctorFilter == 'All' ? null : _selectedDoctorFilter,
      specialty: _selectedSpecialtyFilter == 'All' ? null : _selectedSpecialtyFilter,
      consultationType: _selectedTypeFilter == 'All' ? null : _selectedTypeFilter,
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
    _fetchAdminCalendarFromBackend();
  }

  void _changeMonth(int deltaMonths) {
    final nextMonth = DateTime(_displayedMonth.year, _displayedMonth.month + deltaMonths, 1);
    setState(() {
      _displayedMonth = nextMonth;
    });
    _fetchAdminCalendarFromBackend();
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
  }) _classifyAdminItem(AdminAppointmentItem item) {
    final rawStatus = item.status.trim().toUpperCase();
    final isCompleted = rawStatus == 'COMPLETED';
    final isCancelled = rawStatus == 'CANCELLED' || rawStatus == 'CANCELED' || rawStatus == 'REJECTED';
    final isNoShow = rawStatus == 'NO_SHOW' || rawStatus == 'NOSHOW' || rawStatus == 'NO-SHOW';
    final isInProgress = rawStatus == 'IN_PROGRESS' || rawStatus == 'IN PROGRESS' || rawStatus == 'STARTED';
    final isPending = !isCompleted && !isCancelled && !isNoShow;
    final actuallyVisited = !isCancelled &&
        !isNoShow &&
        (isCompleted ||
            isInProgress ||
            item.actualStartAt.trim().isNotEmpty ||
            item.actualEndAt.trim().isNotEmpty);
    final isOnline = item.mode.toUpperCase().contains('ONLINE') ||
        item.treatment.toUpperCase().contains('ONLINE');
    final consultType = isOnline ? 'Online' : 'In-Person';
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

  String _uniquePatientKeyFromItem(AdminAppointmentItem item) {
    final pid = item.patientId.trim();
    if (pid.isNotEmpty) return 'id:$pid';
    final digits = item.phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 10) return 'ph:${digits.substring(digits.length - 10)}';
    return 'appt:${item.id}';
  }

  Map<String, dynamic> _computeEffectiveAdminAggregation() {
    if (_remoteCalendarData != null && _remoteCalendarData!['success'] == true) {
      return _remoteCalendarData!;
    }

    final targetYmd = _formatYmd(_selectedDate);
    final targetYm = _formatYm(_displayedMonth);

    // Filter appointments by selected Hospital/Clinic, Doctor, Specialty, Consultation Type
    final filteredAppointments = widget.appointments.where((a) {
      final cls = _classifyAdminItem(a);
      if (_selectedHospitalFilter != 'All') {
        final fLower = _selectedHospitalFilter.toLowerCase();
        final matchesClinic = a.clinicId.trim().toLowerCase() == fLower ||
            a.clinicName.trim().toLowerCase() == fLower;
        if (!matchesClinic) return false;
      }
      if (_selectedDoctorFilter != 'All') {
        final fLower = _selectedDoctorFilter.toLowerCase();
        final matchesDoc = a.dentistId.trim().toLowerCase() == fLower ||
            a.dentistName.trim().toLowerCase() == fLower;
        if (!matchesDoc) return false;
      }
      if (_selectedSpecialtyFilter != 'All') {
        if (a.doctorSpecialty.trim().toLowerCase() != _selectedSpecialtyFilter.toLowerCase()) {
          return false;
        }
      }
      if (_selectedTypeFilter != 'All' && cls.consultType != _selectedTypeFilter) {
        return false;
      }
      return true;
    }).toList();

    // Build referral tracking entries (strictly separate from completed visits unless an appointment confirms it)
    final allReferralEntries = <Map<String, dynamic>>[];
    for (final ref in widget.referrals) {
      if (_selectedDoctorFilter != 'All') {
        final fLower = _selectedDoctorFilter.toLowerCase();
        final matchesDoc = ref.doctorId.trim().toLowerCase() == fLower ||
            ref.doctorName.trim().toLowerCase() == fLower;
        if (!matchesDoc) continue;
      }
      if (_selectedSpecialtyFilter != 'All') {
        final sp = (ref.requiredSpecialist.isNotEmpty ? ref.requiredSpecialist : ref.doctorSpecialty).toLowerCase();
        if (!sp.contains(_selectedSpecialtyFilter.toLowerCase())) continue;
      }

      final refYmd = ApiService.toAsiaKolkataYmd(ref.referralDate);
      final refPid = (ref.referredPatientId ?? '').trim();
      final refDigits = ref.referredPatientMobile.replaceAll(RegExp(r'\D'), '');
      final refPh10 = refDigits.length >= 10 ? refDigits.substring(refDigits.length - 10) : refDigits;

      final matchedAppts = widget.appointments.where((a) {
        final aPid = a.patientId.trim();
        final aDigits = a.phone.replaceAll(RegExp(r'\D'), '');
        final aPh10 = aDigits.length >= 10 ? aDigits.substring(aDigits.length - 10) : aDigits;
        if (refPid.isNotEmpty && aPid.isNotEmpty) return refPid == aPid;
        if (refPh10.length == 10 && aPh10.length == 10) return refPh10 == aPh10;
        return false;
      }).toList();

      final nonCancelled = matchedAppts.where((a) => !_classifyAdminItem(a).isCancelled).toList();
      final completedAppt = nonCancelled.where((a) => _classifyAdminItem(a).isCompleted).firstOrNull;
      final activeAppt = completedAppt ?? nonCancelled.firstOrNull;

      allReferralEntries.add({
        'referralId': ref.id,
        'referredPatientName': ref.referredPatientName,
        'referredPatientMobile': ref.referredPatientMobile,
        'referringPatientName': ref.referrerPatientName,
        'referringPatientPhone': ref.referrerPatientPhone,
        'referredDoctorId': ref.doctorId,
        'referredDoctorName': ref.doctorName,
        'specialty': ref.requiredSpecialist.isNotEmpty ? ref.requiredSpecialist : ref.doctorSpecialty,
        'referralDate': refYmd,
        'referralStatus': ref.status,
        'hasBookedAppointment': nonCancelled.isNotEmpty,
        'bookedAppointmentId': activeAppt?.id,
        'bookedAppointmentDate': activeAppt != null ? ApiService.toAsiaKolkataYmd(activeAppt.dateRaw) : null,
        'hasCompletedConsultation': completedAppt != null,
      });
    }

    // Monthly calendar map
    final monthlyCalendar = <String, Map<String, dynamic>>{};
    Map<String, dynamic> ensureDay(String ymd) {
      return monthlyCalendar.putIfAbsent(
        ymd,
        () => <String, dynamic>{
          'date': ymd,
          'totalScheduledAppointments': 0,
          'actualPatientVisits': 0,
          'completedAppointments': 0,
          'pendingAppointments': 0,
          'cancelledAppointments': 0,
          'noShowAppointments': 0,
          'onlineConsultations': 0,
          'inPersonConsultations': 0,
          'newPatientRegistrations': 0,
          'patientReferrals': 0,
          'hasCompleted': false,
          'hasPending': false,
          'hasCancelled': false,
          'hasNoShow': false,
          'hasReferrals': false,
          '_visitedSet': <String>{},
        },
      );
    }

    for (final a in filteredAppointments) {
      final ymd = ApiService.toAsiaKolkataYmd(a.dateRaw);
      if (!ymd.startsWith(targetYm)) continue;
      final bucket = ensureDay(ymd);
      final cls = _classifyAdminItem(a);
      bucket['totalScheduledAppointments'] = (bucket['totalScheduledAppointments'] as int) + 1;
      if (cls.actuallyVisited) {
        (bucket['_visitedSet'] as Set<String>).add(_uniquePatientKeyFromItem(a));
      }
      if (cls.isCompleted) {
        bucket['completedAppointments'] = (bucket['completedAppointments'] as int) + 1;
        bucket['hasCompleted'] = true;
      } else if (cls.isCancelled) {
        bucket['cancelledAppointments'] = (bucket['cancelledAppointments'] as int) + 1;
        bucket['hasCancelled'] = true;
      } else if (cls.isNoShow) {
        bucket['noShowAppointments'] = (bucket['noShowAppointments'] as int) + 1;
        bucket['hasNoShow'] = true;
      } else if (cls.isPending) {
        bucket['pendingAppointments'] = (bucket['pendingAppointments'] as int) + 1;
        bucket['hasPending'] = true;
      }
      if (cls.isOnline) {
        bucket['onlineConsultations'] = (bucket['onlineConsultations'] as int) + 1;
      } else {
        bucket['inPersonConsultations'] = (bucket['inPersonConsultations'] as int) + 1;
      }
    }

    for (final r in allReferralEntries) {
      final ymd = (r['referralDate'] ?? '').toString();
      if (!ymd.startsWith(targetYm)) continue;
      final bucket = ensureDay(ymd);
      bucket['patientReferrals'] = (bucket['patientReferrals'] as int) + 1;
      bucket['hasReferrals'] = true;
    }

    for (final bucket in monthlyCalendar.values) {
      bucket['actualPatientVisits'] = (bucket['_visitedSet'] as Set<String>).length;
      bucket.remove('_visitedSet');
    }

    // Selected Date Statistics
    final apptsOnSelectedDate = filteredAppointments
        .where((a) => ApiService.toAsiaKolkataYmd(a.dateRaw) == targetYmd)
        .toList();
    final referralsOnSelectedDate = allReferralEntries
        .where((r) => r['referralDate'] == targetYmd)
        .toList();

    final uniqueVisitedPatientsOnDate = <String>{};
    int completedCount = 0;
    int pendingCount = 0;
    int cancelledCount = 0;
    int noShowCount = 0;
    int onlineCount = 0;
    int inPersonCount = 0;

    final visitsList = <Map<String, dynamic>>[];
    for (final a in apptsOnSelectedDate) {
      final cls = _classifyAdminItem(a);
      if (cls.actuallyVisited) {
        uniqueVisitedPatientsOnDate.add(_uniquePatientKeyFromItem(a));
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

      visitsList.add({
        'appointmentId': a.id,
        'id': a.id,
        'patientName': a.patientName,
        'patientPhone': widget.canViewPatientContact ? a.phone : null,
        'doctorId': a.dentistId,
        'doctorName': a.dentistName,
        'specialty': a.doctorSpecialty,
        'clinicId': a.clinicId,
        'clinicName': a.clinicName,
        'consultationDate': targetYmd,
        'consultationTime': a.timeSlot,
        'scheduledEndTime': a.scheduledEndTime,
        'consultationType': cls.consultType,
        'treatment': a.treatment,
        'status': cls.rawStatus,
        'actuallyVisited': cls.actuallyVisited,
      });
    }

    // Hospital / Clinic Breakdown on Selected Date
    final hospitalMap = <String, Map<String, dynamic>>{};
    for (final c in widget.clinics) {
      final key = c.id.trim().isNotEmpty ? c.id.trim() : c.clinicName.trim().toLowerCase();
      if (key.isEmpty) continue;
      hospitalMap[key] = {
        'clinicId': c.id.trim().isNotEmpty ? c.id.trim() : key,
        'clinicName': c.clinicName.trim().isNotEmpty ? c.clinicName.trim() : 'Hospital / Clinic',
        'location': c.location,
        'scheduledVisits': 0,
        'actualPatientVisits': 0,
        'completedVisits': 0,
        'pendingVisits': 0,
        'cancelledVisits': 0,
        'noShowVisits': 0,
        'assignedDoctors': <Map<String, dynamic>>[],
        '_docSet': <String>{},
        '_visitedSet': <String>{},
        'visits': <Map<String, dynamic>>[],
      };
    }

    for (final d in widget.doctors) {
      final cName = d.clinicName.trim();
      if (cName.isEmpty) continue;
      Map<String, dynamic>? bucket;
      for (final b in hospitalMap.values) {
        if ((b['clinicName'] ?? '').toString().trim().toLowerCase() == cName.toLowerCase()) {
          bucket = b;
          break;
        }
      }
      bucket ??= hospitalMap.putIfAbsent(
        'clinic:${cName.toLowerCase()}',
        () => {
          'clinicId': 'clinic:${cName.toLowerCase()}',
          'clinicName': cName,
          'location': d.clinicAddress,
          'scheduledVisits': 0,
          'actualPatientVisits': 0,
          'completedVisits': 0,
          'pendingVisits': 0,
          'cancelledVisits': 0,
          'noShowVisits': 0,
          'assignedDoctors': <Map<String, dynamic>>[],
          '_docSet': <String>{},
          '_visitedSet': <String>{},
          'visits': <Map<String, dynamic>>[],
        },
      );
      final docKey = d.id.trim().isNotEmpty ? d.id.trim() : d.name.trim().toLowerCase();
      if ((bucket['_docSet'] as Set<String>).add(docKey)) {
        (bucket['assignedDoctors'] as List<Map<String, dynamic>>).add({
          'doctorId': d.id,
          'doctorName': d.name.toLowerCase().startsWith('dr') ? d.name : 'Dr. ${d.name}',
          'specialty': d.specialty,
        });
      }
    }

    for (int i = 0; i < apptsOnSelectedDate.length; i++) {
      final a = apptsOnSelectedDate[i];
      final vMap = visitsList[i];
      final cls = _classifyAdminItem(a);
      final cId = a.clinicId.trim();
      final cName = a.clinicName.trim();
      Map<String, dynamic>? bucket = cId.isNotEmpty ? hospitalMap[cId] : null;
      if (bucket == null && cName.isNotEmpty) {
        for (final b in hospitalMap.values) {
          if ((b['clinicName'] ?? '').toString().trim().toLowerCase() == cName.toLowerCase()) {
            bucket = b;
            break;
          }
        }
      }
      if (bucket == null && (cId.isNotEmpty || cName.isNotEmpty)) {
        final key = cId.isNotEmpty ? cId : 'clinic:${cName.toLowerCase()}';
        bucket = hospitalMap.putIfAbsent(
          key,
          () => {
            'clinicId': key,
            'clinicName': cName.isNotEmpty ? cName : 'Hospital / Clinic',
            'location': '',
            'scheduledVisits': 0,
            'actualPatientVisits': 0,
            'completedVisits': 0,
            'pendingVisits': 0,
            'cancelledVisits': 0,
            'noShowVisits': 0,
            'assignedDoctors': <Map<String, dynamic>>[],
            '_docSet': <String>{},
            '_visitedSet': <String>{},
            'visits': <Map<String, dynamic>>[],
          },
        );
      }
      if (bucket != null) {
        bucket['scheduledVisits'] = (bucket['scheduledVisits'] as int) + 1;
        if (cls.actuallyVisited) {
          (bucket['_visitedSet'] as Set<String>).add(_uniquePatientKeyFromItem(a));
        }
        if (cls.isCompleted) {
          bucket['completedVisits'] = (bucket['completedVisits'] as int) + 1;
        } else if (cls.isCancelled) {
          bucket['cancelledVisits'] = (bucket['cancelledVisits'] as int) + 1;
        } else if (cls.isNoShow) {
          bucket['noShowVisits'] = (bucket['noShowVisits'] as int) + 1;
        } else if (cls.isPending) {
          bucket['pendingVisits'] = (bucket['pendingVisits'] as int) + 1;
        }
        if (a.dentistName.trim().isNotEmpty) {
          final dKey = a.dentistId.trim().isNotEmpty ? a.dentistId.trim() : a.dentistName.trim().toLowerCase();
          if ((bucket['_docSet'] as Set<String>).add(dKey)) {
            (bucket['assignedDoctors'] as List<Map<String, dynamic>>).add({
              'doctorId': a.dentistId,
              'doctorName': a.dentistName,
              'specialty': a.doctorSpecialty,
            });
          }
        }
        (bucket['visits'] as List<Map<String, dynamic>>).add(vMap);
      }
    }

    final hospitalBreakdown = hospitalMap.values
        .where((b) {
          if (_selectedHospitalFilter != 'All') {
            final fLower = _selectedHospitalFilter.toLowerCase();
            return (b['clinicId'] ?? '').toString().toLowerCase() == fLower ||
                (b['clinicName'] ?? '').toString().toLowerCase() == fLower;
          }
          return true;
        })
        .map((b) {
          final copy = Map<String, dynamic>.from(b);
          copy['actualPatientVisits'] = (b['_visitedSet'] as Set<String>).length;
          copy.remove('_visitedSet');
          copy.remove('_docSet');
          return copy;
        })
        .toList();

    // Doctor-wise Breakdown on Selected Date
    final docStatsMap = <String, Map<String, dynamic>>{};
    for (final d in widget.doctors) {
      final key = d.id.trim().isNotEmpty ? d.id.trim() : d.name.trim().toLowerCase();
      if (key.isEmpty) continue;
      docStatsMap[key] = {
        'doctorId': d.id,
        'doctorName': d.name.toLowerCase().startsWith('dr') ? d.name : 'Dr. ${d.name}',
        'specialty': d.specialty,
        'clinicName': d.clinicName,
        'scheduledConsultations': 0,
        'actualPatientVisits': 0,
        'completedConsultations': 0,
        'pendingConsultations': 0,
        'cancelledConsultations': 0,
        'noShowConsultations': 0,
        '_visitedSet': <String>{},
      };
    }

    for (final a in apptsOnSelectedDate) {
      final cls = _classifyAdminItem(a);
      final key = a.dentistId.trim().isNotEmpty ? a.dentistId.trim() : a.dentistName.trim().toLowerCase();
      if (key.isEmpty) continue;
      final bucket = docStatsMap.putIfAbsent(
        key,
        () => {
          'doctorId': a.dentistId,
          'doctorName': a.dentistName,
          'specialty': a.doctorSpecialty,
          'clinicName': a.clinicName,
          'scheduledConsultations': 0,
          'actualPatientVisits': 0,
          'completedConsultations': 0,
          'pendingConsultations': 0,
          'cancelledConsultations': 0,
          'noShowConsultations': 0,
          '_visitedSet': <String>{},
        },
      );
      bucket['scheduledConsultations'] = (bucket['scheduledConsultations'] as int) + 1;
      if (cls.actuallyVisited) {
        (bucket['_visitedSet'] as Set<String>).add(_uniquePatientKeyFromItem(a));
      }
      if (cls.isCompleted) {
        bucket['completedConsultations'] = (bucket['completedConsultations'] as int) + 1;
      } else if (cls.isCancelled) {
        bucket['cancelledConsultations'] = (bucket['cancelledConsultations'] as int) + 1;
      } else if (cls.isNoShow) {
        bucket['noShowConsultations'] = (bucket['noShowConsultations'] as int) + 1;
      } else if (cls.isPending) {
        bucket['pendingConsultations'] = (bucket['pendingConsultations'] as int) + 1;
      }
    }

    final doctorBreakdown = docStatsMap.values
        .where((d) {
          if (_selectedDoctorFilter != 'All') {
            final fLower = _selectedDoctorFilter.toLowerCase();
            return (d['doctorId'] ?? '').toString().toLowerCase() == fLower ||
                (d['doctorName'] ?? '').toString().toLowerCase() == fLower;
          }
          return true;
        })
        .map((d) {
          final copy = Map<String, dynamic>.from(d);
          copy['actualPatientVisits'] = (d['_visitedSet'] as Set<String>).length;
          copy.remove('_visitedSet');
          return copy;
        })
        .toList();

    return {
      'success': true,
      'selectedDate': targetYmd,
      'month': targetYm,
      'monthlyCalendar': monthlyCalendar,
      'selectedDateStats': {
        'date': targetYmd,
        'totalScheduledAppointments': apptsOnSelectedDate.length,
        'actualPatientVisits': uniqueVisitedPatientsOnDate.length,
        'completedAppointments': completedCount,
        'pendingAppointments': pendingCount,
        'cancelledAppointments': cancelledCount,
        'noShowAppointments': noShowCount,
        'onlineConsultations': onlineCount,
        'inPersonConsultations': inPersonCount,
        'newPatientRegistrations': 0,
        'patientReferrals': referralsOnSelectedDate.length,
      },
      'hospitalClinicBreakdown': hospitalBreakdown,
      'doctorBreakdown': doctorBreakdown,
      'visits': visitsList,
      'referralsOnDate': referralsOnSelectedDate,
      'allReferrals': allReferralEntries,
    };
  }

  @override
  Widget build(BuildContext context) {
    final agg = _computeEffectiveAdminAggregation();
    final stats = Map<String, dynamic>.from((agg['selectedDateStats'] as Map?) ?? const {});
    final monthlyCal = Map<String, dynamic>.from((agg['monthlyCalendar'] as Map?) ?? const {});
    final hospitalBreakdown = ((agg['hospitalClinicBreakdown'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final doctorBreakdown = ((agg['doctorBreakdown'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
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

    // Build filter dropdown options from clinics, doctors, and appointments
    final hospitalOptions = <String>{
      'All',
      ...widget.clinics.map((c) => c.clinicName.trim()).where((s) => s.isNotEmpty),
      ...widget.appointments.map((a) => a.clinicName.trim()).where((s) => s.isNotEmpty),
    }.toList();
    final doctorOptions = <String>{
      'All',
      ...widget.doctors
          .map((d) => d.name.trim().toLowerCase().startsWith('dr') ? d.name.trim() : 'Dr. ${d.name.trim()}')
          .where((s) => s.isNotEmpty && s != 'Dr. '),
      ...widget.appointments.map((a) => a.dentistName.trim()).where((s) => s.isNotEmpty),
    }.toList();
    final specialtyOptions = <String>{
      'All',
      ...widget.doctors.map((d) => d.specialty.trim()).where((s) => s.isNotEmpty),
      ...widget.appointments.map((a) => a.doctorSpecialty.trim()).where((s) => s.isNotEmpty),
    }.toList();

    final safeHospital = hospitalOptions.contains(_selectedHospitalFilter) ? _selectedHospitalFilter : 'All';
    final safeDoctor = doctorOptions.contains(_selectedDoctorFilter) ? _selectedDoctorFilter : 'All';
    final safeSpecialty = specialtyOptions.contains(_selectedSpecialtyFilter) ? _selectedSpecialtyFilter : 'All';

    return Container(
      key: const Key('admin_global_visits_calendar_section'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
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
          // Header Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: AppTheme.gsNavy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.calendar_view_month_rounded, color: AppTheme.gsNavy, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.isSubAdmin
                          ? 'District Visits & Hospitals Calendar'
                          : 'Admin Global Visits & Hospitals Calendar',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Selected Date: $selectedDateYmd (Asia/Kolkata)',
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              TextButton(
                key: const Key('admin_calendar_today_btn'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: _jumpToToday,
                child: const Text('Go to Today', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                key: const Key('admin_calendar_date_picker_btn'),
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
                  key: const Key('admin_calendar_prev_month_btn'),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_left_rounded, color: AppTheme.gsNavy),
                  onPressed: () => _changeMonth(-1),
                ),
                Flexible(
                  child: Text(
                    '${_monthNames[_displayedMonth.month - 1]} ${_displayedMonth.year}',
                    key: const Key('admin_calendar_month_label'),
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  key: const Key('admin_calendar_next_month_btn'),
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

          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _buildLegendDot(const Color(0xFF16A34A), 'Completed'),
              _buildLegendDot(const Color(0xFF2563EB), 'Pending / Confirmed'),
              _buildLegendDot(const Color(0xFFDC2626), 'Cancelled / No-Show'),
              _buildLegendDot(const Color(0xFF7C3AED), 'Referrals'),
            ],
          ),
          const Divider(height: 22, color: Color(0xFFE2E8F0)),

          // Filters Row: Hospital/Clinic, Doctor, Specialty, Consultation Type
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 185),
                child: DropdownButtonFormField<String>(
                  key: const Key('admin_calendar_hospital_filter'),
                  value: safeHospital,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Hospital / Clinic',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  items: hospitalOptions
                      .map(
                        (h) => DropdownMenuItem(
                          value: h,
                          child: Text(
                            h == 'All' ? 'All Hospitals & Clinics' : h,
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedHospitalFilter = val ?? 'All';
                      _selectedDrilldownClinicKey = null;
                    });
                    _fetchAdminCalendarFromBackend();
                  },
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 185),
                child: DropdownButtonFormField<String>(
                  key: const Key('admin_calendar_doctor_filter'),
                  value: safeDoctor,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Doctor',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  items: doctorOptions
                      .map(
                        (d) => DropdownMenuItem(
                          value: d,
                          child: Text(
                            d == 'All' ? 'All Doctors' : d,
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    setState(() => _selectedDoctorFilter = val ?? 'All');
                    _fetchAdminCalendarFromBackend();
                  },
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 170),
                child: DropdownButtonFormField<String>(
                  key: const Key('admin_calendar_specialty_filter'),
                  value: safeSpecialty,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Specialty',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  items: specialtyOptions
                      .map(
                        (s) => DropdownMenuItem(
                          value: s,
                          child: Text(
                            s == 'All' ? 'All Specialties' : s,
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    setState(() => _selectedSpecialtyFilter = val ?? 'All');
                    _fetchAdminCalendarFromBackend();
                  },
                ),
              ),
              ...['All', 'In-Person', 'Online'].map((mode) {
                final selected = _selectedTypeFilter == mode;
                return ChoiceChip(
                  key: Key('admin_calendar_type_filter_$mode'),
                  label: Text(mode, style: const TextStyle(fontSize: 11.5)),
                  selected: selected,
                  selectedColor: AppTheme.gsNavy,
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : const Color(0xFF334155),
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: (_) {
                    setState(() => _selectedTypeFilter = mode);
                    _fetchAdminCalendarFromBackend();
                  },
                );
              }),
            ],
          ),
          const SizedBox(height: 14),

          if (_isLoadingRemote)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: LinearProgressIndicator(minHeight: 2),
            ),

          // Phase 2 Platform-Wide Statistics Grid for Selected Date
          Text(
            'Platform-Wide Statistics on $selectedDateYmd',
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildStatTile(
                key: const Key('admin_cal_stat_total_scheduled'),
                label: 'Scheduled Appts',
                value: '${stats['totalScheduledAppointments'] ?? 0}',
                color: AppTheme.gsNavy,
                icon: Icons.event_note_rounded,
              ),
              _buildStatTile(
                key: const Key('admin_cal_stat_actual_visits'),
                label: 'Actual Visits',
                value: '${stats['actualPatientVisits'] ?? 0}',
                color: const Color(0xFF0F766E),
                icon: Icons.how_to_reg_rounded,
              ),
              _buildStatTile(
                key: const Key('admin_cal_stat_completed'),
                label: 'Completed',
                value: '${stats['completedAppointments'] ?? 0}',
                color: const Color(0xFF16A34A),
                icon: Icons.check_circle_outline_rounded,
              ),
              _buildStatTile(
                key: const Key('admin_cal_stat_pending'),
                label: 'Pending',
                value: '${stats['pendingAppointments'] ?? 0}',
                color: const Color(0xFF2563EB),
                icon: Icons.schedule_rounded,
              ),
              _buildStatTile(
                key: const Key('admin_cal_stat_cancelled'),
                label: 'Cancelled',
                value: '${stats['cancelledAppointments'] ?? 0}',
                color: const Color(0xFFDC2626),
                icon: Icons.cancel_outlined,
              ),
              _buildStatTile(
                key: const Key('admin_cal_stat_no_show'),
                label: 'No-Show',
                value: '${stats['noShowAppointments'] ?? 0}',
                color: const Color(0xFFD97706),
                icon: Icons.person_off_outlined,
              ),
              _buildStatTile(
                key: const Key('admin_cal_stat_online'),
                label: 'Online',
                value: '${stats['onlineConsultations'] ?? 0}',
                color: const Color(0xFF0284C7),
                icon: Icons.videocam_outlined,
              ),
              _buildStatTile(
                key: const Key('admin_cal_stat_in_person'),
                label: 'In-Person',
                value: '${stats['inPersonConsultations'] ?? 0}',
                color: const Color(0xFF4F46E5),
                icon: Icons.local_hospital_outlined,
              ),
              _buildStatTile(
                key: const Key('admin_cal_stat_new_registrations'),
                label: 'New Registrations',
                value: '${stats['newPatientRegistrations'] ?? 0}',
                color: const Color(0xFF0D9488),
                icon: Icons.person_add_alt_1_outlined,
              ),
              _buildStatTile(
                key: const Key('admin_cal_stat_referrals'),
                label: 'Patient Referrals',
                value: '${stats['patientReferrals'] ?? 0}',
                color: const Color(0xFF7C3AED),
                icon: Icons.share_outlined,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Hospital / Clinic Breakdown Section (Phase 2)
          Container(
            key: const Key('admin_calendar_hospital_breakdown_section'),
            width: double.infinity,
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
                    const Icon(Icons.domain_rounded, size: 17, color: AppTheme.gsNavy),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Hospital & Clinic Breakdown (${hospitalBreakdown.length})',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  'Tap a hospital/clinic to inspect its visits',
                  style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                if (hospitalBreakdown.isEmpty)
                  const Text(
                    'No registered hospitals or clinics found for the current filters.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  )
                else
                  ...hospitalBreakdown.map(_buildHospitalBreakdownCard),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Doctor-Wise Consultation Breakdown Section
          if (doctorBreakdown.isNotEmpty) ...[
            Container(
              key: const Key('admin_calendar_doctor_breakdown_section'),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Doctor-Wise Consultation Counts on $selectedDateYmd (${doctorBreakdown.length})',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: doctorBreakdown.map((d) {
                      final dName = (d['doctorName'] ?? 'Doctor').toString();
                      final spec = (d['specialty'] ?? '').toString();
                      final sched = d['scheduledConsultations'] ?? 0;
                      final visited = d['actualPatientVisits'] ?? 0;
                      final comp = d['completedConsultations'] ?? 0;
                      final pend = d['pendingConsultations'] ?? 0;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Text(
                          '$dName${spec.isNotEmpty ? ' ($spec)' : ''}: '
                          'Scheduled $sched • Visited $visited • Completed $comp • Pending $pend',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Detailed Patient Visit List on Selected Date
          Text(
            'Detailed Patient Visits on $selectedDateYmd (${visits.length})',
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 8),
          if (visits.isEmpty)
            Container(
              key: const Key('admin_calendar_empty_visits_state'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Text(
                'No patient visits scheduled on $selectedDateYmd.',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF64748B)),
                textAlign: TextAlign.center,
              ),
            )
          else
            ...visits.map(_buildAdminVisitRow),

          // Separate Referral Tracking Section (Phase 4)
          const SizedBox(height: 14),
          Container(
            key: const Key('admin_calendar_referrals_section'),
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
                Text(
                  referralsOnDate.isNotEmpty
                      ? 'Patient Referrals on $selectedDateYmd (${referralsOnDate.length})'
                      : 'Platform Referral Tracking (${displayedReferrals.length})',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF581C87),
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Referrals are tracked separately and do not count as actual patient visits unless an appointment visit is completed.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF6B21A8)),
                ),
                const SizedBox(height: 8),
                if (displayedReferrals.isEmpty)
                  const Text(
                    'No patient referrals recorded.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  )
                else
                  ...displayedReferrals.map(_buildAdminReferralRow),
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
    final leadingEmpty = firstDayOfMonth.weekday - 1;
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
            childAspectRatio: 1.15,
          ),
          itemBuilder: (context, index) {
            if (index < leadingEmpty) return const SizedBox.shrink();
            final dayNum = index - leadingEmpty + 1;
            final cellDate = DateTime(_displayedMonth.year, _displayedMonth.month, dayNum);
            final cellYmd = _formatYmd(cellDate);
            final isSelected = cellYmd == selectedYmd;
            final isToday = cellYmd == todayYmd;
            final dayInfo = monthlyCal[cellYmd] is Map
                ? Map<String, dynamic>.from(monthlyCal[cellYmd] as Map)
                : null;
            final totalAppts = int.tryParse('${dayInfo?['totalScheduledAppointments'] ?? 0}') ?? 0;
            final hasCompleted = dayInfo?['hasCompleted'] == true ||
                (int.tryParse('${dayInfo?['completedAppointments'] ?? 0}') ?? 0) > 0;
            final hasPending = dayInfo?['hasPending'] == true ||
                (int.tryParse('${dayInfo?['pendingAppointments'] ?? 0}') ?? 0) > 0;
            final hasCancelled = dayInfo?['hasCancelled'] == true ||
                dayInfo?['hasNoShow'] == true ||
                (int.tryParse('${dayInfo?['cancelledAppointments'] ?? 0}') ?? 0) > 0 ||
                (int.tryParse('${dayInfo?['noShowAppointments'] ?? 0}') ?? 0) > 0;
            final hasReferrals = dayInfo?['hasReferrals'] == true ||
                (int.tryParse('${dayInfo?['patientReferrals'] ?? 0}') ?? 0) > 0;

            return InkWell(
              key: Key('admin_calendar_day_$cellYmd'),
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
      width: 144,
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

  Widget _buildHospitalBreakdownCard(Map<String, dynamic> hosp) {
    final clinicId = (hosp['clinicId'] ?? hosp['clinicName'] ?? 'clinic').toString();
    final clinicName = (hosp['clinicName'] ?? 'Hospital / Clinic').toString();
    final sched = hosp['scheduledVisits'] ?? 0;
    final actual = hosp['actualPatientVisits'] ?? 0;
    final comp = hosp['completedVisits'] ?? 0;
    final pend = hosp['pendingVisits'] ?? 0;
    final canc = hosp['cancelledVisits'] ?? 0;
    final assignedDocs = ((hosp['assignedDoctors'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final hospVisits = ((hosp['visits'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final isExpanded = _selectedDrilldownClinicKey == clinicId;

    return Container(
      key: Key('admin_calendar_hospital_card_$clinicId'),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isExpanded ? AppTheme.primaryBlue : const Color(0xFFE2E8F0),
          width: isExpanded ? 1.4 : 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          setState(() {
            _selectedDrilldownClinicKey = isExpanded ? null : clinicId;
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.local_hospital_rounded, size: 17, color: AppTheme.primaryBlue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      clinicName,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: AppTheme.gsNavy,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _miniCountChip('Scheduled: $sched', AppTheme.gsNavy),
                  _miniCountChip('Actual Visits: $actual', const Color(0xFF0F766E)),
                  _miniCountChip('Completed: $comp', const Color(0xFF16A34A)),
                  _miniCountChip('Pending: $pend', const Color(0xFF2563EB)),
                  _miniCountChip('Cancelled: $canc', const Color(0xFFDC2626)),
                ],
              ),
              if (assignedDocs.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Assigned Doctors: ${assignedDocs.map((d) => '${d['doctorName']}${d['specialty'] != null && d['specialty'].toString().isNotEmpty ? ' (${d['specialty']})' : ''}').join(', ')}',
                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (isExpanded) ...[
                const Divider(height: 16, color: Color(0xFFE2E8F0)),
                Text(
                  'Detailed Patient Visits at $clinicName (${hospVisits.length})',
                  key: Key('admin_calendar_hospital_visits_header_$clinicId'),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.gsNavy,
                  ),
                ),
                const SizedBox(height: 6),
                if (hospVisits.isEmpty)
                  const Text(
                    'No patient visits recorded for this hospital/clinic on the selected date.',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                  )
                else
                  ...hospVisits.map(_buildAdminVisitRow),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniCountChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }

  Widget _buildAdminVisitRow(Map<String, dynamic> visit) {
    final apptId = (visit['appointmentId'] ?? visit['id'] ?? '').toString();
    final pName = (visit['patientName'] ?? 'Patient').toString();
    final dName = (visit['doctorName'] ?? 'Doctor').toString();
    final cName = (visit['clinicName'] ?? '').toString();
    final cType = (visit['consultationType'] ?? 'In-Person').toString();
    final spec = (visit['specialty'] ?? '').toString();
    final time = (visit['consultationTime'] ?? '').toString();
    final statusRaw = (visit['status'] ?? 'PENDING').toString();
    final statusLabel = BookingRulesConfig.formatAppointmentStatusLabel(statusRaw);
    final actuallyVisited = visit['actuallyVisited'] == true;

    return Container(
      key: Key('admin_calendar_visit_row_$apptId'),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$pName • #$apptId • $time • $cType • $dName${spec.isNotEmpty ? ' ($spec)' : ''}${cName.isNotEmpty ? ' • $cName' : ''}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          _miniCountChip(
            actuallyVisited ? '$statusLabel (Visited)' : statusLabel,
            actuallyVisited ? const Color(0xFF16A34A) : const Color(0xFF2563EB),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminReferralRow(Map<String, dynamic> ref) {
    final refId = (ref['referralId'] ?? ref['id'] ?? '').toString();
    final referred = (ref['referredPatientName'] ?? 'Referred Patient').toString();
    final referring = (ref['referringPatientName'] ?? 'Referring Patient').toString();
    final doc = (ref['referredDoctorName'] ?? 'Unassigned').toString();
    final date = (ref['referralDate'] ?? '').toString();
    final status = (ref['referralStatus'] ?? 'Pending').toString();
    final booked = ref['hasBookedAppointment'] == true;
    final completed = ref['hasCompletedConsultation'] == true;

    return Container(
      key: Key('admin_calendar_referral_row_$refId'),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                  'Referred: $referred • By: $referring • Doctor: $doc • Date: $date',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _miniCountChip(status, const Color(0xFF7C3AED)),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _miniCountChip(
                booked ? 'Booked Appointment: Yes' : 'Booked Appointment: No',
                booked ? const Color(0xFF2563EB) : const Color(0xFF64748B),
              ),
              _miniCountChip(
                completed ? 'Completed Consultation: Yes' : 'Completed Consultation: No',
                completed ? const Color(0xFF16A34A) : const Color(0xFFD97706),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
