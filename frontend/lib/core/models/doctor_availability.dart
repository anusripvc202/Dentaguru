class DoctorAvailabilityModel {
  final String id;
  final String dentistId;
  final String date;
  final String dayOfWeek;
  final String startTime;
  final String endTime;
  final int slotDurationMinutes;
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

    return DoctorAvailabilityModel(
      id: json['id']?.toString() ?? '',
      dentistId: json['dentistId']?.toString() ?? json['dentist_id']?.toString() ?? '',
      date: json['date']?.toString() ?? '',
      dayOfWeek: json['dayOfWeek']?.toString() ?? json['day_of_week']?.toString() ?? '',
      startTime: json['startTime']?.toString() ?? json['start_time']?.toString() ?? '09:00 AM',
      endTime: json['endTime']?.toString() ?? json['end_time']?.toString() ?? '05:00 PM',
      slotDurationMinutes: int.tryParse(json['slotDurationMinutes']?.toString() ?? json['slot_duration_minutes']?.toString() ?? '30') ?? 30,
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
      allSlots: allSlots ?? this.allSlots,
      bookedSlots: bookedSlots ?? this.bookedSlots,
      availableSlots: availableSlots ?? this.availableSlots,
      isBlocked: isBlocked ?? this.isBlocked,
      blockedReason: blockedReason ?? this.blockedReason,
    );
  }
}

