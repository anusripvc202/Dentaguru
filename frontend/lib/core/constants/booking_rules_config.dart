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

  /// Filters candidate [slots] on [date] considering advance booking, maximum window,
  /// [occupiedIntervals] (each `{startMin, occupiedEndMin}` or similar), and [blockedIntervals].
  static List<String> computeHybridAvailableSlots({
    required DateTime date,
    required Iterable<String> slots,
    String consultationMode = 'In-Person',
    List<Map<String, dynamic>> occupiedIntervals = const [],
    List<Map<String, dynamic>> blockedIntervals = const [],
    DateTime? nowOverride,
    int? minAdvanceMinutes,
    String? workingEndTime,
    String? breakStartTime,
    String? breakEndTime,
  }) {
    final duration = durationForMode(consultationMode);
    final buffer = bufferForMode(consultationMode);
    final totalNeeded = duration + buffer;
    final workEndMin = workingEndTime != null ? parseClockSlotMinutes(workingEndTime) : null;
    final brStartMin = breakStartTime != null ? parseClockSlotMinutes(breakStartTime) : null;
    final brEndMin = breakEndTime != null ? parseClockSlotMinutes(breakEndTime) : null;
    final hasBreak = brStartMin != null && brEndMin != null && brEndMin > brStartMin;

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
      if (hasBreak && intervalsOverlap(candStart, candConsultEnd, brStartMin, brEndMin)) return false;

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
}
