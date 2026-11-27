/// Centralized, separately configurable Smart Hybrid Appointment Booking & Doctor Schedule Rules.
///
/// Unifies In-Person and Online consultations on a single doctor calendar with configurable
/// consultation durations, post-consultation buffers, slot intervals, advance lead times,
/// maximum booking windows, and admin delay alert thresholds.
class BookingRulesConfig {
  BookingRulesConfig._();

  /// In-Person consultation duration in minutes.
  static int inPersonDurationMinutes = 30;

  /// Online consultation duration in minutes.
  static int onlineDurationMinutes = 20;

  /// Buffer time reserved after In-Person consultations in minutes.
  static int inPersonBufferMinutes = 10;

  /// Buffer time reserved after Online consultations in minutes.
  static int onlineBufferMinutes = 5;

  /// Minimum advance lead time (in minutes) required before a slot's start time on today's date.
  static int minAdvanceBookingMinutes = 30;

  /// Default consultation slot interval (in minutes) when generating doctor schedules.
  static int defaultSlotIntervalMinutes = 30;

  /// Maximum days ahead selectable in the appointment calendar.
  static int maxAdvanceBookingDays = 90;

  /// Delay duration (in minutes) at or above which Admin is alerted.
  static int adminDelayAlertThresholdMinutes = 15;

  /// Clinic/server timezone identifier used for hybrid scheduling metadata.
  static String timezone = 'Asia/Kolkata';

  /// Optional test clock override for deterministic unit/widget tests.
  static DateTime? debugNowOverride;

  static const List<String> consultationModes = <String>[
    'In-Person',
    'Online',
  ];

  static const List<String> canonicalAppointmentStatuses = <String>[
    'Pending',
    'Confirmed',
    'In Progress',
    'Delayed',
    'Completed',
    'No-Show',
    'Cancelled',
    'Rejected',
    'Rescheduled',
  ];

  static const List<String> doctorStatuses = <String>[
    'Available',
    'Busy – Online Consultation',
    'Busy – In-Person Consultation',
    'Delayed',
    'Offline',
    'Online',
    'Busy',
    'Unavailable',
  ];

  static void resetDefaults() {
    inPersonDurationMinutes = 30;
    onlineDurationMinutes = 20;
    inPersonBufferMinutes = 10;
    onlineBufferMinutes = 5;
    minAdvanceBookingMinutes = 30;
    defaultSlotIntervalMinutes = 30;
    maxAdvanceBookingDays = 90;
    adminDelayAlertThresholdMinutes = 15;
    timezone = 'Asia/Kolkata';
    debugNowOverride = null;
  }

  static void applyFromJson(Map<String, dynamic> json) {
    int? parsePos(dynamic v, {int min = 0}) {
      if (v == null) return null;
      final parsed = int.tryParse(v.toString());
      if (parsed == null) return null;
      return parsed < min ? min : parsed;
    }

    inPersonDurationMinutes = parsePos(json['inPersonDurationMinutes'], min: 5) ?? inPersonDurationMinutes;
    onlineDurationMinutes = parsePos(json['onlineDurationMinutes'], min: 5) ?? onlineDurationMinutes;
    inPersonBufferMinutes = parsePos(json['inPersonBufferMinutes'], min: 0) ?? inPersonBufferMinutes;
    onlineBufferMinutes = parsePos(json['onlineBufferMinutes'], min: 0) ?? onlineBufferMinutes;
    minAdvanceBookingMinutes = parsePos(json['minAdvanceBookingMinutes'], min: 0) ?? minAdvanceBookingMinutes;
    defaultSlotIntervalMinutes = parsePos(json['defaultSlotIntervalMinutes'], min: 5) ?? defaultSlotIntervalMinutes;
    maxAdvanceBookingDays = parsePos(json['maxAdvanceBookingDays'], min: 1) ?? maxAdvanceBookingDays;
    adminDelayAlertThresholdMinutes =
        parsePos(json['adminDelayAlertThresholdMinutes'], min: 1) ?? adminDelayAlertThresholdMinutes;
    final tz = json['timezone']?.toString().trim() ?? '';
    if (tz.isNotEmpty) timezone = tz;
  }

