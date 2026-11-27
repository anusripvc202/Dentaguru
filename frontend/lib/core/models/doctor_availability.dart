class SlotLockModel {
  final String lockId;
  final String dentistId;
  final String date;
  final String timeSlot;
  final String consultationType;
  final int durationMinutes;
  final int bufferMinutes;
  final String? releasedSlotId;
  final DateTime expiresAt;

  const SlotLockModel({
    required this.lockId,
    required this.dentistId,
    required this.date,
    required this.timeSlot,
    required this.consultationType,
    this.durationMinutes = 30,
    this.bufferMinutes = 10,
    this.releasedSlotId,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Duration get remaining => expiresAt.difference(DateTime.now());

  factory SlotLockModel.fromJson(Map<String, dynamic> json, {String fallbackDentistId = ''}) {
    final rawExp = json['expiresAt']?.toString() ?? json['expires_at']?.toString() ?? '';
    final parsedExp = DateTime.tryParse(rawExp) ?? DateTime.now().add(const Duration(minutes: 5));
    return SlotLockModel(
      lockId: (json['lockId'] ?? json['id'] ?? '').toString(),
      dentistId: (json['dentistId'] ?? json['dentist_id'] ?? fallbackDentistId).toString(),
      date: (json['date'] ?? json['appointment_date'] ?? '').toString(),
      timeSlot: (json['timeSlot'] ?? json['start_time'] ?? '').toString(),
      consultationType: (json['consultationType'] ?? json['consultation_type'] ?? 'In-Person').toString(),
      durationMinutes: int.tryParse((json['durationMinutes'] ?? json['duration_minutes'] ?? '30').toString()) ?? 30,
      bufferMinutes: int.tryParse((json['bufferMinutes'] ?? json['buffer_minutes'] ?? '10').toString()) ?? 10,
      releasedSlotId: (json['releasedSlotId'] ?? json['released_slot_id'])?.toString(),
      expiresAt: parsedExp,
    );
  }
}

class PatientDoctorPreferenceModel {
  final String patientId;
  final String dentistId;
  final bool isFavorite;
  final bool notifyEarlierSlots;
  final String preferredConsultationType; // 'Any' | 'Online' | 'In-Person'
  final String? preferredDate;
  final int? earliestTimeMin;
  final int? latestTimeMin;

  const PatientDoctorPreferenceModel({
    this.patientId = '',
    required this.dentistId,
    this.isFavorite = false,
    this.notifyEarlierSlots = false,
    this.preferredConsultationType = 'Any',
    this.preferredDate,
    this.earliestTimeMin,
    this.latestTimeMin,
  });

  factory PatientDoctorPreferenceModel.fromJson(Map<String, dynamic> json) {
    return PatientDoctorPreferenceModel(
      patientId: (json['patient_id'] ?? json['patientId'] ?? '').toString(),
      dentistId: (json['dentist_id'] ?? json['dentistId'] ?? '').toString(),
      isFavorite: json['is_favorite'] == true || json['isFavorite'] == true,
      notifyEarlierSlots: json['notify_earlier_slots'] == true || json['notifyEarlierSlots'] == true,
      preferredConsultationType:
          (json['preferred_consultation_type'] ?? json['preferredConsultationType'] ?? 'Any').toString(),
      preferredDate: (json['preferred_date'] ?? json['preferredDate'])?.toString(),
      earliestTimeMin: int.tryParse((json['earliest_time_min'] ?? json['earliestTimeMin'] ?? '').toString()),
      latestTimeMin: int.tryParse((json['latest_time_min'] ?? json['latestTimeMin'] ?? '').toString()),
    );
  }

  Map<String, dynamic> toJson() => {
        'dentistId': dentistId,
        'isFavorite': isFavorite,
        'notifyEarlierSlots': notifyEarlierSlots,
        'preferredConsultationType': preferredConsultationType,
        if (preferredDate != null && preferredDate!.isNotEmpty) 'preferredDate': preferredDate,
        if (earliestTimeMin != null) 'earliestTimeMin': earliestTimeMin,
        if (latestTimeMin != null) 'latestTimeMin': latestTimeMin,
      };
}

class DoctorScheduleModel {
  final List<String> workingDays;
  final String startTime;
  final String endTime;
  final int slotDurationMinutes;
  final bool hasBreak;
  final String? breakStartTime;
  final String? breakEndTime;
  final List<Map<String, String>> breaks;
  final bool inPersonEnabled;
  final int inPersonDurationMinutes;
  final bool onlineEnabled;
  final int onlineDurationMinutes;
  final bool useSeparateOnlineHours;
  final List<String>? onlineWorkingDays;
  final String? onlineStartTime;
  final String? onlineEndTime;
  final bool onlineHasBreak;
  final String? onlineBreakStartTime;
  final String? onlineBreakEndTime;
  final List<Map<String, String>> onlineBreaks;
  final int inPersonBufferMinutes;
  final int onlineBufferMinutes;
  final int? maxAppointmentsPerDay;
  final bool allowSimultaneousOnlineAndInPerson;
  final Map<String, List<Map<String, dynamic>>> blockedTimeRanges;
  final bool isConfigured;

  const DoctorScheduleModel({
    this.workingDays = const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'],
    this.startTime = '09:00 AM',
    this.endTime = '05:00 PM',
    this.slotDurationMinutes = 30,
    this.hasBreak = true,
    this.breakStartTime = '01:00 PM',
    this.breakEndTime = '02:00 PM',
    this.breaks = const [
      {'startTime': '01:00 PM', 'endTime': '02:00 PM', 'label': 'Lunch Break'},
    ],
    this.inPersonEnabled = true,
    this.inPersonDurationMinutes = 30,
    this.onlineEnabled = true,
    this.onlineDurationMinutes = 20,
    this.useSeparateOnlineHours = false,
    this.onlineWorkingDays,
    this.onlineStartTime,
    this.onlineEndTime,
    this.onlineHasBreak = false,
    this.onlineBreakStartTime,
    this.onlineBreakEndTime,
    this.onlineBreaks = const [],
    this.inPersonBufferMinutes = 10,
    this.onlineBufferMinutes = 5,
    this.maxAppointmentsPerDay,
    this.allowSimultaneousOnlineAndInPerson = false,
    this.blockedTimeRanges = const {},
    this.isConfigured = false,
  });

  factory DoctorScheduleModel.fromJson(Map<String, dynamic> json) {
    final rawDays = json['workingDays'] ?? json['working_days'];
    final days = rawDays is List
        ? rawDays.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList()
        : <String>[];

    List<Map<String, String>> parseBreakList(dynamic rawBreaks) {
      final out = <Map<String, String>>[];
      if (rawBreaks is List) {
        for (final item in rawBreaks) {
          if (item is Map) {
            final s = (item['startTime'] ?? item['start_time'] ?? '').toString().trim();
            final e = (item['endTime'] ?? item['end_time'] ?? '').toString().trim();
            if (s.isNotEmpty && e.isNotEmpty) {
              out.add({
                'startTime': s,
                'endTime': e,
                'label': (item['label'] ?? 'Break').toString().trim(),
              });
            }
          }
        }
      }
      return out;
    }

    final parsedBreaks = parseBreakList(json['breaks']);
    final bStart = (json['breakStartTime'] ?? json['break_start_time'])?.toString();
    final bEnd = (json['breakEndTime'] ?? json['break_end_time'])?.toString();
    if (parsedBreaks.isEmpty && bStart != null && bStart.isNotEmpty && bEnd != null && bEnd.isNotEmpty) {
      parsedBreaks.add({'startTime': bStart, 'endTime': bEnd, 'label': 'Lunch Break'});
    }

    final hasBreakVal = json['breaks'] is List
        ? parsedBreaks.isNotEmpty
        : (json['hasBreak'] != null
            ? json['hasBreak'] == true
            : (json['has_break'] != null
                ? json['has_break'] == true
                : parsedBreaks.isNotEmpty));

    final parsedOnlineBreaks = parseBreakList(json['onlineBreaks'] ?? json['online_breaks']);
    final obStart = (json['onlineBreakStartTime'] ?? json['online_break_start_time'])?.toString();
    final obEnd = (json['onlineBreakEndTime'] ?? json['online_break_end_time'])?.toString();
    if (parsedOnlineBreaks.isEmpty && obStart != null && obStart.isNotEmpty && obEnd != null && obEnd.isNotEmpty) {
      parsedOnlineBreaks.add({'startTime': obStart, 'endTime': obEnd, 'label': 'Online Break'});
    }
    final onlineHasBreakVal = (json['onlineBreaks'] is List || json['online_breaks'] is List)
        ? parsedOnlineBreaks.isNotEmpty
        : (json['onlineHasBreak'] != null
            ? json['onlineHasBreak'] == true
            : (json['online_has_break'] != null
                ? json['online_has_break'] == true
                : parsedOnlineBreaks.isNotEmpty));

    final inPersonDur = int.tryParse(
          (json['inPersonDurationMinutes'] ??
                  json['in_person_duration_minutes'] ??
                  json['slotDurationMinutes'] ??
                  json['slot_duration_minutes'] ??
                  '30')
              .toString(),
        ) ??
        30;
    final onlineDur = int.tryParse(
          (json['onlineDurationMinutes'] ?? json['online_duration_minutes'] ?? '20').toString(),
        ) ??
        20;

    final rawOnlineDays = json['onlineWorkingDays'] ?? json['online_working_days'];
    final onlineDays = rawOnlineDays is List
        ? rawOnlineDays.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList()
        : null;

    final rawBlockedMap = json['blockedTimeRanges'] ?? json['blocked_time_ranges'];
    final blockedRanges = <String, List<Map<String, dynamic>>>{};
    if (rawBlockedMap is Map) {
      rawBlockedMap.forEach((k, v) {
        if (k.toString() == '_scheduleMeta') return;
        if (v is List) {
          blockedRanges[k.toString()] = v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        }
      });
    }

    final maxPerDayRaw = json['maxAppointmentsPerDay'] ?? json['max_appointments_per_day'];
    final maxPerDay = maxPerDayRaw != null ? int.tryParse(maxPerDayRaw.toString()) : null;

    final resolvedStart = (json['startTime'] ?? json['start_time'] ?? '09:00 AM').toString();
    final rawOnStart = (json['onlineStartTime'] ?? json['online_start_time'])?.toString().trim();
    final rawOnEnd = (json['onlineEndTime'] ?? json['online_end_time'])?.toString().trim();
    final onStart = (rawOnStart != null && rawOnStart.isNotEmpty && rawOnStart != 'null') ? rawOnStart : null;
    final onEnd = (rawOnEnd != null && rawOnEnd.isNotEmpty && rawOnEnd != 'null') ? rawOnEnd : null;

    final bool useSeparate = (json['useSeparateOnlineHours'] != null || json['use_separate_online_hours'] != null)
        ? (json['useSeparateOnlineHours'] == true || json['use_separate_online_hours'] == true)
        : (onStart != null && onEnd != null && (onStart != resolvedStart || parsedOnlineBreaks.isNotEmpty));

    return DoctorScheduleModel(
      workingDays: days.isNotEmpty ? days : const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'],
      startTime: resolvedStart,
      endTime: (json['endTime'] ?? json['end_time'] ?? '05:00 PM').toString(),
      slotDurationMinutes: inPersonDur,
      hasBreak: hasBreakVal,
      breakStartTime: hasBreakVal ? (parsedBreaks.isNotEmpty ? parsedBreaks.first['startTime'] : (bStart ?? '01:00 PM')) : null,
      breakEndTime: hasBreakVal ? (parsedBreaks.isNotEmpty ? parsedBreaks.first['endTime'] : (bEnd ?? '02:00 PM')) : null,
      breaks: hasBreakVal ? parsedBreaks : const [],
      inPersonEnabled: json['inPersonEnabled'] != false && json['in_person_enabled'] != false,
      inPersonDurationMinutes: inPersonDur,
      onlineEnabled: json['onlineEnabled'] != false && json['online_enabled'] != false,
      onlineDurationMinutes: onlineDur,
      useSeparateOnlineHours: useSeparate,
      onlineWorkingDays: (onlineDays != null && onlineDays.isNotEmpty) ? onlineDays : null,
      onlineStartTime: onStart,
      onlineEndTime: onEnd,
      onlineHasBreak: onlineHasBreakVal,
      onlineBreakStartTime: onlineHasBreakVal && parsedOnlineBreaks.isNotEmpty ? parsedOnlineBreaks.first['startTime'] : null,
      onlineBreakEndTime: onlineHasBreakVal && parsedOnlineBreaks.isNotEmpty ? parsedOnlineBreaks.first['endTime'] : null,
      onlineBreaks: onlineHasBreakVal ? parsedOnlineBreaks : const [],
      inPersonBufferMinutes:
          int.tryParse((json['inPersonBufferMinutes'] ?? json['in_person_buffer_minutes'] ?? '10').toString()) ?? 10,
      onlineBufferMinutes:
          int.tryParse((json['onlineBufferMinutes'] ?? json['online_buffer_minutes'] ?? '5').toString()) ?? 5,
      maxAppointmentsPerDay: (maxPerDay != null && maxPerDay > 0) ? maxPerDay : null,
      allowSimultaneousOnlineAndInPerson: json['allowSimultaneousOnlineAndInPerson'] == true ||
          json['allow_simultaneous_online_and_in_person'] == true,
      blockedTimeRanges: blockedRanges,
      isConfigured: json['isConfigured'] == true || json['is_configured'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'workingDays': workingDays,
        'startTime': startTime,
        'endTime': endTime,
        'slotDurationMinutes': inPersonDurationMinutes,
        'hasBreak': hasBreak,
        if (breakStartTime != null) 'breakStartTime': breakStartTime,
        if (breakEndTime != null) 'breakEndTime': breakEndTime,
        'breaks': breaks,
        'inPersonEnabled': inPersonEnabled,
        'inPersonDurationMinutes': inPersonDurationMinutes,
        'onlineEnabled': onlineEnabled,
        'onlineDurationMinutes': onlineDurationMinutes,
        'useSeparateOnlineHours': useSeparateOnlineHours,
        if (onlineWorkingDays != null) 'onlineWorkingDays': onlineWorkingDays,
        if (onlineStartTime != null) 'onlineStartTime': onlineStartTime,
        if (onlineEndTime != null) 'onlineEndTime': onlineEndTime,
        'onlineHasBreak': onlineHasBreak,
        if (onlineBreakStartTime != null) 'onlineBreakStartTime': onlineBreakStartTime,
        if (onlineBreakEndTime != null) 'onlineBreakEndTime': onlineBreakEndTime,
        'onlineBreaks': onlineBreaks,
        'inPersonBufferMinutes': inPersonBufferMinutes,
        'onlineBufferMinutes': onlineBufferMinutes,
        'maxAppointmentsPerDay': maxAppointmentsPerDay,
        'allowSimultaneousOnlineAndInPerson': allowSimultaneousOnlineAndInPerson,
        'blockedTimeRanges': blockedTimeRanges,
        'isConfigured': isConfigured,
      };
}

class DoctorAvailabilityModel {
  final String id;
  final String dentistId;
  final String date;
  final String dayOfWeek;
  final String startTime;
  final String endTime;
  final int slotDurationMinutes;
  final bool hasBreak;
  final String? breakStartTime;
  final String? breakEndTime;
  final List<Map<String, dynamic>> breaks;
  final List<String> workingDays;
  final bool isWorkingDay;
  final bool modeEnabled;
  final int? maxAppointmentsPerDay;
  final bool dailyLimitReached;
  final bool allowSimultaneousOnlineAndInPerson;
  final List<String> allSlots;
  final List<String> bookedSlots;
  final List<String> lockedSlots;
  final List<String> availableSlots;
  final List<Map<String, dynamic>> slotItems;
  final List<Map<String, dynamic>> releasedSlots;
  final List<Map<String, dynamic>> blockedSlots;
  final List<Map<String, dynamic>> occupiedIntervals;
  final String liveDoctorStatus;
  final int activeDelayMinutes;
  final String consultationType;
  final int consultationDurationMinutes;
  final int bufferMinutes;
  final bool isBlocked;
  final String? blockedReason;

  const DoctorAvailabilityModel({
    this.id = '',
    required this.dentistId,
    required this.date,
    this.dayOfWeek = '',
    this.startTime = '09:00 AM',
    this.endTime = '05:00 PM',
    this.slotDurationMinutes = 30,
    this.hasBreak = true,
    this.breakStartTime,
    this.breakEndTime,
    this.breaks = const [],
    this.workingDays = const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'],
    this.isWorkingDay = true,
    this.modeEnabled = true,
    this.maxAppointmentsPerDay,
    this.dailyLimitReached = false,
    this.allowSimultaneousOnlineAndInPerson = false,
    this.allSlots = const [],
    this.bookedSlots = const [],
    this.lockedSlots = const [],
    this.availableSlots = const [],
    this.slotItems = const [],
    this.releasedSlots = const [],
    this.blockedSlots = const [],
    this.occupiedIntervals = const [],
    this.liveDoctorStatus = 'Available',
    this.activeDelayMinutes = 0,
    this.consultationType = 'In-Person',
    this.consultationDurationMinutes = 30,
    this.bufferMinutes = 10,
    this.isBlocked = false,
    this.blockedReason,
  });

  factory DoctorAvailabilityModel.fromJson(Map<String, dynamic> json) {
    List<String> parseStringList(dynamic val) {
      if (val is List) {
        return val.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
      }
      return [];
    }

    List<Map<String, dynamic>> parseMapList(dynamic val) {
      if (val is List) {
        return val.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
      return const [];
    }

    final bStart = json['breakStartTime']?.toString() ?? json['break_start_time']?.toString() ?? json['break_start']?.toString();
    final bEnd = json['breakEndTime']?.toString() ?? json['break_end_time']?.toString() ?? json['break_end']?.toString();
    final parsedBreaks = parseMapList(json['breaks']);
    final hasBreakVal = json['hasBreak'] != null
        ? json['hasBreak'] == true
        : (json['has_break'] != null
            ? json['has_break'] == true
            : (parsedBreaks.isNotEmpty || (bStart != null && bStart.isNotEmpty && bEnd != null && bEnd.isNotEmpty)));

    final maxPerDayRaw = json['maxAppointmentsPerDay'] ?? json['max_appointments_per_day'];
    final maxPerDay = maxPerDayRaw != null ? int.tryParse(maxPerDayRaw.toString()) : null;

    return DoctorAvailabilityModel(
      id: json['id']?.toString() ?? '',
      dentistId: json['dentistId']?.toString() ?? json['dentist_id']?.toString() ?? '',
      date: json['date']?.toString() ?? '',
      dayOfWeek: json['dayOfWeek']?.toString() ?? json['day_of_week']?.toString() ?? '',
      startTime: json['startTime']?.toString() ?? json['start_time']?.toString() ?? '09:00 AM',
      endTime: json['endTime']?.toString() ?? json['end_time']?.toString() ?? '05:00 PM',
      slotDurationMinutes: int.tryParse(json['slotDurationMinutes']?.toString() ?? json['slot_duration_minutes']?.toString() ?? '30') ?? 30,
      hasBreak: hasBreakVal,
      breakStartTime: bStart,
      breakEndTime: bEnd,
      breaks: parsedBreaks,
      workingDays: parseStringList(json['workingDays'] ?? json['working_days']).isNotEmpty
          ? parseStringList(json['workingDays'] ?? json['working_days'])
          : const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'],
      isWorkingDay: json['isWorkingDay'] != false && json['is_working_day'] != false,
      modeEnabled: json['modeEnabled'] != false,
      maxAppointmentsPerDay: (maxPerDay != null && maxPerDay > 0) ? maxPerDay : null,
      dailyLimitReached: json['dailyLimitReached'] == true,
      allowSimultaneousOnlineAndInPerson: json['allowSimultaneousOnlineAndInPerson'] == true,
      allSlots: parseStringList(json['allSlots'] ?? json['slots']),
      bookedSlots: parseStringList(json['bookedSlots']),
      lockedSlots: parseStringList(json['lockedSlots']),
      availableSlots: parseStringList(json['availableSlots'] ?? json['slots']),
      slotItems: parseMapList(json['slotItems']),
      releasedSlots: parseMapList(json['releasedSlots']),
      blockedSlots: parseMapList(json['blockedSlots']),
      occupiedIntervals: parseMapList(json['occupiedIntervals']),
      liveDoctorStatus: (json['liveDoctorStatus'] ?? 'Available').toString(),
      activeDelayMinutes: int.tryParse(json['activeDelayMinutes']?.toString() ?? '0') ?? 0,
      consultationType: (json['consultationType'] ?? 'In-Person').toString(),
      consultationDurationMinutes: int.tryParse(json['consultationDurationMinutes']?.toString() ?? '30') ?? 30,
      bufferMinutes: int.tryParse(json['bufferMinutes']?.toString() ?? '10') ?? 10,
      isBlocked: json['isBlocked'] == true || json['is_blocked'] == true,
      blockedReason: json['blockedReason']?.toString() ?? json['blocked_reason']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      'dentistId': dentistId,
      'date': date,
      'dayOfWeek': dayOfWeek,
      'startTime': startTime,
      'endTime': endTime,
      'slotDurationMinutes': slotDurationMinutes,
      'hasBreak': hasBreak,
      if (breakStartTime != null) 'breakStartTime': breakStartTime,
      if (breakEndTime != null) 'breakEndTime': breakEndTime,
      'breaks': breaks,
      'workingDays': workingDays,
      'isWorkingDay': isWorkingDay,
      'modeEnabled': modeEnabled,
      'maxAppointmentsPerDay': maxAppointmentsPerDay,
      'dailyLimitReached': dailyLimitReached,
      'allowSimultaneousOnlineAndInPerson': allowSimultaneousOnlineAndInPerson,
      'slots': allSlots,
      'allSlots': allSlots,
      'bookedSlots': bookedSlots,
      'lockedSlots': lockedSlots,
      'availableSlots': availableSlots,
      'slotItems': slotItems,
      'releasedSlots': releasedSlots,
      'blockedSlots': blockedSlots,
      'occupiedIntervals': occupiedIntervals,
      'liveDoctorStatus': liveDoctorStatus,
      'activeDelayMinutes': activeDelayMinutes,
      'consultationType': consultationType,
      'consultationDurationMinutes': consultationDurationMinutes,
      'bufferMinutes': bufferMinutes,
      'isBlocked': isBlocked,
      if (blockedReason != null) 'blockedReason': blockedReason,
    };
  }

  DoctorAvailabilityModel copyWith({
    String? id,
    String? dentistId,
    String? date,
    String? dayOfWeek,
    String? startTime,
    String? endTime,
    int? slotDurationMinutes,
    bool? hasBreak,
    String? breakStartTime,
    String? breakEndTime,
    List<Map<String, dynamic>>? breaks,
    List<String>? workingDays,
    bool? isWorkingDay,
    bool? modeEnabled,
    int? maxAppointmentsPerDay,
    bool? dailyLimitReached,
    bool? allowSimultaneousOnlineAndInPerson,
    List<String>? allSlots,
    List<String>? bookedSlots,
    List<String>? lockedSlots,
    List<String>? availableSlots,
    List<Map<String, dynamic>>? slotItems,
    List<Map<String, dynamic>>? releasedSlots,
    List<Map<String, dynamic>>? blockedSlots,
    List<Map<String, dynamic>>? occupiedIntervals,
    String? liveDoctorStatus,
    int? activeDelayMinutes,
    String? consultationType,
    int? consultationDurationMinutes,
    int? bufferMinutes,
    bool? isBlocked,
    String? blockedReason,
  }) {
    return DoctorAvailabilityModel(
      id: id ?? this.id,
      dentistId: dentistId ?? this.dentistId,
      date: date ?? this.date,
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      slotDurationMinutes: slotDurationMinutes ?? this.slotDurationMinutes,
      hasBreak: hasBreak ?? this.hasBreak,
      breakStartTime: breakStartTime ?? this.breakStartTime,
      breakEndTime: breakEndTime ?? this.breakEndTime,
      breaks: breaks ?? this.breaks,
      workingDays: workingDays ?? this.workingDays,
      isWorkingDay: isWorkingDay ?? this.isWorkingDay,
      modeEnabled: modeEnabled ?? this.modeEnabled,
      maxAppointmentsPerDay: maxAppointmentsPerDay ?? this.maxAppointmentsPerDay,
      dailyLimitReached: dailyLimitReached ?? this.dailyLimitReached,
      allowSimultaneousOnlineAndInPerson:
          allowSimultaneousOnlineAndInPerson ?? this.allowSimultaneousOnlineAndInPerson,
      allSlots: allSlots ?? this.allSlots,
      bookedSlots: bookedSlots ?? this.bookedSlots,
      lockedSlots: lockedSlots ?? this.lockedSlots,
      availableSlots: availableSlots ?? this.availableSlots,
      slotItems: slotItems ?? this.slotItems,
      releasedSlots: releasedSlots ?? this.releasedSlots,
      blockedSlots: blockedSlots ?? this.blockedSlots,
      occupiedIntervals: occupiedIntervals ?? this.occupiedIntervals,
      liveDoctorStatus: liveDoctorStatus ?? this.liveDoctorStatus,
      activeDelayMinutes: activeDelayMinutes ?? this.activeDelayMinutes,
      consultationType: consultationType ?? this.consultationType,
      consultationDurationMinutes: consultationDurationMinutes ?? this.consultationDurationMinutes,
      bufferMinutes: bufferMinutes ?? this.bufferMinutes,
      isBlocked: isBlocked ?? this.isBlocked,
      blockedReason: blockedReason ?? this.blockedReason,
    );
  }
}
