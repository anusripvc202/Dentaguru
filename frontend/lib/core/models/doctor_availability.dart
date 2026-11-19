class DoctorScheduleModel {
  final List<String> workingDays;
  final String startTime;
  final String endTime;
  final int slotDurationMinutes;
  final bool hasBreak;
  final String? breakStartTime;
  final String? breakEndTime;
  final bool isConfigured;

  const DoctorScheduleModel({
    this.workingDays = const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'],
    this.startTime = '09:00 AM',
    this.endTime = '05:00 PM',
    this.slotDurationMinutes = 30,
    this.hasBreak = true,
    this.breakStartTime = '01:00 PM',
    this.breakEndTime = '02:00 PM',
    this.isConfigured = false,
  });

  factory DoctorScheduleModel.fromJson(Map<String, dynamic> json) {
    final rawDays = json['workingDays'] ?? json['working_days'];
    final days = rawDays is List
        ? rawDays.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList()
        : <String>[];
    final bStart = (json['breakStartTime'] ?? json['break_start_time'])?.toString();
    final bEnd = (json['breakEndTime'] ?? json['break_end_time'])?.toString();
    final hasBreakVal = json['hasBreak'] != null
        ? json['hasBreak'] == true
        : (json['has_break'] != null ? json['has_break'] == true : (bStart != null && bStart.isNotEmpty && bEnd != null && bEnd.isNotEmpty));

    return DoctorScheduleModel(
      workingDays: days.isNotEmpty ? days : const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'],
      startTime: (json['startTime'] ?? json['start_time'] ?? '09:00 AM').toString(),
      endTime: (json['endTime'] ?? json['end_time'] ?? '05:00 PM').toString(),
      slotDurationMinutes: int.tryParse((json['slotDurationMinutes'] ?? json['slot_duration_minutes'] ?? '30').toString()) ?? 30,
      hasBreak: hasBreakVal,
      breakStartTime: hasBreakVal ? (bStart ?? '01:00 PM') : null,
      breakEndTime: hasBreakVal ? (bEnd ?? '02:00 PM') : null,
      isConfigured: json['isConfigured'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'workingDays': workingDays,
        'startTime': startTime,
        'endTime': endTime,
        'slotDurationMinutes': slotDurationMinutes,
        'hasBreak': hasBreak,
        if (breakStartTime != null) 'breakStartTime': breakStartTime,
        if (breakEndTime != null) 'breakEndTime': breakEndTime,
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
  final List<String> workingDays;
  final bool isWorkingDay;
  final List<String> allSlots;
  final List<String> bookedSlots;
  final List<String> availableSlots;
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
    this.workingDays = const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'],
    this.isWorkingDay = true,
    this.allSlots = const [],
    this.bookedSlots = const [],
    this.availableSlots = const [],
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

    final bStart = json['breakStartTime']?.toString() ?? json['break_start_time']?.toString() ?? json['break_start']?.toString();
    final bEnd = json['breakEndTime']?.toString() ?? json['break_end_time']?.toString() ?? json['break_end']?.toString();
    final hasBreakVal = json['hasBreak'] != null
        ? json['hasBreak'] == true
        : (json['has_break'] != null
            ? json['has_break'] == true
            : (bStart != null && bStart.isNotEmpty && bEnd != null && bEnd.isNotEmpty));

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
      workingDays: parseStringList(json['workingDays'] ?? json['working_days']).isNotEmpty
          ? parseStringList(json['workingDays'] ?? json['working_days'])
          : const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'],
      isWorkingDay: json['isWorkingDay'] != false && json['is_working_day'] != false,
      allSlots: parseStringList(json['allSlots'] ?? json['slots']),
      bookedSlots: parseStringList(json['bookedSlots']),
      availableSlots: parseStringList(json['availableSlots'] ?? json['slots']),
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
      'workingDays': workingDays,
      'isWorkingDay': isWorkingDay,
      'slots': allSlots,
      'allSlots': allSlots,
      'bookedSlots': bookedSlots,
      'availableSlots': availableSlots,
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
    List<String>? workingDays,
    bool? isWorkingDay,
    List<String>? allSlots,
    List<String>? bookedSlots,
    List<String>? availableSlots,
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
      workingDays: workingDays ?? this.workingDays,
      isWorkingDay: isWorkingDay ?? this.isWorkingDay,
      allSlots: allSlots ?? this.allSlots,
      bookedSlots: bookedSlots ?? this.bookedSlots,
      availableSlots: availableSlots ?? this.availableSlots,
      isBlocked: isBlocked ?? this.isBlocked,
      blockedReason: blockedReason ?? this.blockedReason,
    );
  }
}