  static Map<String, dynamic> toJson() => <String, dynamic>{
        'inPersonDurationMinutes': inPersonDurationMinutes,
        'onlineDurationMinutes': onlineDurationMinutes,
        'inPersonBufferMinutes': inPersonBufferMinutes,
        'onlineBufferMinutes': onlineBufferMinutes,
        'minAdvanceBookingMinutes': minAdvanceBookingMinutes,
        'defaultSlotIntervalMinutes': defaultSlotIntervalMinutes,
        'maxAdvanceBookingDays': maxAdvanceBookingDays,
        'adminDelayAlertThresholdMinutes': adminDelayAlertThresholdMinutes,
        'timezone': timezone,
      };

  static String normalizeConsultationMode(String raw) {
    final lower = raw.trim().toLowerCase();
    if (lower.contains('online') || lower.contains('video') || lower.contains('tele') || lower.contains('virtual')) {
      return 'Online';
    }
    return 'In-Person';
  }

  static String normalizeConsultationType(String raw) => normalizeConsultationMode(raw);

  static int durationForMode(String mode) =>
      normalizeConsultationMode(mode) == 'Online' ? onlineDurationMinutes : inPersonDurationMinutes;

  static int durationForType(String mode) => durationForMode(mode);

  static int bufferForMode(String mode) =>
      normalizeConsultationMode(mode) == 'Online' ? onlineBufferMinutes : inPersonBufferMinutes;

  static int bufferForType(String mode) => bufferForMode(mode);

  static String minutesToClockSlot(int totalMinutes) {
    final wrapped = ((totalMinutes % 1440) + 1440) % 1440;
    int hours = wrapped ~/ 60;
    final mins = wrapped % 60;
    final period = hours >= 12 ? 'PM' : 'AM';
    if (hours > 12) hours -= 12;
    if (hours == 0) hours = 12;
    return '${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')} $period';
  }

  static String formatMinutesToSlot(int totalMinutes) => minutesToClockSlot(totalMinutes);

  static int? parseSlotToMinutes(String rawSlot) => parseClockSlotMinutes(rawSlot);

  static bool intervalsOverlap(int startA, int endA, int startB, int endB) =>
      startA < endB && endA > startB;

  /// Generates non-overlapping base time slots for a consultation mode given start/end times,
  /// duration, optional buffer step, and multiple breaks.
  static List<String> generateSlotsWithBreaks({
    required String startTime,
    required String endTime,
    required int durationMinutes,
    int bufferMinutes = 0,
    int? stepMinutes,
    List<Map<String, dynamic>> breaks = const [],
  }) {
    final startMin = parseClockSlotMinutes(startTime);
    final endMin = parseClockSlotMinutes(endTime);
    final dur = durationMinutes >= 5 ? durationMinutes : 30;
    final buf = bufferMinutes >= 0 ? bufferMinutes : 0;
    final step = (stepMinutes != null && stepMinutes > 0) ? stepMinutes : (buf > 0 ? dur + buf : dur);
    if (startMin == null || endMin == null || startMin >= endMin) return const [];

    final parsedBreaks = <({int startMin, int endMin})>[];
    for (final b in breaks) {
      final s = int.tryParse(b['startMin']?.toString() ?? '') ??
          parseClockSlotMinutes((b['startTime'] ?? b['start_time'] ?? '').toString());
      final e = int.tryParse(b['endMin']?.toString() ?? '') ??
          parseClockSlotMinutes((b['endTime'] ?? b['end_time'] ?? '').toString());
      if (s != null && e != null && e > s) {
        parsedBreaks.add((startMin: s, endMin: e));
      }
    }
    parsedBreaks.sort((a, b) => a.startMin.compareTo(b.startMin));

    final slots = <String>[];
    int current = startMin;
    while (current + dur <= endMin) {
      final slotEnd = current + dur;
      ({int startMin, int endMin})? hitBreak;
      for (final br in parsedBreaks) {
        if (intervalsOverlap(current, slotEnd, br.startMin, br.endMin)) {
          hitBreak = br;
          break;
        }
      }
      if (hitBreak != null) {
        current = hitBreak.endMin > (current + 5) ? hitBreak.endMin : (current + 5);
        continue;
      }
      slots.add(minutesToClockSlot(current));
      current += step;
    }
    return slots;
  }

  /// Filters candidate [slots] on [date] considering advance booking, maximum window,
  /// [occupiedIntervals] (each `{startMin, occupiedEndMin}` or similar), and [blockedIntervals].
  static List<String> computeHybridAvailableSlots({
    required DateTime date,
    required Iterable<String> slots,
    String consultationMode = 'In-Person',
    int? durationMinutesOverride,
    int? bufferMinutesOverride,
    List<Map<String, dynamic>> breaks = const [],
    List<Map<String, dynamic>> occupiedIntervals = const [],
    List<Map<String, dynamic>> blockedIntervals = const [],
    DateTime? nowOverride,
    int? minAdvanceMinutes,
    String? workingEndTime,
    String? breakStartTime,
    String? breakEndTime,
  }) {
    final duration = (durationMinutesOverride != null && durationMinutesOverride > 0)
        ? durationMinutesOverride
        : durationForMode(consultationMode);
    final buffer = (bufferMinutesOverride != null && bufferMinutesOverride >= 0)
        ? bufferMinutesOverride
        : bufferForMode(consultationMode);
    final totalNeeded = duration + buffer;
    final workEndMin = workingEndTime != null ? parseClockSlotMinutes(workingEndTime) : null;
    final brStartMin = breakStartTime != null ? parseClockSlotMinutes(breakStartTime) : null;
    final brEndMin = breakEndTime != null ? parseClockSlotMinutes(breakEndTime) : null;
    final hasBreak = brStartMin != null && brEndMin != null && brEndMin > brStartMin;

    final parsedBreaks = <({int startMin, int endMin})>[];
    for (final b in breaks) {
      final s = int.tryParse(b['startMin']?.toString() ?? '') ??
          parseClockSlotMinutes((b['startTime'] ?? b['start_time'] ?? '').toString());
      final e = int.tryParse(b['endMin']?.toString() ?? '') ??
          parseClockSlotMinutes((b['endTime'] ?? b['end_time'] ?? '').toString());
      if (s != null && e != null && e > s) {
        parsedBreaks.add((startMin: s, endMin: e));
      }
    }

    return slots.where((slot) {
      if (!isSlotBookableForDate(
        date,
        slot,
        nowOverride: nowOverride,
        minAdvanceMinutes: minAdvanceMinutes,
      )) {
        return false;
      }
      final candStart = parseClockSlotMinutes(slot);
      if (candStart == null) return true;
      final candConsultEnd = candStart + duration;
      final candOccupiedEnd = candStart + totalNeeded;

      if (workEndMin != null && candConsultEnd > workEndMin) return false;
      if (parsedBreaks.isNotEmpty) {
        if (parsedBreaks.any((br) => intervalsOverlap(candStart, candConsultEnd, br.startMin, br.endMin))) {
          return false;
        }
      } else if (hasBreak && intervalsOverlap(candStart, candConsultEnd, brStartMin, brEndMin)) {
        return false;
      }

      for (final b in blockedIntervals) {
        final bStart = int.tryParse(b['startMin']?.toString() ?? '') ??
            parseClockSlotMinutes(b['startTime']?.toString() ?? b['slot']?.toString() ?? '');
        final bEnd = int.tryParse(b['endMin']?.toString() ?? '') ??
            parseClockSlotMinutes(b['endTime']?.toString() ?? '') ??
            (bStart != null ? bStart + defaultSlotIntervalMinutes : null);
        if (bStart != null && bEnd != null && intervalsOverlap(candStart, candConsultEnd, bStart, bEnd)) {
          return false;
        }
      }

      for (final occ in occupiedIntervals) {
        final oStart = int.tryParse(occ['startMin']?.toString() ?? '') ??
            parseClockSlotMinutes(occ['timeSlot']?.toString() ?? '');
        final oEnd = int.tryParse(occ['occupiedEndMin']?.toString() ?? '') ??
            (oStart != null
                ? oStart +
                    (int.tryParse(occ['durationMinutes']?.toString() ?? '') ?? inPersonDurationMinutes) +
                    (int.tryParse(occ['bufferMinutes']?.toString() ?? '') ?? inPersonBufferMinutes) +
                    (int.tryParse(occ['delayMinutes']?.toString() ?? '') ?? 0)
                : null);
        if (oStart != null && oEnd != null && intervalsOverlap(candStart, candOccupiedEnd, oStart, oEnd)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  /// Parses `"hh:mm AM/PM"` into minutes from midnight, or returns `null` for non-clock labels.
  static int? parseClockSlotMinutes(String rawSlot) {
    final trimmed = rawSlot.trim();
    final match = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)$', caseSensitive: false)
        .firstMatch(trimmed);
    if (match == null) return null;
    int hours = int.tryParse(match.group(1)!) ?? -1;
    final int mins = int.tryParse(match.group(2)!) ?? -1;
    final String period = match.group(3)!.toUpperCase();
    if (hours < 1 || hours > 12 || mins < 0 || mins > 59) return null;
    if (period == 'PM' && hours < 12) hours += 12;
    if (period == 'AM' && hours == 12) hours = 0;
    return hours * 60 + mins;
  }

  /// Returns `true` if [slot] on [date] is not in the past and satisfies [minAdvanceBookingMinutes].
  static bool isSlotBookableForDate(
    DateTime date,
    String slot, {
    DateTime? nowOverride,
    int? minAdvanceMinutes,
  }) {
    final now = nowOverride ?? debugNowOverride ?? DateTime.now();
    final minAdv = minAdvanceMinutes ?? minAdvanceBookingMinutes;

    final targetDay = DateTime(date.year, date.month, date.day);
    final todayDay = DateTime(now.year, now.month, now.day);

    if (targetDay.isBefore(todayDay)) return false;
    final maxDay = todayDay.add(Duration(days: maxAdvanceBookingDays));
    if (targetDay.isAfter(maxDay)) return false;
    if (targetDay.isAfter(todayDay)) return true;

    // Same calendar day: enforce past-slot removal + minimum advance notice
    final slotMins = parseClockSlotMinutes(slot);
    if (slotMins == null) return true;
    final nowMins = now.hour * 60 + now.minute;
    return slotMins >= (nowMins + minAdv);
  }

  /// Filters [slots] for [date], removing past slots and slots inside the advance-booking window.
  static List<String> filterBookableSlotsForDate(
    DateTime date,
    Iterable<String> slots, {
    DateTime? nowOverride,
    int? minAdvanceMinutes,
  }) {
    return slots
        .where(
          (s) => isSlotBookableForDate(
            date,
            s,
            nowOverride: nowOverride,
            minAdvanceMinutes: minAdvanceMinutes,
          ),
        )
        .toList();
  }

  /// Formats a doctor's consultation fee cleanly without duplicating currency symbols or inventing dummy fees.
  static String formatRealFee(String? rawFee, {String emptyFallback = 'As per clinic tariff'}) {
    final clean = (rawFee ?? '').trim();
    if (clean.isEmpty ||
        clean.toLowerCase() == 'null' ||
        clean == r'$75' ||
        clean == '75') {
      return emptyFallback;
    }
    if (clean.startsWith('₹') || RegExp(r'^[A-Za-z₹$€£]').hasMatch(clean)) {
      return clean;
    }
    return '₹$clean';
  }

  /// Maps backend/local status strings into canonical display statuses.
  static String formatAppointmentStatusLabel(String rawStatus) {
    final s = rawStatus.trim().toUpperCase();
    if (s == 'CONFIRMED' || s == 'ACCEPTED' || s == 'DENTIST_ACCEPTED') {
      return 'Confirmed';
    }
    if (s == 'IN_PROGRESS' || s == 'STARTED') return 'In Progress';
    if (s == 'DELAYED') return 'Delayed';
    if (s == 'NO_SHOW' || s == 'NOSHOW') return 'No-Show';
    if (s == 'CANCELLED' || s == 'CANCELED') return 'Cancelled';
    if (s == 'COMPLETED') return 'Completed';
    if (s == 'REJECTED' || s == 'DECLINED') return 'Rejected';
    if (s == 'RESCHEDULED') return 'Rescheduled';
    return 'Pending';
  }

  /// Returns the current wall-clock [DateTime] in `Asia/Kolkata` (IST, UTC+05:30).
  /// When [nowOverride] or [debugNowOverride] is set:
  /// - If it is a UTC [DateTime], converts to IST (`UTC + 5h30m`).
  /// - If it is a non-UTC [DateTime], treats its wall-clock year/month/day/hour/minute directly as `Asia/Kolkata`.
  /// When using the real system clock, converts `DateTime.now().toUtc()` to `Asia/Kolkata` (`UTC + 5h30m`).
  static DateTime nowInIst({DateTime? nowOverride}) {
    final override = nowOverride ?? debugNowOverride;
    if (override != null) {
      if (override.isUtc) {
        final ist = override.add(const Duration(hours: 5, minutes: 30));
        return DateTime(ist.year, ist.month, ist.day, ist.hour, ist.minute, ist.second);
      }
      return DateTime(
        override.year,
        override.month,
        override.day,
        override.hour,
        override.minute,
        override.second,
      );
    }
    final utcNow = DateTime.now().toUtc();
    final ist = utcNow.add(const Duration(hours: 5, minutes: 30));
    return DateTime(ist.year, ist.month, ist.day, ist.hour, ist.minute, ist.second);
  }

  /// Formats a [DateTime] into `YYYY-MM-DD`.
  static String formatYmd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  /// Normalizes a raw date string (`YYYY-MM-DD` or ISO timestamp) into an `Asia/Kolkata` `YYYY-MM-DD` string.
  static String normalizeDateToIstYmd(String? rawDate) {
    final str = (rawDate ?? '').trim();
    if (str.isEmpty || str == 'null') return '';
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(str)) {
      return str;
    }
    if (RegExp(r'^\d{4}-\d{2}-\d{2}T00:00:00(?:\.000)?Z?$', caseSensitive: false).hasMatch(str)) {
      return str.substring(0, 10);
    }
    final parsed = DateTime.tryParse(str);
    if (parsed != null) {
      if (parsed.isUtc) {
        final ist = parsed.add(const Duration(hours: 5, minutes: 30));
        return formatYmd(ist);
      }
      return formatYmd(parsed);
    }
    if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(str)) {
      return str.substring(0, 10);
    }
    return '';
  }

  /// Returns `true` only if [rawStatus] is an eligible confirmed/accepted or active status for Current Consultation,
  /// and [actualEndAt] is not populated.
  /// Excludes Completed, Cancelled, No-Show, Rejected, and Pending/unconfirmed statuses.
  static bool isEligibleForCurrentConsultation(
    String? rawStatus, {
    String? actualEndAt,
  }) {
    if (actualEndAt != null && actualEndAt.trim().isNotEmpty && actualEndAt.trim() != 'null') {
      return false;
    }
    final s = (rawStatus ?? '').trim().toUpperCase();
    if (s.isEmpty) return false;
    const excluded = <String>{
      'COMPLETED',
      'CANCELLED',
      'CANCELED',
      'REJECTED',
      'DECLINED',
      'NO_SHOW',
      'NOSHOW',
      'NO-SHOW',
      'PENDING',
      'PENDING_ADMIN_REVIEW',
      'PENDING ADMIN REVIEW',
      'SUBMITTED',
      'ADMIN REVIEW',
      'UNCONFIRMED',
      'AWAITING',
      'EXPIRED',
    };
    if (excluded.contains(s)) return false;
    const allowed = <String>{
      'CONFIRMED',
      'ACCEPTED',
      'DENTIST_ACCEPTED',
      'DOCTOR_ASSIGNED',
      'DOCTOR ASSIGNED',
      'APPROVED',
      'SCHEDULED',
      'IN_PROGRESS',
      'IN PROGRESS',
      'STARTED',
      'DELAYED',
      'RESCHEDULED',
    };
    return allowed.contains(s);
  }

  /// Returns `true` only if [rawStatus] is an eligible upcoming confirmed status for Next Patient,
  /// and [actualEndAt] is not populated.
  /// Excludes Completed, Cancelled, No-Show, Rejected, Pending/unconfirmed, and already-started In-Progress statuses.
  static bool isEligibleForNextConsultation(
    String? rawStatus, {
    String? actualEndAt,
  }) {
    if (!isEligibleForCurrentConsultation(rawStatus, actualEndAt: actualEndAt)) {
      return false;
    }
    final s = (rawStatus ?? '').trim().toUpperCase();
    return s != 'IN_PROGRESS' && s != 'IN PROGRESS' && s != 'STARTED';
  }

  /// Evaluates the live Current Patient and Next Patient for a single doctor on [targetDateYmd]
  /// (defaults to today in `Asia/Kolkata`) using the actual current time in `Asia/Kolkata`.
  ///
  /// Rules enforced:
  /// - **Current Patient**: Only when `startMin <= currentMinutes < endMin` on today's date in `Asia/Kolkata`,
  ///   with an eligible confirmed/accepted/ongoing status. Immediately removed once `currentMinutes >= endMin`
  ///   or when marked Completed / Cancelled / No-Show.
  /// - **Next Patient**: Next eligible upcoming confirmed appointment on today's date whose `startMin > currentMinutes`,
  ///   sorted by actual start time ascending, excluding the current appointment and preventing duplicate patients.
  static Map<String, dynamic> evaluateDoctorLiveSchedule({
    required String doctorId,
    required String doctorName,
    String specialty = '',
    String initialAvailability = 'Available',
    int initialDelayMinutes = 0,
    required List<Map<String, dynamic>> appointments,
    DateTime? nowOverride,
    String? targetDateYmd,
  }) {
    final nowIst = nowInIst(nowOverride: nowOverride);
    final todayIstYmd = formatYmd(nowIst);
    final effectiveDateYmd = (targetDateYmd != null && targetDateYmd.trim().isNotEmpty)
        ? targetDateYmd.trim()
        : todayIstYmd;
    final isTargetToday = effectiveDateYmd == todayIstYmd;
    final nowMinutes = nowIst.hour * 60 + nowIst.minute;

    String patientKeyFor(Map<String, dynamic> a) {
      final pid = (a['patientId'] ?? a['patient_id'] ?? '').toString().trim().toLowerCase();
      final pname = (a['patientName'] ?? a['patient_name'] ?? '').toString().trim().toLowerCase();
      final pphone = (a['phone'] ?? a['patient_phone'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
      if (pid.isNotEmpty && pid != 'null') return pid;
      return '$pname|$pphone';
    }

    final seenSlotPatientKeys = <String>{};
    final validTodayAppts = <Map<String, dynamic>>[];
    int maxExplicitDelayMinutes = initialDelayMinutes;

    for (final raw in appointments) {
      final statusRaw = (raw['status'] ?? '').toString().trim();
      final statusUpper = statusRaw.toUpperCase();
      final actualEndAt = (raw['actualEndAt'] ?? raw['actual_end_at'] ?? '').toString().trim();
      final rawDelay = int.tryParse((raw['delayMinutes'] ?? raw['delay_minutes'] ?? '0').toString()) ?? 0;
      if (statusUpper == 'DELAYED' && actualEndAt.isEmpty && rawDelay > maxExplicitDelayMinutes) {
        maxExplicitDelayMinutes = rawDelay;
      }

      if (statusUpper == 'CANCELLED' ||
          statusUpper == 'CANCELED' ||
          statusUpper == 'REJECTED' ||
          statusUpper == 'DECLINED' ||
          statusUpper == 'NO_SHOW' ||
          statusUpper == 'NOSHOW' ||
          statusUpper == 'NO-SHOW') {
        continue;
      }

      // Strictly use appointment date (never booking creation timestamp)
      final rawDateStr = (raw['date'] ?? raw['dateRaw'] ?? raw['appointment_date'] ?? '').toString().trim();
      final apptDateYmd = normalizeDateToIstYmd(rawDateStr);
      if (apptDateYmd.isEmpty || apptDateYmd != effectiveDateYmd) {
        continue;
      }

      // Strictly use scheduled appointment start time slot (never booking creation timestamp)
      final rawStartSlot = (raw['scheduledStartTime'] ??
              raw['scheduled_start_time'] ??
              raw['timeSlot'] ??
              raw['time_slot'] ??
              '')
          .toString()
          .trim();
      final startMin = parseClockSlotMinutes(rawStartSlot);
      if (startMin == null) continue;

      final rawMode = (raw['consultationType'] ??
              raw['consultationMode'] ??
              raw['consultation_type'] ??
              raw['mode'] ??
              raw['treatment'] ??
              '')
          .toString();
      final consultationType = normalizeConsultationMode(rawMode);

      final rawEndSlot = (raw['scheduledEndTime'] ?? raw['scheduled_end_time'] ?? '').toString().trim();
      final parsedEndMin = parseClockSlotMinutes(rawEndSlot);
      final explicitDuration = int.tryParse((raw['durationMinutes'] ?? raw['duration_minutes'] ?? '').toString());
      final durationMin = (parsedEndMin != null && parsedEndMin > startMin)
          ? (parsedEndMin - startMin)
          : ((explicitDuration != null && explicitDuration > 0)
              ? explicitDuration
              : durationForMode(consultationType));
      final endMin = startMin + durationMin;

      final pKey = patientKeyFor(raw);
      final dedupKey = '$pKey|$apptDateYmd|$startMin';
      if (!seenSlotPatientKeys.add(dedupKey)) {
        continue;
      }

      validTodayAppts.add({
        ...raw,
        '_apptDateYmd': apptDateYmd,
        '_startMin': startMin,
        '_endMin': endMin,
        '_durationMin': durationMin,
        '_consultationType': consultationType,
        '_patientKey': pKey,
      });
    }

    validTodayAppts.sort((a, b) => (a['_startMin'] as int).compareTo(b['_startMin'] as int));

    // Clamp consecutive appointments on the same doctor's schedule so intervals do not overlap
    for (int i = 0; i < validTodayAppts.length - 1; i++) {
      final cur = validTodayAppts[i];
      final nxt = validTodayAppts[i + 1];
      final curStart = cur['_startMin'] as int;
      final curEnd = cur['_endMin'] as int;
      final nxtStart = nxt['_startMin'] as int;
      if (curStart < nxtStart && curEnd > nxtStart) {
        cur['_endMin'] = nxtStart;
      }
    }

    // 1. Identify Current Patient: ONLY when target date is today in Asia/Kolkata AND startMin <= nowMinutes < endMin
    Map<String, dynamic>? activeCurrent;
    if (isTargetToday) {
      final currentCandidates = validTodayAppts.where((a) {
        final st = (a['status'] ?? '').toString();
        final actualEnd = (a['actualEndAt'] ?? a['actual_end_at'] ?? '').toString();
        if (!isEligibleForCurrentConsultation(st, actualEndAt: actualEnd)) {
          return false;
        }
        final sMin = a['_startMin'] as int;
        final eMin = a['_endMin'] as int;
        return sMin <= nowMinutes && nowMinutes < eMin;
      }).toList();

      if (currentCandidates.isNotEmpty) {
        activeCurrent = currentCandidates.firstWhere(
          (a) {
            final st = (a['status'] ?? '').toString().trim().toUpperCase();
            return st == 'IN_PROGRESS' || st == 'IN PROGRESS' || st == 'STARTED' || st == 'DELAYED';
          },
          orElse: () => currentCandidates.last,
        );
      }
    }

    // 2. Identify Next Patient: strictly startMin > nowMinutes, eligible confirmed status, not current patient
    Map<String, dynamic>? nextAppt;
    if (isTargetToday) {
      final nextCandidates = validTodayAppts.where((a) {
        final st = (a['status'] ?? '').toString();
        final actualEnd = (a['actualEndAt'] ?? a['actual_end_at'] ?? '').toString();
        if (!isEligibleForNextConsultation(st, actualEndAt: actualEnd)) {
          return false;
        }
        final sMin = a['_startMin'] as int;
        if (sMin <= nowMinutes) return false;
        if (activeCurrent != null) {
          final curId = (activeCurrent['id'] ?? '').toString().trim();
          final candId = (a['id'] ?? '').toString().trim();
          if (curId.isNotEmpty && curId == candId) return false;
          final curPKey = (activeCurrent['_patientKey'] ?? '').toString();
          final candPKey = (a['_patientKey'] ?? '').toString();
          if (curPKey.isNotEmpty && curPKey == candPKey) return false;
          final curEndMin = activeCurrent['_endMin'] as int;
          if (sMin < curEndMin) return false;
        }
        return true;
      }).toList();

      nextCandidates.sort((a, b) => (a['_startMin'] as int).compareTo(b['_startMin'] as int));
      if (nextCandidates.isNotEmpty) {
        nextAppt = nextCandidates.first;
      }
    }

    final currentDelay = activeCurrent != null
        ? (int.tryParse((activeCurrent['delayMinutes'] ?? activeCurrent['delay_minutes'] ?? '0').toString()) ?? 0)
        : 0;
    final delayDuration = currentDelay > 0 ? currentDelay : maxExplicitDelayMinutes;

    String liveAvailability = initialAvailability.trim().isNotEmpty ? initialAvailability.trim() : 'Available';
    if (activeCurrent != null) {
      final curSt = (activeCurrent['status'] ?? '').toString().trim().toUpperCase();
      if (curSt == 'DELAYED' || currentDelay > 0) {
        liveAvailability = 'Delayed';
      } else {
        final cType = (activeCurrent['_consultationType'] ?? 'In-Person').toString();
        liveAvailability = cType == 'Online'
            ? 'Busy – Online Consultation'
            : 'Busy – In-Person Consultation';
      }
    } else if (delayDuration > 0) {
      liveAvailability = 'Delayed';
    } else if (liveAvailability.startsWith('Busy')) {
      liveAvailability = 'Available';
    }

    Map<String, dynamic>? formattedCurrent;
    if (activeCurrent != null) {
      final sMin = activeCurrent['_startMin'] as int;
      final eMin = activeCurrent['_endMin'] as int;
      final curSt = (activeCurrent['status'] ?? '').toString().trim().toUpperCase();
      final actualStart = (activeCurrent['actualStartAt'] ?? activeCurrent['actual_start_at'] ?? '').toString().trim();
      final String liveStatusLabel = (curSt == 'DELAYED' || currentDelay > 0)
          ? 'Delayed'
          : (curSt == 'IN_PROGRESS' || curSt == 'IN PROGRESS' || curSt == 'STARTED' || actualStart.isNotEmpty)
              ? 'In Progress'
              : 'Ongoing';
      formattedCurrent = <String, dynamic>{
        'id': (activeCurrent['id'] ?? '').toString(),
        'patientId': (activeCurrent['patientId'] ?? activeCurrent['patient_id'] ?? '').toString(),
        'patientName': (activeCurrent['patientName'] ?? activeCurrent['patient_name'] ?? 'Patient').toString().trim(),
        'consultationType': (activeCurrent['_consultationType'] ?? 'In-Person').toString(),
        'consultationMode': (activeCurrent['_consultationType'] ?? 'In-Person').toString(),
        'scheduledStartTime': minutesToClockSlot(sMin),
        'scheduledEndTime': minutesToClockSlot(eMin),
        'startMin': sMin,
        'endMin': eMin,
        'status': (activeCurrent['status'] ?? 'CONFIRMED').toString(),
        'liveStatus': liveStatusLabel,
        'actualStartAt': actualStart.isNotEmpty ? actualStart : null,
        'actualEndAt': null,
        'delayMinutes': currentDelay,
      };
    }

    Map<String, dynamic>? formattedNext;
    if (nextAppt != null) {
      final sMin = nextAppt['_startMin'] as int;
      final eMin = nextAppt['_endMin'] as int;
      final estStart = (nextAppt['estimatedStartTime'] ?? nextAppt['estimated_start_time'] ?? '').toString().trim();
      formattedNext = <String, dynamic>{
        'id': (nextAppt['id'] ?? '').toString(),
        'patientId': (nextAppt['patientId'] ?? nextAppt['patient_id'] ?? '').toString(),
        'patientName': (nextAppt['patientName'] ?? nextAppt['patient_name'] ?? 'Patient').toString().trim(),
        'consultationType': (nextAppt['_consultationType'] ?? 'In-Person').toString(),
        'consultationMode': (nextAppt['_consultationType'] ?? 'In-Person').toString(),
        'scheduledStartTime': minutesToClockSlot(sMin),
        'scheduledEndTime': minutesToClockSlot(eMin),
        'startMin': sMin,
        'endMin': eMin,
        'status': (nextAppt['status'] ?? 'CONFIRMED').toString(),
        'estimatedStartTime': estStart.isNotEmpty ? estStart : null,
      };
    }

    return <String, dynamic>{
      'doctorId': doctorId,
      'doctorName': doctorName,
      'specialty': specialty,
      'currentAvailability': liveAvailability,
      'delayDurationMinutes': delayDuration,
      'currentAppointment': formattedCurrent,
      'nextAppointment': formattedNext,
    };
  }
}
